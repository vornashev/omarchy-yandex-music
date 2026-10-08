#!/usr/bin/env python3
"""Verify the pinned wheel against pinned upstream source without executing either."""

import argparse
import base64
import csv
from email import policy
from email.parser import BytesParser
import hashlib
import io
from pathlib import Path
import stat
import sys
import tarfile
import urllib.error
import urllib.request
import zipfile


COMMIT = "0fa54f2d32084a9e461bce41890d1c9ab70d91aa"
WHEEL_NAME = "yandex_music-3.1.0b2-py3-none-any.whl"
WHEEL_SHA256 = "2f200b887b2be33b37f4eb05a4762703b11fe334205c16d7fac29f24d8a52e31"
SOURCE_URL = f"https://codeload.github.com/MarshalX/yandex-music-api/tar.gz/{COMMIT}"
SOURCE_SHA256 = "8f9adb3a49d05c606255357f9c620263c7d1dac1422c9689ed2a083e47c0e5fd"
SOURCE_ROOT = f"yandex-music-api-{COMMIT}"
DIST_INFO = "yandex_music-3.1.0b2.dist-info/"
RECORD = DIST_INFO + "RECORD"
METADATA_FILES = {DIST_INFO + name for name in (
    "licenses/LICENSE", "METADATA", "WHEEL", "top_level.txt", "RECORD",
)}
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_archive(stream):
    data = stream.read(MAX_ARCHIVE_BYTES + 1)
    require(len(data) <= MAX_ARCHIVE_BYTES, "archive exceeds 32 MiB limit")
    return data


def check_sha256(data, expected, label):
    actual = hashlib.sha256(data).hexdigest()
    require(actual == expected, f"{label} SHA-256 mismatch: expected {expected}, got {actual}")
    return actual


def safe_path(name):
    require(
        name and not any(ord(char) < 32 or ord(char) == 127 for char in name)
        and "\\" not in name and ":" not in name
        and all(part not in ("", ".", "..") for part in name.split("/")),
        f"unsafe archive path: {name!r}",
    )


def read_wheel(data):
    files = {}
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for member in archive.infolist():
            name = member.filename
            require(member.orig_filename == name, "wheel contains a truncated filename")
            safe_path(name)
            require(name not in files, f"duplicate wheel member: {name}")
            mode = member.external_attr >> 16
            require(not member.is_dir() and stat.S_IFMT(mode) in (0, stat.S_IFREG),
                    f"non-regular wheel member: {name}")
            require(not member.flag_bits & 1, f"encrypted wheel member: {name}")
            files[name] = archive.read(member)
    return files


def read_source(data):
    files = {}
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            name = member.name.removesuffix("/") if member.isdir() else member.name
            safe_path(name)
            require(name not in seen, f"duplicate source member: {name}")
            seen.add(name)
            require(name == SOURCE_ROOT or name.startswith(SOURCE_ROOT + "/"),
                    f"unexpected source root: {name}")
            require(member.isdir() or member.isfile(), f"non-regular source member: {name}")
            if member.isfile():
                require(name != SOURCE_ROOT, "source root must be a directory")
                with archive.extractfile(member) as stream:
                    files[name[len(SOURCE_ROOT) + 1:]] = stream.read()
    return files


def check_record(files):
    seen = set()
    rows = csv.reader(io.StringIO(files[RECORD].decode("utf-8"), newline=""), strict=True)
    hashed = 0
    for row in rows:
        require(len(row) == 3, "RECORD row must have exactly three columns")
        name, digest, size = row
        safe_path(name)
        require(name not in seen, f"duplicate RECORD row: {name}")
        seen.add(name)
        require(name in files, f"RECORD names absent wheel member: {name}")
        if name == RECORD:
            require(digest == size == "", "RECORD must leave its own hash and size empty")
            continue
        expected = base64.urlsafe_b64encode(hashlib.sha256(files[name]).digest()).rstrip(b"=")
        require(digest == "sha256=" + expected.decode("ascii"), f"RECORD hash mismatch: {name}")
        require(size == str(len(files[name])), f"RECORD size mismatch: {name}")
        hashed += 1
    require(seen == files.keys(), "RECORD does not cover every wheel member exactly once")
    return hashed


def check_metadata(files):
    parser = BytesParser(policy=policy.default)
    metadata = parser.parsebytes(files[DIST_INFO + "METADATA"])
    require(not metadata.defects, "malformed METADATA")
    for name, value in (("Name", "yandex-music"), ("Version", "3.1.0b2"),
                        ("License-File", "LICENSE")):
        require(metadata.get_all(name) == [value], f"unexpected METADATA {name}")
    wheel = parser.parsebytes(files[DIST_INFO + "WHEEL"])
    require(not wheel.defects, "malformed WHEEL metadata")
    expected = {
        "Wheel-Version": "1.0",
        "Generator": "setuptools (84.0.0)",
        "Root-Is-Purelib": "true",
        "Tag": "py3-none-any",
    }
    require(set(wheel.keys()) == expected.keys(), "unexpected WHEEL metadata fields")
    for name, value in expected.items():
        require(wheel.get_all(name) == [value], f"unexpected WHEEL {name}")
    require(files[DIST_INFO + "top_level.txt"] == b"tests\nyandex_music\n",
            "unexpected top-level packages")


def verify(wheel_data, source_data):
    files = read_wheel(wheel_data)
    source = read_source(source_data)
    payload = {name for name in source if name.startswith(("yandex_music/", "tests/"))}
    require(payload, "source contains no package/test payload")
    expected = payload | METADATA_FILES
    require(files.keys() == expected,
            f"wheel payload differs: missing={sorted(expected - files.keys())}, "
            f"extra={sorted(files.keys() - expected)}")
    for name in sorted(payload):
        require(files[name] == source[name], f"upstream payload mismatch: {name}")
    require("LICENSE" in source, "upstream LICENSE is missing")
    require(files[DIST_INFO + "licenses/LICENSE"] == source["LICENSE"],
            "wheel license differs from upstream LICENSE")
    hashed = check_record(files)
    check_metadata(files)
    package_count = sum(name.startswith("yandex_music/") for name in payload)
    test_count = sum(name.startswith("tests/") for name in payload)
    print(f"Payload: {len(payload)} byte-identical upstream files "
          f"({package_count} package, {test_count} tests)")
    print("License: byte-identical upstream LICENSE")
    print(f"RECORD: {len(files)} members covered, {hashed} SHA-256 hashes/sizes valid; "
          "RECORD self-entry unhashed")
    print("Metadata: yandex-music 3.1.0b2; purelib=true; py3-none-any; "
          "generator=setuptools (84.0.0)")
    print("Extras: only LICENSE, METADATA, WHEEL, top_level.txt and RECORD; "
          "no unexplained payload")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel", type=Path, default=Path(__file__).resolve().with_name(WHEEL_NAME),
                        help="wheel to check (default: vendored wheel beside this script)")
    parser.add_argument("--source-archive", type=Path,
                        help="exact pinned codeload .tar.gz for offline verification; "
                             "otherwise download it over HTTPS")
    args = parser.parse_args()
    try:
        with args.wheel.open("rb") as stream:
            wheel_data = read_archive(stream)
        wheel_sha = check_sha256(wheel_data, WHEEL_SHA256, "wheel")
        if args.source_archive is not None:
            with args.source_archive.open("rb") as stream:
                source_data = read_archive(stream)
        else:
            with urllib.request.urlopen(SOURCE_URL, timeout=60) as stream:
                source_data = read_archive(stream)
        source_sha = check_sha256(source_data, SOURCE_SHA256, "source archive")
        print(f"Upstream commit: {COMMIT}")
        print(f"Wheel SHA-256: {wheel_sha}")
        print(f"Source archive SHA-256: {source_sha}")
        verify(wheel_data, source_data)
    except (OSError, ValueError, UnicodeError, csv.Error, tarfile.TarError,
            zipfile.BadZipFile, urllib.error.URLError, EOFError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: pinned artifact matches upstream payload; not a security audit or rebuild proof")
    return 0


if __name__ == "__main__":
    sys.exit(main())
