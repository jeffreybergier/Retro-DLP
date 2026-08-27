# Retro-DLP

Retro-DLP is a tiny YouTube downloader for old Macs and jailbroken iPhones. I
built it because yt-dlp cannot run on an iPhone 5 with iOS 6 or a PowerPC Mac
with Tiger, but those machines can still play H.264 video just fine.

This is not a full yt-dlp port. Retro-DLP does one job: it downloads ordinary
YouTube videos as MP4 files. It can download a progressive stream or combine
separate H.264 video and AAC audio tracks with its built-in MP4 muxer. It does
not need Python, FFmpeg, or another external executable.

I have tested Retro-DLP on a real iPhone 5 running iOS 6 and a PowerPC Mac
running Mac OS X Tiger. The iPhone successfully downloaded and muxed a
two-hour, 1.8 GB, 1080p video.

## Features

- Downloads YouTube videos from a video ID or common YouTube URL
- Downloads progressive H.264/AAC MP4 streams
- Downloads and muxes separate H.264 video and AAC audio tracks
- Includes `low`, `med`, and `high` quality presets
- Accepts exact yt-dlp-style itags such as `18` or `137+140`
- Lists every format that YouTube advertises with `-F`
- Supports authenticated sessions through Netscape-format cookie files
- Solves YouTube's JavaScript URL challenges with QuickJS and yt-dlp EJS
- Prints normalized, yt-dlp-style metadata with `--dump-json`
- Uses the YouTube title as the default UTF-8 filename
- Writes downloads atomically and refuses to overwrite existing files
- Caches player data and challenge results under `~/.retro-dlp/cache`

## Compatibility

| Platform | Architectures | Minimum OS | I have tested |
|---|---|---|---|
| macOS | PowerPC, i386, x86_64, arm64 | 10.4 for PowerPC/i386, 10.9 for x86_64, 11.0 for arm64 | PowerPC Tiger and modern macOS |
| iOS | armv7, arm64 | iOS 5.0 for armv7, iOS 7.0 for arm64 | iPhone 5 with iOS 6 |
| Linux | Native host architecture | Development build only | Automated tests |

The macOS release contains one quad-fat executable. The iOS release contains
one universal armv7/arm64 executable and requires a jailbroken device.

## Install

Download the macOS or iOS ZIP from
[GitHub Releases](https://github.com/jeffreybergier/Retro-DLP/releases). Keep
`retro-dlp` and `cacert.pem` together because Retro-DLP uses that certificate
bundle for HTTPS.

### Mac

Unzip the macOS release and put both files wherever you want. For example:

```sh
unzip Retro-DLP-X.Y.Z-macOS.zip
mkdir -p ~/.local/bin
mv retro-dlp cacert.pem ~/.local/bin/
chmod +x ~/.local/bin/retro-dlp
~/.local/bin/retro-dlp assets install
```

Add `~/.local/bin` to your `PATH` if your shell does not already include it.

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

I also include [`retro-vlc`](source/iOS/scripts/retro-vlc), a small helper for
VLC on iOS. It finds VLC's Documents directory, changes into it, and downloads
the high preset there so the video immediately appears in VLC. The script
requires `ipainstaller`, VLC with the `org.videolan.vlc-ios` identifier, and a
cookie file at `~/.retro-dlp/cookies.txt`.

```sh
scp source/iOS/scripts/retro-vlc mobile@iphone-ip-address:/var/mobile/bin/
ssh mobile@iphone-ip-address 'chmod 755 /var/mobile/bin/retro-vlc'
retro-vlc VIDEO_ID_OR_URL
```

Run the final command on the iPhone.

## Usage

The presets provide the easiest way to choose a format:

```sh
retro-dlp -t low VIDEO    # 18
retro-dlp -t med VIDEO    # 135+140/134+140
retro-dlp -t high VIDEO   # 137+599/137+140/136+599/136+140
```

`VIDEO` means an 11-character YouTube video ID or a common YouTube URL.
Retro-DLP saves the video as `TITLE.mp4` in the current directory. Use `-o` to
choose another filename.

List the formats for a video:

```sh
retro-dlp -F VIDEO
```

Choose exact formats:

```sh
retro-dlp -f 18 VIDEO
retro-dlp -f 136+140 VIDEO
retro-dlp -f '137+599/137+140/136+140' VIDEO
```

`+` combines one video-only stream with one audio-only stream. `/` tries exact
alternatives from left to right. Retro-DLP never silently picks an unlisted
fallback. Its default format expression is `22/18`.

Print metadata without downloading:

```sh
retro-dlp --dump-json VIDEO
```

Use `--simulate` to resolve a video without downloading it or writing a file.

Use exported YouTube cookies:

```sh
retro-dlp --cookies /path/to/cookies.txt VIDEO
retro-dlp --cookies-default VIDEO
```

`--cookies-default` reads `~/.retro-dlp/cookies.txt`. Cookie files grant access
to your YouTube account, so protect them with `chmod 600` and never commit or
share them.

## Limitations

- Retro-DLP supports YouTube only.
- It handles ordinary videos, not playlists, live streams, subtitles, comments,
  manifests, DRM, or every restricted video.
- It supports H.264 video and mono or stereo AAC audio in MP4 containers. It
  does not support WebM, VP9, AV1, Opus, conversion, or transcoding.
- Its `--format` syntax only supports exact itags, `+` pairs, and `/`
  alternatives. It does not implement yt-dlp's selectors, filters, or automatic
  quality rules.
- It does not generate YouTube PO tokens. YouTube may return HTTP 403 for some
  videos, accounts, or networks even when URL challenge solving succeeds.
- `SUPPORT: Yes` in `--list-formats` means Retro-DLP can download or mux that
  format. It does not guarantee that every old device can play it. For example,
  an iPhone 4 has much stricter playback limits than a modern Mac.
- YouTube changes constantly and can break Retro-DLP without warning.

## Build from Source

Retro-DLP uses the Docker-based
[Altivec Intelligence](https://github.com/jeffreybergier/AltivecIntelligence)
cross-compile environment. The included `compose.yml` runs every build command
inside the prebuilt Altivec Intelligence container, so you do not need to
install the compilers on your computer.

```sh
git clone --recursive https://github.com/jeffreybergier/Retro-DLP.git
cd Retro-DLP
docker compose pull
```

Create `.altivec-sdk` and put these three Apple SDK archives inside it:

```text
MacOSX10.5.sdk.tar.xz
MacOSX11.3.sdk.tar.xz
iPhoneOS8.4.sdk.tar.gz
```

Verify and install the SDKs into the Compose volumes, then build both releases:

```sh
docker compose run --rm altivec-sdk preflight
docker compose run --rm altivec-sdk install
docker compose run --rm altivec "make clean && make macOS && make iOS"
```

The builds land in `build/macOS` and `build/iOS`. Each directory contains the
executable and its matching `cacert.pem`.

Build the native Linux executable or run the offline test suite in the same
container:

```sh
docker compose run --rm altivec "make linux"
docker compose run --rm altivec "make test"
```

The tests use local fixtures and never connect to YouTube or Google Video.

## License

I release Retro-DLP under the [MIT License](LICENSE). cJSON, QuickJS, L-SMASH,
yt-dlp EJS, and the other third-party components keep their own licenses.

## Development Status

Retro-DLP works for my use case, but I still consider it experimental personal
software. See [`PLAN.md`](PLAN.md) for the implementation history and future
work.
