#!/usr/bin/env python3
"""Scaffold and validate Editable Pets animation packs using only stdlib."""

import argparse
import json
import re
import struct
import sys
from pathlib import Path

STATES = (
    "idle",
    "running-right",
    "running-left",
    "waving",
    "jumping",
    "failed",
    "waiting",
    "running",
    "review",
)
ID_PATTERN = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def manifest(display_name: str) -> dict:
    return {
        "displayName": display_name,
        "description": f"An original {display_name} companion.",
        "layout": "animation-atlases-4x2",
        "states": {state: f"animations/{state}.png" for state in STATES},
    }


def scaffold(repo: Path, pet_id: str, display_name: str) -> None:
    if not ID_PATTERN.fullmatch(pet_id):
        raise ValueError("pet-id must use lowercase letters, digits, and single hyphens")
    if not display_name.strip():
        raise ValueError("display name cannot be empty")
    if not (repo / "pets").is_dir() or not (repo / "RonaldinhoPet" / "main.swift").is_file():
        raise ValueError(f"not an Editable Pets checkout: {repo}")
    pack = repo / "pets" / pet_id
    if pack.exists():
        raise ValueError(f"pack already exists: {pack}")
    (pack / "animations").mkdir(parents=True)
    (pack / "pet.json").write_text(json.dumps(manifest(display_name.strip()), indent=2) + "\n")
    print(pack)


def png_geometry(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:29]
    if len(data) != 29 or data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError(f"not a PNG: {path}")
    width, height, _depth, color_type, _compression, _filter, _interlace = struct.unpack(">IIBBBBB", data[16:29])
    if color_type not in (4, 6):
        raise ValueError(f"PNG has no alpha channel: {path}")
    if width % 4 or height % 2:
        raise ValueError(f"atlas must divide into a 4x2 grid: {path} ({width}x{height})")
    return width, height


def validate(pack: Path) -> None:
    manifest_path = pack / "pet.json"
    try:
        data = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"invalid manifest {manifest_path}: {error}") from error
    if not isinstance(data.get("displayName"), str) or not data["displayName"].strip():
        raise ValueError("manifest displayName must be a non-empty string")
    expected = {state: f"animations/{state}.png" for state in STATES}
    if data.get("layout") != "animation-atlases-4x2" or data.get("states") != expected:
        raise ValueError("manifest must declare the standard nine-state 4x2 layout")
    geometries = {png_geometry(pack / path) for path in expected.values()}
    if len(geometries) != 1:
        raise ValueError(f"all atlases must have the same dimensions: {sorted(geometries)}")
    width, height = geometries.pop()
    print(f"Valid pet pack: {pack} (9 atlases, {width}x{height})")


def main() -> int:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("scaffold")
    create.add_argument("repo", type=Path)
    create.add_argument("pet_id")
    create.add_argument("display_name")
    check = commands.add_parser("validate")
    check.add_argument("pack", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "scaffold":
            scaffold(args.repo.resolve(), args.pet_id, args.display_name)
        else:
            validate(args.pack.resolve())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
