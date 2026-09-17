# C API examples

These programs use only installed Retro-DLP headers. From the repository root,
run `make examples` to build them in `build/linux/examples` or
`make validate-examples` to build them and run the offline custom-transport
example.

- `resolve.c` resolves a video and prints every media URL and required header.
- `authenticated.c` resolves with a Netscape-format cookie file.
- `playlist.c` lists the entries in a playlist.
- `custom_transport.c` injects a synchronous in-memory transport and needs no
  network access.
- `download.c` resolves and downloads through the optional download component.

The network examples use the system libcurl trust configuration. Real
applications can fill `rdlp_config` to set an explicit CA bundle, cache, EJS
asset directory, timeout, callbacks, or custom transport before creating the
context.
