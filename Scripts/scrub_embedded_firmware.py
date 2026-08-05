#!/usr/bin/env python3
"""Remove exact Commodore firmware payloads embedded in a built VICE core.

The VICE libretro build currently embeds firmware data from vice/data. POKE64
uses external, user-imported firmware instead. This script scans the generated
Mach-O dylib for exact byte-for-byte copies of firmware files in the upstream
C64 and DRIVES data directories and replaces each occurrence with zero bytes.
It then verifies that none of those exact payloads remains in the core.

This is intentionally a post-link operation: the dylib has not yet been signed.
The Xcode embed phase signs the resulting file later.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

FIRMWARE_SIZES = {4096, 8192, 16384, 32768, 65536}
REQUIRED_CATEGORIES = {"basic", "kernal", "chargen", "drive"}


@dataclass
class Candidate:
    digest: str
    payload: bytes
    paths: list[str] = field(default_factory=list)
    categories: set[str] = field(default_factory=set)
    occurrences: int = 0


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
    search_roots = [data_root / "C64", data_root / "DRIVES"]
    candidates: dict[str, Candidate] = {}

    for search_root in search_roots:
        if not search_root.is_dir():
            raise RuntimeError(f"Expected firmware directory not found: {search_root}")

        for path in sorted(search_root.rglob("*")):
            if not path.is_file():
                continue
            size = path.stat().st_size
            if size not in FIRMWARE_SIZES:
                continue

            categories = category_for(path, data_root)
            if not categories:
                continue

            payload = path.read_bytes()
            digest = hashlib.sha256(payload).hexdigest()
            candidate = candidates.get(digest)
            if candidate is None:
                candidate = Candidate(digest=digest, payload=payload)
                candidates[digest] = candidate
            candidate.paths.append(str(path.relative_to(source_root)))
            candidate.categories.update(categories)

    if not candidates:
        raise RuntimeError("No firmware-sized files were found in vice/data/C64 or vice/data/DRIVES")
    return candidates


def replace_all(binary: bytearray, needle: bytes) -> int:
    count = 0
    offset = 0
    replacement = b"\x00" * len(needle)
    while True:
        position = binary.find(needle, offset)
        if position < 0:
            return count
        binary[position : position + len(needle)] = replacement
        count += 1
        offset = position + len(needle)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    if not args.core.is_file():
        raise RuntimeError(f"Core not found: {args.core}")
    if not args.source.is_dir():
        raise RuntimeError(f"VICE source directory not found: {args.source}")

    candidates = collect_candidates(args.source)
    core = bytearray(args.core.read_bytes())
    original_size = len(core)

    found_categories: set[str] = set()
    scrubbed: list[dict[str, object]] = []

    for candidate in candidates.values():
        count = replace_all(core, candidate.payload)
        candidate.occurrences = count
        if count:
            found_categories.update(candidate.categories)
            scrubbed.append(
                {
                    "sha256": candidate.digest,
                    "size": len(candidate.payload),
                    "occurrences": count,
                    "categories": sorted(candidate.categories),
                    "source_paths": candidate.paths,
                }
            )

    if len(core) != original_size:
        raise RuntimeError("Internal error: firmware scrubbing changed the dylib size")

    missing_categories = sorted(REQUIRED_CATEGORIES - found_categories)
    if missing_categories:
        details = ", ".join(missing_categories)
        raise RuntimeError(
            "The generated core did not contain detectable embedded payloads for: "
            f"{details}. Upstream layout may have changed; refusing to publish an unverified core."
        )

    args.core.write_bytes(core)

    # Verify after writing, using exact source payloads again.
    verified = args.core.read_bytes()
    remaining = [
        candidate.digest
        for candidate in candidates.values()
        if candidate.payload in verified
    ]
    if remaining:
        raise RuntimeError(
            "Firmware verification failed; exact payloads remain in the dylib: "
            + ", ".join(remaining)
        )

    report = {
        "core": str(args.core),
        "core_size": original_size,
        "candidate_payloads_scanned": len(candidates),
        "payloads_scrubbed": len(scrubbed),
        "occurrences_scrubbed": sum(int(item["occurrences"]) for item in scrubbed),
        "verified_categories": sorted(found_categories),
        "scrubbed": scrubbed,
        "verification": "No exact firmware payload collected from vice/data/C64 or vice/data/DRIVES remains in the dylib.",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        f"Scrubbed {report['occurrences_scrubbed']} embedded firmware occurrence(s) "
        f"from {report['payloads_scrubbed']} unique payload(s)."
    )
    print(f"Verification report: {args.report}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - command-line diagnostic
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
