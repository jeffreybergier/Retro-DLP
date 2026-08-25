PROGRAM := retro-dlp
VERSION := 0.1.0

SHARED_SOURCES := source/shared/main.c source/shared/cli.c
MACOS_SOURCES := $(SHARED_SOURCES) source/macOS/platform.c
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

CPPFLAGS := -Isource/shared -DRETRO_DLP_VERSION=\"$(VERSION)\"
MACOS_CPPFLAGS := $(CPPFLAGS) -I$(ALTIVECCORE_DIR)/include
LINUX_CPPFLAGS := $(CPPFLAGS) -I$(CJSON_DIR)
QUICKJS_CPPFLAGS := -I$(QUICKJS_DIR) -D_GNU_SOURCE \
	-DCONFIG_VERSION=\"$(QUICKJS_VERSION)\"
CFLAGS ?= -O3 -g
COMMON_CFLAGS := $(CFLAGS) -std=c99 -Wall -Wextra -Werror
QUICKJS_CFLAGS := $(CFLAGS) -std=gnu11 -Wall -Wextra -funsigned-char \
	-fwrapv -Wno-sign-compare -Wno-missing-field-initializers \
	-Wno-unused-parameter -Wno-discarded-qualifiers \
	-Wno-implicit-fallthrough
QUICKJS_MACOS_CFLAGS := $(CFLAGS) -std=gnu11 -Wall -Wextra \
	-funsigned-char -fwrapv -Wno-sign-compare \
	-Wno-missing-field-initializers -Wno-unused-parameter
LEGACY_CFLAGS := -fno-stack-protector -fno-common \
	-fno-zero-initialized-in-bss
MODERN_CFLAGS := -Wsign-conversion -Wfloat-conversion
MACOS_LIBRARIES := $(ALTIVECCORE) -framework Foundation \
	-framework CoreFoundation -framework SystemConfiguration -lobjc

MACOS_INT_DIR := $(INTERMEDIATE_DIR)/macOS
LINUX_INT_DIR := $(INTERMEDIATE_DIR)/linux
QUICKJS_INT_DIR := $(LINUX_INT_DIR)/QuickJS
QUICKJS_OBJECTS := $(addprefix $(QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o))
QUICKJS_LIBRARY := $(LINUX_INT_DIR)/libquickjs.a
LINUX_LIBRARIES := -Wl,--whole-archive $(QUICKJS_LIBRARY) \
	-Wl,--no-whole-archive -lm -ldl -lpthread
X86_64_QUICKJS_INT_DIR := $(MACOS_INT_DIR)/x86_64/QuickJS
ARM64_QUICKJS_INT_DIR := $(MACOS_INT_DIR)/arm64/QuickJS
X86_64_QUICKJS_OBJECTS := $(addprefix $(X86_64_QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o))
ARM64_QUICKJS_OBJECTS := $(addprefix $(ARM64_QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o))
X86_64_QUICKJS_LIBRARY := $(MACOS_INT_DIR)/x86_64/libquickjs.a
ARM64_QUICKJS_LIBRARY := $(MACOS_INT_DIR)/arm64/libquickjs.a
QUICKJS_MACOS_LIBRARIES := -lm -lpthread

PPC_OBJECTS := $(MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/ppc/%.o)
I386_OBJECTS := $(MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/i386/%.o)
X86_64_OBJECTS := $(MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/x86_64/%.o)
ARM64_OBJECTS := $(MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/arm64/%.o)
LINUX_OBJECTS := $(LINUX_SOURCES:%.c=$(LINUX_INT_DIR)/%.o)

PPC_BINARY := $(MACOS_INT_DIR)/ppc/$(PROGRAM)
I386_BINARY := $(MACOS_INT_DIR)/i386/$(PROGRAM)
X86_64_BINARY := $(MACOS_INT_DIR)/x86_64/$(PROGRAM)
ARM64_BINARY := $(MACOS_INT_DIR)/arm64/$(PROGRAM)

.DEFAULT_GOAL := release

release: macOS

macOS: validate $(MACOS_BUILD_DIR)/$(PROGRAM)

linux: $(LINUX_BUILD_DIR)/$(PROGRAM)

test: linux
	@echo "--- Running retro-dlp Linux tests ---"
	@tests/linux/cli_test.sh "$(abspath $(LINUX_BUILD_DIR)/$(PROGRAM))"

$(MACOS_BUILD_DIR)/$(PROGRAM): $(PPC_BINARY) $(I386_BINARY) \
		$(X86_64_BINARY) $(ARM64_BINARY)
	@echo " [5/5] Merging quad-fat binary (ppc, i386, x86_64, arm64)..."
	@mkdir -p $(dir $@)
	@$(LIPO) -create $^ -output $@
	@echo "  > $@"

$(PPC_BINARY): $(PPC_OBJECTS) $(ALTIVECCORE)
	@echo "  > linking ppc binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		-arch ppc -isysroot $(SDK_PPC_PATH) $(PPC_OBJECTS) \
		$(MACOS_LIBRARIES) -lgcc_s.10.4 -o $@

$(I386_BINARY): $(I386_OBJECTS) $(ALTIVECCORE)
	@echo "  > linking i386 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		-arch i386 -isysroot $(SDK_X86_PATH) $(I386_OBJECTS) \
		$(MACOS_LIBRARIES) -lgcc_s.10.4 -o $@

$(X86_64_BINARY): $(X86_64_OBJECTS) $(ALTIVECCORE) \
		$(X86_64_QUICKJS_LIBRARY)
	@echo "  > linking x86_64 binary"
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_X64) \
		-isysroot $(SDK_X64_PATH) -fuse-ld=$(LD64_LLD) \
		-Wl,-platform_version,macos,$(MAC_MIN_X64),$(SDK_MAC_NEW) \
		$(X86_64_OBJECTS) $(MACOS_LIBRARIES) \
		-Wl,-force_load,$(X86_64_QUICKJS_LIBRARY) \
		$(QUICKJS_MACOS_LIBRARIES) -o $@

$(ARM64_BINARY): $(ARM64_OBJECTS) $(ALTIVECCORE) \
		$(ARM64_QUICKJS_LIBRARY)
	@echo "  > linking arm64 binary"
	@$(COMPILER_ARM64) -target arm64-apple-macos$(MAC_MIN_ARM64) \
		-isysroot $(SDK_ARM64_PATH) $(ARM64_OBJECTS) \
		$(MACOS_LIBRARIES) -Wl,-force_load,$(ARM64_QUICKJS_LIBRARY) \
		$(QUICKJS_MACOS_LIBRARIES) -o $@

$(MACOS_INT_DIR)/ppc/%.o: %.c
	@echo " [1/5] Compiling ppc: $<"
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		$(MACOS_CPPFLAGS) $(COMMON_CFLAGS) $(LEGACY_CFLAGS) -arch ppc \
		-isysroot $(SDK_PPC_PATH) -c $< -o $@

$(MACOS_INT_DIR)/i386/%.o: %.c
	@echo " [2/5] Compiling i386: $<"
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		$(MACOS_CPPFLAGS) $(COMMON_CFLAGS) $(LEGACY_CFLAGS) -arch i386 \
		-isysroot $(SDK_X86_PATH) -c $< -o $@

$(MACOS_INT_DIR)/x86_64/%.o: %.c
	@echo " [3/5] Compiling x86_64: $<"
	@mkdir -p $(dir $@)
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_X64) \
		-arch x86_64 -isysroot $(SDK_X64_PATH) $(MACOS_CPPFLAGS) \
		$(COMMON_CFLAGS) $(MODERN_CFLAGS) -c $< -o $@

$(MACOS_INT_DIR)/arm64/%.o: %.c
	@echo " [4/5] Compiling arm64: $<"
	@mkdir -p $(dir $@)
	@$(COMPILER_ARM64) -target arm64-apple-macos$(MAC_MIN_ARM64) \
		-arch arm64 -isysroot $(SDK_ARM64_PATH) $(MACOS_CPPFLAGS) \
		$(COMMON_CFLAGS) $(MODERN_CFLAGS) -c $< -o $@

$(X86_64_QUICKJS_LIBRARY): $(X86_64_QUICKJS_OBJECTS)
	@echo "  > archiving x86_64 QuickJS static library"
	@$(AR_MODERN) rcs $@ $^

$(ARM64_QUICKJS_LIBRARY): $(ARM64_QUICKJS_OBJECTS)
	@echo "  > archiving arm64 QuickJS static library"
	@$(AR_MODERN) rcs $@ $^

$(X86_64_QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_X64) \
		-arch x86_64 -isysroot $(SDK_X64_PATH) $(QUICKJS_CPPFLAGS) \
		$(QUICKJS_MACOS_CFLAGS) -c $< -o $@

$(ARM64_QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(COMPILER_ARM64) -target arm64-apple-macos$(MAC_MIN_ARM64) \
		-arch arm64 -isysroot $(SDK_ARM64_PATH) $(QUICKJS_CPPFLAGS) \
		$(QUICKJS_MACOS_CFLAGS) -c $< -o $@

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
	@$(CC) $(LINUX_CPPFLAGS) $(COMMON_CFLAGS) -c $< -o $@

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
