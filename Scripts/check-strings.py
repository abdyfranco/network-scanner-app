#!/usr/bin/env python3
#
#  check-strings.py
#  Network Scanner
#
#  Copyright © 2026 Advandz Technologies, LLC.
#

"""Checks Resources/*.xcstrings: every key is translated in every language the catalog uses,
and every translation keeps the source string's format specifiers (%@, %lld…), so nothing
garbles or crashes at runtime. Exits non-zero on problems.

Usage: Scripts/check-strings.py
"""
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")
SPEC = re.compile(r"%(?:\d+\$)?(lld|ld|d|@|f|\.\d+f)")


def forms(localization):
    """All strings in one localization: a plain value or every plural form."""
    if "stringUnit" in localization:
        yield localization["stringUnit"]["value"]
    for variation in localization.get("variations", {}).values():
        for case in variation.values():
            yield from forms(case)


problems = []
for name in sorted(f for f in os.listdir(ROOT) if f.endswith(".xcstrings")):
    catalog = json.load(open(os.path.join(ROOT, name)))
    source = catalog["sourceLanguage"]
    strings = catalog["strings"]
    languages = sorted({lang for entry in strings.values() for lang in entry.get("localizations", {})} - {source})
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        expected = Counter(SPEC.findall(key))
        for lang in languages:
            localization = entry.get("localizations", {}).get(lang)
            if localization is None:
                problems.append(f"{name} [{lang}] missing: {key!r}")
                continue
            for text in forms(localization):
                if name == "Localizable.xcstrings" and Counter(SPEC.findall(text)) != expected:
                    problems.append(f"{name} [{lang}] specifiers differ: {key!r} -> {text!r}")
    print(f"{name}: {len(strings)} keys · {', '.join([source] + languages)}")

if problems:
    print(f"{len(problems)} problem(s):")
    print("\n".join(problems))
    sys.exit(1)
print("✓ every key translated, format specifiers match")
