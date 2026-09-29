#!/usr/bin/env python3
"""Golden Gate Web: native Safari-inspired chrome over Chromium / Qt WebEngine."""
import html
import os
from pathlib import Path
import sys

from PySide6.QtCore import QLockFile, QStandardPaths, Qt, QTimer, QUrl
from PySide6.QtGui import QAction, QColor, QIcon, QKeySequence, QShortcut
from PySide6.QtWidgets import (QApplication, QDialog, QFileDialog, QFrame, QHBoxLayout,
    QLabel, QLineEdit, QListWidget, QListWidgetItem, QMainWindow, QMessageBox,
    QProgressBar, QPushButton, QSplitter, QStackedWidget, QTabBar, QToolButton,
    QVBoxLayout, QWidget)
from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile, QWebEngineSettings
from PySide6.QtWebEngineWidgets import QWebEngineView
from model import Store, address_url

ASSETS = Path(__file__).resolve().parents[1] / 'lib/assets/symbols'


def button(symbol, label, action):
    btn = QToolButton()
    icon = ASSETS / (symbol + '.svg')
    if icon.exists():
        btn.setIcon(QIcon(str(icon)))
    else:
        btn.setText(label)
    btn.setProperty("symbol", symbol)
    btn.setToolTip(label)
    btn.setAccessibleName(label)
    btn.setFixedSize(32, 30)
    btn.clicked.connect(action)
    return btn


class Toolbar(QFrame):
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton and self.window().windowHandle():
            self.window().windowHandle().startSystemMove()
        super().mousePressEvent(event)

    def mouseDoubleClickEvent(self, event):
        if event.button() == Qt.LeftButton:
            window = self.window()
            window.showNormal() if window.isMaximized() else window.showMaximized()


class WebView(QWebEngineView):
    def __init__(self, owner):
        super().__init__()
        self.owner = owner
        self.setPage(QWebEnginePage(owner.profile, self))
        self.page().newWindowRequested.connect(self.new_window)
        self.page().windowCloseRequested.connect(lambda: owner.close_view(self))
        self.page().permissionRequested.connect(self.permission)
        self.page().fullScreenRequested.connect(self.fullscreen)
        self.settings().setAttribute(QWebEngineSettings.FullScreenSupportEnabled, True)
        self.settings().setAttribute(QWebEngineSettings.ScrollAnimatorEnabled, True)
        self.renderProcessTerminated.connect(lambda status, code: owner.renderer_failed(self, code))

    def new_window(self, request):
        if not request.isUserInitiated():
            self.owner.message('A pop-up was blocked. Open its link in a new tab to continue.')
            return
        view = self.owner.add_tab()
        request.openIn(view.page())

    def permission(self, request):
        answer = QMessageBox.question(self.owner, 'Website permission',
            f'{request.origin().toDisplayString()} requests {request.permissionType().name}.\nAllow this website?')
        request.grant() if answer == QMessageBox.Yes else request.deny()

    def fullscreen(self, request):
        if self != self.owner.current():
            request.reject()
            return
        request.accept()
        self.owner.set_web_fullscreen(request.toggleOn())


class Browser(QMainWindow):
    def __init__(self, private=False, urls=None, data_dir=None):
        super().__init__()
        self.private = private
        self.setWindowTitle('Web — Private Browsing' if private else 'Web')
        self.setWindowFlags(self.windowFlags() | Qt.FramelessWindowHint)
        self.resize(1160, 760)
        self.setMinimumSize(640, 440)
        path = Path(data_dir or QStandardPaths.writableLocation(QStandardPaths.AppDataLocation))
        self.store = Store(path / 'state.json', private)
        self.profile = QWebEngineProfile(self) if private else QWebEngineProfile('GoldenGate', self)
        if not private:
            self.profile.setPersistentStoragePath(str(path / 'profile'))
            self.profile.setCachePath(str(path / 'cache'))
            self.profile.setPersistentCookiesPolicy(QWebEngineProfile.AllowPersistentCookies)
        self.profile.downloadRequested.connect(self.download)
        self.fullscreen_state = None
        self.views = []
        self.downloads = []
        self.shortcut_objects = []
        self.state_timer = QTimer(self)
        self.state_timer.setSingleShot(True)
        self.state_timer.timeout.connect(self.save)
        self.download_dialog = QDialog(self)
        self.download_dialog.setWindowTitle('Downloads')
        self.download_dialog.resize(540, 300)
        dl_layout = QVBoxLayout(self.download_dialog)
        self.download_list = QListWidget()
        dl_layout.addWidget(self.download_list)
        cancel = QPushButton('Cancel Selected Download')
        cancel.clicked.connect(self.cancel_download)
        dl_layout.addWidget(cancel)

        frame = QWidget()
        frame.setObjectName('frame')
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        self.setCentralWidget(frame)
        self.toolbar = Toolbar()
        self.toolbar.setObjectName('toolbar')
        self.toolbar.setFixedHeight(58)
        bar = QHBoxLayout(self.toolbar)
        bar.setContentsMargins(18, 10, 14, 10)
        bar.setSpacing(7)
        for color, label, action in [('#ff5f57', 'Close window', self.close),
                ('#febc2e', 'Minimize', self.showMinimized),
                ('#28c840', 'Zoom window', self.zoom_window)]:
            light = QPushButton()
            light.setToolTip(label)
            light.setAccessibleName(label)
            light.setFixedSize(13, 13)
            light.setStyleSheet(f'QPushButton {{background:{color};border:1px solid rgba(0,0,0,0.12);border-radius:6px;}} QPushButton:focus {{border:2px solid #007aff;}}')
            light.clicked.connect(action)
            bar.addWidget(light)
        bar.addSpacing(14)
        bar.addWidget(button('sidebar', 'Show Sidebar', self.toggle_sidebar))
        self.back = button('chevron-left', 'Back (Alt+Left)', lambda: self.current().back())
        self.forward = button('chevron-right', 'Forward (Alt+Right)', lambda: self.current().forward())
        bar.addWidget(self.back)
        bar.addWidget(self.forward)
        bar.addStretch(1)
        self.address = QLineEdit()
        self.address.setObjectName('address')
        self.address.setPlaceholderText('Search or enter website name')
        self.address.setAccessibleName('Search or enter website name')
        self.address.setMinimumWidth(180)
        self.address.setMaximumWidth(660)
        self.address.returnPressed.connect(self.navigate)
        bar.addWidget(self.address, 8)
        self.reload = button('arrow-clockwise', 'Reload / Stop (Ctrl+R)', self.reload_stop)
        bar.addWidget(self.reload)
        bar.addStretch(1)
        bar.addWidget(button('bookmark', 'Bookmark This Page (Ctrl+D)', self.bookmark))
        bar.addWidget(button('download', 'Downloads', self.show_downloads))
        bar.addWidget(button('plus', 'New Tab (Ctrl+T)', lambda: self.new_tab()))
        layout.addWidget(self.toolbar)
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.progress.setFixedHeight(2)
        self.progress.hide()
        layout.addWidget(self.progress)
        self.notice = QLabel()
        self.notice.setTextFormat(Qt.PlainText)
        self.notice.setWordWrap(True)
        self.notice.setMargin(10)
        self.notice.hide()
        layout.addWidget(self.notice)
        self.splitter = QSplitter()
        layout.addWidget(self.splitter, 1)
        self.sidebar = QWidget()
        self.sidebar.setObjectName('sidebar')
        self.sidebar.setMinimumWidth(170)
        self.sidebar.setMaximumWidth(300)
        side = QVBoxLayout(self.sidebar)
        title = QLabel('Private Browsing' if private else 'Web')
        title.setObjectName('sideTitle')
        side.addWidget(title)
        for label, action in [('Start Page', lambda: self.go('about:blank')),
                ('Bookmarks', lambda: self.show_library('bookmarks')),
                ('History', lambda: self.show_library('history')),
                ('New Private Window', self.private_window)]:
            item = QPushButton(label)
            item.clicked.connect(action)
            side.addWidget(item)
        side.addWidget(QLabel('OPEN TABS'))
        self.tab_list = QListWidget()
        self.tab_list.currentRowChanged.connect(self.select_tab)
        side.addWidget(self.tab_list, 1)
        self.splitter.addWidget(self.sidebar)
        content = QWidget()
        content_layout = QVBoxLayout(content)
        content_layout.setContentsMargins(0, 0, 0, 0)
        content_layout.setSpacing(0)
        self.tabs = QTabBar()
        self.tabs.setDocumentMode(True)
        self.tabs.setExpanding(True)
        self.tabs.setTabsClosable(False)
        self.tabs.setElideMode(Qt.ElideRight)
        self.tabs.currentChanged.connect(self.select_tab)
        self.tabs.tabCloseRequested.connect(self.close_tab)
        content_layout.addWidget(self.tabs)
        self.stack = QStackedWidget()
        content_layout.addWidget(self.stack, 1)
        self.splitter.addWidget(content)
        self.splitter.setSizes([210, 950])
        self.statusBar().setSizeGripEnabled(True)
        self.statusBar().hide()  # resizing is also provided by Hyprland's extended border
        self.apply_theme()
        QApplication.styleHints().colorSchemeChanged.connect(self.apply_theme)
        for keys, action in [('Ctrl+L', self.focus_address), ('Ctrl+T', self.new_tab),
                ('Ctrl+W', lambda: self.close_tab(self.tabs.currentIndex())),
                ('Ctrl+R', lambda: self.current().reload()), ('F5', lambda: self.current().reload()),
                ('Alt+Left', lambda: self.current().back()), ('Alt+Right', lambda: self.current().forward()),
                ('Ctrl+Tab', lambda: self.select_tab((self.tabs.currentIndex() + 1) % len(self.views))),
                ('Ctrl+Shift+Tab', lambda: self.select_tab((self.tabs.currentIndex() - 1) % len(self.views))),
                ('Ctrl+D', self.bookmark), ('Ctrl+J', self.show_downloads),
                ('Ctrl+Shift+N', self.private_window), ('Escape', self.escape),
                ('Ctrl++', lambda: self.zoom(0.1)), ('Ctrl+-', lambda: self.zoom(-0.1)),
                ('Ctrl+0', lambda: self.current().setZoomFactor(1.0))]:
            shortcut = QShortcut(QKeySequence(keys), self)
            shortcut.activated.connect(action)
            self.shortcut_objects.append(shortcut)
        for url in (urls or self.store.data['tabs']):
            self.add_tab(url, activate=False)
        self.select_tab(0)

    def apply_theme(self, *_):
        dark = QApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark
        bg, panel, text, field, selected = ('#242428', '#2d2d32', '#f5f5f7', '#424248', '#484852') if dark else ('#f5f5f7', '#eaeaf0', '#25252b', '#ffffff', '#d8e5f7')
        self.setStyleSheet(f'''
            QWidget {{font-family:Inter; font-size:13px; color:{text};}}
            #frame, QDialog {{background:{bg}; border-radius:12px;}}
            #toolbar, #sidebar {{background:{panel};}}
            #sideTitle {{font-size:22px;font-weight:600;padding:12px 4px;}}
            QLineEdit {{background:{field};border:1px solid #80808040;border-radius:9px;padding:7px 14px;}}
            QLineEdit:focus {{border:2px solid #589cec;padding:6px 13px;}}
            QToolButton, QPushButton {{border:0;border-radius:6px;padding:6px;background:transparent;}}
            QToolButton:hover, QPushButton:hover {{background:{selected};}}
            QToolButton:focus, QPushButton:focus {{border:1px solid #589cec;}}
            QToolButton:disabled {{color:#888;}}
            QListWidget {{background:transparent;border:0;outline:0;}}
            QListWidget::item {{padding:9px;border-radius:7px;}}
            QListWidget::item:selected {{background:{selected};color:{text};}}
            #sidebar QPushButton {{text-align:left;padding:9px;}}
            QTabBar::tab {{background:{panel};padding:10px 14px;min-width:50px;max-width:240px;border-right:1px solid #80808030;}}
            QTabBar::tab:selected {{background:{bg};}}
            QProgressBar {{border:0;background:transparent;}}
            QProgressBar::chunk {{background:#007aff;}}
            QSplitter::handle {{background:{panel};width:1px;}}
        ''')
        for btn in self.findChildren(QToolButton):
            # The shared icon set includes light-on-dark variants.
            icon_name = btn.property('symbol')
            if icon_name:
                btn.setIcon(QIcon(str(ASSETS / (icon_name + ('' if dark else '@dark') + '.svg'))))
        # Match Chromium's backing surface to the window so dark mode does not
        # flash white between navigations or while a renderer is starting.
        page_color = QColor(bg)
        for view in self.views:
            view.page().setBackgroundColor(page_color)

    def current(self):
        return self.stack.currentWidget()

    def add_tab(self, url='about:blank', activate=True):
        view = WebView(self)
        dark = QApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark
        view.page().setBackgroundColor(QColor('#242428' if dark else '#f5f5f7'))
        view.pending_url = url
        self.views.append(view)
        self.tabs.blockSignals(True)
        self.tab_list.blockSignals(True)
        self.stack.addWidget(view)
        index = self.tabs.addTab('Start Page')
        close = button('xmark', 'Close Tab', lambda: self.close_view(view))
        dark = QApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark
        close.setIcon(QIcon(str(ASSETS / ('xmark' + ('' if dark else '@dark') + '.svg'))))
        close.setFixedSize(24, 22)
        self.tabs.setTabButton(index, QTabBar.RightSide, close)
        self.tab_list.addItem('Start Page')
        view.titleChanged.connect(lambda title: self.title_changed(view, title))
        view.urlChanged.connect(lambda _: self.sync_view(view))
        view.loadProgress.connect(lambda value: self.loading(view, value))
        view.loadFinished.connect(lambda ok: self.loaded(view, ok))
        self.tabs.blockSignals(False)
        self.tab_list.blockSignals(False)
        if activate:
            self.select_tab(len(self.views) - 1)
        return view

    def new_tab(self):
        self.add_tab()
        self.focus_address()

    def select_tab(self, index):
        if not 0 <= index < len(self.views):
            return
        for widget in (self.tabs, self.tab_list):
            widget.blockSignals(True)
        self.tabs.setCurrentIndex(index)
        self.tab_list.setCurrentRow(index)
        self.stack.setCurrentIndex(index)
        for widget in (self.tabs, self.tab_list):
            widget.blockSignals(False)
        self.notice.hide()
        view = self.views[index]
        if view.pending_url is not None:
            url = view.pending_url
            view.pending_url = None
            self.load(view, url)
        self.sync_view(view)

    def close_view(self, view):
        if view in self.views:
            self.close_tab(self.views.index(view))

    def close_tab(self, index):
        if not 0 <= index < len(self.views):
            return
        if len(self.views) == 1:
            self.new_tab()
        self.tabs.blockSignals(True)
        self.tab_list.blockSignals(True)
        view = self.views.pop(index)
        self.stack.removeWidget(view)
        self.tabs.removeTab(index)
        self.tab_list.takeItem(index)
        view.stop()
        view.deleteLater()
        self.tabs.blockSignals(False)
        self.tab_list.blockSignals(False)
        self.select_tab(min(index, len(self.views) - 1))
        self.schedule_save()

    def title_changed(self, view, title):
        if view not in self.views:
            return
        index = self.views.index(view)
        title = title or 'Untitled'
        self.tabs.setTabText(index, title[:40])
        self.tabs.setTabToolTip(index, title)
        self.tab_list.item(index).setText(title)
        self.sync_view(view)

    def sync_view(self, view):
        if view != self.current():
            return
        url = view.url().toString()
        if not self.address.hasFocus():
            self.address.setText('' if url in ('about:blank', '') or url.startswith('data:') else url)
        self.back.setEnabled(view.history().canGoBack())
        self.forward.setEnabled(view.history().canGoForward())
        self.setWindowTitle((view.title() or 'Web') + (' — Private Browsing' if self.private else ' — Web'))
        self.progress.setVisible(view.page().isLoading())
        self.schedule_save()

    def focus_address(self):
        self.address.setFocus()
        self.address.selectAll()

    def navigate(self):
        try:
            url = address_url(self.address.text())
        except ValueError as error:
            self.message(str(error))
            return
        self.current().setFocus()
        self.notice.hide()
        self.go(url)

    def go(self, url):
        self.load(self.current(), url)

    def load(self, view, url):
        if url == 'about:blank':
            view.setHtml(self.start_page(), QUrl('about:blank'))
        else:
            view.setUrl(QUrl(url))

    def start_page(self):
        links = self.store.data['bookmarks'] or [
            {'title': 'Wikipedia', 'url': 'https://wikipedia.org'},
            {'title': 'DuckDuckGo', 'url': 'https://duckduckgo.com'},
            {'title': 'Arch Linux', 'url': 'https://archlinux.org'}]
        cards = ''.join(f'<a href="{html.escape(r["url"], quote=True)}"><span>{html.escape(r["title"][:1].upper())}</span>{html.escape(r["title"])}</a>' for r in links[:18])
        return f'''<!doctype html><html><head><meta name="color-scheme" content="light dark"><title>Start Page</title>
        <style>body{{margin:0;font:15px Inter,system-ui;background:light-dark(#f5f5f7,#242428);color:light-dark(#25252b,#eee)}}
        main{{max-width:820px;box-sizing:border-box;margin:10vh auto;padding:clamp(20px,4vw,42px)}}h1{{font-size:38px;letter-spacing:-1px}}p{{opacity:.65;line-height:1.6;overflow-wrap:anywhere}}section{{display:flex;gap:24px;flex-wrap:wrap;margin-top:30px}}
        a{{width:110px;text-align:center;text-decoration:none;color:inherit;font-size:13px;overflow-wrap:anywhere}}a span{{display:grid;place-items:center;margin:0 auto 12px;width:66px;height:66px;border-radius:17px;background:linear-gradient(140deg,#7db6f1,#746bb7);color:white;font-size:30px;box-shadow:0 6px 15px #0001}}a:hover span{{transform:translateY(-3px)}}
        </style></head><body><main><h1>{'Private Browsing' if self.private else 'Favorites'}</h1>
        <p>{'History and cookies stay in this window. Downloads you save remain on disk.' if self.private else 'Your corner of the web. Search from the address bar above.'}</p><section>{cards}</section></main></body></html>'''

    def show_library(self, key):
        dialog = QDialog(self)
        dialog.setWindowTitle(key.title())
        dialog.resize(560, 380)
        layout = QVBoxLayout(dialog)
        listing = QListWidget()
        for record in self.store.data[key]:
            item = QListWidgetItem(record['title'] + '\n' + record['url'])
            item.setData(Qt.UserRole, record['url'])
            listing.addItem(item)
        listing.itemActivated.connect(lambda item: (self.go(item.data(Qt.UserRole)), dialog.accept()))
        layout.addWidget(listing)
        clear = QPushButton('Remove Selected')
        def remove():
            index = listing.currentRow()
            if index >= 0:
                self.store.data[key].pop(index)
                listing.takeItem(index)
                self.schedule_save()
        clear.clicked.connect(remove)
        layout.addWidget(clear)
        dialog.exec()

    def bookmark(self):
        view = self.current()
        # During back/forward navigation Qt can update the history item/title a
        # frame before QWebEngineView.url(). Bookmark the logical current
        # history entry so a quick Ctrl+D never captures the page we just left.
        item = view.history().currentItem()
        history_url = item.url().toString() if item.isValid() else ''
        url = history_url if self.store.valid(history_url) else view.url().toString()
        if not self.store.valid(url):
            self.message('Open a website to add a bookmark.')
            return
        title = item.title() if item.isValid() and item.url().toString() == url else view.title()
        if not any(r['url'] == url for r in self.store.data['bookmarks']):
            self.store.data['bookmarks'].append({'title': title or url, 'url': url})
            self.schedule_save()
        self.message('Bookmark saved' + (' for this private window.' if self.private else '.'))

    def loading(self, view, value):
        if view == self.current():
            self.progress.setValue(value)
            self.progress.setVisible(value < 100)

    def loaded(self, view, ok):
        self.sync_view(view)
        if ok:
            self.store.visit(view.url().toString(), view.title())
            self.schedule_save()
        elif view == self.current() and view.url().scheme() in ('http', 'https'):
            self.message('This page could not be loaded. Check the address or connection, then reload.')

    def message(self, text):
        self.notice.setText(text)
        self.notice.show()

    def renderer_failed(self, view, code):
        if view == self.current():
            self.message(f'This tab stopped unexpectedly (code {code}). Press Ctrl+R to reload. Other tabs remain open.')

    def reload_stop(self):
        view = self.current()
        view.stop() if view.page().isLoading() else view.reload()

    def toggle_sidebar(self):
        self.sidebar.setVisible(not self.sidebar.isVisible())

    def zoom_window(self):
        self.showNormal() if self.isMaximized() else self.showMaximized()

    def zoom(self, delta):
        view = self.current()
        view.setZoomFactor(max(0.25, min(5.0, view.zoomFactor() + delta)))

    def set_web_fullscreen(self, enabled):
        if enabled:
            if self.fullscreen_state is None:
                self.fullscreen_state = (self.isMaximized(), self.sidebar.isVisible())
            for widget in (self.toolbar, self.tabs, self.sidebar, self.progress):
                widget.hide()
            self.showFullScreen()
            self.message('Full screen — press Esc to exit.')
        else:
            maximized, sidebar = self.fullscreen_state or (False, True)
            self.fullscreen_state = None
            self.toolbar.show(); self.tabs.show(); self.sidebar.setVisible(sidebar)
            self.showMaximized() if maximized else self.showNormal()
            self.notice.hide()

    def escape(self):
        if self.isFullScreen():
            self.current().page().triggerAction(QWebEnginePage.ExitFullScreen)
            if self.fullscreen_state is not None:
                self.set_web_fullscreen(False)
        else:
            self.current().stop()
        self.notice.hide()

    def show_downloads(self):
        self.download_dialog.show()
        self.download_dialog.raise_()

    def download(self, request):
        folder = QStandardPaths.writableLocation(QStandardPaths.DownloadLocation)
        path, _ = QFileDialog.getSaveFileName(self, 'Save Download', str(Path(folder) / Path(request.suggestedFileName()).name))
        if not path:
            request.cancel()
            return
        request.setDownloadDirectory(str(Path(path).parent))
        request.setDownloadFileName(Path(path).name)
        item = QListWidgetItem()
        self.download_list.addItem(item)
        self.downloads.append(request)
        def progress():
            total = request.totalBytes()
            size = f'{request.receivedBytes() / 1048576:.1f} MB' if total <= 0 else f'{100 * request.receivedBytes() / total:.0f}%'
            item.setText(f'{Path(path).name} — {size} — {request.state().name.removeprefix("Download")}')
            item.setToolTip(request.interruptReasonString())
        request.receivedBytesChanged.connect(progress)
        request.stateChanged.connect(progress)
        request.accept()
        progress()
        self.show_downloads()

    def cancel_download(self):
        index = self.download_list.currentRow()
        if 0 <= index < len(self.downloads):
            self.downloads[index].cancel()

    def private_window(self):
        import subprocess
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--private'], close_fds=True)

    def schedule_save(self):
        self.state_timer.start(500)

    def save(self):
        self.store.data['tabs'] = [v.pending_url if v.pending_url is not None else (v.url().toString() if self.store.valid(v.url().toString()) else 'about:blank') for v in self.views]
        try:
            self.store.save()
        except OSError:
            self.message('Browser state could not be saved. Check free disk space and folder permissions.')

    def closeEvent(self, event):
        if any(not item.isFinished() for item in self.downloads):
            if QMessageBox.question(self, 'Downloads in progress', 'Quit and cancel active downloads?') != QMessageBox.Yes:
                event.ignore()
                return
        self.state_timer.stop()
        self.save()
        for item in self.downloads:
            if not item.isFinished():
                item.cancel()
        # Delete pages before their profile to avoid Qt shutdown crashes.
        for view in self.views:
            view.stop()
            view.page().deleteLater()
        super().closeEvent(event)


def main():
    if os.geteuid() == 0:
        sys.exit('Run Web as your desktop user, not root. Chromium sandboxing remains enabled.')
    app = QApplication(sys.argv)
    app.setApplicationName('GoldenGateWeb')
    app.setDesktopFileName('org.goldengate.Web')
    private = '--private' in sys.argv
    path = Path(QStandardPaths.writableLocation(QStandardPaths.AppDataLocation))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = QLockFile(str(path / 'browser.lock'))
    if not private and not lock.tryLock(0):
        # Queue URLs for the existing process instead of opening the profile twice.
        from PySide6.QtNetwork import QLocalSocket
        import json
        socket = QLocalSocket()
        socket.connectToServer('goldengate-web-' + str(os.getuid()))
        if socket.waitForConnected(1500):
            socket.write(json.dumps(sys.argv[1:] or ['about:blank']).encode() + b'\n')
            socket.waitForBytesWritten(1500)
            return 0
        QMessageBox.warning(None, 'Web is already running', 'The browser is starting or closing. Try again in a moment.')
        return 1
    urls = []
    for value in sys.argv[1:]:
        if value != '--private':
            try:
                urls.append(address_url(value))
            except ValueError:
                pass
    browser = Browser(private=private, urls=urls or None)
    if not private:
        from PySide6.QtNetwork import QLocalServer
        import json
        server = QLocalServer(app)
        name = 'goldengate-web-' + str(os.getuid())
        QLocalServer.removeServer(name)
        server.setSocketOptions(QLocalServer.UserAccessOption)
        server.listen(name)
        def connected():
            socket = server.nextPendingConnection()
            def read():
                if not socket.canReadLine():
                    return
                try:
                    values = json.loads(bytes(socket.readLine()).decode())
                    if isinstance(values, list):
                        for value in values[:30]:
                            if isinstance(value, str):
                                browser.add_tab(address_url(value))
                    browser.showNormal()
                    browser.raise_()
                    browser.activateWindow()
                except (ValueError, TypeError):
                    pass
                socket.disconnectFromServer()
            socket.readyRead.connect(read)
            socket.disconnected.connect(socket.deleteLater)
            read()
        server.newConnection.connect(connected)
    browser.show()
    return app.exec()


if __name__ == '__main__':
    sys.exit(main())
