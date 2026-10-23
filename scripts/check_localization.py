#!/usr/bin/env python3
"""Check every paired .strings table, printf arguments, and literal Swift lookups."""
import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
import sys

ENTRY = re.compile(r'\s*(?:/\*.*?\*/\s*|//[^\n]*\n\s*)*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;', re.S)
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|[hljztL])?([@diuoxXfFeEgGaAcCsSp%])')
LANGUAGE_FILE = re.compile(r'^(?:Base|[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*)\.lproj$')


def read_table(path):
    source = path.read_text(encoding='utf-8')
    result = {}
    offset = 0
    while source[offset:].strip():
        match = ENTRY.match(source, offset)
        if not match:
            raise ValueError(f'{path}: invalid .strings syntax at offset {offset}')
        key, value = (json.loads(item) for item in match.groups())
        if key in result:
            raise ValueError(f'{path}: duplicate key: {key}')
        if not value.strip():
            raise ValueError(f'{path}: empty value: {key}')
        result[key] = value
        offset = match.end()
    return result


def arguments(value):
    sequence = 0
    result = Counter()
    for match in FORMAT.finditer(value):
        position, length, kind = match.groups()
        if kind == '%':
            continue
        sequence += 1
        result[(int(position) if position else sequence, (length or '') + kind)] += 1
    return result


def read_tables(resources):
    paths = sorted(resources.glob('*.lproj/Localizable.strings'))
    tables = {path.parent.stem: read_table(path) for path in paths}
    for directory in sorted(resources.glob('*.lproj')):
        if not LANGUAGE_FILE.match(directory.name):
            raise ValueError(f'{directory}: unrecognized localization directory name')
        if not directory.is_dir() or not (directory / 'Localizable.strings').is_file():
            raise ValueError(f'{directory}: missing Localizable.strings')
    for language in ('en', 'zh-Hans'):
        if language not in tables:
            raise ValueError(f'missing {language}.lproj/Localizable.strings')
    declared = {name for name in tables if name != 'Base'}
    for name in ('Info.plist', 'PlayerInfo.plist'):
        path = resources / name
        if not path.is_file():
            continue
        localizations = plistlib.loads(path.read_bytes()).get('CFBundleLocalizations')
        if localizations is None:
            raise ValueError(f'{name}: missing CFBundleLocalizations')
        missing = sorted(declared - set(localizations))
        unexpected = sorted(set(localizations) - declared)
        if missing or unexpected:
            raise ValueError(f'{name}: CFBundleLocalizations mismatch: missing {missing}; unexpected {unexpected}')
    return tables


def check(resources, sources):
    tables = read_tables(resources)
    reference = tables['en']
    for language, table in tables.items():
        missing = sorted(reference.keys() - table.keys())
        unexpected = sorted(table.keys() - reference.keys())
        if missing or unexpected:
            raise ValueError(f'key mismatch in {language}: missing {missing}; unexpected {unexpected}')
        mismatches = [key for key in reference if arguments(table[key]) != arguments(reference[key])]
        if mismatches:
            raise ValueError(f'format argument mismatch in {language}: {mismatches}')
    for path in sources.rglob('*.swift'):
        source = path.read_text(encoding='utf-8')
        keys = re.findall(r'\bL\("([^"\\]+)"\)', source)
        keys += re.findall(r"return error\('([^']+)'\)", source)
        for key in keys:
            if key not in reference:
                raise ValueError(f'{path}: missing lookup: {key}')
    keys = len(reference)
    languages = ', '.join(sorted(tables))
    print(f'Localization OK: {len(tables)} languages ({languages}) × {keys} keys; no duplicates, empty values, missing lookups, or format mismatches.')


if __name__ == '__main__':
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', type=Path, default=root / 'Resources')
    parser.add_argument('--sources', type=Path, default=root / 'Sources')
    options = parser.parse_args()
    try:
        check(options.resources, options.sources)
    except (OSError, ValueError) as error:
        print(f'Localization check failed: {error}', file=sys.stderr)
        sys.exit(1)
