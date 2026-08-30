PROGRAM := retro-dlp
VERSION_PLIST := source/shared/Info.plist
VERSION ?= $(shell awk '/<key>CFBundleShortVersionString<\/key>/{getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit}' $(VERSION_PLIST))
BUILD_DIR := build
INTERMEDIATE_DIR := $(BUILD_DIR)/intermediates
MACOS_BUILD_DIR := $(BUILD_DIR)/macOS
MACOS_LEGACY_BUILD_DIR := $(MACOS_BUILD_DIR)/ppc-i386
MACOS_MODERN_BUILD_DIR := $(MACOS_BUILD_DIR)/x86_64-arm64
IOS_BUILD_DIR := $(BUILD_DIR)/iOS
LINUX_BUILD_DIR := $(BUILD_DIR)/linux

CLI_SOURCES := source/shared/main.c source/shared/cli.c \
	source/shared/cli_options.c source/shared/cli_render.c \
	source/shared/cli_assets.c source/shared/cli_asset_store.c
CORE_SOURCES := source/shared/retrodlp.c \
	source/shared/retrodlp_assets.c source/shared/rdlp_curl.c \
	source/shared/rdlp_ejs_manifest.c \
	source/shared/yt_http.c source/shared/yt_resolver.c \
	source/shared/yt_formats.c source/shared/yt_challenges.c \
	source/shared/yt_failure_cache.c \
	source/shared/yt_innertube.c \
	source/shared/yt_playlist.c source/shared/yt_session.c \
	source/shared/yt_util.c source/shared/yt_webpage.c \
	source/shared/yt_cache.c source/shared/yt_crypto.c source/shared/yt_cookies.c \
	source/shared/yt_ejs.c source/shared/yt_ejs_assets.c
DOWNLOAD_SOURCES := source/shared/retrodlp_download.c source/shared/yt_mux.c
SHARED_SOURCES := $(CLI_SOURCES) $(CORE_SOURCES) $(DOWNLOAD_SOURCES)
TEST_SOURCES := \
	source/shared/test/allocation_test.c source/shared/test/cache_test.c \
	source/shared/test/cookie_test.c \
	source/shared/test/ejs_test.c source/shared/test/ejs_test_data.c \
	source/shared/test/self_test.c source/shared/test/self_test_data.c \
	source/shared/test/yt_formats_test_support.c
MACOS_COMMON_SOURCES := $(CLI_SOURCES)
IOS_COMMON_SOURCES := $(CLI_SOURCES)
CJSON_DIR := source/deps/cJSON
CJSON_SOURCE := $(CJSON_DIR)/cJSON.c
QUICKJS_DIR := source/deps/QuickJS
QUICKJS_VERSION := $(shell cat $(QUICKJS_DIR)/VERSION 2>/dev/null)
QUICKJS_SOURCE_NAMES := quickjs.c dtoa.c libregexp.c libunicode.c cutils.c \
	quickjs-libc.c
LSMASH_DIR := source/deps/L-SMASH
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
LSMASH_CPPFLAGS := -I$(LSMASH_DIR)
LSMASH_CFLAGS := $(CFLAGS) -std=c99 -Wall -Wextra -Wno-unused-parameter
LINUX_SOURCES := $(CLI_SOURCES)
LINUX_TEST_PROGRAM := retro-dlp-tests
LINUX_CONSUMER_TEST_PROGRAM := retro-dlp-consumer-test
LINUX_DOWNLOAD_CONSUMER_TEST_PROGRAM := retro-dlp-download-consumer-test
LINUX_LIBRARY := $(LINUX_BUILD_DIR)/libretrodlp.a
LINUX_DOWNLOAD_LIBRARY := $(LINUX_BUILD_DIR)/libretrodlp-download.a
MACOS_LIBRARY := $(MACOS_BUILD_DIR)/libretrodlp.a
MACOS_DOWNLOAD_LIBRARY := $(MACOS_BUILD_DIR)/libretrodlp-download.a
MACOS_LEGACY_PROGRAM := $(MACOS_LEGACY_BUILD_DIR)/$(PROGRAM)
MACOS_MODERN_PROGRAM := $(MACOS_MODERN_BUILD_DIR)/$(PROGRAM)
IOS_LIBRARY := $(IOS_BUILD_DIR)/libretrodlp.a
IOS_DOWNLOAD_LIBRARY := $(IOS_BUILD_DIR)/libretrodlp-download.a
LINUX_CONSUMER_TEST_SOURCE := source/linux/test/public_consumer.c
LINUX_DOWNLOAD_CONSUMER_TEST_SOURCE := source/linux/test/download_consumer.c
LINUX_EXAMPLE_DIR := $(LINUX_BUILD_DIR)/examples
LINUX_RESOLVER_EXAMPLE_NAMES := resolve authenticated playlist custom_transport
LINUX_RESOLVER_EXAMPLES := $(addprefix $(LINUX_EXAMPLE_DIR)/, \
	$(LINUX_RESOLVER_EXAMPLE_NAMES))
LINUX_DOWNLOAD_EXAMPLE := $(LINUX_EXAMPLE_DIR)/download
LINUX_EXAMPLE_OBJECTS := $(addprefix $(LINUX_INT_DIR)/examples/, \
	$(addsuffix .o,$(LINUX_RESOLVER_EXAMPLE_NAMES) download))
LINUX_TEST_SOURCES := $(filter-out source/shared/main.c, \
	$(SHARED_SOURCES)) $(TEST_SOURCES) source/linux/test/test_main.c \
	source/linux/platform.c $(CJSON_SOURCE)

ALTIVEC_ROOT ?= /altivec
# Linux-only targets must remain usable outside the Apple build container.
-include $(ALTIVEC_ROOT)/altivec_toolchains.mk

ALTIVECCORE_DIR ?= $(ALTIVEC_ROOT)/libs/core/build-mac
ALTIVECCORE := $(ALTIVECCORE_DIR)/lib/libAltivecCore.a
ALTIVEC_CRYPTO := $(ALTIVECCORE_DIR)/lib/libcrypto.a
MACOS_CA_SOURCE := $(ALTIVECCORE_DIR)/lib/cacert.pem
MACOS_CA_BUNDLE := $(MACOS_BUILD_DIR)/cacert.pem

IOS_ALTIVECCORE_DIR ?= $(ALTIVEC_ROOT)/libs/core/build-phone
IOS_ALTIVECCORE := $(IOS_ALTIVECCORE_DIR)/lib/libAltivecCore.a
IOS_ALTIVEC_CRYPTO := $(IOS_ALTIVECCORE_DIR)/lib/libcrypto.a
IOS_CA_SOURCE := $(IOS_ALTIVECCORE_DIR)/lib/cacert.pem
IOS_CA_BUNDLE := $(IOS_BUILD_DIR)/cacert.pem

SDK_MAC_OLD := 10.5
SDK_MAC_NEW := 11.3
MAC_MIN_OLD := 10.4
MAC_MIN_X64 := 10.9
MAC_MIN_ARM64 := 11.0
IOS_MIN_ARMV7 := 5.0
IOS_MIN_ARM64 := 7.0

CPPFLAGS ?=
PROJECT_CPPFLAGS := -Iinclude -Isource/shared -I$(QUICKJS_DIR) \
	-Isource/deps/L-SMASH \
	-DRETRO_DLP_VERSION=\"$(VERSION)\"
MACOS_BASE_CPPFLAGS := $(CPPFLAGS) $(PROJECT_CPPFLAGS) \
	-I$(ALTIVECCORE_DIR)/include
LINUX_CPPFLAGS := $(CPPFLAGS) $(PROJECT_CPPFLAGS) -I$(CJSON_DIR)
QUICKJS_CPPFLAGS := -I$(QUICKJS_DIR) -D_GNU_SOURCE \
	-DCONFIG_VERSION=\"$(QUICKJS_VERSION)\"
CFLAGS ?= -O3 -g
LDFLAGS ?=
LDLIBS ?=
PREFIX ?= /usr/local
DESTDIR ?=
INSTALL ?= install
ZERO_AR_DATE ?= 1
export ZERO_AR_DATE
COMMON_CFLAGS := $(CFLAGS) -std=c99 -Wall -Wextra -Werror
QUICKJS_CFLAGS := $(CFLAGS) -std=gnu11 -Wall -Wextra -funsigned-char \
	-fwrapv -Wno-sign-compare -Wno-missing-field-initializers \
	-Wno-unused-parameter -Wno-discarded-qualifiers \
	-Wno-implicit-fallthrough
MACOS_BASE_LIBRARIES := $(ALTIVECCORE) -framework Foundation \
	-framework CoreFoundation -framework SystemConfiguration -lobjc \
	$(ALTIVEC_CRYPTO)

MACOS_INT_DIR := $(INTERMEDIATE_DIR)/macOS
IOS_INT_DIR := $(INTERMEDIATE_DIR)/iOS
LINUX_INT_DIR := $(INTERMEDIATE_DIR)/linux
QUICKJS_INT_DIR := $(LINUX_INT_DIR)/QuickJS
QUICKJS_OBJECTS := $(addprefix $(QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o))
QUICKJS_LIBRARY := $(LINUX_INT_DIR)/libquickjs.a
LINUX_LSMASH_INT_DIR := $(LINUX_INT_DIR)/L-SMASH
LINUX_LSMASH_OBJECTS := $(addprefix $(LINUX_LSMASH_INT_DIR)/, \
	$(LSMASH_SOURCE_NAMES:.c=.o))
LINUX_LSMASH_LIBRARY := $(LINUX_INT_DIR)/liblsmash.a
LINUX_LIBRARIES := -Wl,--whole-archive $(QUICKJS_LIBRARY) \
	-Wl,--no-whole-archive $(LINUX_LSMASH_LIBRARY) \
	-lcurl -lcrypto -lm -ldl -lpthread
LINUX_OBJECTS := $(LINUX_SOURCES:%.c=$(LINUX_INT_DIR)/%.o)
LINUX_TEST_OBJECTS := $(LINUX_TEST_SOURCES:%.c=$(LINUX_INT_DIR)/%.o)
LINUX_LIBRARY_SOURCES := $(CORE_SOURCES) source/linux/platform.c \
	$(CJSON_SOURCE)
LINUX_LIBRARY_OBJECTS := $(LINUX_LIBRARY_SOURCES:%.c=$(LINUX_INT_DIR)/%.o)
LINUX_DOWNLOAD_OBJECTS := $(DOWNLOAD_SOURCES:%.c=$(LINUX_INT_DIR)/%.o)
LINUX_CONSUMER_TEST_OBJECT := \
	$(LINUX_INT_DIR)/$(LINUX_CONSUMER_TEST_SOURCE:.c=.o)
LINUX_DOWNLOAD_CONSUMER_TEST_OBJECT := \
	$(LINUX_INT_DIR)/$(LINUX_DOWNLOAD_CONSUMER_TEST_SOURCE:.c=.o)

include source/make/apple-gcc4.mk
include source/make/clang.mk
include source/make/ios-clang.mk

OTOOL_MODERN ?= $(MODERN_BIN)/otool

APPLICATION_DEPENDENCIES := $(LINUX_OBJECTS:.o=.d) \
	$(LINUX_TEST_OBJECTS:.o=.d) $(PPC_OBJECTS:.o=.d) \
	$(LINUX_CONSUMER_TEST_OBJECT:.o=.d) \
	$(LINUX_DOWNLOAD_CONSUMER_TEST_OBJECT:.o=.d) \
	$(LINUX_EXAMPLE_OBJECTS:.o=.d) \
	$(LINUX_LSMASH_OBJECTS:.o=.d) \
	$(I386_OBJECTS:.o=.d) $(X86_64_OBJECTS:.o=.d) $(ARM64_OBJECTS:.o=.d) \
	$(IOS_OBJECTS:.o=.d) $(PPC_LSMASH_OBJECTS:.o=.d) \
	$(I386_LSMASH_OBJECTS:.o=.d) $(X86_64_LSMASH_OBJECTS:.o=.d) \
	$(ARM64_LSMASH_OBJECTS:.o=.d) $(IOS_ARMV7_LSMASH_OBJECTS:.o=.d) \
	$(IOS_ARM64_LSMASH_OBJECTS:.o=.d)
-include $(APPLICATION_DEPENDENCIES)

$(LINUX_INT_DIR)/source/shared/yt_ejs.o \
$(MACOS_INT_DIR)/ppc/source/shared/yt_ejs.o \
$(MACOS_INT_DIR)/i386/source/shared/yt_ejs.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter

$(MACOS_INT_DIR)/x86_64/source/shared/yt_ejs.o \
$(MACOS_INT_DIR)/arm64/source/shared/yt_ejs.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter -Wno-sign-conversion

$(IOS_INT_DIR)/source/shared/yt_ejs.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter -Wno-sign-conversion

$(LINUX_INT_DIR)/source/shared/test/self_test.o \
$(MACOS_INT_DIR)/ppc/source/shared/test/self_test.o \
$(MACOS_INT_DIR)/i386/source/shared/test/self_test.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter

$(MACOS_INT_DIR)/x86_64/source/shared/test/self_test.o \
$(MACOS_INT_DIR)/arm64/source/shared/test/self_test.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter -Wno-sign-conversion

$(IOS_INT_DIR)/source/shared/test/self_test.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter -Wno-sign-conversion

.DEFAULT_GOAL := release

release: macOS iOS

macOS: validate $(MACOS_LEGACY_PROGRAM) $(MACOS_MODERN_PROGRAM) \
	$(MACOS_LIBRARY) \
	$(MACOS_DOWNLOAD_LIBRARY) $(MACOS_CA_BUNDLE)

iOS: validate-iOS $(IOS_BUILD_DIR)/$(PROGRAM) $(IOS_LIBRARY) \
	$(IOS_DOWNLOAD_LIBRARY) $(IOS_CA_BUNDLE)

linux: $(LINUX_BUILD_DIR)/$(PROGRAM) $(LINUX_LIBRARY) \
	$(LINUX_DOWNLOAD_LIBRARY)

test: linux $(LINUX_BUILD_DIR)/$(LINUX_TEST_PROGRAM) \
		$(LINUX_BUILD_DIR)/$(LINUX_CONSUMER_TEST_PROGRAM) \
		$(LINUX_BUILD_DIR)/$(LINUX_DOWNLOAD_CONSUMER_TEST_PROGRAM) \
		validate-package validate-examples
	@echo "--- Running retro-dlp Linux tests ---"
	@source/linux/test/cli_test.sh \
		"$(abspath $(LINUX_BUILD_DIR)/$(PROGRAM))" \
		"$(abspath $(LINUX_BUILD_DIR)/$(LINUX_TEST_PROGRAM))"
	@$(LINUX_BUILD_DIR)/$(LINUX_CONSUMER_TEST_PROGRAM)
	@source/linux/test/download_test.sh \
		"$(abspath $(LINUX_BUILD_DIR)/$(LINUX_DOWNLOAD_CONSUMER_TEST_PROGRAM))"

examples: $(LINUX_RESOLVER_EXAMPLES) $(LINUX_DOWNLOAD_EXAMPLE)

validate-examples: examples
	@$(LINUX_EXAMPLE_DIR)/custom_transport
	@echo "PASS: public API examples compile and offline example runs"

install: linux
	@$(INSTALL) -d "$(DESTDIR)$(PREFIX)/include/retrodlp" \
		"$(DESTDIR)$(PREFIX)/lib" "$(DESTDIR)$(PREFIX)/bin"
	@$(INSTALL) -m 644 include/retrodlp/retrodlp.h \
		include/retrodlp/assets.h include/retrodlp/download.h \
		include/retrodlp/version.h \
		"$(DESTDIR)$(PREFIX)/include/retrodlp/"
	@$(INSTALL) -m 644 $(LINUX_LIBRARY) $(LINUX_DOWNLOAD_LIBRARY) \
		"$(DESTDIR)$(PREFIX)/lib/"
	@$(INSTALL) -m 755 $(LINUX_BUILD_DIR)/$(PROGRAM) \
		"$(DESTDIR)$(PREFIX)/bin/"

validate-package: $(LINUX_LIBRARY) $(LINUX_DOWNLOAD_LIBRARY)
	@source/linux/test/package_consumer_test.sh \
		"$(abspath .)" "$(abspath $(BUILD_DIR))" "$(CC)" "$(CXX)" \
		"$(CFLAGS)" "$(LDFLAGS)" "$(LDLIBS)"

package-libraries: linux macOS iOS
	@source/make/package-library.sh linux "$(BUILD_DIR)"
	@source/make/package-library.sh macOS "$(BUILD_DIR)"
	@source/make/package-library.sh iOS "$(BUILD_DIR)"

validate-apple-artifacts: macOS iOS
	@source/make/validate-apple-artifacts.sh \
		"$(LIPO)" "$(LIPO_MODERN)" "$(OTOOL_MODERN)" "$(BUILD_DIR)"

sanitize:
	@$(MAKE) --no-print-directory -f source/make/Makefile \
		BUILD_DIR="$(BUILD_DIR)/sanitize" \
		CFLAGS="-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined" \
		LDFLAGS="-fsanitize=address,undefined" test

$(MACOS_LEGACY_PROGRAM): $(PPC_BINARY) $(I386_BINARY)
	@echo " [5/5] Merging legacy binary (ppc, i386)..."
	@mkdir -p $(dir $@)
	@$(LIPO) -create $^ -output $@
	@echo "  > $@"

$(MACOS_MODERN_PROGRAM): $(X86_64_BINARY) $(ARM64_BINARY)
	@echo " [5/5] Merging modern binary (x86_64, arm64)..."
	@mkdir -p $(dir $@)
	@$(LIPO) -create $^ -output $@
	@echo "  > $@"

$(MACOS_LIBRARY): $(PPC_LIBRARY) $(I386_LIBRARY) $(X86_64_LIBRARY) \
		$(ARM64_LIBRARY)
	@echo "  > merging quad-fat resolver library"
	@mkdir -p $(dir $@)
	@$(LIPO) -create $^ -output $@

$(MACOS_DOWNLOAD_LIBRARY): $(PPC_DOWNLOAD_LIBRARY) \
		$(I386_DOWNLOAD_LIBRARY) $(X86_64_DOWNLOAD_LIBRARY) \
		$(ARM64_DOWNLOAD_LIBRARY)
	@echo "  > merging quad-fat optional download library"
	@mkdir -p $(dir $@)
	@$(LIPO) -create $^ -output $@

$(MACOS_CA_BUNDLE): $(MACOS_CA_SOURCE)
	@echo "  > copying macOS CA certificate bundle"
	@mkdir -p $(dir $@)
	@cp $< $@

$(IOS_CA_BUNDLE): $(IOS_CA_SOURCE)
	@echo "  > copying iOS CA certificate bundle"
	@mkdir -p $(dir $@)
	@cp $< $@

$(LINUX_BUILD_DIR)/$(PROGRAM): $(LINUX_OBJECTS) \
		$(LINUX_DOWNLOAD_LIBRARY) $(LINUX_LIBRARY)
	@echo "--- Building retro-dlp Linux Release (-O3) ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LDFLAGS) $(LINUX_OBJECTS) $(LINUX_DOWNLOAD_LIBRARY) \
		$(LINUX_LIBRARY) -lcurl -lcrypto -lm -ldl -lpthread \
		$(LDLIBS) -o $@
	@echo "  > $@"

$(LINUX_BUILD_DIR)/$(LINUX_TEST_PROGRAM): $(LINUX_TEST_OBJECTS) \
		$(QUICKJS_LIBRARY) $(LINUX_LSMASH_LIBRARY)
	@echo "--- Building retro-dlp Linux Tests ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LDFLAGS) -Wl,--wrap=malloc -Wl,--wrap=calloc \
		$(LINUX_TEST_OBJECTS) $(LINUX_LIBRARIES) $(LDLIBS) -o $@
	@echo "  > $@"

$(LINUX_BUILD_DIR)/$(LINUX_CONSUMER_TEST_PROGRAM): \
		$(LINUX_CONSUMER_TEST_OBJECT) $(LINUX_LIBRARY)
	@echo "--- Building public API consumer test ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LDFLAGS) $(LINUX_CONSUMER_TEST_OBJECT) $(LINUX_LIBRARY) \
		-lcurl -lcrypto -lm -ldl -lpthread \
		$(LDLIBS) -o $@
	@echo "  > $@"

$(LINUX_BUILD_DIR)/$(LINUX_DOWNLOAD_CONSUMER_TEST_PROGRAM): \
		$(LINUX_DOWNLOAD_CONSUMER_TEST_OBJECT) $(LINUX_DOWNLOAD_LIBRARY) \
		$(LINUX_LIBRARY)
	@echo "--- Building optional download API consumer test ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LDFLAGS) $(LINUX_DOWNLOAD_CONSUMER_TEST_OBJECT) \
		$(LINUX_DOWNLOAD_LIBRARY) $(LINUX_LIBRARY) \
		-lcurl -lcrypto -lm -ldl -lpthread $(LDLIBS) -o $@
	@echo "  > $@"

$(LINUX_EXAMPLE_DIR)/%: $(LINUX_INT_DIR)/examples/%.o $(LINUX_LIBRARY)
	@echo "--- Building public API example $(@F) ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LDFLAGS) $< $(LINUX_LIBRARY) \
		-lcurl -lcrypto -lm -ldl -lpthread $(LDLIBS) -o $@
	@echo "  > $@"

$(LINUX_DOWNLOAD_EXAMPLE): $(LINUX_INT_DIR)/examples/download.o \
		$(LINUX_DOWNLOAD_LIBRARY) $(LINUX_LIBRARY)
	@echo "--- Building optional download example ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LDFLAGS) $< $(LINUX_DOWNLOAD_LIBRARY) $(LINUX_LIBRARY) \
		-lcurl -lcrypto -lm -ldl -lpthread $(LDLIBS) -o $@
	@echo "  > $@"

$(LINUX_LIBRARY): $(LINUX_LIBRARY_OBJECTS) $(QUICKJS_OBJECTS)
	@echo "  > archiving resolver library"
	@mkdir -p $(dir $@)
	@$(AR) rcs $@ $^

$(LINUX_DOWNLOAD_LIBRARY): $(LINUX_DOWNLOAD_OBJECTS) \
		$(LINUX_LSMASH_OBJECTS)
	@echo "  > archiving optional download library"
	@mkdir -p $(dir $@)
	@$(AR) rcs $@ $^

$(QUICKJS_LIBRARY): $(QUICKJS_OBJECTS)
	@echo "  > archiving QuickJS static library"
	@$(AR) rcs $@ $^

$(LINUX_LSMASH_LIBRARY): $(LINUX_LSMASH_OBJECTS)
	@echo "  > archiving Linux L-SMASH static library"
	@$(AR) rcs $@ $^

$(LINUX_LSMASH_INT_DIR)/%.o: $(LSMASH_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(CC) $(LSMASH_CPPFLAGS) $(LSMASH_CFLAGS) \
		-Wno-sign-compare -Wno-missing-field-initializers \
		-MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(CC) $(QUICKJS_CPPFLAGS) $(QUICKJS_CFLAGS) -c $< -o $@

$(LINUX_INT_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	@$(CC) $(LINUX_CPPFLAGS) $(COMMON_CFLAGS) $(SOURCE_WARNING_FLAGS) \
		-MMD -MP -MF $(@:.o=.d) -c $< -o $@

validate:
	@test -d "$(SDK_PPC_PATH)" || \
		{ echo "Missing SDK: $(SDK_PPC_PATH)" >&2; exit 1; }
	@test -d "$(SDK_X86_PATH)" || \
		{ echo "Missing SDK: $(SDK_X86_PATH)" >&2; exit 1; }
	@test -d "$(SDK_X64_PATH)" || \
		{ echo "Missing SDK: $(SDK_X64_PATH)" >&2; exit 1; }
	@test -d "$(SDK_ARM64_PATH)" || \
		{ echo "Missing SDK: $(SDK_ARM64_PATH)" >&2; exit 1; }
	@test -n "$(COMPILER_X64)" -a -x "$(COMPILER_X64)" || \
		{ echo "Missing x86_64 compiler" >&2; exit 1; }
	@test -n "$(COMPILER_ARM64)" -a -x "$(COMPILER_ARM64)" || \
		{ echo "Missing arm64 compiler" >&2; exit 1; }
	@test -f "$(ALTIVECCORE)" || \
		{ echo "Missing AltivecCore: $(ALTIVECCORE)" >&2; exit 1; }
	@test -f "$(ALTIVEC_CRYPTO)" || \
		{ echo "Missing libcrypto: $(ALTIVEC_CRYPTO)" >&2; exit 1; }

validate-iOS:
	@test -d "$(SDK_IOS_PATH)" || \
		{ echo "Missing SDK: $(SDK_IOS_PATH)" >&2; exit 1; }
	@test -n "$(COMPILER_IOS)" -a -x "$(COMPILER_IOS)" || \
		{ echo "Missing iOS compiler" >&2; exit 1; }
	@test -f "$(IOS_ALTIVECCORE)" || \
		{ echo "Missing iOS AltivecCore: $(IOS_ALTIVECCORE)" >&2; exit 1; }
	@test -f "$(IOS_ALTIVEC_CRYPTO)" || \
		{ echo "Missing iOS libcrypto: $(IOS_ALTIVEC_CRYPTO)" >&2; exit 1; }
	@test -f "$(IOS_CA_SOURCE)" || \
		{ echo "Missing iOS CA bundle: $(IOS_CA_SOURCE)" >&2; exit 1; }

clean: clean-macOS clean-iOS clean-linux

clean-macOS:
	@echo "Cleaning retro-dlp macOS build artifacts..."
	@for dir in $(MACOS_INT_DIR) $(MACOS_BUILD_DIR); do \
		if [ -d "$$dir" ]; then \
			find "$$dir" -mindepth 1 -maxdepth 1 \
				-exec rm -rf {} +; \
		fi; \
	done

clean-iOS:
	@echo "Cleaning retro-dlp iOS build artifacts..."
	@for dir in $(IOS_INT_DIR) $(IOS_BUILD_DIR); do \
		if [ -d "$$dir" ]; then \
			find "$$dir" -mindepth 1 -maxdepth 1 \
				-exec rm -rf {} +; \
		fi; \
	done

clean-linux:
	@echo "Cleaning retro-dlp Linux build artifacts..."
	@for dir in $(LINUX_INT_DIR) $(LINUX_BUILD_DIR); do \
		if [ -d "$$dir" ]; then \
			find "$$dir" -mindepth 1 -maxdepth 1 \
				-exec rm -rf {} +; \
		fi; \
	done

.PHONY: release macOS iOS linux test sanitize install package-libraries \
	examples validate-examples validate-package validate-apple-artifacts \
	validate validate-iOS clean clean-macOS clean-iOS clean-linux
