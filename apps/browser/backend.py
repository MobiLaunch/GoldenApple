#!/usr/bin/env python3
"""State and native services for Golden Gate Web's QML chrome."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlsplit

from PySide6.QtCore import QObject, Property, QStandardPaths, Signal, Slot
from PySide6.QtGui import QGuiApplication

from model import Store, address_url


class BrowserBackend(QObject):
    darkChanged = Signal()
    libraryChanged = Signal()
    toastRequested = Signal(str)
    externalUrlRequested = Signal(str)
    externalUrls = Signal(str)

    def __init__(self, *, private=False, launch_values=None, data_dir=None, cache_dir=None, download_dir=None, parent=None):
        super().__init__(parent)
        self.private = bool(private)
        self.launch_values = list(launch_values or [])
        data = Path(data_dir or QStandardPaths.writableLocation(QStandardPaths.AppDataLocation))
        cache = Path(cache_dir or QStandardPaths.writableLocation(QStandardPaths.CacheLocation))
        downloads = Path(download_dir or QStandardPaths.writableLocation(QStandardPaths.DownloadLocation))
        data.mkdir(parents=True, exist_ok=True, mode=0o700)
        cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        downloads.mkdir(parents=True, exist_ok=True)
        self._data_dir = data
        self._cache_dir = cache
        self._downloads_dir = downloads
        self.store = Store(data / ("private-state.json" if self.private else "state.json"), self.private)
        self._dark = self._is_dark()
        QGuiApplication.styleHints().colorSchemeChanged.connect(self._scheme_changed)

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

    @Slot(str, result=str)
    def resolveAddress(self, text):
        try:
            return address_url(text)
        except ValueError as error:
            self.toastRequested.emit(str(error))
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
            search_url = address_url(query)
        except ValueError:
            search_url = ""
        if search_url:
            is_search = "duckduckgo.com/?q=" in search_url
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
        self._save()

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

    @Slot()
    def openPrivateWindow(self):
        subprocess.Popen(
            [sys.executable, str(Path(__file__).with_name("browser.py")), "--private"],
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
