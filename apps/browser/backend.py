#!/usr/bin/env python3
"""State and native services for CitronOS Web's QML chrome."""
from __future__ import annotations

import json
import os
import re
import secrets
from pathlib import Path
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlsplit

from PySide6.QtCore import QCoreApplication, QObject, Property, QStandardPaths, Qt, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtWebEngineCore import QWebEngineUrlRequestInterceptor

from model import Store, address_url
from passwords import Passwords, origin_of


def profile_key(name):
    key = re.sub(r"[^a-z0-9._-]+", "-", (name or "Personal").strip().lower()).strip("-")
    return key[:48] or "personal"


class PrivacyInterceptor(QWebEngineUrlRequestInterceptor):
    """Conservative third-party tracker blocking for CitronOS Web.

    This is intentionally a small built-in domain set, not a claim of parity
    with Safari's Intelligent Tracking Prevention or a full ad blocker.
    """
    blocked = Signal(str, str)

    TRACKERS = (
        "doubleclick.net",
        "googlesyndication.com",
        "google-analytics.com",
        "analytics.google.com",
        "googletagmanager.com",
        "connect.facebook.net",
        "facebook.net",
        "ads-twitter.com",
        "analytics.twitter.com",
        "scorecardresearch.com",
        "segment.io",
        "segment.com",
        "api.segment.io",
        "mixpanel.com",
        "api.mixpanel.com",
        "amplitude.com",
        "api.amplitude.com",
        "hotjar.com",
        "static.hotjar.com",
    )

    def __init__(self, parent=None):
        super().__init__(parent)
        self.enabled = True

    @staticmethod
    def _matches(host, domain):
        return host == domain or host.endswith("." + domain)

    def interceptRequest(self, info):
        if not self.enabled:
            return
        try:
            request_host = info.requestUrl().host().lower().rstrip(".")
            first_host = info.firstPartyUrl().host().lower().rstrip(".")
        except Exception:
            return
        if not request_host or not first_host:
            return
        # Never block the site the user intentionally opened or one of its own
        # subdomains. Protection applies only to known third-party trackers.
        if request_host == first_host or request_host.endswith("." + first_host):
            return
        tracker = next((domain for domain in self.TRACKERS if self._matches(request_host, domain)), None)
        if not tracker:
            return
        info.block(True)
        self.blocked.emit(first_host, tracker)


class BrowserBackend(QObject):
    darkChanged = Signal()
    libraryChanged = Signal()
    profilesChanged = Signal()
    privacyChanged = Signal()
    toastRequested = Signal(str)
    externalUrls = Signal(str)

    def __init__(self, *, private=False, launch_values=None, profile_name="Personal",
                 data_dir=None, cache_dir=None, download_dir=None, parent=None):
        super().__init__(parent)
        self.private = bool(private)
        self.launch_values = list(launch_values or [])
        clean_profile = (profile_name or "Personal").strip()
        self.profile_name = clean_profile[:60] or "Personal"

        base_data = Path(data_dir or QStandardPaths.writableLocation(QStandardPaths.AppDataLocation))
        base_cache = Path(cache_dir or QStandardPaths.writableLocation(QStandardPaths.CacheLocation))
        downloads = Path(download_dir or QStandardPaths.writableLocation(QStandardPaths.DownloadLocation))
        base_data.mkdir(parents=True, exist_ok=True, mode=0o700)
        base_cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        downloads.mkdir(parents=True, exist_ok=True)

        self._base_data_dir = base_data
        self._base_cache_dir = base_cache
        self._profiles_file = base_data / "profiles.json"

        # Preserve the original GoldenGateWeb paths for the default Personal
        # profile; named profiles are isolated underneath profiles/<slug>/.
        if self.profile_name == "Personal":
            data = base_data
            cache = base_cache
        else:
            key = profile_key(self.profile_name)
            data = base_data / "profiles" / key
            cache = base_cache / "profiles" / key
        data.mkdir(parents=True, exist_ok=True, mode=0o700)
        cache.mkdir(parents=True, exist_ok=True, mode=0o700)

        self._data_dir = data
        self._cache_dir = cache
        self._downloads_dir = downloads
        self._ensure_profile_registered(self.profile_name)
        if self.private:
            # Private Browsing can still see the active profile's Favorites,
            # Reading List, groups and preferences, but its Store is explicitly
            # off-record so none of its visits/tabs/changes are written back.
            saved = Store(data / "state.json", False)
            self.store = Store(data / "private-state.json", True)
            for key in ("bookmarks", "readingList", "tabGroups", "settings"):
                self.store.data[key] = json.loads(json.dumps(saved.data[key]))
            self.store.data["tabs"] = ["about:blank"]
            self.store.data["history"] = []
            self.store.data["closedTabs"] = []
        else:
            self.store = Store(data / "state.json", False)

        self._privacy_total = 0
        self._privacy_sites = {}
        self._privacy_interceptor = PrivacyInterceptor(self)
        self._privacy_interceptor.enabled = bool(self.store.data["settings"].get("privacyProtection", True))
        self._privacy_interceptor.blocked.connect(self._tracker_blocked)

        self._dark = self._is_dark()
        QGuiApplication.styleHints().colorSchemeChanged.connect(self._scheme_changed)

        # Saved passwords, in the keyring, per profile. Which sites have any is
        # read once so a page load only asks the keyring when there is
        # something to fill. The token marks messages from Web's own page
        # script, which runs where the page's scripts can't see it.
        self.passwords = Passwords(profile_key(self.profile_name))
        self._password_token = secrets.token_hex(12)
        self._password_sites = None
        self._copyRequested.connect(self._copy_secret, Qt.QueuedConnection)

    def _read_profiles(self):
        names = ["Personal"]
        try:
            raw = json.loads(self._profiles_file.read_text(encoding="utf-8"))
            if isinstance(raw, list):
                for value in raw:
                    if isinstance(value, str) and value.strip() and value.strip() not in names:
                        names.append(value.strip()[:60])
        except (OSError, ValueError, TypeError):
            pass
        return names[:20]

    def _write_profiles(self, names):
        temp = self._profiles_file.with_suffix(".tmp")
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(names[:20], stream, ensure_ascii=False)
        temp.replace(self._profiles_file)

    def _ensure_profile_registered(self, name):
        names = self._read_profiles()
        if name not in names:
            names.append(name)
            try:
                self._write_profiles(names)
            except OSError:
                pass

    def _is_dark(self):
        return QGuiApplication.styleHints().colorScheme().name.lower() == "dark"

    def _scheme_changed(self, *_):
        dark = self._is_dark()
        if dark != self._dark:
            self._dark = dark
            self.darkChanged.emit()

    @Property(bool, notify=darkChanged)
    def dark(self):
        return self._dark

    @Property(bool, constant=True)
    def privateMode(self):
        return self.private

    @Property(bool, constant=True)
    def safeGraphics(self):
        return os.environ.get("GG_WEB_LIVE_SAFE") == "1" or os.environ.get("GG_WEB_SOFTWARE") == "1" or os.environ.get("LIBGL_ALWAYS_SOFTWARE") == "1"

    @Slot()
    def restartInSafeMode(self):
        # browser.py saves tabs and releases the profile lock on orderly quit.
        # launch.sh sees 79 and retries once with Mesa software GL.
        if not self.safeGraphics:
            QCoreApplication.exit(79)

    @Property(str, constant=True)
    def profileName(self):
        return self.profile_name

    @Property(str, notify=profilesChanged)
    def profilesJson(self):
        return json.dumps(self._read_profiles())

    @Property(str, constant=True)
    def dataDir(self):
        return str(self._data_dir)

    @Property(str, constant=True)
    def cacheDir(self):
        return str(self._cache_dir)

    @Property(str, constant=True)
    def downloadDir(self):
        return str(self._downloads_dir)

    @Property(str, constant=True)
    def initialTabsJson(self):
        if self.launch_values:
            values = []
            for value in self.launch_values[:30]:
                try:
                    values.append(address_url(value))
                except ValueError:
                    pass
            return json.dumps(values or ["about:blank"])
        if self.private:
            return json.dumps(["about:blank"])
        if not self.store.data["settings"].get("restoreSession", True):
            return json.dumps(["about:blank"])
        return json.dumps(self.store.data["tabs"] or ["about:blank"])

    @Property(str, constant=True)
    def settingsJson(self):
        return json.dumps(self.store.data["settings"])

    def _tracker_blocked(self, site, domain):
        self._privacy_total += 1
        site_record = self._privacy_sites.setdefault(site, {})
        site_record[domain] = site_record.get(domain, 0) + 1
        self.privacyChanged.emit()

    def _privacy_payload(self, site=None):
        domains = {}
        if site:
            domains = dict(self._privacy_sites.get(site, {}))
            total = sum(domains.values())
        else:
            total = self._privacy_total
            for record in self._privacy_sites.values():
                for domain, count in record.items():
                    domains[domain] = domains.get(domain, 0) + count
        ranked = [
            {"domain": domain, "count": count}
            for domain, count in sorted(domains.items(), key=lambda item: (-item[1], item[0]))
        ]
        return {
            "enabled": bool(self._privacy_interceptor.enabled),
            "blocked": total,
            "domains": ranked[:30],
        }

    @Slot(QObject)
    def attachProfile(self, profile):
        setter = getattr(profile, "setUrlRequestInterceptor", None)
        if setter is None:
            self.toastRequested.emit("Privacy protection could not attach to this browser profile.")
            return
        setter(self._privacy_interceptor)

    @Slot(result=str)
    def privacyReportJson(self):
        return json.dumps(self._privacy_payload())

    @Slot(str, result=str)
    def privacyReportForUrl(self, value):
        try:
            site = (urlsplit(value).hostname or "").lower()
        except (ValueError, AttributeError):
            site = ""
        return json.dumps(self._privacy_payload(site))

    @Slot(str, result=str)
    def resolveAddress(self, text):
        try:
            return address_url(text, self.store.data["settings"].get("searchEngine", "duckduckgo"))
        except ValueError as error:
            self.toastRequested.emit(str(error))
            return ""

    @Slot(str, result=str)
    def securityOrigin(self, value):
        try:
            parsed = urlsplit(value)
            if parsed.scheme not in ("http", "https") or not parsed.hostname:
                return ""
            host = parsed.hostname
            if parsed.port:
                host += f":{parsed.port}"
            return f"{parsed.scheme}://{host}"
        except (ValueError, AttributeError):
            return ""

    @Slot(str, result=str)
    def displayAddress(self, value):
        if not value or value == "about:blank":
            return ""
        try:
            parsed = urlsplit(value)
            host = parsed.hostname or ""
            if parsed.port:
                host += f":{parsed.port}"
            return host.removeprefix("www.")
        except (ValueError, AttributeError):
            return value

    @Slot(str, str, result=str)
    def suggestions(self, query, tabs_json):
        q = (query or "").strip().lower()
        try:
            tabs = json.loads(tabs_json or "[]")
        except (TypeError, ValueError):
            tabs = []
        out = []
        seen = set()

        def add(kind, title, url, subtitle=""):
            if not isinstance(url, str) or url in seen or (url != "about:blank" and not self.store.valid(url)):
                return
            seen.add(url)
            out.append({"kind": kind, "title": title or url, "url": url, "subtitle": subtitle})

        if not q:
            if self.store.data["settings"].get("showFavoritesOnFocus", True):
                for record in self.store.data["bookmarks"][:8]:
                    add("favorite", record["title"], record["url"], "Favorite")
            return json.dumps(out)

        for tab in tabs:
            if not isinstance(tab, dict):
                continue
            title, url = str(tab.get("title", "")), str(tab.get("url", ""))
            if q in title.lower() or q in url.lower():
                add("tab", title or self.displayAddress(url), url, "Open Tab")

        for kind, key, subtitle in (
            ("favorite", "bookmarks", "Favorite"),
            ("history", "history", "History"),
            ("reading", "readingList", "Reading List"),
        ):
            for record in self.store.data[key]:
                if q in record["title"].lower() or q in record["url"].lower():
                    add(kind, record["title"], record["url"], subtitle)
                if len(out) >= 7:
                    break
            if len(out) >= 7:
                break

        try:
            search_url = address_url(query, self.store.data["settings"].get("searchEngine", "duckduckgo"))
        except ValueError:
            search_url = ""
        if search_url:
            is_search = any(host in search_url for host in (
                "duckduckgo.com/?q=", "search.brave.com/search?q=",
                "bing.com/search?q=", "google.com/search?q="
            ))
            add("search" if is_search else "go", query, search_url,
                "Search the Web" if is_search else self.displayAddress(search_url))
        return json.dumps(out[:8])

    @Slot(result=str)
    def startPageJson(self):
        history = self.store.data["history"]
        return json.dumps({
            "favorites": self.store.data["bookmarks"][:10],
            "frequent": history[:8],
            "readingList": self.store.data["readingList"][:6],
            "recentlyClosed": self.store.data["closedTabs"][:6],
            "private": self.private,
            "privacy": self._privacy_payload(),
        })

    @Slot(str, result=str)
    def collectionJson(self, key):
        allowed = {"bookmarks", "history", "readingList", "closedTabs", "tabGroups"}
        if key not in allowed:
            return "[]"
        return json.dumps(self.store.data[key])

    @Slot(str, str)
    def visit(self, url, title):
        self.store.visit(url, title)
        self._save()
        self.libraryChanged.emit()

    @Slot(str, str, result=bool)
    def addBookmark(self, url, title):
        if not self.store.valid(url):
            return False
        if not any(item["url"] == url for item in self.store.data["bookmarks"]):
            self.store.data["bookmarks"].insert(0, {"title": title or self.displayAddress(url), "url": url})
            self.store.data["bookmarks"] = self.store.data["bookmarks"][:200]
            self._save()
            self.libraryChanged.emit()
        self.toastRequested.emit("Added to Favorites")
        return True

    @Slot(str, str, result=bool)
    def addReadingList(self, url, title):
        if not self.store.valid(url):
            return False
        records = [r for r in self.store.data["readingList"] if r["url"] != url]
        records.insert(0, {"title": title or self.displayAddress(url), "url": url})
        self.store.data["readingList"] = records[:200]
        self._save()
        self.libraryChanged.emit()
        self.toastRequested.emit("Added to Reading List")
        return True

    @Slot(str, str)
    def rememberClosedTab(self, url, title):
        if self.private or not self.store.valid(url):
            return
        records = [r for r in self.store.data["closedTabs"] if r["url"] != url]
        records.insert(0, {"title": title or self.displayAddress(url), "url": url})
        self.store.data["closedTabs"] = records[:30]
        self._save()
        self.libraryChanged.emit()

    @Slot(str)
    def saveTabs(self, tabs_json):
        if self.private:
            return
        try:
            values = json.loads(tabs_json)
        except (TypeError, ValueError):
            return
        tabs = []
        for value in values[:30]:
            if value == "about:blank" or self.store.valid(value):
                tabs.append(value)
        self.store.data["tabs"] = tabs or ["about:blank"]
        self._save()

    @Slot(str, str)
    def setSetting(self, key, value_json):
        if key not in self.store.data["settings"]:
            return
        try:
            value = json.loads(value_json)
        except (TypeError, ValueError):
            return
        self.store.data["settings"][key] = value
        if key == "privacyProtection":
            self._privacy_interceptor.enabled = bool(value)
            self.privacyChanged.emit()
        self._save()


    @Slot(str, str, result=bool)
    def saveTabGroup(self, name, tabs_json):
        if self.private:
            return False
        clean_name = (name or "").strip()
        if not clean_name:
            self.toastRequested.emit("Give this Tab Group a name.")
            return False
        if len(clean_name) > 60:
            clean_name = clean_name[:60]
        try:
            values = json.loads(tabs_json or "[]")
        except (TypeError, ValueError):
            return False
        tabs = []
        for value in values[:30]:
            if isinstance(value, dict):
                url = value.get("url")
                title = value.get("title") or self.displayAddress(url or "")
            else:
                url = value
                title = self.displayAddress(url or "")
            if url == "about:blank" or self.store.valid(url):
                tabs.append({"title": title or "Start Page", "url": url})
        if not tabs:
            self.toastRequested.emit("There are no tabs to save.")
            return False
        groups = [g for g in self.store.data["tabGroups"] if g.get("name") != clean_name]
        groups.insert(0, {"name": clean_name, "tabs": tabs})
        self.store.data["tabGroups"] = groups[:20]
        self._save()
        self.libraryChanged.emit()
        self.toastRequested.emit("Tab Group saved")
        return True

    @Slot(int)
    def removeTabGroup(self, index):
        groups = self.store.data["tabGroups"]
        if 0 <= index < len(groups):
            groups.pop(index)
            self._save()
            self.libraryChanged.emit()

    @Slot(str, int)
    def removeCollectionItem(self, key, index):
        if key not in {"bookmarks", "history", "readingList", "closedTabs"}:
            return
        records = self.store.data[key]
        if 0 <= index < len(records):
            records.pop(index)
            self._save()
            self.libraryChanged.emit()

    @Slot()
    def clearHistory(self):
        self.store.data["history"] = []
        self._save()
        self.libraryChanged.emit()
        self.toastRequested.emit("History cleared")

    @Slot(str)
    def copyText(self, text):
        QGuiApplication.clipboard().setText(text)

    @Slot(str)
    def notify(self, text):
        self.toastRequested.emit(text)

    # ------------------------------------------------------------ passwords
    passwordsChanged = Signal()

    @Property(str, constant=True)
    def passwordToken(self):
        return self._password_token

    # Tests only: answer "Save Password" by themselves.
    @Property(bool, constant=True)
    def testAcceptsPasswords(self):
        return os.environ.get("GG_WEB_TEST_ACCEPT_PASSWORDS") == "1"

    # The keyring is only ever reached from one background worker: a locked
    # or slow keyring (secret-tool can wait 20 s for an unlock) must never
    # freeze the window. Results come back as signals; each site's logins
    # are cached for a while and a lookup already under way is shared.
    passwordScriptReady = Signal(str, str)      # request, page script
    passwordOfferReady = Signal(str, str)       # request, "save" | "update" | ""
    passwordSaved = Signal(bool, str)           # saved, kind
    savedLoginsReady = Signal(str)              # [{origin, username}] as JSON
    keyringWaitingChanged = Signal()
    CACHE_SECONDS = 120

    def _keyring(self):
        if not hasattr(self, "_kr_pool"):
            self._kr_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="web-keyring")
            self._kr_lock = threading.Lock()
            self._kr_cache = {}                 # origin → (when, credentials)
            self._kr_pending = 0
            self._kr_waiting = False
        return self._kr_pool

    @Property(bool, notify=keyringWaitingChanged)
    def keyringWaiting(self):
        return getattr(self, "_kr_waiting", False)

    def _set_waiting(self, on):
        if on != getattr(self, "_kr_waiting", False):
            self._kr_waiting = on
            self.keyringWaitingChanged.emit()

    def _in_background(self, job):
        """Run job() on the keyring worker; after 1.5 s without an answer, say
        it's waiting for the keyring (it may be asking to be unlocked)."""
        pool = self._keyring()
        with self._kr_lock:
            self._kr_pending += 1

        def slow():
            if self._kr_pending:
                self._set_waiting(True)

        timer = threading.Timer(1.5, slow)
        timer.daemon = True
        timer.start()

        def run():
            try:
                job()
            except Exception as exc:            # never lose the worker to one bad call
                print("Web: keyring:", exc, file=sys.stderr)
            finally:
                timer.cancel()
                with self._kr_lock:
                    self._kr_pending -= 1
                    idle = self._kr_pending == 0
                if idle:
                    self._set_waiting(False)
        pool.submit(run)

    def _sites_with_passwords(self):
        if self._password_sites is None:
            self._password_sites = {login["origin"] for login in self.passwords.logins()}
        return self._password_sites

    def _credentials(self, origin):
        """(Worker only.) This site's logins, from the cache when it's fresh."""
        hit = self._kr_cache.get(origin)
        if hit and time.monotonic() - hit[0] < self.CACHE_SECONDS:
            return hit[1]
        creds = self.passwords.credentials(origin) if origin in self._sites_with_passwords() else []
        self._kr_cache[origin] = (time.monotonic(), creds)
        return creds

    def _forget_cache(self, origin=None):
        if hasattr(self, "_kr_cache"):
            if origin is None:
                self._kr_cache.clear()
            else:
                self._kr_cache.pop(origin, None)

    def _never_save(self):
        value = self.store.data["settings"].get("neverSavePasswords", [])
        return value if isinstance(value, list) else []

    @staticmethod
    def _fillable(url):
        """The page's origin if a saved login may be filled there: its exact
        origin, and only over HTTPS (or this computer), so a password never
        goes to a page that could be faked."""
        origin = origin_of(url)
        host = (urlsplit(origin).hostname or "") if origin else ""
        secure = origin.startswith("https://") or host in ("localhost", "127.0.0.1", "::1")
        return origin if origin and secure else ""

    def _script(self, creds_json):
        if not hasattr(self, "_password_js"):
            self._password_js = (Path(__file__).with_name("passwords.js").read_text(encoding="utf-8")
                                 .replace("__TOKEN__", self._password_token))
        return self._password_js.replace("__CREDENTIALS__", creds_json)

    @Slot(str, str)
    def requestPasswordScript(self, request, url):
        """The page script for this page (it notices sign-ins, and fills a
        saved login for the page's own site), as passwordScriptReady."""
        origin = self._fillable(url)
        if not origin:
            self.passwordScriptReady.emit(request, self._script("[]"))
            return
        self._in_background(lambda: self.passwordScriptReady.emit(
            request, self._script(json.dumps(self._credentials(origin)))))

    @Slot(str, str, str, str)
    def requestPasswordOffer(self, request, url, username, password):
        """What to ask after a sign-in, as passwordOfferReady: "save",
        "update" or "" (nothing)."""
        origin = origin_of(url)
        if self.private or not origin or not password or origin in self._never_save():
            self.passwordOfferReady.emit(request, "")
            return

        def job():
            if origin not in self._sites_with_passwords():
                kind = "save"
            else:
                saved = {c["username"]: c["password"] for c in self._credentials(origin)}
                kind = ("" if saved[username] == password else "update") if username in saved else "save"
            self.passwordOfferReady.emit(request, kind)
        self._in_background(job)

    @Slot(str, str, str, str)
    def savePasswordAsync(self, url, username, password, kind):
        origin = origin_of(url)
        if self.private or not origin:
            self.passwordSaved.emit(False, kind)
            return

        def job():
            ok = self.passwords.save(origin, username, password)
            self._forget_cache(origin)
            if ok:
                self._sites_with_passwords().add(origin)
                self.passwordsChanged.emit()
            else:
                reason = self.passwords.error or "the keyring is locked."
                print("Web: a password couldn't be saved:", reason, file=sys.stderr)
                self.toastRequested.emit("The password couldn't be saved: " + reason)
            self.passwordSaved.emit(ok, kind)
        self._in_background(job)

    @Slot(str)
    def neverSavePasswordsFor(self, url):
        origin = origin_of(url)
        if not origin or self.private:
            return
        sites = self._never_save()
        if origin not in sites:
            self.store.data["settings"]["neverSavePasswords"] = sites + [origin]
            self._save()

    @Slot()
    def requestSavedLogins(self):
        def job():
            logins = self.passwords.logins()
            self._password_sites = {login["origin"] for login in logins}
            self.savedLoginsReady.emit(json.dumps(logins))
        self._in_background(job)

    @Slot(str, str)
    def removeSavedPassword(self, origin, username):
        def job():
            if not self.passwords.remove(origin, username):
                self.toastRequested.emit("That password couldn't be removed: " + (self.passwords.error or "the keyring is locked."))
            self._password_sites = None
            self._forget_cache(origin)
            self.passwordsChanged.emit()
            logins = self.passwords.logins()
            self._password_sites = {login["origin"] for login in logins}
            self.savedLoginsReady.emit(json.dumps(logins))
        self._in_background(job)

    @Slot(str, str)
    def copySavedPassword(self, origin, username):
        def job():
            secret = self.passwords.password(origin, username)
            if secret is None:
                self.toastRequested.emit("That password couldn't be read from the keyring.")
                return
            self._copyRequested.emit(secret)
        self._in_background(job)

    # The clipboard belongs to the main thread: the worker hands it over.
    _copyRequested = Signal(str)

    def _copy_secret(self, secret):
        QGuiApplication.clipboard().setText(secret)
        self.toastRequested.emit("Password copied.")

    @Slot(str, result=bool)
    def createProfile(self, name):
        clean = (name or "").strip()
        if not clean or len(clean) > 60 or any(ord(c) < 32 for c in clean):
            self.toastRequested.emit("Enter a profile name up to 60 characters.")
            return False
        names = self._read_profiles()
        if clean in names:
            self.toastRequested.emit("That profile already exists.")
            return False
        names.append(clean)
        try:
            self._write_profiles(names)
        except OSError:
            self.toastRequested.emit("The profile could not be saved.")
            return False
        self.profilesChanged.emit()
        self.toastRequested.emit("Profile created")
        return True

    @Slot(str)
    def openProfile(self, name):
        clean = (name or "").strip()
        if clean not in self._read_profiles():
            return
        subprocess.Popen(
            [sys.executable, str(Path(__file__).with_name("browser.py")), "--profile", clean],
            close_fds=True,
            start_new_session=True,
        )

    @Slot()
    def openPrivateWindow(self):
        subprocess.Popen(
            [sys.executable, str(Path(__file__).with_name("browser.py")),
             "--profile", self.profile_name, "--private"],
            close_fds=True,
            start_new_session=True,
        )

    @Slot()
    def openDownloadsFolder(self):
        subprocess.Popen(["xdg-open", self.downloadDir], close_fds=True, start_new_session=True)

    def _save(self):
        try:
            self.store.save()
        except OSError:
            self.toastRequested.emit("Browser state could not be saved.")
