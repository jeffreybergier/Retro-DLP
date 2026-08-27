Sat, Aug 1 at 5:47 PM
Can you investigate the feasibility of porting a very small portion of the yt-dlp which I think is written in python to use iOS 4.3 SDK and Clang 15? Basically I want the ability of yt-dlp to generate the URL of a video that we can then use CURL to fetch. We do not need to do any video conversion or anything. just get the URL. We would nee to port this code to C... and we can use something like the tiny embedded javascript library created by the French guy that made ffmpeg. I can't remember the name in order to execute javascript required by YouTube to get this URL. Please investigate thoroughly because this is an app I really want to make for my iPhone 4 running iOS 4.3. I always build apps for it with this toolchain and it works great.
Feasibility verdict
Yes—this is feasible, provided the first version is deliberately narrow. The JavaScript engine you were remembering is QuickJS, created by Fabrice Bellard and Charlie Gordon. It is an interpreter rather than a JIT, is designed to be embedded as a few C source files, and has an efficient 32-bit representation that is well suited to ARMv7.
The practical project is not really “port a tiny part of yt-dlp from Python to C.” It is:

Write a small C YouTube playback resolver modeled on yt-dlp, and embed yt-dlp’s JavaScript challenge solver inside QuickJS.
As of August 1, 2026, I would rate the likely outcomes this way:
Goal	Feasibility
Public, logged-out, non-live videos with a progressive MP4 stream	Good
Videos whose URL requires current s and n JavaScript solving	Reasonable with QuickJS + yt-dlp-ejs
High-resolution video without combining separate audio/video streams	Poor
Age-restricted, private, members-only, or account-dependent videos	Outside a sensible first version
Live streams and YouTube’s newer SABR streaming path	Outside a sensible first version
Videos requiring a newly generated PO token	Major unresolved maintenance risk
A maintenance-free resolver that keeps working indefinitely	Not realistic
Current yt-dlp now treats an external JavaScript runtime and its separate yt-dlp-ejs package as necessary for full YouTube support. The current extractor defaults to the visionos, android_vr, and web clients, with the first two specifically marked as “JSless” clients. It nevertheless gathers s and n challenges from returned format URLs and solves them in bulk when necessary.
What “get the URL” involves in 2026
A simplified resolver now looks like this:
YouTube URL
    ↓
Extract 11-character video ID
    ↓
Call YouTube's Innertube player API
    ↓
Read streamingData.formats
    ↓
┌───────────────────────────────────────────┐
│ Direct URL?                               │
│   yes → possibly transform its "n" value │
│   no  → parse signatureCipher             │
│         solve "s" signature               │
└───────────────────────────────────────────┘
    ↓
Attach a PO token when the chosen client/format requires one
    ↓
Select a muxed H.264/AAC MP4
    ↓
Return URL + headers + cookies + expiration information
    ↓
Download with libcurl
There are three independent moving parts.
1. Innertube player requests
You send a JSON request containing a client context and the video ID to YouTube’s internal player endpoint. Depending on the client, the request may also need a signature timestamp, visitor data, cookies, or a player PO token.
A schematic body is:

{
  "context": {
    "client": {
      "clientName": "CLIENT_NAME",
      "clientVersion": "CLIENT_VERSION",
      "hl": "en",
      "timeZone": "UTC",
      "utcOffsetMinutes": 0
    }
  },
  "videoId": "XXXXXXXXXXX",
  "contentCheckOk": true,
  "racyCheckOk": true,
  "playbackContext": {
    "contentPlaybackContext": {
      "signatureTimestamp": 12345
    }
  }
}
The client names, versions, numeric IDs, user agents, API key, and policy flags need to live in an updateable configuration file, not as permanent C constants. Current yt-dlp changes these values regularly. Its present defaults are visionos, android_vr, and web; both visionos and android_vr currently permit player requests without first obtaining the JavaScript player.
2. s and n JavaScript challenges
A format can contain either:
{
  "url": "https://....googlevideo.com/...?n=CHALLENGE..."
}
or:
{
  "signatureCipher": "url=...&s=ENCRYPTED_SIGNATURE&sp=sig"
}
For signatureCipher:
URL-decode url.
pass s through the signature solver;
append the result using the parameter named by sp, defaulting to signature.
For a URL containing n, transform the existing n value and replace it in the URL. Current yt-dlp first collects all such challenges, solves them in one batch, and then constructs the final URLs.
3. PO tokens
A Proof of Origin token is not another player-JavaScript signature. It is a separate anti-abuse attestation result. Depending on the client, YouTube may require a PO token for:
the Innertube player request;
the Google Video Server media request;
subtitles.
The current yt-dlp documentation describes tokens produced through BotGuard for web clients, DroidGuard for Android, and iOSGuard for iOS. Tokens can be bound to a visitor/session or to a particular video ID, and enforcement is still changing.
This distinction is critical:

QuickJS plus yt-dlp-ejs solves s and n. It does not generate PO tokens.
The MVP I recommend for the iPhone 4
The first release should support:
ordinary public videos;
logged-out access;
non-live videos;
a single progressive MP4 containing both video and audio;
H.264/AVC video and AAC audio;
direct URLs and signatureCipher;
n transformation;
no playlists, subtitles, comments, metadata scraping, manifests, merging, or conversion.
The ideal first format is itag 18. Current yt-dlp expressly exempts stream ID 18 when deciding whether an HTTPS format must be discarded for lack of a GVS PO token. That exemption could change, but it makes itag 18 unusually valuable for this application today.
A muxed H.264/AAC MP4 is also exactly what you want for an iPhone 4. Apple documents support for H.264 up to 720p/30, Main Profile level 3.1, with AAC-LC in MP4/M4V/MOV. The familiar itag 18 stream is normally a much safer 360p AVC/AAC combination and requires no remuxing.

The initial unsupported cases should be explicit rather than partially working:

typedef enum {
    YT_OK = 0,
    YT_ERR_NETWORK,
    YT_ERR_INVALID_VIDEO_ID,
    YT_ERR_UNAVAILABLE,
    YT_ERR_LOGIN_REQUIRED,
    YT_ERR_LIVE_UNSUPPORTED,
    YT_ERR_DRM_UNSUPPORTED,
    YT_ERR_NO_PROGRESSIVE_MP4,
    YT_ERR_PO_TOKEN_REQUIRED,
    YT_ERR_JS_CHALLENGE,
    YT_ERR_PROTOCOL_CHANGED
} YTStatus;
That will make the app much easier to maintain than attempting yt-dlp-style fallbacks for every possible video category.
Recommended extraction strategy
First path: API-first, no webpage
For each configured JSless client:
Build its Innertube context.
POST to the player endpoint.
Check playabilityStatus.
Inspect only streamingData.formats.
Look for a non-DRM, non-live, non-OTF, muxed MP4.
Prefer itag == 18.
If the format has an immediately usable URL without n, return it without even starting QuickJS.
Current yt-dlp skips DRM formats, live adaptive entries, and FORMAT_STREAM_TYPE_OTF entries in its normal HTTPS-format path. Your first implementation should do the same.
This path is important for the iPhone 4 because it means many resolutions may require:

one JSON request;
one small JSON parse;
no HTML parsing;
no player JavaScript download;
no QuickJS runtime work.
Second path: obtain and process the player JavaScript
When a candidate has signatureCipher or an n challenge:
Obtain the current player JavaScript URL.
It may be available in the player response.
Otherwise fetch the watch page.
Download base.js.
Pass it and all collected challenges to yt-dlp-ejs running in QuickJS.
Cache the resulting preprocessed player.
construct the final media URL.
For watch-page parsing, do not use one enormous regular expression. Write a small balanced-brace scanner that understands JavaScript strings and escapes, and extract only:
ytInitialPlayerResponse;
ytcfg.set(...);
the player JavaScript URL;
visitor data when present.
That is still much less work than porting yt-dlp’s general extraction machinery.
Third path: additional client fallback
A sensible present-day client order would be approximately:
visionos
android_vr
web_embedded, for embeddable videos
web, only when needed
Do not treat this order as permanent. For example, the current source warns that:
android_vr does not expose made-for-kids videos;
versions above a certain point may return SABR-only streams;
selective PO-token enforcement has been observed since July 2026.
The current PO-token wiki still lists android_vr as not requiring a token, while the newer extractor source contains that selective-enforcement warning. That discrepancy is a strong demonstration of why the client table needs to be updateable.
Use yt-dlp-ejs rather than porting the decipher logic to C
This is the most encouraging part of the investigation.
yt-dlp has already separated the volatile player-JavaScript analysis into the yt-dlp-ejs project. Its current solver:

parses the complete YouTube player with Meriyah;
walks and modifies its JavaScript AST;
generates a reduced player program using Astring;
extracts solvers for sig and n;
executes the generated code;
optionally returns a preprocessed_player value that can be cached.
Its input model is already almost perfect for a C embedding:
{
  "type": "player",
  "player": "THE COMPLETE BASE.JS SOURCE",
  "requests": [
    {
      "type": "sig",
      "challenges": ["ENCRYPTED_SIGNATURE"]
    },
    {
      "type": "n",
      "challenges": ["N_VALUE"]
    }
  ],
  "output_preprocessed": true
}
On later videos using the same player:
{
  "type": "preprocessed",
  "preprocessed_player": "CACHED REDUCED PLAYER",
  "requests": [
    {
      "type": "sig",
      "challenges": ["..."]
    },
    {
      "type": "n",
      "challenges": ["..."]
    }
  ]
}
The EJS code only exposes n and sig request types, so its boundary is small and well defined.
The current packaged EJS wheel is only about 53.4 kB compressed, so storage is not a problem. Runtime memory while parsing the complete player AST will be much more significant than the bundle’s on-disk size.

Important QuickJS feature requirements
Do not build an excessively stripped QuickJS context initially. EJS currently uses:
Function(...);
Set;
Object.fromEntries;
regular expressions;
JSON;
generated modern JavaScript syntax.
In particular, the solver directly evaluates its reduced player using:
Function("_result", code)(resultObj)
Therefore QuickJS’s eval/compiler support must remain enabled.
Start with JS_NewContext(). After everything works, you can investigate JS_NewContextRaw() with an explicitly selected set of intrinsics, but the memory saving may not justify the extra compatibility risk.

Porting QuickJS to the iOS 4.3 SDK
I see no architectural blocker. There is one very likely source patch and then a number of things to smoke-test against your exact SDK.
Compile only the engine
Use the release sources for:
quickjs.c
dtoa.c
libregexp.c
libunicode.c
cutils.c
Do not compile:
qjs.c
qjsc.c
quickjs-libc.c
You do not want QuickJS’s command-line interpreter, POSIX-flavored std/os library, dynamic modules, filesystem access, or process-launching support.
The JavaScript environment should contain no native networking or filesystem APIs at all. C downloads the player source and passes a string into JavaScript; JavaScript returns transformed strings.

Disable QuickJS Atomics
Current QuickJS automatically enables CONFIG_ATOMICS on non-Emscripten platforms. That path includes C atomics and pthread support and uses clock_gettime(CLOCK_REALTIME) for Atomics.wait. It is unnecessary for EJS and is the first thing likely to cause trouble when targeting the iOS 4.3 SDK. QuickJS’s own documentation explicitly says Atomics may be disabled on systems where their support is unavailable.
I would make this tiny upstream patch:

/* quickjs.c */

#if !defined(__EMSCRIPTEN__) && !defined(QJS_NO_ATOMICS)
#define CONFIG_ATOMICS
#endif
Then build with:
-DQJS_NO_ATOMICS
Simply passing -UCONFIG_ATOMICS will not be sufficient because quickjs.c defines it again internally.
Also call:

JS_SetCanBlock(runtime, 0);
Likely compiler flags
Adapted to your existing SDK setup, the QuickJS portion should be built approximately as:
-arch armv7
-miphoneos-version-min=4.3
-std=gnu11
-Os
-fwrapv
-DQJS_NO_ATOMICS
Clang 15 provides the necessary modern C front end even though the target SDK is old. QuickJS is an interpreter and does not require writable executable memory or JIT support.
The current implementation specifically uses NaN boxing for its 32-bit build, keeping each JSValue in two CPU registers. That is favorable for an ARMv7 device rather than an unsupported afterthought.

Resource containment
The player script is untrusted input. QuickJS supplies the controls needed to contain it:
JS_SetMemoryLimit(runtime, measured_limit);
JS_SetMaxStackSize(runtime, measured_stack_limit);
JS_SetInterruptHandler(runtime, deadline_callback, deadline_context);
JS_SetCanBlock(runtime, 0);
QuickJS documents memory, stack, and interrupt limits directly. It also documents that a runtime does not support concurrent execution internally, so keep it on one serial resolver thread or dispatch queue.
I would use one persistent runtime/context that has EJS loaded once. Destroy and recreate it after:

an interrupt timeout;
an out-of-memory exception;
an unexpected uncaught exception;
a configurable number of player preprocess operations.
That prevents one malformed or unusually large player from leaving the runtime in a questionable state.
Cache aggressively
The expensive operation is not transforming one n string. It is parsing the entire base.js player into an AST.
Cache by canonical player JavaScript URL or a cryptographic hash:

player URL/hash
    → raw base.js
    → EJS preprocessed_player
    → discovered sig/n solvers
Many different videos use the same player version. A cold resolution might need to parse the player; subsequent resolutions should reuse preprocessed_player.
Do not download QuickJS bytecode as an update format. QuickJS states that bytecode is version-specific and does not receive security validation before execution. Use signed JavaScript source assets for updates. A built-in bundle could optionally be compiled with qjsc, but remotely updated bundles should remain source text.

C project architecture
I would divide the code approximately like this:
Component	Responsibility
yt_url.c	Extract and validate video IDs
yt_http.c	libcurl sessions, cookies, headers, redirects, compression
yt_json.c	JSON parsing and typed accessors
yt_clients.c	Load updateable Innertube client definitions
yt_player.c	Build player requests and parse playability/streaming data
yt_watch.c	Limited watch-page and player-URL extraction
yt_ejs.c	QuickJS lifetime and EJS invocation
yt_formats.c	Parse, filter, solve, and rank formats
yt_pot.c	Abstract PO-token provider interface
yt_cache.c	Client manifests, player JS, and preprocessed player cache
A suitable public result type would be:
typedef struct {
    char *name;
    char *value;
} YTHeader;

typedef struct {
    char *url;

    YTHeader *headers;
    size_t header_count;

    char *cookie_header;

    int64_t expires_unix;
    int64_t content_length;

    int itag;
    int width;
    int height;

    char *mime_type;
    char *video_codec;
    char *audio_codec;
} YTMediaRequest;

YTStatus yt_resolve_video(
    YTContext *context,
    const char *youtube_url_or_id,
    YTMediaRequest *result
);
Even though the main product is a URL, returning only char *url is unnecessarily fragile. The media request may need the same:
user agent;
origin/referer;
cookies;
visitor/session context;
PO token;
expiry information.
The downloader should therefore use the same YTContext cookie state or a copy of its libcurl cookie list.
For TLS, use your own current libcurl/TLS stack and a current CA bundle rather than depending on the 2011 system trust environment. Curl supports selectable TLS backends and dedicated CA bundles. Certificate verification should remain enabled.

Format filtering
For the first release, inspect only streamingData.formats and require:
mimeType starts with video/mp4
codecs contain both AVC/H.264 and AAC
no drmFamilies
not FORMAT_STREAM_TYPE_OTF
not a live adaptive format
has URL or a complete signatureCipher
has both video and audio
Ranking can be very simple:
score = 0;

if (itag == 18)
    score += 10000;

if (has_h264 && has_aac)
    score += 1000;

if (is_muxed)
    score += 1000;

score += height;
Do not accidentally select a video-only entry from adaptiveFormats. Without remuxing it will produce silent video, and without decoding/re-encoding it cannot be turned into the single file you want.
A useful validation step before returning success is:

Range: bytes=0-4095
Accept 206 Partial Content or a valid small 200 response, and confirm that the beginning looks like an ISO Base Media File Format file, normally containing an ftyp box. This catches:
expired URLs;
bad n transformations;
missing PO tokens;
wrong headers;
HTML error pages returned with status 200.
For a longer download, remember that the URL can expire. Record an expiration timestamp where available. On expiration, resolve the same video again, confirm the same itag and content length, and resume with a byte range.
The PO-token problem
This is the part that prevents me from calling the project “easy.”
The present yt-dlp PO-token guide says:

PO-token enforcement is still being rolled out;
affected URLs can return HTTP 403 without a token;
some tokens are bound to a video ID;
manually obtaining tokens is no longer recommended;
provider plugins are the preferred mechanism;
BotGuard, DroidGuard, and iOSGuard tokens are platform-specific.
The featured BotGuard provider is not a tiny decipher function. It is an HTTP service or generated script using BgUtils and currently requires Node 20+ or Deno 2+. BgUtils itself warns that merely executing the BotGuard code is not sufficient: the runtime environment must satisfy BotGuard’s checks.
So these are separate projects:

Reasonable first project
Innertube + format parsing + EJS/QuickJS + itag 18
Much harder future project
BotGuard/DroidGuard/iOSGuard environment emulation and PO generation
I would create a provider boundary now even though the initial implementation returns “unavailable”:
typedef enum {
    YT_POT_PLAYER,
    YT_POT_GVS,
    YT_POT_SUBTITLES
} YTPoTokenType;

typedef YTStatus (*YTPoTokenProvider)(
    void *opaque,
    YTPoTokenType type,
    const char *client_name,
    const char *video_id,
    const char *visitor_data,
    char **token_out
);
Possible providers can later be:
no provider;
cached/manual provider for development;
on-device provider, should that become practical;
optional modern companion service.
The standalone client should always be attempted first. A companion should be a fallback, not a fundamental requirement.
Maintenance design matters more than C versus Python
The C resolver itself is manageable. The volatile data must be updateable independently:
{
  "manifest_version": 17,
  "minimum_resolver_version": 3,
  "clients": {
    "visionos": {
      "client_name": "VISIONOS",
      "client_name_id": 101,
      "client_version": "...",
      "user_agent": "...",
      "api_key": "...",
      "requires_player_js": false,
      "pot_policy": "..."
    }
  },
  "ejs": {
    "version": "0.8.0",
    "core_sha256": "...",
    "lib_sha256": "..."
  }
}
The app should ship with a last-known-good manifest and EJS bundle, then optionally download a signed update. The update should be:
verified using a public key built into the executable;
atomically installed;
versioned;
rollback-capable;
rejected when it requires a newer native resolver.
This mirrors an important current yt-dlp behavior: yt-dlp pins itself to a specific EJS version instead of assuming arbitrary solver versions are interchangeable.
Development sequence
1. Build a desktop C resolver first
Make a command-line program such as:
ytresolve VIDEO_ID
Output:
{
  "url": "https://....googlevideo.com/...",
  "itag": 18,
  "width": 640,
  "height": 360,
  "mimeType": "video/mp4",
  "expires": 1785580000,
  "headers": {
    "User-Agent": "..."
  }
}
Use current desktop yt-dlp as the comparison oracle. For each test video, compare:
selected itag;
final host and important query fields;
s result;
n result;
range-request success.
Current yt-dlp itself uses the public Big Buck Bunny upload as one of its basic YouTube extractor tests, making it a reasonable initial fixture.
2. Implement direct itag 18 only
No QuickJS yet:
parse video ID;
call one JSless client;
parse JSON;
return an immediately usable itag 18 URL;
verify with a range request.
That proves the network, JSON, client configuration, format selection, and download pipeline.
3. Add QuickJS and EJS
Test EJS independently before integrating it with HTTP:
base.js fixture + known s/n input
    → C/QuickJS/EJS
    → expected transformed output
Then connect it to live player responses.
4. Add caches
Cache:
client manifest;
player JavaScript;
preprocessed_player;
successful client choice for a limited period;
failure classifications.
5. Cross-compile for armv7/iOS 4.3
At this point the platform-specific work is largely:
QuickJS compilation;
libcurl/TLS compilation;
filesystem cache locations;
memory instrumentation;
Objective-C wrapper/UI.
6. Add the signed update channel
Do this before trying to support many edge cases. It will save repeated application rebuilds whenever YouTube changes a client version or EJS release.
Expected size and performance
My rough engineering estimate—not a measurement—is:
roughly 1,000–2,000 lines of C for an intentionally crude direct-itag 18 proof of concept;
roughly 3,000–8,000 lines of application C for good error handling, caching, multiple clients, EJS integration, and testing;
plus QuickJS, libcurl/TLS, and a C JSON parser.
For comparison, the current yt-dlp YouTube video extractor file alone is more than 4,300 lines, but most of it concerns metadata, playlists, manifests, subtitles, live streams, multiple audio tracks, authentication, format ranking, and years of edge cases that this app can omit.
On the iPhone 4, the likely expensive cold operation is Meriyah parsing a complete modern YouTube player script into an AST. The mitigations are strong:

bypass JavaScript entirely for direct URLs;
invoke EJS only when necessary;
batch all challenges;
cache preprocessed_player;
keep only one chosen format;
release the raw player and temporary AST results promptly;
run resolution off the UI thread.
I have not compiled the current QuickJS release against the iOS 4.3 SDK or benchmarked EJS on an Apple A4, so transient memory consumption and cold-solve latency remain the two platform questions that require a real device test. From static source inspection, disabling Atomics is the only obvious SDK-age-specific QuickJS change; there may still be minor libc or libm compatibility adjustments exposed by the actual link.
Licensing and service terms
The code-licensing situation is favorable:
yt-dlp itself uses the Unlicense;
yt-dlp-ejs uses the Unlicense;
the bundled Meriyah and Astring code use ISC and MIT respectively;
QuickJS uses MIT.
The commonly used BgUtils PO-token provider is GPL-3.0, so directly incorporating its source would introduce separate GPL obligations.
Separately, YouTube’s current terms restrict unauthorized downloading, circumvention, and automated access. The resolver should therefore be used for content and use cases for which you have authorization; distributing it broadly may create terms-of-service and review concerns independent of the open-source licenses.

Bottom line
I think this app is worth building. A small, useful, completely native iOS 4.3 resolver is technically plausible today when scoped to public VODs and muxed H.264/AAC—especially itag 18.
The correct design is:

C resolver
+ libcurl/current TLS
+ small C JSON parser
+ embedded QuickJS
+ bundled/updateable yt-dlp-ejs
+ updateable Innertube client definitions
+ explicit future PO-token provider interface
The primary risk is not Clang 15, ARMv7, QuickJS, or the age of UIKit. Those all appear tractable. The primary risk is YouTube’s continuing migration toward PO-token enforcement and SABR streaming. Designing the client around an updateable protocol manifest and a clean PO-provider boundary turns that from an immediate blocker into a later, separable problem.





