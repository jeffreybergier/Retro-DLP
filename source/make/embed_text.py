#!/usr/bin/env python3
"""Convert a text asset to adjacent C string literals."""

import os
import pathlib
import sys
import tempfile


def c_escape(chunk: bytes) -> str:
    result = []
    for value in chunk:
        if value == 0x22:
            result.append(r'\"')
        elif value == 0x5C:
            result.append(r'\\')
        elif value == 0x3F:
            result.append(r'\?')
        elif value == 0x0A:
            result.append(r'\n')
        elif value == 0x0D:
            result.append(r'\r')
        elif value == 0x09:
            result.append(r'\t')
        elif 0x20 <= value <= 0x7E:
            result.append(chr(value))
        else:
            result.append(f'\\{value:03o}')
    return ''.join(result)


def main() -> int:
    if len(sys.argv) != 3:
        print(f'usage: {sys.argv[0]} INPUT OUTPUT', file=sys.stderr)
        return 2

    source = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    data = source.read_bytes()
    destination.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary_name = tempfile.mkstemp(
        dir=destination.parent, prefix=f'.{destination.name}.', text=True)
    try:
        with os.fdopen(descriptor, 'w', encoding='ascii', newline='\n') as output:
            output.write(f'/* Generated from {source.as_posix()}. */\n')
            for offset in range(0, len(data), 80):
                output.write(f'"{c_escape(data[offset:offset + 80])}"\n')
        os.replace(temporary_name, destination)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
