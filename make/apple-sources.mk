CLI_SOURCES := $(PROJECT_ROOT)/source/cli/main.c $(PROJECT_ROOT)/source/cli/cli.c \
	$(PROJECT_ROOT)/source/cli/cli_options.c $(PROJECT_ROOT)/source/cli/cli_render.c \
	$(PROJECT_ROOT)/source/cli/cli_assets.c $(PROJECT_ROOT)/source/cli/cli_asset_store.c
CORE_SOURCES := $(PROJECT_ROOT)/source/library/shared/retrodlp.c \
	$(PROJECT_ROOT)/source/library/shared/retrodlp_assets.c $(PROJECT_ROOT)/source/library/shared/rdlp_curl.c \
	$(PROJECT_ROOT)/source/library/shared/rdlp_ejs_manifest.c \
	$(PROJECT_ROOT)/source/library/shared/yt_http.c $(PROJECT_ROOT)/source/library/shared/yt_resolver.c \
	$(PROJECT_ROOT)/source/library/shared/yt_formats.c $(PROJECT_ROOT)/source/library/shared/yt_challenges.c \
	$(PROJECT_ROOT)/source/library/shared/yt_failure_cache.c \
	$(PROJECT_ROOT)/source/library/shared/yt_innertube.c \
	$(PROJECT_ROOT)/source/library/shared/yt_playlist.c $(PROJECT_ROOT)/source/library/shared/yt_session.c \
	$(PROJECT_ROOT)/source/library/shared/yt_util.c $(PROJECT_ROOT)/source/library/shared/yt_webpage.c \
	$(PROJECT_ROOT)/source/library/shared/yt_cache.c $(PROJECT_ROOT)/source/library/shared/yt_crypto.c $(PROJECT_ROOT)/source/library/shared/yt_cookies.c \
	$(PROJECT_ROOT)/source/library/shared/yt_ejs.c $(PROJECT_ROOT)/source/library/shared/yt_ejs_assets.c
DOWNLOAD_SOURCES := $(PROJECT_ROOT)/source/library/shared/retrodlp_download.c $(PROJECT_ROOT)/source/library/shared/yt_mux.c
SHARED_SOURCES := $(CLI_SOURCES) $(CORE_SOURCES) $(DOWNLOAD_SOURCES)
CJSON_DIR := $(PROJECT_ROOT)/source/deps/cJSON
CJSON_SOURCE := $(CJSON_DIR)/cJSON.c
QUICKJS_DIR := $(PROJECT_ROOT)/source/deps/QuickJS
QUICKJS_VERSION := $(shell cat $(QUICKJS_DIR)/VERSION 2>/dev/null)
QUICKJS_SOURCE_NAMES := quickjs.c dtoa.c libregexp.c libunicode.c cutils.c \
	quickjs-libc.c
LSMASH_DIR := $(PROJECT_ROOT)/source/deps/L-SMASH
LSMASH_SOURCE_NAMES := common/alloc.c common/bits.c common/bytes.c \
	common/list.c common/multibuf.c common/osdep.c common/utils.c \
	codecs/a52.c codecs/alac.c codecs/description.c codecs/dts.c \
	codecs/h264.c codecs/hevc.c codecs/id.c codecs/mp4sys.c codecs/mp4a.c \
	codecs/mp4v.c codecs/nalu.c codecs/qt_wfex.c codecs/vc1.c codecs/wma.c \
	importer/a52_imp.c importer/adts_imp.c importer/als_imp.c \
	importer/amr_imp.c importer/dts_imp.c importer/importer.c \
	importer/isobm_imp.c importer/mp3_imp.c importer/nalu_imp.c \
	importer/vc1_imp.c importer/wave_imp.c core/box.c core/box_default.c \
	core/box_type.c core/chapter.c core/file.c core/fragment.c core/isom.c \
	core/meta.c core/print.c core/read.c core/summary.c core/timeline.c \
	core/write.c
