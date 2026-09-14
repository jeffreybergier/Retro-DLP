# Retro-DLP

The stable reusable C interface is documented in
[`docs/library-api.md`](docs/library-api.md). Applications should include only
headers from `include/retrodlp`; concise resolver, authentication, playlist,
custom-transport, and optional-download programs are in
[`examples/`](examples/README.md).

Retro-DLP is a super minimalist/reduced-scope conversion of 
[yt-dlp](https://github.com/yt-dlp/yt-dlp) from Python into C. I built 
Retro-DLP so I could play videos on my retro Apple devices like my iMac G4 and
my iPhone 5. Retro-DLP brings together venerable open source projects to
accomplish a singular goal:

- [libcurl](https://curl.se/libcurl/): Downloads with TLS 1.2 support
- [QuickJS](https://bellard.org/quickjs/): Solves JavaScript challenges
- [L-SMASH](https://github.com/l-smash/l-smash): Muxes together separate audio
  and video downloads
- [cJSON](https://github.com/DaveGamble/cJSON): Parses JSON responses

Implementation research is maintained as a short list of
[upstream references](docs/upstream-references.md); the repository does not
vendor yt-dlp as a build or test dependency.

## Cocoa applications

Native macOS and iOS frontends provide a SQLite playlist library, quality-specific
download queue, and offline playback. macOS prefers VLC when installed, otherwise
uses the system default player, and exports M3U8 playlists under
`~/Documents/RetroDLP`; iOS keeps videos inside its own Documents directory and
uses the native player. Both apps group playlists and download qualities, confirm
bulk/destructive actions, and process queued work automatically while active.
See [app usage, builds, and architecture](docs/cocoa-apps.md).

Build both frontends with `make apps`; run their offline Linux tests with
`make app-test`.

## Features

- Downloads videos from a video ID or URL
- Lists public and private playlists with `--flat-playlist`
- Includes `low`, `med`, and `high` quality presets
- Accepts exact yt-dlp-style itags such as `18` or `137+140`
- Supports authenticated sessions through Netscape-format cookie files

## Limitations

- Does not support [PO token](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide) generation (and probably never will)
- Identifies as `mweb` client. See PO Token Guide above for implications.
- Does not support WebM, VP9, AV1, Opus, conversion, or transcoding (and probably never will)
- Does not implement yt-dlp's selectors, filters, or automatic quality rules

## Usage Tips

Because Retro-DLP cannot generate PO tokens, most requests for quality over
"low" (itag 18) will fail with 403 status. However, if you have a Premium
account, use the --cookies option to increase reliability. This is because
currently, premium accounts do not need a PO token. However, according to the
[PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide):

> Proof of Origin (PO) Token is a parameter that [REDACTED] requires to be sent
> with requests from some clients. Without it, requests for the affected
> clients' format URLs may return HTTP Error 403, or result in your account
> or IP address being blocked.

So if you authenticate with cookies, **please be careful.**

- [Exporting Cookies Guide](https://github.com/yt-dlp/yt-dlp/wiki/Extractors)

## Compatibility

| Platform | Architectures | Minimum OS | Tested |
|---|---|---|---|
| macOS legacy | PowerPC, i386 | Mac OS X 10.4+ | 10.4 (PPC), 10.5 (PPC) |
| macOS modern | x86_64, arm64 | OS X 10.9+ (Intel), macOS 11+ (Apple Silicon) | macOS 15 (arm64) |
| iOS | armv7, arm64 | iOS 5+ | iPhone 5 iOS 6 |

The macOS release provides separate `ppc-i386` and `x86_64-arm64` archives so
each OS selects from compatible executable slices. The iOS release contains one
universal armv7/arm64 executable and requires a jailbroken device.

## Install

Download the macOS or iOS ZIP from
[GitHub Releases](https://github.com/jeffreybergier/Retro-DLP/releases). Keep
`retro-dlp` and `cacert.pem` together because Retro-DLP uses that certificate
bundle for HTTPS.

### Mac

Download the `ppc-i386` archive for PowerPC Macs or Intel Macs running OS X
10.4 through 10.8. Download the `x86_64-arm64` archive for Intel Macs running
OS X 10.9 or newer and for Apple Silicon Macs. Unzip it and put both files
wherever you want. For example:

```sh
unzip Retro-DLP-X.Y.Z-macOS-ppc-i386.zip
# Or: unzip Retro-DLP-X.Y.Z-macOS-x86_64-arm64.zip
mkdir -p ~/bin
mv retro-dlp cacert.pem ~/bin/
chmod +x ~/bin/retro-dlp
~/bin/retro-dlp assets install
```

Add `~/bin` to your `PATH` if your shell does not already include it.

### Jailbroken iPhone

Install OpenSSH on the iPhone, unzip the iOS release on your computer, and copy
both files to the device:

```sh
ssh mobile@iphone-ip-address 'mkdir -p /var/mobile/bin'
scp retro-dlp cacert.pem mobile@iphone-ip-address:/var/mobile/bin/
ssh mobile@iphone-ip-address \
  'chmod 755 /var/mobile/bin/retro-dlp && /var/mobile/bin/retro-dlp assets install'
```

Old iPhones may require the legacy SSH options
`HostKeyAlgorithms=+ssh-rsa` and `PubkeyAcceptedAlgorithms=+ssh-rsa`.

I also include [`find-vlc`](source/iOS/scripts/find-vlc), a small helper script
that prints VLC's Documents directory on iOS. Use its output with `cd` to change
the current shell's working directory. The script requires `ipainstaller` and
VLC with the `org.videolan.vlc-ios` identifier.

#### Install

```sh
scp source/iOS/scripts/find-vlc mobile@iphone-ip-address:/var/mobile/bin/
ssh mobile@iphone-ip-address 'chmod 755 /var/mobile/bin/find-vlc'
```

#### Use

Run this command on your iPhone using a terminal app.

```sh
cd $(find-vlc) && retro-dlp --cookies-default -t med 'VIDEO_ID_OR_URL'
```

## Usage

The presets provide the easiest way to choose a format:

```sh
retro-dlp -t low VIDEO_ID_OR_URL    # 18 (generally 360p)
retro-dlp -t med VIDEO_ID_OR_URL    # 136+140 (generally 720p)
retro-dlp -t high VIDEO_ID_OR_URL   # 137+140 (generally 1080p)
```

List the formats for a video:

```sh
retro-dlp -F VIDEO_ID_OR_URL
```

Choose exact formats:

```sh
retro-dlp -f 18 VIDEO_ID_OR_URL
retro-dlp -f 136+140 VIDEO_ID_OR_URL
retro-dlp -f '137+599/137+140/136+140' VIDEO_ID_OR_URL
```

`+` combines one video-only stream with one audio-only stream. `/` tries exact
alternatives from left to right. Retro-DLP never silently picks an unlisted
fallback. Its default format expression is `22/18`.

Print metadata without downloading:

```sh
retro-dlp --dump-json VIDEO_ID_OR_URL
```

Use `--simulate` to resolve a video without downloading it or writing a file.

List the entries of a public playlist without resolving or downloading its
videos:

```sh
retro-dlp --flat-playlist PLAYLIST_URL_OR_ID
retro-dlp --flat-playlist --dump-json PLAYLIST_URL_OR_ID
```

Quote playlist URLs containing `&` so the shell does not treat portions of the
URL as separate commands. Authenticated playlists can be combined with
`--cookies` or `--cookies-default`.

List the playlists saved in your account:

```sh
retro-dlp --flat-playlist --cookies /path/to/cookies.txt \
  ACCOUNT_PLAYLISTS_URL
```

This account collection URL requires signed-in cookies. Add
`--dump-json` for one normalized playlist object per line.

Use exported account cookies:

```sh
retro-dlp --cookies /path/to/cookies.txt VIDEO_ID_OR_URL
retro-dlp --cookies-default VIDEO_ID_OR_URL
```

`--cookies-default` reads `~/.retro-dlp/cookies.txt`. Cookie files grant access
to your account, so protect them with `chmod 600` and never commit or share
them.

## Build from Source

This project uses the Docker-based retro development environment
[Altivec Intelligence](https://github.com/jeffreybergier/AltivecIntelligence).

### BYOSDK

Altivec Intelligence is BYOSDK (Bring Your Own SDK), so you must supply the
Apple SDK archives yourself. See the
[Altivec Intelligence BYOSDK instructions](https://github.com/jeffreybergier/AltivecIntelligence#byosdk)
for details before building Retro-DLP.

### Build Retro-DLP

**1. Clone the repo**

```sh
git clone --recursive https://github.com/jeffreybergier/Retro-DLP.git
cd Retro-DLP
```

**2. Pull the Docker image and install the SDKs**

```sh
docker compose pull
docker compose run --rm altivec-sdk install
```

**3. Build Retro-DLP**

```sh
docker compose run --rm altivec "make clean release"
```

The builds land in `build/macOS` and `build/iOS`. Each directory contains the
executable, its matching `cacert.pem`, `libretrodlp.a`, and the optional
`libretrodlp-download.a`.

Optional: build the native Linux executable or run the offline test suite:

```sh
docker compose run --rm altivec "make linux"
docker compose run --rm altivec "make test"
```

The tests use local fixtures and never connect to the internet.

Run `make package-libraries` after all three platform builds to create static
library ZIPs. Linux supports staged installation with `make install
PREFIX=/usr/local DESTDIR=/package/root`. Link flags, dependencies, and
consumer validation are documented in [`docs/library-api.md`](docs/library-api.md).

The container reference in `compose.yml` is pinned by digest so release inputs
do not change implicitly. Update all occurrences together when intentionally
adopting a newer Altivec Intelligence image.

Release CI requires repository secrets containing the HTTPS URLs for the three
private SDK archives. The pinned build image's `altivec-sdk preflight` and
`altivec-sdk install` commands verify each archive's byte size, SHA-256 digest,
format, and paths against the image's embedded catalog before extraction.

## License

I release Retro-DLP under the [MIT License](LICENSE). Third-party components,
including [libcurl](https://curl.se/libcurl/),
[QuickJS](https://bellard.org/quickjs/),
[L-SMASH](https://github.com/l-smash/l-smash), and
[cJSON](https://github.com/DaveGamble/cJSON), keep their own licenses.
