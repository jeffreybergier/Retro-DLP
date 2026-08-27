PROGRAM := retro-dlp
VERSION_PLIST := source/shared/Info.plist
VERSION ?= $(shell awk '/<key>CFBundleShortVersionString<\/key>/{getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit}' $(VERSION_PLIST))
BUILD_DIR := build
INTERMEDIATE_DIR := $(BUILD_DIR)/intermediates
MACOS_BUILD_DIR := $(BUILD_DIR)/macOS
IOS_BUILD_DIR := $(BUILD_DIR)/iOS
LINUX_BUILD_DIR := $(BUILD_DIR)/linux

SHARED_SOURCES := source/shared/main.c source/shared/cli.c \
	source/shared/yt_http.c source/shared/yt_resolver.c \
	source/shared/yt_mux.c \
	source/shared/yt_cache.c source/shared/yt_crypto.c source/shared/yt_cookies.c \
	source/shared/yt_ejs.c source/shared/yt_ejs_assets.c
TEST_SOURCES := \
	source/shared/test/cache_test.c source/shared/test/cookie_test.c \
	source/shared/test/ejs_test.c source/shared/test/ejs_test_data.c \
	source/shared/test/self_test.c source/shared/test/self_test_data.c
MACOS_COMMON_SOURCES := $(SHARED_SOURCES) source/macOS/platform.c
IOS_COMMON_SOURCES := $(SHARED_SOURCES) source/iOS/platform.c
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
LINUX_SOURCES := $(SHARED_SOURCES) source/linux/platform.c $(CJSON_SOURCE)
LINUX_TEST_PROGRAM := retro-dlp-tests
LINUX_TEST_SOURCES := $(filter-out source/shared/main.c source/shared/cli.c, \
	$(SHARED_SOURCES)) $(TEST_SOURCES) source/linux/test/test_main.c \
	source/linux/platform.c $(CJSON_SOURCE)

ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/altivec_toolchains.mk

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

CPPFLAGS := -Isource/shared -I$(QUICKJS_DIR) -Isource/deps/L-SMASH \
	-DRETRO_DLP_VERSION=\"$(VERSION)\"
MACOS_BASE_CPPFLAGS := $(CPPFLAGS) -I$(ALTIVECCORE_DIR)/include
LINUX_CPPFLAGS := $(CPPFLAGS) -I$(CJSON_DIR)
QUICKJS_CPPFLAGS := -I$(QUICKJS_DIR) -D_GNU_SOURCE \
	-DCONFIG_VERSION=\"$(QUICKJS_VERSION)\"
CFLAGS ?= -O3 -g
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

include source/make/apple-gcc4.mk
include source/make/clang.mk
include source/make/ios-clang.mk

APPLICATION_DEPENDENCIES := $(LINUX_OBJECTS:.o=.d) \
	$(LINUX_TEST_OBJECTS:.o=.d) $(PPC_OBJECTS:.o=.d) \
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

release: macOS

macOS: validate $(MACOS_BUILD_DIR)/$(PROGRAM) $(MACOS_CA_BUNDLE)

iOS: validate-iOS $(IOS_BUILD_DIR)/$(PROGRAM) $(IOS_CA_BUNDLE)

linux: $(LINUX_BUILD_DIR)/$(PROGRAM)

test: linux $(LINUX_BUILD_DIR)/$(LINUX_TEST_PROGRAM)
	@echo "--- Running retro-dlp Linux tests ---"
	@source/linux/test/cli_test.sh \
		"$(abspath $(LINUX_BUILD_DIR)/$(PROGRAM))" \
		"$(abspath $(LINUX_BUILD_DIR)/$(LINUX_TEST_PROGRAM))"

$(MACOS_BUILD_DIR)/$(PROGRAM): $(PPC_BINARY) $(I386_BINARY) \
		$(X86_64_BINARY) $(ARM64_BINARY)
	@echo " [5/5] Merging quad-fat binary (ppc, i386, x86_64, arm64)..."
	@mkdir -p $(dir $@)
	@$(LIPO) -create $^ -output $@
	@echo "  > $@"

$(MACOS_CA_BUNDLE): $(MACOS_CA_SOURCE)
	@echo "  > copying macOS CA certificate bundle"
	@mkdir -p $(dir $@)
	@cp $< $@

$(IOS_CA_BUNDLE): $(IOS_CA_SOURCE)
	@echo "  > copying iOS CA certificate bundle"
	@mkdir -p $(dir $@)
	@cp $< $@

$(LINUX_BUILD_DIR)/$(PROGRAM): $(LINUX_OBJECTS) $(QUICKJS_LIBRARY) \
		$(LINUX_LSMASH_LIBRARY)
	@echo "--- Building retro-dlp Linux Release (-O3) ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LINUX_OBJECTS) $(LINUX_LIBRARIES) -o $@
	@echo "  > $@"

$(LINUX_BUILD_DIR)/$(LINUX_TEST_PROGRAM): $(LINUX_TEST_OBJECTS) \
		$(QUICKJS_LIBRARY) $(LINUX_LSMASH_LIBRARY)
	@echo "--- Building retro-dlp Linux Tests ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LINUX_TEST_OBJECTS) $(LINUX_LIBRARIES) -o $@
	@echo "  > $@"

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
			find "$$dir" -mindepth 1 -maxdepth 1 ! -name .gitkeep \
				-exec rm -rf {} +; \
		fi; \
	done

clean-iOS:
	@echo "Cleaning retro-dlp iOS build artifacts..."
	@for dir in $(IOS_INT_DIR) $(IOS_BUILD_DIR); do \
		if [ -d "$$dir" ]; then \
			find "$$dir" -mindepth 1 -maxdepth 1 ! -name .gitkeep \
				-exec rm -rf {} +; \
		fi; \
	done

clean-linux:
	@echo "Cleaning retro-dlp Linux build artifacts..."
	@for dir in $(LINUX_INT_DIR) $(LINUX_BUILD_DIR); do \
		if [ -d "$$dir" ]; then \
			find "$$dir" -mindepth 1 -maxdepth 1 ! -name .gitkeep \
				-exec rm -rf {} +; \
		fi; \
	done

.PHONY: release macOS iOS linux test validate validate-iOS clean \
	clean-macOS clean-iOS clean-linux
