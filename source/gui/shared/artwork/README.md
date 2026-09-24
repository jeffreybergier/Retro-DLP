# App icons

`RetroDLP-source.png` is the unchanged supplied
`ChatGPT Image Sep 17, 2026 at 07_25_55 PM.png`, relocated here. It depicts a
red glass play triangle in a brushed metal screen bezel. Both platform masters
are prepared with ImageMagick; no generated edits are used.

- `RetroDLP-macOS.png` preserves the source's 1254 × 1254 canvas and RGB pixels.
  Its replacement alpha mask removes the stray colored pixels outside the
  casing and makes the entire body opaque. The rounded rectangle runs from
  (46, 54) to (1208, 1200), with a 64-pixel radius, slightly inside the clean
  chrome. The mask is drawn at 4× resolution and reduced for smooth edges.
- `RetroDLP-iOS.png` is an opaque 1024 × 1024 crop at (115, 95). Its center is
  (626.5, 606.5), aligning the play button's vertical bounds (y=266..947)
  with the icon center. This moves the composition down relative to the old
  centered crop and balances the screen's top and bottom margins. The slightly
  tighter crop excludes the outer chrome rim while keeping brushed metal at
  every edge and corner. The original RGB pixels are preserved.

To regenerate the masters and exports with ImageMagick 7, Pillow, and OpenJPEG
installed:

```sh
sh source/gui/shared/artwork/prepare_icons.sh
python3 source/gui/shared/scripts/generate_icons.py
make apps
make app-validate
```

Generated assets are committed resources; ordinary builds do not run the
generator or require its image libraries.

- iOS: 20 opaque RGB PNGs in `source/gui/iOS/Resources`, covering notification,
  Settings, Spotlight, and home-screen sizes for iPhone and iPad, including
  legacy 57/72-point icons and Retina variants. `RetroDLP-iOS-1024.png` is the
  large export. The plist declares legacy `CFBundleIconFile`/`CFBundleIconFiles`
  and device-specific `CFBundleIcons`, following ENIL and Strappy-Cocoa.
  `UIPrerenderedIcon` is false in the top-level, iPhone, and iPad declarations,
  allowing older iOS versions to add gloss; iOS supplies its own corner mask.
- macOS: `RetroDLP.iconset` contains standard 1x/2x PNG exports. The installed
  `source/gui/macOS/Resources/RetroDLP.icns` has classic 16/32/48/128-pixel
  planar RGB plus 8-bit alpha masks for Tiger, and JPEG 2000 elements for
  256/512/1024-pixel and Retina representations, following both reference apps.

Each ICNS element, **including its eight-byte header**, is limited to 300,000
bytes. The generator tries lossless JPEG 2000 first, then increases compression
only when needed. The complete ICNS is also limited to 1,000,000 bytes: Leopard
can open larger ICNS files in Preview but reject them as application icons.
The 1024-pixel representation is encoded last within the remaining byte budget,
preserving every smaller representation and all standard/Retina sizes.
Packaging validation checks both limits, required legacy
elements, icon declarations, dimensions, opacity, and copies in the final archives.
