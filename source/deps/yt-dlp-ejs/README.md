# Vendored yt-dlp-ejs solver

This directory contains the minified solver assets from `yt-dlp-ejs` 0.8.0,
the exact version required by the vendored yt-dlp checkout.

- Upstream: <https://github.com/yt-dlp/ejs>
- PyPI release: `yt-dlp-ejs==0.8.0`
- Wheel: `yt_dlp_ejs-0.8.0-py3-none-any.whl`
- Wheel SHA-256:
  `79300e5fca7f937a1eeede11f0456862c1b41107ce1d726871e0207424f4bdb4`
- Upstream `core.min.js` SHA-256 before newline normalization:
  `18da6ce0758b416e7ae645084f4f8801f9f9d59d6c477c05eaa0ff94ebd8cc00`
- Vendored `core.min.js` SHA-256:
  `bee40cad5f2bbb9655ee2882c0241178c81bef47c01e2349bd0fbbfce37ba724`
- Upstream `lib.min.js` SHA-256 before newline normalization:
  `c55987fe697e5b9ee18830163f7af85327e9bb5c3e674b969d38c8d205eaa577`
- Vendored `lib.min.js` SHA-256:
  `dcccf3265a1e6743ebdab0bfcea02ac8ed9b0a70d80407bc29720217bc454f9a`

The EJS core is released under the Unlicense. The wheel's `lib.min.js` also
bundles Meriyah 6.1.4 under ISC and Astring 1.9.0 under MIT. Their complete
notices are retained in the banner at the beginning of `lib.min.js`.

The JavaScript files are upstream build artifacts and should not be edited by
hand. When updating them, update all version and hash records together with the
matching yt-dlp pin and golden fixtures.
