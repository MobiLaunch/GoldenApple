#!/usr/bin/env python3
"""Maps (apps/maps.qml) offline: your location (the blue dot) from
lib/location/locate.py, directions starting from My Location, Find Nearby,
Favorites remembered in maps.json, Share and Copy Coordinates, and the scale
bar's lengths."""
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
from PySide6.QtCore import QMetaObject, QObject, QUrl, Q_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


def feature(name, lon, lat, **props):
    return {"type": "Feature", "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": dict(name=name, city="Houston", state="Texas", country="United States", **props)}


def write_fixture(d: Path):
    d.mkdir(parents=True)
    (d / "search.json").write_text(json.dumps({"features": [
        feature("Blue Bottle", -95.36, 29.75, osm_key="amenity", osm_value="cafe"),
        feature("Common Bond", -95.39, 29.74, osm_key="amenity", osm_value="cafe")]}))
    (d / "reverse.json").write_text(json.dumps({"features": [feature("", -95.37, 29.76, street="Main St", housenumber="1000")]}))
    (d / "route.json").write_text(json.dumps({"code": "Ok", "routes": [{
        "distance": 3200, "duration": 540,
        "geometry": {"type": "LineString", "coordinates": [[-95.37, 29.76], [-95.36, 29.75]]},
        "legs": [{"steps": []}]}]}))


class Maps(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp())
        write_fixture(self.temp / "fx")
        (self.temp / "config/golden-gate").mkdir(parents=True)

    def tearDown(self):
        if getattr(self, "root", None) is not None:
            self.root.deleteLater(); APP.processEvents()

    def load(self, location=True):
        if not location:
            (self.temp / "config/golden-gate/privacy.json").write_text(json.dumps({"location": False}))
        env = {"HOME": str(self.temp), "USER": "test", "XDG_CONFIG_HOME": str(self.temp / "config"),
               "XDG_CACHE_HOME": str(self.temp / "cache"), "XDG_RUNTIME_DIR": str(self.temp),
               "GG_MAPS_FIXTURE": str(self.temp / "fx"), "GG_LOCATION_FIXTURE": "29.76,-95.37,Houston"}
        self.view = QQuickView()
        self.fake = preview.Preview(env, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        component = QQmlComponent(self.view.engine())
        url = QUrl.fromLocalFile(str(ROOT / "tests" / "MapsFixture.qml"))
        component.setData(b'import QtQuick\nItem { width: 1200; height: 800; Loader { source: "../apps/maps.qml" } }', url)
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.component = component
        self.button = None
        for _ in range(40):
            QTest.qWait(50)
            self.button = self.root.findChild(QObject, "mapsLocate")
            if self.button is not None:
                break
        self.assertIsNotNone(self.button)
        self.app = self.button
        while self.app is not None and self.app.property("favorites") is None:
            self.app = self.app.parent()
        self.assertIsNotNone(self.app)

    def value(self, name):
        v = self.app.property(name)
        return v.toVariant() if hasattr(v, "toVariant") else v

    def wait_for(self, check, ms=4000):
        for _ in range(ms // 50):
            if check():
                return True
            QTest.qWait(50)
        return check()

    def call(self, name, *args):
        QMetaObject.invokeMethod(self.app, name, *[Q_ARG("QVariant", a) for a in args])

    def test_my_location_and_directions_from_it(self):
        self.load()
        self.assertTrue(self.wait_for(lambda: self.value("here")), "located on launch")
        here = self.value("here")
        self.assertAlmostEqual(here["lat"], 29.76)
        self.assertTrue(here["current"])
        dot = [o for o in self.root.findChildren(QObject) if o.property("accuracy") is not None and o.property("view") is not None]
        self.assertTrue(dot and dot[0].property("visible"), "the blue dot shows")
        # The location button flies the map there.
        self.button.clicked.emit()
        self.call("startDirections", {"name": "Blue Bottle", "address": "", "lat": 29.75, "lon": -95.36, "kind": "cafe", "key": "amenity"})
        self.assertEqual(self.value("from")["name"], "My Location")
        self.assertTrue(self.wait_for(lambda: self.value("routes")), "a route from the fixture")

    def test_location_services_off(self):
        self.load(location=False)
        self.assertTrue(self.wait_for(lambda: self.value("locateError")))
        self.assertFalse(self.value("here"))

    def test_find_nearby_favorites_and_sharing(self):
        self.load()
        self.call("nearby", {"name": "Coffee", "tag": "amenity:cafe", "symbol": "cup", "tint": "#a2845e"})
        self.assertTrue(self.wait_for(lambda: len(self.value("results") or []) == 2))
        self.assertEqual(self.value("nearbyName"), "Coffee")
        first = self.value("results")[0]
        self.call("toggleFavorite", first)
        self.assertTrue(self.wait_for(lambda: self.value("favorites")))
        self.assertEqual(self.value("favorites")[0]["name"], "Blue Bottle")
        store = [o for o in self.root.findChildren(QObject) if o.property("__text") is not None]
        saved = next((json.loads(o.property("__text")) for o in store if "favorites" in (o.property("__text") or "")), None)
        self.assertIsNotNone(saved, "favorites written to maps.json")
        self.assertEqual(saved["favorites"][0]["name"], "Blue Bottle")
        # Toggling again removes it.
        self.call("toggleFavorite", first)
        self.assertFalse(self.value("favorites"))


class Api(unittest.TestCase):
    """The pure helpers in apps/maps/api.js, under node."""

    def node(self, expr):
        # api.js declares top-level vars and functions: evaluate it in this scope.
        script = (f"const fs=require('fs');eval(fs.readFileSync({json.dumps(str(ROOT / 'apps/maps/api.js'))},'utf8')"
                  f".replace(/^\\.pragma.*$/m,''));console.log(JSON.stringify({expr}))")
        return json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)

    def test_scale_bar(self):
        bar = self.node("scaleBar(0, 15, 100, false)")
        self.assertTrue(bar["label"].endswith(" m") or bar["label"].endswith(" km"), bar)
        self.assertLessEqual(bar["px"], 100)
        self.assertGreater(bar["px"], 30)
        self.assertIn(self.node("scaleBar(40, 10, 100, true)")["label"].split(" ")[1], ("mi", "ft"))

    def test_share_and_nearby_urls(self):
        self.assertEqual(self.node("shareUrl({lat: 29.76, lon: -95.37})"),
                         "https://www.openstreetmap.org/?mlat=29.76000&mlon=-95.37000#map=17/29.76000/-95.37000")
        url = self.node("nearbyUrl(NEARBY[1], 29.76, -95.37)")
        self.assertIn("photon", url)
        self.assertIn("lat=29.76", url)


if __name__ == "__main__":
    unittest.main()
