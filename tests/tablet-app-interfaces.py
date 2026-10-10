#!/usr/bin/env python3
"""Tablet-mode responsive app contracts: one OS, adaptive touch layouts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / name).read_text()


class TabletApps(unittest.TestCase):
    def test_shared_window_watches_runtime_preferences(self):
        q = source("apps/lib/AppWindow.qml")
        self.assertIn("readonly property bool tabletCompact: tabletEnabled && width < 960", q)
        self.assertIn("watchChanges: true", q)
        self.assertIn("tablet?.enabled === true", q)
        self.assertIn('Quickshell.env("GG_TABLET_PREVIEW")', q)

    def test_touch_target_sizes_are_shared_and_generated(self):
        qml = source("apps/lib/theme/qmldir")
        gen = source("design/build.mjs")
        controls = source("apps/lib/ToolbarButton.qml")
        rows = source("apps/lib/SidebarRow.qml")
        self.assertIn("singleton Touch 1.0 Touch.qml", qml)
        self.assertIn("singleton Touch 1.0 Touch.qml", gen)
        self.assertIn("implicitHeight: Touch.enabled ? 44", controls)
        self.assertIn("round ? (Touch.enabled ? 44 : 36)", controls)
        self.assertIn("Touch.enabled ? Math.max(46", rows)
        state = source("apps/lib/theme/Touch.qml")
        self.assertIn("onFileChanged: reload()", state)
        self.assertIn('tablet?.enabled === true', state)

    def test_files_and_photos_collapse_sidebars_only_on_tablet(self):
        files = source("apps/files.qml")
        photos = source("apps/photos.qml")
        self.assertIn("property bool sidebarShown: !win.tabletCompact", files)
        self.assertIn("sidebarShown ? (win.tabletCompact ?", files)
        self.assertIn("property bool sidebarOpen: !win.tabletCompact", photos)
        self.assertIn("app.sidebarOpen ? (win.tabletCompact ?", photos)

    def test_mail_adapts_to_single_column_and_back(self):
        mail = source("apps/mail.qml")
        self.assertIn("readonly property bool compactReading: win.tabletCompact || width < 700", mail)
        self.assertIn('symbol: "chevron-left"', mail)
        self.assertIn("onClicked: mail.leaveMessage()", mail)

    def test_notes_list_to_full_editor_has_safe_back(self):
        notes = source("apps/notes.qml")
        self.assertIn("property bool mobileShowingNote: false", notes)
        self.assertIn("tabletNotesBack", notes)
        self.assertIn("win.whenSaved(() => app.mobileShowingNote = false)", notes)
        self.assertIn("visible: !win.tabletCompact || !app.mobileShowingNote", notes)
        self.assertIn("visible: !win.tabletCompact || app.mobileShowingNote", notes)

    def test_messages_and_settings_have_category_back_navigation(self):
        messages = source("apps/messages.qml")
        settings = source("apps/settings.qml")
        self.assertIn("tabletMessagesBack", messages)
        self.assertIn('app.currentKey = ""', messages)
        self.assertIn("!app.currentKey && !app.composing ? win.width : 0", messages)
        self.assertIn("property bool showMobileCategories: true", settings)
        self.assertIn("if (win.tabletCompact) showMobileCategories = false", settings)
        self.assertIn("app.showMobileCategories ? win.width : 0", settings)

    def test_calendar_and_music_can_reveal_optional_navigation(self):
        calendar = source("apps/calendar.qml")
        music = source("apps/music.qml")
        self.assertIn("property bool tabletAgendaShown: false", calendar)
        self.assertIn("win.tabletAgendaShown = !win.tabletAgendaShown", calendar)
        self.assertIn("property bool showMobileNavigation: false", music)
        self.assertIn("win.showMobileNavigation = false", music)
        self.assertIn("win.showMobileNavigation = !win.showMobileNavigation", music)


if __name__ == "__main__":
    unittest.main(verbosity=2)
