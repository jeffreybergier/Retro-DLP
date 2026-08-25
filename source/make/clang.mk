# x86_64 and arm64 rules for the modern Clang toolchain and macOS 11.3 SDK.
# This profile always compiles the pristine QuickJS submodule. Do not put
# Apple GCC 4 or Tiger compatibility workarounds in this file.

MODERN_MACOS_EXTRA_SOURCES ?=
MODERN_MACOS_SOURCES := $(MACOS_COMMON_SOURCES) \
	$(MODERN_MACOS_EXTRA_SOURCES)
MODERN_MACOS_EXTRA_CPPFLAGS ?=
MODERN_MACOS_EXTRA_CFLAGS ?=
MODERN_MACOS_EXTRA_LIBRARIES ?=
MODERN_MACOS_CPPFLAGS := $(MACOS_BASE_CPPFLAGS) \
	$(MODERN_MACOS_EXTRA_CPPFLAGS)
MODERN_MACOS_CFLAGS := $(COMMON_CFLAGS) -Wsign-conversion \
	-Wfloat-conversion $(MODERN_MACOS_EXTRA_CFLAGS)
MODERN_MACOS_LIBRARIES := $(MACOS_BASE_LIBRARIES) \
	$(MODERN_MACOS_EXTRA_LIBRARIES)

MODERN_QUICKJS_CPPFLAGS := -I$(QUICKJS_DIR) -D_GNU_SOURCE \
	-DCONFIG_VERSION=\"$(QUICKJS_VERSION)\"
MODERN_QUICKJS_CFLAGS := $(CFLAGS) -std=gnu11 -Wall -Wextra \
	-funsigned-char -fwrapv -Wno-sign-compare \
	-Wno-missing-field-initializers -Wno-unused-parameter
MODERN_QUICKJS_LIBRARIES := -lm -lpthread

X86_64_OBJECTS := $(MODERN_MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/x86_64/%.o)
ARM64_OBJECTS := $(MODERN_MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/arm64/%.o)

X86_64_BINARY := $(MACOS_INT_DIR)/x86_64/$(PROGRAM)
ARM64_BINARY := $(MACOS_INT_DIR)/arm64/$(PROGRAM)

X86_64_QUICKJS_INT_DIR := $(MACOS_INT_DIR)/x86_64/QuickJS
ARM64_QUICKJS_INT_DIR := $(MACOS_INT_DIR)/arm64/QuickJS
X86_64_QUICKJS_OBJECTS := $(addprefix $(X86_64_QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o))
ARM64_QUICKJS_OBJECTS := $(addprefix $(ARM64_QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o))
X86_64_QUICKJS_LIBRARY := $(MACOS_INT_DIR)/x86_64/libquickjs.a
ARM64_QUICKJS_LIBRARY := $(MACOS_INT_DIR)/arm64/libquickjs.a

$(X86_64_BINARY): $(X86_64_OBJECTS) $(ALTIVECCORE) \
		$(X86_64_QUICKJS_LIBRARY)
	@echo "  > linking x86_64 binary"
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_X64) \
		-isysroot $(SDK_X64_PATH) -fuse-ld=$(LD64_LLD) \
		-Wl,-platform_version,macos,$(MAC_MIN_X64),$(SDK_MAC_NEW) \
		$(X86_64_OBJECTS) $(MODERN_MACOS_LIBRARIES) \
		-Wl,-force_load,$(X86_64_QUICKJS_LIBRARY) \
		$(MODERN_QUICKJS_LIBRARIES) -o $@

$(ARM64_BINARY): $(ARM64_OBJECTS) $(ALTIVECCORE) \
		$(ARM64_QUICKJS_LIBRARY)
	@echo "  > linking arm64 binary"
	@$(COMPILER_ARM64) -target arm64-apple-macos$(MAC_MIN_ARM64) \
		-isysroot $(SDK_ARM64_PATH) $(ARM64_OBJECTS) \
		$(MODERN_MACOS_LIBRARIES) \
		-Wl,-force_load,$(ARM64_QUICKJS_LIBRARY) \
		$(MODERN_QUICKJS_LIBRARIES) -o $@

$(MACOS_INT_DIR)/x86_64/%.o: %.c
	@echo " [3/5] Compiling x86_64: $<"
	@mkdir -p $(dir $@)
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_X64) \
		-arch x86_64 -isysroot $(SDK_X64_PATH) \
		$(MODERN_MACOS_CPPFLAGS) $(MODERN_MACOS_CFLAGS) \
		$(SOURCE_WARNING_FLAGS) -c $< -o $@

$(MACOS_INT_DIR)/arm64/%.o: %.c
	@echo " [4/5] Compiling arm64: $<"
	@mkdir -p $(dir $@)
	@$(COMPILER_ARM64) -target arm64-apple-macos$(MAC_MIN_ARM64) \
		-arch arm64 -isysroot $(SDK_ARM64_PATH) \
		$(MODERN_MACOS_CPPFLAGS) $(MODERN_MACOS_CFLAGS) \
		$(SOURCE_WARNING_FLAGS) -c $< -o $@

$(X86_64_QUICKJS_LIBRARY): $(X86_64_QUICKJS_OBJECTS)
	@echo "  > archiving x86_64 QuickJS static library"
	@$(AR_MODERN) rcs $@ $^

$(ARM64_QUICKJS_LIBRARY): $(ARM64_QUICKJS_OBJECTS)
	@echo "  > archiving arm64 QuickJS static library"
	@$(AR_MODERN) rcs $@ $^

$(X86_64_QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(COMPILER_X64) -target x86_64-apple-macos$(MAC_MIN_X64) \
		-arch x86_64 -isysroot $(SDK_X64_PATH) \
		$(MODERN_QUICKJS_CPPFLAGS) $(MODERN_QUICKJS_CFLAGS) -c $< -o $@

$(ARM64_QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(COMPILER_ARM64) -target arm64-apple-macos$(MAC_MIN_ARM64) \
		-arch arm64 -isysroot $(SDK_ARM64_PATH) \
		$(MODERN_QUICKJS_CPPFLAGS) $(MODERN_QUICKJS_CFLAGS) -c $< -o $@
