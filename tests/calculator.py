#!/usr/bin/env python3
"""Calculator (apps/calculator.qml), driven as a person would, by keys and
its buttons' functions: Basic precedence, Scientific parentheses, functions in
degrees and radians and memory, Programmer hex and bit switches, unit
conversion, and the window growing for each mode."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import sys
import tempfile
import unittest
from PySide6.QtCore import QCoreApplication, QEvent, QMetaObject, QObject, Qt, QUrl, Q_ARG
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class Calculator(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.view = QQuickView()
        self.fake = preview.Preview({"HOME": self.temp.name, "USER": "test"}, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        component = QQmlComponent(self.view.engine())
        url = QUrl.fromLocalFile(str(ROOT / "tests" / "CalculatorFixture.qml"))
        component.setData(b'import QtQuick\nItem { width: 900; height: 700; Loader { source: "../apps/calculator.qml" } }', url)
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.component = component
        QTest.qWait(60)
        self.calc = self.root.findChild(QObject, "calculator")
        self.display = self.root.findChild(QObject, "calcDisplay")
        self.assertIsNotNone(self.calc)

    def tearDown(self):
        self.root.deleteLater(); APP.processEvents()
        self.temp.cleanup()

    def type(self, text):
        for ch in text:
            key = {"\n": Qt.Key_Return, "\b": Qt.Key_Backspace}.get(ch, 0)
            for kind in (QEvent.KeyPress, QEvent.KeyRelease):
                QCoreApplication.sendEvent(self.calc, QKeyEvent(kind, key, Qt.NoModifier, "" if key else ch))

    def call(self, name, *args):
        QMetaObject.invokeMethod(self.calc, name, *[Q_ARG("QVariant", a) for a in args])

    def shown(self):
        return self.display.property("text")

    def test_basic_precedence_and_history(self):
        self.type("2+3*4\n")
        self.assertEqual(self.shown(), "14")
        self.assertEqual(len(self.calc.property("history").toVariant()), 1)
        self.type("\x1b")

    def test_scientific_parentheses_functions_and_memory(self):
        self.calc.setProperty("mode", "scientific")
        self.type("(2+3)*4\n")
        self.assertEqual(self.shown(), "20")
        self.type("30"); self.call("fn", "sin")
        self.assertEqual(self.shown(), "0.5", "degrees by default")
        self.calc.setProperty("rad", True)
        self.call("constant", 3.141592653589793); self.call("fn", "cos")
        self.assertEqual(self.shown(), "-1")
        self.type("2^10\n")
        self.assertEqual(self.shown(), "1,024")
        self.call("memoryKey", "m+"); self.type("5\n"); self.call("memoryKey", "mr")
        self.assertEqual(self.shown(), "1,024")

    def test_programmer_hex_bits_and_bases(self):
        self.calc.setProperty("mode", "programmer")
        self.call("setBase", 16)
        self.type("ff&f0\n")
        self.assertEqual(self.shown(), "F0")
        self.call("toggleBit", 0)
        self.assertEqual(self.shown(), "F1")
        self.call("setBase", 10)
        self.assertEqual(self.shown(), "241")
        self.call("setBase", 2)
        self.assertEqual(self.shown(), "1111 0001")
        self.type("\x1b\x1b"); self.call("setBase", 10)
        self.type("1/0\n")
        self.assertEqual(self.shown(), "Error")

    def test_conversion(self):
        self.calc.setProperty("convert", True)
        self.call("setCategory", "Temperature")
        self.calc.setProperty("fromUnit", "Celsius"); self.calc.setProperty("toUnit", "Fahrenheit")
        self.type("100")
        self.assertEqual(self.root.findChild(QObject, "calcConverted").property("text"), "212")

    def test_window_grows_for_each_mode(self):
        win = self.calc.parent()
        while win is not None and win.property("fixed") is None:
            win = win.parent()
        self.assertIsNotNone(win)
        sizes = {}
        for mode in ("basic", "scientific", "programmer"):
            self.calc.setProperty("mode", mode); QTest.qWait(10)
            sizes[mode] = win.property("fixed")
        self.assertLess(sizes["basic"].width(), sizes["programmer"].width())
        self.assertLess(sizes["programmer"].width(), sizes["scientific"].width())
        self.assertLess(sizes["basic"].height(), sizes["programmer"].height())


if __name__ == "__main__":
    unittest.main()
