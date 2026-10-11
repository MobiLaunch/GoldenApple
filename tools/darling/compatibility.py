#!/usr/bin/env python3
"""Inspect the checked-in Darling roadmap; refuse unsupported compatibility claims."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "third_party/darling/compatibility.json"


def validate(data: dict, root: Path = ROOT) -> None:
    if data.get("schema") != 1:
        raise ValueError("Unsupported compatibility schema")
    milestones = {m["id"]: m for m in data["milestones"]}
    if len(milestones) != len(data["milestones"]):
        raise ValueError("Duplicate milestone ID")
    visiting, visited = set(), set()

    def visit(key):
        if key in visiting:
            raise ValueError("Milestone dependency cycle")
        if key not in milestones:
            raise ValueError(f"Unknown milestone: {key}")
        if key in visited:
            return
        visiting.add(key)
        milestone = milestones[key]
        if milestone["status"] not in ("planned", "in-progress", "blocked", "validated"):
            raise ValueError(f"Invalid milestone status: {key}")
        for dependency in milestone["requires"]:
            visit(dependency)
        checks = milestone["checks"]
        if not checks or len({c["id"] for c in checks}) != len(checks):
            raise ValueError(f"Missing or duplicate checks: {key}")
        for check in checks:
            if check["status"] not in ("pending", "passed", "failed"):
                raise ValueError(f"Invalid evidence status: {key}")
            if check["status"] in ("passed", "failed") and not check["evidence"]:
                raise ValueError(f"Result requires evidence: {key}/{check['id']}")
        if milestone["status"] == "validated":
            if any(c["status"] != "passed" for c in checks):
                raise ValueError(f"Cannot validate {key}: checks have not all passed")
            if any(milestones[d]["status"] != "validated" for d in milestone["requires"]):
                raise ValueError(f"Cannot validate {key}: prerequisites are unvalidated")
        for filename in milestone["files"]:
            path = (root / filename).resolve()
            if root.resolve() not in path.parents or not path.is_file():
                raise ValueError(f"Missing or unsafe milestone file: {filename}")
        visiting.remove(key)
        visited.add(key)

    for key in milestones:
        visit(key)
    ids = set()
    for target in data["targets"]:
        if target["id"] in ids:
            raise ValueError("Duplicate target ID")
        ids.add(target["id"])
        if target["status"] not in ("unverified", "blocked", "supported"):
            raise ValueError("Invalid target status")
        if target["milestone"] not in milestones:
            raise ValueError("Target requires an unknown milestone")
        if target["status"] == "supported":
            if target["blockers"] or milestones[target["milestone"]]["status"] != "validated":
                raise ValueError(f"Cannot label {target['id']} supported without validated workflow evidence")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "list", "target"))
    parser.add_argument("id", nargs="?")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    data = json.loads(MANIFEST.read_text())
    validate(data)
    if args.action == "check":
        print("PASS: compatibility milestones, dependencies and evidence gates")
        return
    if args.action == "target":
        target = next((t for t in data["targets"] if t["id"] == args.id), None)
        if target is None:
            parser.error("Choose a target: " + ", ".join(t["id"] for t in data["targets"]))
        if args.json:
            print(json.dumps(target, indent=2))
        else:
            print(f"{target['name']}: {target['status']} ({target['milestone']})")
            for blocker in target["blockers"]:
                print("  - " + blocker)
        return
    if args.json:
        print(json.dumps(data, indent=2))
    else:
        for milestone in data["milestones"]:
            done = sum(c["status"] == "passed" for c in milestone["checks"])
            print(f"{milestone['id']}: {milestone['name']} — {milestone['status']} ({done}/{len(milestone['checks'])} checks)")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Invalid compatibility record: {error}", file=sys.stderr)
        sys.exit(1)
