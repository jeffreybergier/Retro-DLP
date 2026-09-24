# Leopard application icon size limit

Verified on 2026-09-24 using `imac-rsa` (PowerPC, Mac OS X 10.5.8) and
`x4-vm` (PowerPC, Mac OS X 10.4.11).

Retro-DLP's original ICNS was 1,072,881 bytes. Leopard returned its generic
application icon for both the installed app and a new minimal test bundle using
that ICNS. Its `CFBundleIconFile` resolved to the existing resource correctly.
Removing the filename extension or adding `CFBundleSignature` did not help.
The working reference files were ENIL at 175,756 bytes and Strappy at 708,422.
All three used JPEG 2000 for their large representations.

The native probe used `NSWorkspace iconForFile:` and rendered the returned icon
to a 128-pixel PNG. Every test bundle had a distinct identifier and path; no
system icon caches were cleared. The following variations isolated file size:

| ICNS variation | Bytes | Leopard result |
| --- | ---: | --- |
| Original, all 15 representations | 1,072,881 | Generic application icon |
| Original without `ic11`–`ic14` | 697,367 | Correct icon |
| Original without `ic10` | 810,940 | Correct icon |
| Working icon plus inert padding | 1,048,574 | Correct icon |
| Same image payloads plus one more padding byte | 1,048,575 | Generic application icon |
| Fixed, all 15 representations | 985,690 | Correct icon |

The padded variants retained the same image payloads and added two unrecognized
ICNS elements. A binary search established the adjacent working/failing sizes
above on this Leopard installation. Standalone Preview decoding does not prove
that Leopard's application-icon lookup will accept the file.

The generator now caps the whole file at 1,000,000 bytes as well as retaining
the existing 300,000-byte per-element cap. It budgets the 1024-pixel `ic10`
representation last and increases its JPEG 2000 compression as necessary.
All other representation payloads remain byte-for-byte identical. The fixed
icon's Leopard rendering matches the successful smaller test variants. On
Tiger, the original and fixed icons produce identical rendered PNGs.

`make app-validate` checks both byte limits and all required representations,
including the copies shipped inside the app bundle and ZIP. The updated
release ZIP passed package validation and archive integrity checks.
