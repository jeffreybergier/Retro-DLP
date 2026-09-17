"""Export app icons from the approved masters (requires Pillow/OpenJPEG).

Keep the generated files in Git; normal app builds do not need this script.
Legacy ICNS RGB + mask elements match ENIL and Strappy-Cocoa's packaging.
"""
from io import BytesIO
from pathlib import Path
import struct

from PIL import Image

APPS = Path(__file__).resolve().parents[2]
ARTWORK = APPS / 'shared/artwork'
MAX_ELEMENT_BYTES = 300_000  # Decimal KB, including the ICNS element header.
IOS_ICONS = {
    'AppIcon20x20.png': 20,
    'AppIcon20x20@2x.png': 40,
    'AppIcon20x20@3x.png': 60,
    'AppIcon29x29.png': 29,
    'AppIcon29x29@2x.png': 58,
    'AppIcon29x29@3x.png': 87,
    'AppIcon40x40.png': 40,
    'AppIcon40x40@2x.png': 80,
    'AppIcon40x40@3x.png': 120,
    'AppIcon50x50~ipad.png': 50,
    'AppIcon50x50@2x~ipad.png': 100,
    'AppIcon57x57.png': 57,
    'AppIcon57x57@2x.png': 114,
    'AppIcon60x60@2x.png': 120,
    'AppIcon60x60@3x.png': 180,
    'AppIcon72x72~ipad.png': 72,
    'AppIcon72x72@2x~ipad.png': 144,
    'AppIcon76x76~ipad.png': 76,
    'AppIcon76x76@2x~ipad.png': 152,
    'AppIcon83.5x83.5@2x~ipad.png': 167,
}


def pack_channel(data):
    """ICNS planar PackBits: literals 1..128, repeated bytes 3..130."""
    output = bytearray()
    position = 0
    while position < len(data):
        run = 1
        while (run < 130 and position + run < len(data)
               and data[position + run] == data[position]):
            run += 1
        if run >= 3:
            output.extend((run + 125, data[position]))
            position += run
            continue
        start = position
        while position < len(data) and position - start < 128:
            if (position + 2 < len(data)
                    and data[position] == data[position + 1] == data[position + 2]):
                break
            position += 1
        output.append(position - start - 1)
        output.extend(data[start:position])
    return bytes(output)


def element(kind, payload):
    length = len(payload) + 8
    if length > MAX_ELEMENT_BYTES:
        raise ValueError(f'{kind}: {length} bytes exceeds the 300 KB slice limit')
    print(f'{kind.decode()}: {length:,} bytes')
    return struct.pack('>4sI', kind, length) + payload


def jpeg2000(image):
    # Try lossless first. Rate-limited JPEG 2000 keeps large slices compatible
    # with the reference apps while bounding each slice independently.
    for rate in (None, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64):
        output = BytesIO()
        options = {} if rate is None else dict(
            quality_mode='rates', quality_layers=[rate], irreversible=True)
        image.save(output, format='JPEG2000', **options)
        payload = output.getvalue()
        if len(payload) + 8 <= MAX_ELEMENT_BYTES:
            return payload
    raise ValueError('Cannot encode a JPEG 2000 slice within 300 KB')


def main():
    ios = Image.open(ARTWORK / 'RetroDLP-iOS.png').convert('RGB')
    mac = Image.open(ARTWORK / 'RetroDLP-macOS.png').convert('RGBA')
    if ios.width != ios.height or mac.width != mac.height:
        raise ValueError('Icon masters must be square')
    ios_directory = APPS / 'iOS/Resources'
    ios_directory.mkdir(parents=True, exist_ok=True)
    for name, size in IOS_ICONS.items():
        ios.resize((size, size), Image.Resampling.LANCZOS).save(
            ios_directory / name, optimize=True)
    ios.resize((1024, 1024), Image.Resampling.LANCZOS).save(
        ARTWORK / 'RetroDLP-iOS-1024.png', optimize=True)

    sizes = {size: mac.resize((size, size), Image.Resampling.LANCZOS)
             for size in (16, 32, 48, 64, 128, 256, 512, 1024)}
    iconset = ARTWORK / 'RetroDLP.iconset'
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        sizes[size].save(iconset / f'icon_{size}x{size}.png', optimize=True)
        sizes[size * 2].save(iconset / f'icon_{size}x{size}@2x.png', optimize=True)

    chunks = []
    for size, rgb, mask in ((16, b'is32', b's8mk'), (32, b'il32', b'l8mk'),
                            (48, b'ih32', b'h8mk'), (128, b'it32', b't8mk')):
        channels = sizes[size].split()
        pixels = b''.join(pack_channel(channel.tobytes()) for channel in channels[:3])
        if size == 128:
            pixels = b'\0\0\0\0' + pixels
        chunks.extend((element(rgb, pixels), element(mask, channels[3].tobytes())))
    for kind, size in ((b'ic08', 256), (b'ic09', 512), (b'ic10', 1024),
                       (b'ic11', 32), (b'ic12', 64), (b'ic13', 256), (b'ic14', 512)):
        chunks.append(element(kind, jpeg2000(sizes[size])))
    body = b''.join(chunks)
    destination = APPS / 'macOS/Resources/RetroDLP.icns'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(struct.pack('>4sI', b'icns', len(body) + 8) + body)
    # Decode every representation, including the classic RGB/mask pairs.
    with Image.open(destination) as encoded:
        for size in encoded.info['sizes']:
            decoded = encoded.icns.getimage(size)
            decoded.load()
            if size[2] == 1 and size[0] in (16, 32, 48, 128):
                if decoded.tobytes() != sizes[size[0]].tobytes():
                    raise ValueError(f'Legacy ICNS pixels changed at {size}')
    print(f'Exported {len(IOS_ICONS)} iOS icons, a 1024px master, an iconset, '
          f'and {len(chunks)} ICNS elements.')


if __name__ == '__main__':
    main()
