#ifndef RETRO_DLP_PLAYLIST_METADATA_FIXTURES_H
#define RETRO_DLP_PLAYLIST_METADATA_FIXTURES_H

/* Synthetic renderer fixtures. No network or thumbnail downloads are used. */
static const char playlist_metadata_browse[] =
    "{\"contents\":[{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\",\"title\":{\"runs\":[{\"text\":\"A \"},{\"text"
    "\":\"rich title\"}]},\"lengthSeconds\":\"62\",\"shortBylineText\":{\"runs\":[{\"text\":\"The \"},{\"text\":\"channel\","
    "\"navigationEndpoint\":{\"browseEndpoint\":{\"browseId\":\"UC_fixture\"}}}]},\"thumbnail\":{\"thumbnails\":[{\"ur"
    "l\":\"https://img.example/small.jpg\"},{\"url\":\"https://img.example/large.jpg\"},{\"url\":false},{}]},\"view"
    "CountText\":{\"runs\":[{\"text\":\"1,234\"},{\"text\":\" views\"}]},\"publishedTimeText\":{\"simpleText\":\"2 days a"
    "go\"},\"descriptionSnippet\":{\"runs\":[{\"text\":\"Hello \"},{\"text\":\"world…\"}]}}},{\"playlistVideoRenderer\":"
    "{\"videoId\":\"AAAAAAAAAAA\"}},{\"playlistVideoRenderer\":{\"videoId\":\"BBBBBBBBBBB\",\"title\":{\"simpleText\":\""
    "Zero\"},\"lengthSeconds\":0,\"viewCountText\":{\"simpleText\":\"No views\"}}},{\"playlistVideoRenderer\":{\"vide"
    "oId\":\"CCCCCCCCCCC\",\"title\":{\"simpleText\":\"Malformed\"},\"lengthSeconds\":-1,\"lengthText\":{\"simpleText\":"
    "\"1:99\"},\"thumbnail\":{\"thumbnails\":{}},\"publishedTimeText\":12,\"descriptionSnippet\":{\"runs\":[{},{\"text"
    "\":false}]},\"viewCountText\":{\"simpleText\":\"1,2 views\"}}},{\"playlistVideoRenderer\":{\"videoId\":\"DDDDDDD"
    "DDDD\",\"title\":{\"simpleText\":\"Fallbacks\"},\"lengthSeconds\":\"invalid\",\"thumbnailOverlays\":[{\"thumbnailO"
    "verlayTimeStatusRenderer\":{\"text\":{\"runs\":[{\"text\":\"1:02:03\"}]}}}],\"ownerText\":{\"simpleText\":\"Owner "
    "only\"},\"detailedMetadataSnippets\":[{\"snippetText\":{\"runs\":[{\"text\":\"Detailed \"},{\"text\":\"snippet\"}]}"
    "}],\"videoInfo\":{\"simpleText\":\"1.2M views • 10 years ago\"}}},{\"playlistVideoRenderer\":{\"videoId\":\"EEE"
    "EEEEEEEE\",\"title\":{\"simpleText\":\"Live\"},\"thumbnailOverlays\":[{\"thumbnailOverlayTimeStatusRenderer\":{"
    "\"text\":{\"simpleText\":\"LIVE\"},\"style\":\"LIVE\"}}],\"viewCountText\":{\"simpleText\":\"123 views\"}}},{\"playli"
    "stVideoRenderer\":{\"videoId\":\"FFFFFFFFFFF\",\"title\":{\"simpleText\":\"Upcoming\"},\"upcomingEventData\":{\"st"
    "artTime\":\"12345\"},\"viewCountText\":{\"simpleText\":\"100 views\"}}},{\"playlistVideoRenderer\":{\"videoId\":\""
    "GGGGGGGGGGG\",\"title\":{\"simpleText\":\"Fraction\"},\"lengthSeconds\":1.5,\"shortViewCountText\":{\"simpleText"
    "\":\"1.2M views\"}}},{\"continuationItemRenderer\":{\"continuationEndpoint\":{\"continuationCommand\":{\"token"
    "\":\"metadata-page-two\"}}}}]}"
    ;

static const char playlist_metadata_continuation[] =
    "{\"onResponseReceivedActions\":[{\"appendContinuationItemsAction\":{\"continuationItems\":[{\"lockupViewMod"
    "el\":{\"contentId\":\"HHHHHHHHHHH\",\"contentType\":\"LOCKUP_CONTENT_TYPE_VIDEO\",\"contentImage\":{\"thumbnailV"
    "iewModel\":{\"image\":{\"sources\":[{\"url\":\"https://img.example/lockup.jpg\"}]},\"overlays\":[{\"thumbnailBot"
    "tomOverlayViewModel\":{\"badges\":[{\"thumbnailBadgeViewModel\":{\"text\":\"HD\"}},{\"thumbnailBadgeViewModel\""
    ":{\"text\":\"2:03\"}}]}}]}},\"metadata\":{\"lockupMetadataViewModel\":{\"title\":{\"content\":\"Lockup title\"},\"m"
    "etadata\":{\"contentMetadataViewModel\":{\"metadataRows\":[{\"metadataParts\":[{\"text\":{\"content\":\"Lockup C"
    "hannel\",\"commandRuns\":[{\"onTap\":{\"innertubeCommand\":{\"browseEndpoint\":{\"browseId\":\"UC_lockup\"}}}}]}}"
    "]},{\"metadataParts\":[{\"text\":{\"content\":\"12,345 views\"}},{\"text\":{\"content\":\"3 weeks ago\"},\"accessib"
    "ilityLabel\":\"Published 3 weeks ago\"}]}]}}}}}},{\"lockupViewModel\":{\"contentId\":\"IIIIIIIIIII\",\"content"
    "Type\":\"LOCKUP_CONTENT_TYPE_VIDEO\",\"contentImage\":{\"thumbnailViewModel\":{\"image\":{\"sources\":[{\"url\":\""
    "https://img.example/lockup.jpg\"}]},\"overlays\":[{\"thumbnailBottomOverlayViewModel\":{\"badges\":[{\"thumb"
    "nailBadgeViewModel\":{\"text\":\"HD\"}},{\"thumbnailBadgeViewModel\":{\"text\":\"UPCOMING\"}}]}}]}},\"metadata\":"
    "{\"lockupMetadataViewModel\":{\"title\":{\"content\":\"Lockup title\"},\"metadata\":{\"contentMetadataViewModel"
    "\":{\"metadataRows\":[{\"metadataParts\":[{\"text\":{\"content\":\"Lockup Channel\",\"commandRuns\":[{\"onTap\":{\"i"
    "nnertubeCommand\":{\"browseEndpoint\":{\"browseId\":\"UC_lockup\"}}}}]}}]},{\"metadataParts\":[{\"text\":{\"cont"
    "ent\":\"100 views\"}},{\"text\":{\"content\":\"Tomorrow\"},\"accessibilityLabel\":\"Tomorrow\"}]}]}}}}}}]}}]}"
    ;

static const char playlist_metadata_absent[] =
    "{\"contents\":[{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\",\"title\":{\"simpleText\":\"Absent\"}}},{\"c"
    "ontinuationItemRenderer\":{\"continuationEndpoint\":{\"continuationCommand\":{\"token\":\"metadata-page-two\""
    "}}}}]}"
    ;

static const char playlist_metadata_absent_continuation[] =
    "{\"contents\":[{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\",\"title\":{\"simpleText\":\"Duplicate\"}}}]"
    "}"
    ;

static const char playlist_metadata_browse_bootstrap[] =
    "<html><script>ytcfg.set({\"INNERTUBE_API_KEY\":\"fixture-key\",\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"1.202"
    "60915.00.00\"});var ytInitialData={\"contents\":[{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\",\"tit"
    "le\":{\"runs\":[{\"text\":\"A \"},{\"text\":\"rich title\"}]},\"lengthSeconds\":\"62\",\"shortBylineText\":{\"runs\":[{"
    "\"text\":\"The \"},{\"text\":\"channel\",\"navigationEndpoint\":{\"browseEndpoint\":{\"browseId\":\"UC_fixture\"}}}]"
    "},\"thumbnail\":{\"thumbnails\":[{\"url\":\"https://img.example/small.jpg\"},{\"url\":\"https://img.example/lar"
    "ge.jpg\"},{\"url\":false},{}]},\"viewCountText\":{\"runs\":[{\"text\":\"1,234\"},{\"text\":\" views\"}]},\"published"
    "TimeText\":{\"simpleText\":\"2 days ago\"},\"descriptionSnippet\":{\"runs\":[{\"text\":\"Hello \"},{\"text\":\"world"
    "…\"}]}}},{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\"}},{\"playlistVideoRenderer\":{\"videoId\":\"BBB"
    "BBBBBBBB\",\"title\":{\"simpleText\":\"Zero\"},\"lengthSeconds\":0,\"viewCountText\":{\"simpleText\":\"No views\"}}"
    "},{\"playlistVideoRenderer\":{\"videoId\":\"CCCCCCCCCCC\",\"title\":{\"simpleText\":\"Malformed\"},\"lengthSecond"
    "s\":-1,\"lengthText\":{\"simpleText\":\"1:99\"},\"thumbnail\":{\"thumbnails\":{}},\"publishedTimeText\":12,\"descr"
    "iptionSnippet\":{\"runs\":[{},{\"text\":false}]},\"viewCountText\":{\"simpleText\":\"1,2 views\"}}},{\"playlistV"
    "ideoRenderer\":{\"videoId\":\"DDDDDDDDDDD\",\"title\":{\"simpleText\":\"Fallbacks\"},\"lengthSeconds\":\"invalid\","
    "\"thumbnailOverlays\":[{\"thumbnailOverlayTimeStatusRenderer\":{\"text\":{\"runs\":[{\"text\":\"1:02:03\"}]}}}],"
    "\"ownerText\":{\"simpleText\":\"Owner only\"},\"detailedMetadataSnippets\":[{\"snippetText\":{\"runs\":[{\"text\":"
    "\"Detailed \"},{\"text\":\"snippet\"}]}}],\"videoInfo\":{\"simpleText\":\"1.2M views • 10 years ago\"}}},{\"playl"
    "istVideoRenderer\":{\"videoId\":\"EEEEEEEEEEE\",\"title\":{\"simpleText\":\"Live\"},\"thumbnailOverlays\":[{\"thum"
    "bnailOverlayTimeStatusRenderer\":{\"text\":{\"simpleText\":\"LIVE\"},\"style\":\"LIVE\"}}],\"viewCountText\":{\"si"
    "mpleText\":\"123 views\"}}},{\"playlistVideoRenderer\":{\"videoId\":\"FFFFFFFFFFF\",\"title\":{\"simpleText\":\"Up"
    "coming\"},\"upcomingEventData\":{\"startTime\":\"12345\"},\"viewCountText\":{\"simpleText\":\"100 views\"}}},{\"pl"
    "aylistVideoRenderer\":{\"videoId\":\"GGGGGGGGGGG\",\"title\":{\"simpleText\":\"Fraction\"},\"lengthSeconds\":1.5,"
    "\"shortViewCountText\":{\"simpleText\":\"1.2M views\"}}},{\"continuationItemRenderer\":{\"continuationEndpoin"
    "t\":{\"continuationCommand\":{\"token\":\"metadata-page-two\"}}}}]};</script></html>"
    ;

static const char playlist_metadata_absent_bootstrap[] =
    "<html><script>ytcfg.set({\"INNERTUBE_API_KEY\":\"fixture-key\",\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"1.202"
    "60915.00.00\"});var ytInitialData={\"contents\":[{\"playlistVideoRenderer\":{\"videoId\":\"AAAAAAAAAAA\",\"tit"
    "le\":{\"simpleText\":\"Absent\"}}},{\"continuationItemRenderer\":{\"continuationEndpoint\":{\"continuationComm"
    "and\":{\"token\":\"metadata-page-two\"}}}}]};</script></html>"
    ;

#endif
