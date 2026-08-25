PROGRAM := retro-dlp
VERSION := 0.1.0

SHARED_SOURCES := source/shared/main.c source/shared/cli.c \
	source/shared/test/self_test.c source/shared/test/self_test_data.c
MACOS_COMMON_SOURCES := $(SHARED_SOURCES) source/macOS/platform.c
CJSON_DIR := source/deps/cJSON
CJSON_SOURCE := $(CJSON_DIR)/cJSON.c
QUICKJS_DIR := source/deps/QuickJS
QUICKJS_VERSION := $(shell cat $(QUICKJS_DIR)/VERSION 2>/dev/null)
QUICKJS_SOURCE_NAMES := quickjs.c dtoa.c libregexp.c libunicode.c cutils.c \
	quickjs-libc.c
LINUX_SOURCES := $(SHARED_SOURCES) source/linux/platform.c $(CJSON_SOURCE)

BUILD_DIR := build
INTERMEDIATE_DIR := $(BUILD_DIR)/intermediates
MACOS_BUILD_DIR := $(BUILD_DIR)/macOS
LINUX_BUILD_DIR := $(BUILD_DIR)/linux

ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/altivec_toolchains.mk

ALTIVECCORE_DIR ?= $(ALTIVEC_ROOT)/libs/core/build-mac
ALTIVECCORE := $(ALTIVECCORE_DIR)/lib/libAltivecCore.a

SDK_MAC_OLD := 10.5
SDK_MAC_NEW := 11.3
MAC_MIN_OLD := 10.4
MAC_MIN_X64 := 10.9
MAC_MIN_ARM64 := 11.0

CPPFLAGS := -Isource/shared -I$(QUICKJS_DIR) \
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
	-framework CoreFoundation -framework SystemConfiguration -lobjc

MACOS_INT_DIR := $(INTERMEDIATE_DIR)/macOS
LINUX_INT_DIR := $(INTERMEDIATE_DIR)/linux
QUICKJS_INT_DIR := $(LINUX_INT_DIR)/QuickJS
QUICKJS_OBJECTS := $(addprefix $(QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o))
QUICKJS_LIBRARY := $(LINUX_INT_DIR)/libquickjs.a
LINUX_LIBRARIES := -Wl,--whole-archive $(QUICKJS_LIBRARY) \
	-Wl,--no-whole-archive -lm -ldl -lpthread
LINUX_OBJECTS := $(LINUX_SOURCES:%.c=$(LINUX_INT_DIR)/%.o)

include source/make/apple-gcc4.mk
include source/make/clang.mk

$(LINUX_INT_DIR)/source/shared/test/self_test.o \
$(MACOS_INT_DIR)/ppc/source/shared/test/self_test.o \
$(MACOS_INT_DIR)/i386/source/shared/test/self_test.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter

$(MACOS_INT_DIR)/x86_64/source/shared/test/self_test.o \
$(MACOS_INT_DIR)/arm64/source/shared/test/self_test.o: \
	SOURCE_WARNING_FLAGS := -Wno-unused-parameter -Wno-sign-conversion

.DEFAULT_GOAL := release

release: macOS

macOS: validate $(MACOS_BUILD_DIR)/$(PROGRAM)

linux: $(LINUX_BUILD_DIR)/$(PROGRAM)

test: linux
	@echo "--- Running retro-dlp Linux tests ---"
	@source/linux/test/cli_test.sh \
		"$(abspath $(LINUX_BUILD_DIR)/$(PROGRAM))"

$(MACOS_BUILD_DIR)/$(PROGRAM): $(PPC_BINARY) $(I386_BINARY) \
		$(X86_64_BINARY) $(ARM64_BINARY)
	@echo " [5/5] Merging quad-fat binary (ppc, i386, x86_64, arm64)..."
	@mkdir -p $(dir $@)
	@$(LIPO) -create $^ -output $@
	@echo "  > $@"

$(LINUX_BUILD_DIR)/$(PROGRAM): $(LINUX_OBJECTS) $(QUICKJS_LIBRARY)
	@echo "--- Building retro-dlp Linux Release (-O3) ---"
	@mkdir -p $(dir $@)
	@$(CC) $(LINUX_OBJECTS) $(LINUX_LIBRARIES) -o $@
	@echo "  > $@"

$(QUICKJS_LIBRARY): $(QUICKJS_OBJECTS)
	@echo "  > archiving QuickJS static library"
	@$(AR) rcs $@ $^

$(QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(CC) $(QUICKJS_CPPFLAGS) $(QUICKJS_CFLAGS) -c $< -o $@

$(LINUX_INT_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	@$(CC) $(LINUX_CPPFLAGS) $(COMMON_CFLAGS) $(SOURCE_WARNING_FLAGS) \
		-c $< -o $@

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

clean:
	@echo "Cleaning retro-dlp build artifacts..."
	@find $(INTERMEDIATE_DIR) $(MACOS_BUILD_DIR) $(LINUX_BUILD_DIR) \
		-mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +

.PHONY: release macOS linux test validate clean
