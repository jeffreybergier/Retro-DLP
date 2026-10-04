# Retro-DLP

Retro-DLP is a minimal re-implementation of yt-dlp written in C for retro Apple
devices. It's a C library plus a CLI for iOS 5+ and Mac OS X 10.4+. As well there
are simple GUI applications written for iOS 5+ and Mac OS X 10.4+.

Retro-DLP integrates several open source projects into 1 working solution:

- libcurl + OpenSSL: Modern networking with TLS 1.2 support
- QuickJS: Amazing C library that provides a working JavaScript runtime
- L-SMASH: Amazing C library that can mux audio and video files together into a single mp4
- SQLite: Provides a database for the GUI applications

## How it Works

Retro-DLP basically tries to do exactly what yt-delp does. It downloads
the Player Javascript, uses QuickJS to solve a challenge written in Javascript, 
downloads the audio and video files, then uses L-SMASH to mux them together into
a single H.264 file that your device can play back. 

The main thing that distinguishes it from yt-dlp is that it is written in C and
depends only on C libraries and thus can run on basically any device, no matter 
how old.

## Demo Videos

TBD

## Features

### Mac and iPhone Apps

- Download videos manually
- Add playlists manually
- Sync playlists from your account (read-only)
- Download videos at your specified quality level
- Download management
- Download queue
- Video Playback (VLC on Mac and custom player on iOS)
- Playlist Playback (VLC on Mac and custom player on iOS)
- Add cookies for authentication

### Command-Line Tool

Copies the yt-dlp command line arguments as best as possible given its limited
subset of features.

- Download videos at a specified quality
- Authenticate with a cookies file
- List a playlist
- List your playlists

### C Library

Core functionality written in a platform agnostic way. The library and the
CLI should be compatible and usable on any UNIX style OS on pretty much any
kind of hardware.

## Architecture

## Compatibility

Retro-DLP should work on any UNIX style OS on pretty much any hardware. But
the tested configurations and the binaries I distribute are compatible with
the following

- Mac OS X GUI: 10.4 Tiger - 10.14 Mojave - PowerPC and i386
- Mac OS X CLI: 10.4 Tiger - 10.14 Mojave - PowerPC and i386
- iOS GUI: iOS 5+ - armv7 and arm64 - Tested on iOS 6/8/15
   - Requires Jailbreak or install with [Impactor](https://github.com/claration/Impactor)
- iOS CLI: iOS 5+ - armv7 and arm64
   - Requires Jailbreak and a Terminal Application

## Video Formats

Retro-DLP downloads videos as MP4 files containing H.264 (AVC) video
and AAC audio. It supports both progressive MP4 files (video and audio already
combined) and separate video and audio tracks, which L-SMASH combines into one
MP4 without re-encoding.

| Media | Supported formats |
| --- | --- |
| Video | H.264 / AVC (`avc1`) in MP4 |
| Progressive audio | AAC-LC (`mp4a.40.2`) |
| Separate audio tracks | AAC-LC (`mp4a.40.2`) or HE-AAC (`mp4a.40.5`), mono or stereo |
| Output | MP4 containing both video and audio |


### Formats and Presets

Different videos have different video and audio formats available and they
are specified as numbers separated by a + sign. In the CLI to select a format 
manually use `-f`, to see available formats for a video use `-F`, and `-t` 
to use a preset below.

| Preset | Resolution | Format IDs |
| --- | --- | --- |
| `low` (Default) | 360p | `18` (combined video and audio) |
| `med` | 720p → 480p → 360p | `136+140/135+140/18` |
| `high` | 1080p → 720p → 480p → 360p | `137+140/136+140/135+140/18` |

Fallbacks apply when a format is unavailable during selection, not when
a media download fails (for example, with HTTP 403).

### Recommended Formats

It is important to remember that these videos are H.264 encoded which is a
very intense codec for retro computers. Read more about that in my blog post
[Retro Stream Tutorial.](https://jeffburg.com/retro-tech/2025/08/17/Retro-Stream-Tutorial.html#why-cant-old-computers-play-youtube)

- PPC Macs: 360p (18) 480p (135+140) are likely to play whereas 720p (136+140) ~~might~~ play
- Intel Macs: Untested, but 720p (136+140) and 1080p (137+140) will likely play
- Retina iOS Devices: 720p (136+140) can sometimes appear pixelated. 1080p (137+140) plays fine but take up a lot more disk space
- Non-Retina iOS Devices: Untested but 720p (136+140) will likely play and should look fantastic

## Known limitations:

- WebM, VP8, VP9, AV1, HEVC, and Opus are not supported. There is no
  transcoding, audio extraction, or audio-only download mode.
- Format selection accepts numeric IDs, `+` to pair video and audio, and `/`
  for alternatives, such as `137+140/136+140/18`. General yt-dlp selectors
  such as `bestvideo`, codec filters, and sorting expressions are not supported.
- The library's automatic adaptive selection is limited to 720p or 1080p,
  at up to 30 fps, with AAC-LC audio. Explicit format IDs can select HE-AAC
  and do not impose those resolution or frame-rate limits, but the codecs
  must still be supported and the requested tracks must be available.
- The original audio track is always selected for downloaded. Other languages
  are not selectable.
- Retro-DLP uses `mweb` client and does not generate Proof of
  Origin (PO) tokens.
  
### PO Tokens

PO Tokens are a tricky subject even for the original yt-dlp. Basically, 
Retro-DLP has sufficient JavaScript chops via QuickJS that it can solve the 
simple JavaScript Player Challenge and find the URL's for the videos. However,
if you select a video format higher quality than 360p (18), your download will 
likely fail because of lack of a PO token. Stick to 360p OR you can 
authenticate with an account that is a Premium account. But before you do that,
please read the as its and the Cookies Extraction Guide not a simple problem 
and there are risks.

- [PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/Po-Token-Guide)
- [Cookies Extraction Guide](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies)

## Install from Releases

### iOS

### Mac

### Command-Line Tool

## Using Retro-DLP

### Downloading Videos

### Playlists

## Compile from Source

### BYOSDK

### Mac and iOS

### Linux

### Running Tests

## Source Map

## Contributing

### Wish List

## Credits

## Status and License
