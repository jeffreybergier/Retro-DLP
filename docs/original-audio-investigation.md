# Original audio investigation

Investigated 2026-09-25 against Retro-DLP commit
`1f846b82c69f25c5db43b11a184199d8d06b9ecd`.

## Downloads on gomadango

Read the production app over SSH and copied its SQLite database (including WAL)
and the two completed MP4s with SCP. The copied database passed SQLite's integrity
check. No production files were changed.

| Job | YouTube video | Title | Requested / actual format |
| --- | --- | --- | --- |
| 21 | `Od6M0AXpcxQ` | iPhone 18 Pro/Duo Impressions: Mogged | `136+140` / `136+140` |
| 22 | `6D__H_DO2Xk` | iPhone Duo: What We Missed! | `136+140` / `136+140` |

Fresh YouTube metadata identifies Marques Brownlee as the author of both videos.
Both copied MP4s contain H.264 video and one AAC audio stream. Both audio streams
have `language=und`; the database records no selected audio-track ID or language.
Consequently, these artifacts do not independently establish the reported Chinese
language. The original player responses used during those downloads were not
available in the copied library database.

## Reproduction

Fetched fresh player responses using Retro-DLP's MWEB client name, version,
user agent, and English metadata locale. Compiled a temporary C harness that
includes the checkout's unmodified `yt_formats.c` and calls
`find_exact_candidate(document, 140, 0, 1, &selected)`.

| Video | Current selector chooses | Chosen bitrate | Available original bitrate |
| --- | --- | --- | --- |
| `Od6M0AXpcxQ` | Turkish dub (`tr.3`) | 131398 | 131264 |
| `6D__H_DO2Xk` | Turkish dub (`tr.3`) | 131058 | 130934 |

Bitrates are the integer `bitrate` values from YouTube, in bits per second.
The selected URLs carry `xtags=acont=dubbed:lang=tr`. Both responses also contain
`audioTrack.displayName="English original"`, `audioTrack.id="en.4"`, and
`audioIsDefault=true`; those URLs carry `acont=original:lang=en`.

Restricting the same responses to original audio variants makes the unchanged
selector choose the non-DRC `en.4` track for both videos. This verifies that the
original tracks meet the existing AAC/MP4 compatibility requirements. It is a
selection test, not an end-to-end download test. Attempts to fetch fresh audio
samples directly without solving the URL challenge returned HTTP 403, so no
byte comparison with the phone's audio was completed.

These fresh responses reproduce incorrect dub selection, but do not establish
which dub the earlier download response selected.

## Cause in Retro-DLP

- `source/gui/shared/rdapp_service.c` passes the job's numeric format expression
  directly to the library. Both affected jobs therefore use exact selection.
- `read_format_candidate()` in `source/library/shared/yt_formats.c` reads bitrate
  and DRC status, but ignores `audioTrack` entirely.
- `exact_candidate_is_better()` prefers non-DRC, then URLs without challenges,
  then higher bitrate. Multiple languages can share itag `140`.
- `adaptive_audio_is_better()` similarly compares bitrate without track identity.
- `add_format_info()` collapses variants sharing an itag, media type, and MIME
  type. The public format inventory cannot distinguish languages either.
- Format expressions accept numeric itags, `+`, and `/`; there is no current
  original-audio option or language filter.

## yt-dlp's handling

Reviewed upstream master `c7fb478d21e9e59524befbe23f7801bb267fb880`:

- [YouTube extractor](https://github.com/yt-dlp/yt-dlp/blob/c7fb478d21e9e59524befbe23f7801bb267fb880/yt_dlp/extractor/youtube/_video.py):
  checks `audioTrack.displayName` case-insensitively. Descriptive audio gets
  preference -10, original audio 10, default audio 5, and other audio -1.
  Stream identity includes the itag, audio-track ID, and DRC flag.
- [Format sorter](https://github.com/yt-dlp/yt-dlp/blob/c7fb478d21e9e59524befbe23f7801bb267fb880/yt_dlp/utils/_utils.py):
  uses `language_preference` ahead of quality and bitrate in its default order.

`audioIsDefault` alone is insufficient: yt-dlp explicitly distinguishes default
from original. Checking for English would also fail the desired behavior for
videos whose originals use another language.

## Proposed library behavior

Parse the original/default/descriptive classification and track ID, then choose
original audio before comparing DRC, URL challenges, or bitrate. Apply this to
both exact and automatic selection, including audio-bearing progressive variants
when track metadata is present. Existing expressions such as `136+140` can retain
their syntax; this can be the library's default behavior without a new UI setting.

For a strict original-audio requirement, do not silently choose a known dub if
the original is identified but unavailable in a supported format. Ordinary
single-track videos without track metadata should continue to work. Ambiguous
multi-track responses with no original marker need an explicit fallback policy;
yt-dlp's default-track fallback is a preference, not proof of originality.

Useful regression cases include a higher-bitrate dub, a default dub alongside an
original, a non-English original alongside an English dub, DRC original variants,
missing track metadata, and an unavailable supported original. Retaining the
selected track ID/language in diagnostics would make future reports verifiable.

Local investigation artifacts and the C reproduction harness are in
`/tmp/retro-dlp-audio-investigation/`. The initial investigation made no
implementation or deployment changes.

## Implementation follow-up

The library now filters audio by original track identity in exact, automatic,
and progressive selection. Ambiguous multiple-track responses fail instead of
choosing a default dub. A single non-alternate track or a response without track
metadata remains supported. The selected language is available through
`rdlp_selection_media_audio_language` and is written as ISO 639-2/T metadata on
the audio track during adaptive MP4 muxing.

The fixed selector selects `acont=original:lang=en` for both saved MWEB responses.
Offline regressions cover multilingual selection, unsupported originals,
fallbacks, and real MP4 language metadata. Independent `ffprobe` checks verified
`eng`, `jpn`, `zho`, and `und`, with unchanged SHA-256 hashes for every audio and
video packet. No deployment or modification of gomadango's downloads was made.
