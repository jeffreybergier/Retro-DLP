"""Check shared UI lookup coverage and .strings syntax without an Apple runtime."""
from pathlib import Path
import json
import re

GUI = Path(__file__).resolve().parents[2]
STRING = r'"(?:[^"\\]|\\.)*"'
ENTRY = re.compile(r'\s*(' + STRING + r')\s*=\s*(' + STRING + r')\s*;')


def read_table(path):
    text = re.sub(r'/\*.*?\*/', '', path.read_text(), flags=re.S)
    table = {}
    while text.strip():
        match = ENTRY.match(text)
        assert match, f'Malformed strings entry in {path}: {text[:100]}'
        key, value = (json.loads(token) for token in match.groups())
        assert key not in table, f'Duplicate key in {path}: {key}'
        assert value, f'Empty translation in {path}: {key}'
        table[key] = value
        text = text[match.end():]
    return table


english = read_table(GUI/'shared/Resources/en.lproj/Localizable.strings')
lookup = re.compile(r'NSLocalizedString\(\s*@(' + STRING + r')\s*,')
for source in GUI.rglob('*.m'):
    if 'tests' in source.parts:
        continue
    for match in lookup.finditer(source.read_text()):
        key = json.loads(match[1])
        assert key in english, f'Missing shared UI string in {source}: {key}'

# These keys are passed to NSLocalizedString at the presentation boundary;
# the original values remain stable menu, sidebar, and saved player identifiers.
for key in ('File', 'Edit', 'View', 'Window', 'Help', 'Download Quality',
            'Video Player', 'Cookies', 'VLC', 'QuickTime', 'Default App',
            'System', 'Added Playlists', 'My Playlists', 'Unsupported Playlists',
            'All Downloads'):
    assert key in english, f'Missing dynamically localized key: {key}'

def printf_arguments(text):
    # C formats use explicit positional arguments when translators reorder them.
    token = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|[hljztL])?([diuoxXfFeEgGaAcsp%])')
    arguments = {}
    next_index = 1
    for match in token.finditer(text):
        position, length, conversion = match.groups()
        if conversion == '%':
            continue
        index = int(position) if position else next_index
        next_index += not bool(position)
        signature = (length or '', conversion)
        assert index not in arguments or arguments[index] == signature
        arguments[index] = signature
    # Reject unsupported/malformed conversions, including %n and dynamic widths.
    assert '%' not in token.sub('', text), f'Invalid C format: {text}'
    return arguments


# C keys are resolved dynamically by the Objective-C startup bridge.
for match in re.finditer(r'RDAPP_STRING\(\w+,\s*(' + STRING + r')\)',
                         (GUI/'shared/rdapp_strings.def').read_text()):
    key = json.loads(match[1])
    assert key in english, f'Missing C UI string: {key}'
    if '%' in key:
        for path in (GUI/'shared/Resources').glob('*.lproj/Localizable.strings'):
            translation = read_table(path).get(key, key)
            assert printf_arguments(translation) == printf_arguments(key), \
                f'C format arguments changed in {path}: {key}'

for platform in ('macOS', 'iOS'):
    makefile = (GUI/platform/'Makefile').read_text()
    assert 'BUNDLE_LOCALIZATION_DIRS = $(SHARED_DIR)/Resources' in makefile
    bundle = '$(BUNDLE)' if platform == 'macOS' else '$(APP_BUNDLE)'
    assert re.search(re.escape(bundle) + r':[^\n]*\$\(LOCALIZATION_FILES\)', makefile), \
        f'{platform} must repackage edited translations'

print(f'PASS: {len(english)} shared strings cover macOS, iOS, and player lookups')
