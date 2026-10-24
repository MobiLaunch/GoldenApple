#!/usr/bin/env python3
"""The firewall (CS2-017): public networks reach nothing, private ones can
reach AirDrop and the AirPlay Receiver.

The NetworkManager dispatcher script runs against stub nmcli and
firewall-cmd: wired networks and Wi-Fi with a password go to "home", open
Wi-Fi, WPA Enterprise and hotspots stay "public", and a zone the connection
names itself always wins. The zones, services, package list, ISO and
installer agree with each other and with the ports AirDrop and UxPlay use.
"""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / "distro/archiso/overlay"
DISPATCHER = OVERLAY / "etc/NetworkManager/dispatcher.d/50-citronos-zone"

NMCLI = r'''#!/usr/bin/env python3
import json, os, sys
# nmcli -g FIELD connection show uuid UUID
conn = json.load(open(os.environ["STUB_CONNECTION"]))
print(conn.get(sys.argv[2], ""))
'''
FIREWALL_CMD = '''#!/bin/sh
printf '%s\\n' "$*" >> "$STUB_LOG"
'''


class Dispatcher(unittest.TestCase):
    def run_for(self, connection: dict, action="up"):
        with tempfile.TemporaryDirectory() as t:
            t = Path(t)
            (t / "nmcli").write_text(NMCLI)
            (t / "firewall-cmd").write_text(FIREWALL_CMD)
            for f in ("nmcli", "firewall-cmd"):
                (t / f).chmod(0o755)
            (t / "conn.json").write_text(json.dumps(connection))
            env = {"PATH": f"{t}:/usr/bin:/bin", "STUB_CONNECTION": str(t / "conn.json"),
                   "STUB_LOG": str(t / "log"), "CONNECTION_UUID": "1234"}
            p = subprocess.run(["sh", str(DISPATCHER), "wlan0", action], env=env, capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
            return (t / "log").read_text().splitlines() if (t / "log").exists() else []

    def zone(self, **connection):
        calls = self.run_for(connection)
        self.assertEqual(len(calls), 1, calls)
        self.assertIn("--change-interface=wlan0", calls[0])
        return re.search(r"--zone=(\S+)", calls[0]).group(1)

    def test_private_networks_are_home(self):
        self.assertEqual(self.zone(**{"connection.type": "802-3-ethernet"}), "home")
        for key in ("wpa-psk", "sae"):
            self.assertEqual(self.zone(**{"connection.type": "802-11-wireless", "802-11-wireless.mode": "infrastructure",
                                          "802-11-wireless-security.key-mgmt": key}), "home", key)

    def test_shared_networks_are_public(self):
        for key in ("", "none", "owe", "wpa-eap", "wpa-eap-suite-b-192"):
            self.assertEqual(self.zone(**{"connection.type": "802-11-wireless", "802-11-wireless.mode": "infrastructure",
                                          "802-11-wireless-security.key-mgmt": key}), "public", key)
        # This computer's own hotspot, and anything that isn't Wi-Fi or wired.
        self.assertEqual(self.zone(**{"connection.type": "802-11-wireless", "802-11-wireless.mode": "ap",
                                      "802-11-wireless-security.key-mgmt": "wpa-psk"}), "public")
        self.assertEqual(self.zone(**{"connection.type": "gsm"}), "public")

    def test_the_connections_own_zone_wins(self):
        self.assertEqual(self.run_for({"connection.type": "802-11-wireless", "connection.zone": "public",
                                       "802-11-wireless-security.key-mgmt": "wpa-psk"}), [])

    def test_only_when_a_network_comes_up(self):
        self.assertEqual(self.run_for({"connection.type": "802-3-ethernet"}, action="down"), [])


def service_ports(name):
    root = ET.parse(OVERLAY / f"etc/firewalld/services/{name}.xml").getroot()
    return {(p.get("protocol"), p.get("port")) for p in root.iter("port")}


def zone_services(name):
    root = ET.parse(OVERLAY / f"etc/firewalld/zones/{name}.xml").getroot()
    return {s.get("name") for s in root.iter("service")}


class Image(unittest.TestCase):
    def test_airdrop_service_is_airdrops_port(self):
        sys.path.insert(0, str(ROOT / "apps/airdrop"))
        old = os.environ.pop("GG_AIRDROP_PORT", None)
        try:
            import airdropd
        finally:
            if old is not None:
                os.environ["GG_AIRDROP_PORT"] = old
        self.assertEqual(service_ports("citronos-airdrop"), {("tcp", str(airdropd.PORT)), ("udp", str(airdropd.PORT))})

    def test_airplay_service_is_uxplays_fixed_ports(self):
        sys.path.insert(0, str(ROOT / "apps/mirroring"))
        import airplay
        self.assertIn("-p", airplay.command({"requirePin": False, "fullScreen": False}, "Test"))
        self.assertEqual(service_ports("citronos-airplay"),
                         {("tcp", "7000"), ("tcp", "7001"), ("tcp", "7100"), ("udp", "6000"), ("udp", "6001"), ("udp", "7011")})

    def test_zones(self):
        public, home = zone_services("public"), zone_services("home")
        self.assertFalse({"citronos-airdrop", "citronos-airplay", "ssh"} & public, public)
        self.assertLessEqual({"citronos-airdrop", "citronos-airplay", "mdns"}, home)

    def test_installed_and_enabled(self):
        packages = (ROOT / "distro/archiso/packages.x86_64").read_text().split()
        self.assertIn("firewalld", packages)
        build = (ROOT / "distro/archiso/build.sh").read_text()
        self.assertIn('firewalld.service "$WANTS/firewalld.service"', build)
        self.assertIn('["/etc/NetworkManager/dispatcher.d/50-citronos-zone"]="0:0:755"', build)
        self.assertIn('"firewalld.service"', (ROOT / "apps/installer/helper.py").read_text())
        self.assertTrue(os.access(DISPATCHER, os.X_OK))


if __name__ == "__main__":
    unittest.main(verbosity=2)
