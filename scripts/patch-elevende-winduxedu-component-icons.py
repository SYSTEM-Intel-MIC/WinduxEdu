#!/usr/bin/env python3
"""Inject WinduxEdu component icon aliases into ElevenDE's application resolver."""
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) == 2 else None
if path is None or not path.is_file():
    raise SystemExit("usage: patch-elevende-winduxedu-component-icons.py PATH/TO/shell/main.c")

entries = (
    ("linux-pcmanager", "linux-pcmanager"),
    ("linux-regedit", "linux-regedit"),
    ("devmgr", "winduxedu-device-manager"),
    ("winduxedu-store", "winduxedu-store"),
    ("linux-store", "winduxedu-store"),
    ("copilot-for-linux", "copilot-for-linux"),
    ("peazip", "peazip"),
    ("winduxedu-troubleshooting", "winduxedu-troubleshooting"),
    ("winduxedu-sticky-keys", "winduxedu-sticky-keys"),
    ("winduxedu-widgets", "winduxedu-widgets"),
    ("winduxedu-windowshit", "winduxedu-windowshit"),
    ("winsat", "winduxedu-winsat"),
    ("winver", "winduxedu-winver"),
    ("feedbackhub", "feedbackhub"),
)
marker = '        { "", "" }\n'
text = path.read_text(encoding="utf-8")
if '/* WINDUXEDU-COMPONENT-ICON-MAP */' in text:
    raise SystemExit("WinduxEdu component icon map is already present")
if marker not in text:
    raise SystemExit("ElevenDE app icon table marker was not found")
block = '        /* WINDUXEDU-COMPONENT-ICON-MAP */\n' + ''.join(
    f'        {{ "{window_class}", "{icon}" }},\n' for window_class, icon in entries
)
path.write_text(text.replace(marker, block + marker, 1), encoding="utf-8")
print(f"added {len(entries)} WinduxEdu component icon resolver aliases")
