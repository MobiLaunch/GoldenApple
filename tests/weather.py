#!/usr/bin/env python3
"""Weather (apps/weather.qml) with its offline fixture: My Location leads the
places (from lib/location/locate.py), the large temperature shows, °C/°F
switches and is remembered, and with Location Services off no location is
asked for. Also the location helper itself: off means off."""
import json
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from PySide6.QtCore import QObject, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class Weather(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp())
        subprocess.run([sys.executable, str(ROOT / "apps/weather/tests/make-fixture.py"), str(self.temp / "wx")],
                       check=True, capture_output=True)
        (self.temp / "config/golden-gate").mkdir(parents=True)

    def tearDown(self):
        if getattr(self, "root", None) is not None:
            self.root.deleteLater(); APP.processEvents()

    def load(self, location=True):
        if not location:
            (self.temp / "config/golden-gate/privacy.json").write_text(json.dumps({"location": False}))
        env = {"HOME": str(self.temp), "USER": "test", "XDG_CONFIG_HOME": str(self.temp / "config"),
               "XDG_CACHE_HOME": str(self.temp / "cache"), "XDG_RUNTIME_DIR": str(self.temp),
               "GG_WEATHER_FIXTURE": str(self.temp / "wx"), "GG_LOCATION_FIXTURE": "29.76,-95.37,Houston",
               "GG_WEATHER_UNITS": ""}
        self.view = QQuickView()
        self.fake = preview.Preview(env, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        component = QQmlComponent(self.view.engine())
        url = QUrl.fromLocalFile(str(ROOT / "tests" / "WeatherFixture.qml"))
        component.setData(b'import QtQuick\nItem { width: 1100; height: 860; Loader { source: "../apps/weather.qml" } }', url)
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.component = component
        for _ in range(60):
            QTest.qWait(50)
            temp = self.root.findChild(QObject, "weatherTemp")
            if temp is not None and temp.property("text"):
                break
        self.temp_label = self.root.findChild(QObject, "weatherTemp")

    def app(self):
        # The item holding places: the temperature label's ancestors.
        item = self.temp_label
        while item is not None and item.property("places") is None:
            item = item.parent()
        return item

    def test_my_location_and_units(self):
        self.load()
        self.assertEqual(self.temp_label.property("text"), "28°")
        places = self.app().property("places").toVariant()
        self.assertTrue(places[0].get("current"), places)
        self.assertEqual(places[0]["name"], "Houston")
        units = self.root.findChild(QObject, "weatherUnits")
        units.clicked.emit()
        QTest.qWait(80)
        self.assertEqual(self.temp_label.property("text"), "82°")
        # What Weather writes to weather.json (the preview keeps it in memory).
        saved = json.loads(self.root.findChild(QObject, "weatherStore").property("__text"))
        self.assertEqual(saved["units"], "imperial")
        self.assertFalse(any(p.get("current") for p in saved["places"]), "My Location isn't saved: it moves")

    def test_location_services_off(self):
        self.load(location=False)
        QTest.qWait(300)
        places = self.app().property("places").toVariant()
        self.assertFalse(any(p.get("current") for p in places), places)

    def test_helper_respects_location_services(self):
        env = {**os.environ, "XDG_CONFIG_HOME": str(self.temp / "config")}
        (self.temp / "config/golden-gate/privacy.json").write_text(json.dumps({"location": False}))
        out = json.loads(subprocess.run([sys.executable, str(ROOT / "apps/lib/location/locate.py")],
                                        env=env, capture_output=True, text=True).stdout)
        self.assertEqual(out["code"], "disabled")


if __name__ == "__main__":
    unittest.main()
