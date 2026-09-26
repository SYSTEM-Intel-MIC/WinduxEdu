#!/usr/bin/env python3
"""Reassemble the split (分卷) proprietary DEB volumes under edu-software/.

edu-software/ stores every collected .deb as fixed 50 MiB parts so the
repository stays within GitHub's per-file limit.  This script verifies every
part against edu-software/PARTS-INDEX.tsv, concatenates them in order, and
verifies the reassembled file against the whole-file SHA-256 recorded in
edu-software/DEB-INVENTORY.tsv.  Files are never modified; assembly writes to
a separate output directory only.

Usage:
  python3 scripts/assemble-edu-debs.py            # assemble + verify
  python3 scripts/assemble-edu-debs.py --check    # verify parts only
  python3 scripts/assemble-edu-debs.py --output /tmp/edu-debs
"""
import argparse
import csv
import hashlib
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EDU = os.path.join(REPO, "edu-software")
INVENTORY = os.path.join(EDU, "DEB-INVENTORY.tsv")
PARTS_INDEX = os.path.join(EDU, "PARTS-INDEX.tsv")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_tsv(path):
    with open(path, encoding="utf-8", newline="") as f:
        for row in csv.reader(f, delimiter="\t"):
            if row and not row[0].startswith("#"):
                yield row


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", default=os.path.join(REPO, "artifacts", "edu-debs"),
                    help="directory to write reassembled .deb files")
    ap.add_argument("--check", action="store_true",
                    help="only verify part hashes; do not assemble")
    args = ap.parse_args()

    parts = {}
    for file_rel, part, size, digest in read_tsv(PARTS_INDEX):
        parts.setdefault(file_rel, []).append((part, int(size), digest))

    failures = 0
    for file_rel, pkg, version, arch, size, whole_sha in (
            (r[1], r[2], r[3], r[4], int(r[5]), r[6]) for r in read_tsv(INVENTORY)):
        vol = parts.get(file_rel)
        if not vol:
            print(f"FAIL {file_rel}: no parts recorded")
            failures += 1
            continue
        src_dir = os.path.join(EDU, os.path.dirname(file_rel))
        paths = []
        for part, psize, psha in vol:
            p = os.path.join(src_dir, part)
            if not os.path.isfile(p):
                print(f"FAIL {file_rel}: missing part {part}")
                failures += 1
                break
            if os.path.getsize(p) != psize:
                print(f"FAIL {file_rel}: size mismatch {part}")
                failures += 1
                break
            if sha256_file(p) != psha:
                print(f"FAIL {file_rel}: sha256 mismatch {part}")
                failures += 1
                break
            paths.append(p)
        else:
            total = sum(psize for _, psize, _ in vol)
            if total != size:
                print(f"FAIL {file_rel}: total parts size {total} != {size}")
                failures += 1
                continue
            if args.check:
                print(f"OK   {file_rel}: {len(vol)} parts verified")
                continue
            os.makedirs(args.output, exist_ok=True)
            out = os.path.join(args.output, os.path.basename(file_rel))
            h = hashlib.sha256()
            with open(out, "wb") as w:
                for p in paths:
                    with open(p, "rb") as r:
                        for chunk in iter(lambda: r.read(1 << 20), b""):
                            w.write(chunk)
                            h.update(chunk)
            if h.hexdigest() != whole_sha:
                print(f"FAIL {file_rel}: reassembled sha256 mismatch")
                failures += 1
                continue
            print(f"OK   {file_rel}: assembled -> {out} "
                  f"({pkg} {version} {arch}, sha256 verified)")

    if failures:
        print(f"{failures} failure(s)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
