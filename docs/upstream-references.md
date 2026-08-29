# Upstream references

Retro-DLP is an independent C implementation with deliberately narrower scope
than yt-dlp. The following upstream projects and documentation inform its
YouTube protocol handling and embedded JavaScript challenge support:

- [yt-dlp YouTube extractor](https://github.com/yt-dlp/yt-dlp/tree/master/yt_dlp/extractor/youtube)
- [yt-dlp PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide)
- [yt-dlp EJS](https://github.com/yt-dlp/ejs)
- [QuickJS](https://bellard.org/quickjs/)
- [YouTube embedded-player parameters](https://developers.google.com/youtube/player_parameters)

These are research references, not repository dependencies. Client identifiers,
request behavior, challenge formats, and PO-token enforcement can change; code
and fixture updates should link the specific upstream issue, documentation, or
commit that motivated them in the relevant change description.
