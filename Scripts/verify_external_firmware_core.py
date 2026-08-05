#!/usr/bin/env python3
"""Verify that a built VICE core contains no exact proprietary ROM payloads.

Unlike the removed v0.2.1 scrubber, this script never modifies the Mach-O file.
It only scans and fails the build if source firmware bytes are present.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

FIRMWARE_SIZES = {4096, 8192, 16384, 32768, 65536}
REQUIRED_SOURCE_CATEGORIES = {"basic", "kernal", "chargen", "drive"}


@dataclass
class Candidate:
    digest: str
    payload: bytes
    paths: list[str] = field(default_factory=list)
    categories: set[str] = field(default_factory=set)


def category_for(path: Path, root: Path) -> set[str]:
    relative = path.relative_to(root)
    name = path.name.lower()
    categories: set[str] = set()
    if relative.parts and relative.parts[0].upper() == "DRIVES":
        categories.add("drive")
    if "basic" in name:
        categories.add("basic")
    if "kernal" in name or "kernel" in name:
        categories.add("kernal")
    if "chargen" in name or "character" in name:
        categories.add("chargen")
    return categories


def collect_candidates(source_root: Path) -> dict[str, Candidate]:
    data_root = source_root / "vice" / "data"
    candidates: dict[str, Candidate] = {}
    found_categories: set[str] = set()

    for search_root in (data_root / "C64", data_root / "DRIVES"):
        if not search_root.is_dir():
            raise RuntimeError(f"Expected firmware directory not found: {search_root}")
        for path in sorted(search_root.rglob("*")):
            if not path.is_file() or path.stat().st_size not in FIRMWARE_SIZES:
                continue
            categories = category_for(path, data_root)
            if not categories:
                continue
            payload = path.read_bytes()
            digest = hashlib.sha256(payload).hexdigest()
            candidate = candidates.setdefault(digest, Candidate(digest=digest, payload=payload))
            candidate.paths.append(str(path.relative_to(source_root)))
            candidate.categories.update(categories)
            found_categories.update(categories)

    missing = REQUIRED_SOURCE_CATEGORIES - found_categories
    if missing:
        raise RuntimeError(
            "Unable to construct a complete verification set from VICE source; missing categories: "
            + ", ".join(sorted(missing))
        )
    return candidates


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    if not args.core.is_file():
        raise RuntimeError(f"Core not found: {args.core}")
    candidates = collect_candidates(args.source)
    binary = args.core.read_bytes()

    detected: list[dict[str, object]] = []
    for candidate in candidates.values():
        occurrences = binary.count(candidate.payload)
        if occurrences:
            detected.append(
                {
                    "sha256": candidate.digest,
                    "size": len(candidate.payload),
                    "occurrences": occurrences,
                    "categories": sorted(candidate.categories),
                    "source_paths": candidate.paths,
                }
            )

    report = {
        "core": str(args.core),
        "core_size": len(binary),
        "candidate_payloads_scanned": len(candidates),
        "detected_payloads": detected,
        "verification": "passed" if not detected else "failed",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if detected:
        summary = ", ".join(
            f"{item['categories']} ({item['sha256']})" for item in detected
        )
        raise RuntimeError(
            "The compiled core still contains exact firmware payloads. "
            "The source patch is incomplete; refusing to use this build: " + summary
        )

    print(
        f"Verified {len(candidates)} firmware payload(s): none is embedded in {args.core.name}."
    )
    print(f"Verification report: {args.report}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
