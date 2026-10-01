"""Golden Gate widget adapters for the isolated Qt WebEngine browser.

Web intentionally stays outside Quickshell so Chromium renderer failures cannot
take down the desktop. These adapters keep its controls, icons and metrics
centralized instead of constructing one-off Qt widgets throughout browser.py.
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable

from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QLineEdit, QPushButton, QToolButton, QWidget

ASSETS = Path(__file__).resolve().parents[1] / "lib/assets/symbols"


def symbol_path(symbol: str, dark: bool) -> Path:
    suffix = "" if dark else "@dark"
    themed = ASSETS / f"{symbol}{suffix}.svg"
    return themed if themed.exists() else ASSETS / f"{symbol}.svg"


class GGToolButton(QToolButton):
    def __init__(self, symbol: str, label: str, action: Callable[[], None], parent: QWidget | None = None):
        super().__init__(parent)
        self.symbol_name = symbol
        self.setProperty("symbol", symbol)
        self.setToolTip(label)
        self.setAccessibleName(label)
        self.setFixedSize(32, 30)
        self.clicked.connect(action)

    def apply_icon(self, dark: bool) -> None:
        path = symbol_path(self.symbol_name, dark)
        if path.exists():
            self.setIcon(QIcon(str(path)))
            self.setText("")
        else:
            self.setIcon(QIcon())
            self.setText(self.toolTip())


class GGButton(QPushButton):
    def __init__(self, text: str = "", action: Callable[[], None] | None = None, parent: QWidget | None = None):
        super().__init__(text, parent)
        self.setAccessibleName(text)
        if action is not None:
            self.clicked.connect(action)


class GGLineEdit(QLineEdit):
    def __init__(self, placeholder: str = "", parent: QWidget | None = None):
        super().__init__(parent)
        if placeholder:
            self.setPlaceholderText(placeholder)
            self.setAccessibleName(placeholder)


def traffic_light(color: str, label: str, action: Callable[[], None], parent: QWidget | None = None) -> GGButton:
    light = GGButton("", action, parent)
    light.setProperty("trafficLight", True)
    light.setProperty("trafficColor", color)
    light.setToolTip(label)
    light.setAccessibleName(label)
    light.setFixedSize(13, 13)
    # The three semantic colors are data, not independent widget styling.
    light.setStyleSheet(
        "QPushButton {"
        f"background:{color};"
        "border:1px solid rgba(0,0,0,0.12);"
        "border-radius:6px;"
        "padding:0;"
        "}"
        "QPushButton:focus {border:2px solid #007aff;}"
        "QPushButton:pressed {border:1px solid rgba(0,0,0,0.30);}"
    )
    return light


def palette(dark: bool) -> dict[str, str]:
    if dark:
        return {
            "bg": "#242428",
            "panel": "#2d2d32",
            "text": "#f5f5f7",
            "field": "#424248",
            "selected": "#484852",
            "secondary": "#aeb0b6",
        }
    return {
        "bg": "#f5f5f7",
        "panel": "#eaeaf0",
        "text": "#25252b",
        "field": "#ffffff",
        "selected": "#d8e5f7",
        "secondary": "#6e6e73",
    }


def stylesheet(dark: bool) -> str:
    p = palette(dark)
    return f"""
        QWidget {{
            font-family: Inter;
            font-size: 13px;
            color: {p['text']};
        }}
        #frame, QDialog {{
            background: {p['bg']};
            border-radius: 12px;
        }}
        #toolbar, #sidebar {{
            background: {p['panel']};
        }}
        #sideTitle {{
            font-size: 22px;
            font-weight: 600;
            padding: 12px 4px;
        }}
        QLineEdit {{
            background: {p['field']};
            border: 1px solid #80808040;
            border-radius: 9px;
            padding: 7px 14px;
            selection-background-color: #007aff55;
        }}
        QLineEdit:focus {{
            border: 2px solid #589cec;
            padding: 6px 13px;
        }}
        QToolButton, QPushButton {{
            border: 0;
            border-radius: 7px;
            padding: 6px;
            background: transparent;
        }}
        QToolButton:hover, QPushButton:hover {{
            background: {p['selected']};
        }}
        QToolButton:pressed, QPushButton:pressed {{
            background: #80808032;
        }}
        QToolButton:focus, QPushButton:focus {{
            border: 1px solid #589cec;
        }}
        QToolButton:disabled, QPushButton:disabled {{
            color: #888888;
        }}
        QListWidget {{
            background: transparent;
            border: 0;
            outline: 0;
        }}
        QListWidget::item {{
            padding: 9px;
            border-radius: 7px;
        }}
        QListWidget::item:selected {{
            background: {p['selected']};
            color: {p['text']};
        }}
        #sidebar QPushButton {{
            text-align: left;
            padding: 9px;
        }}
        QTabBar::tab {{
            background: {p['panel']};
            padding: 10px 14px;
            min-width: 50px;
            max-width: 240px;
            border-right: 1px solid #80808030;
        }}
        QTabBar::tab:selected {{
            background: {p['bg']};
        }}
        QProgressBar {{
            border: 0;
            background: transparent;
        }}
        QProgressBar::chunk {{
            background: #007aff;
        }}
        QSplitter::handle {{
            background: {p['panel']};
            width: 1px;
        }}
    """


def refresh_icons(root: QWidget, dark: bool) -> None:
    for button in root.findChildren(GGToolButton):
        button.apply_icon(dark)
