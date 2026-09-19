# Universal armv7 and arm64 rules for Clang and the iPhoneOS 8.4 SDK.
# This compiles the pristine QuickJS submodule with iOS compatibility helpers.
# Clang emits both architectures in one compile and link invocation, matching
# the Altivec phone build convention.

IOS_BASE_QUICKJS_CPPFLAGS := -I$(QUICKJS_DIR) -D_GNU_SOURCE \
	-DCONFIG_VERSION=\"$(QUICKJS_VERSION)\"
IOS_BASE_QUICKJS_CFLAGS := $(CFLAGS) -std=gnu11 -Wall -Wextra \
	-funsigned-char -fwrapv -Wno-sign-compare \
	-Wno-missing-field-initializers -Wno-unused-parameter
IOS_BASE_QUICKJS_LIBRARIES := -lm -lpthread

IOS_EXTRA_SOURCES ?=
IOS_SOURCES := $(IOS_COMMON_SOURCES) $(IOS_EXTRA_SOURCES)
IOS_EXTRA_CPPFLAGS ?=
IOS_EXTRA_CFLAGS ?=
IOS_EXTRA_LIBRARIES ?=
IOS_CPPFLAGS := $(CPPFLAGS) $(PROJECT_CPPFLAGS) \
	-I$(IOS_ALTIVECCORE_DIR)/include \
	$(IOS_EXTRA_CPPFLAGS)
IOS_CFLAGS := $(COMMON_CFLAGS) -Wsign-conversion -Wfloat-conversion \
	-Wno-unused-command-line-argument $(IOS_EXTRA_CFLAGS)
IOS_LIBRARIES := $(IOS_ALTIVECCORE) -framework Foundation \
	-framework CoreFoundation -framework SystemConfiguration \
	-framework Security -lobjc $(IOS_ALTIVEC_CRYPTO) \
	$(IOS_EXTRA_LIBRARIES)

IOS_ARCH_FLAGS := -target arm64-apple-ios -arch armv7 -arch arm64 \
	-Xarch_armv7 -miphoneos-version-min=$(IOS_MIN_ARMV7) \
	-Xarch_arm64 -miphoneos-version-min=$(IOS_MIN_ARM64)
IOS_TOOLCHAIN_FLAGS := -isysroot $(SDK_IOS_PATH) -B$(MODERN_BIN)

IOS_QUICKJS_COMPAT_DIR := source/library/iOS/clang/QuickJS
IOS_QUICKJS_CPPFLAGS := -I$(IOS_QUICKJS_COMPAT_DIR) \
	-include $(IOS_QUICKJS_COMPAT_DIR)/quickjs_compat.h \
	$(IOS_BASE_QUICKJS_CPPFLAGS)
IOS_QUICKJS_CFLAGS := $(IOS_BASE_QUICKJS_CFLAGS) \
	-Wno-unused-command-line-argument
IOS_QUICKJS_LIBRARIES := $(IOS_BASE_QUICKJS_LIBRARIES)
IOS_QUICKJS_SOURCE_NAMES := $(filter-out quickjs-libc.c, \
	$(QUICKJS_SOURCE_NAMES))

IOS_OBJECTS := $(IOS_SOURCES:%.c=$(IOS_INT_DIR)/%.o)
IOS_CORE_OBJECTS := $(CORE_SOURCES:%.c=$(IOS_INT_DIR)/%.o) \
	$(IOS_INT_DIR)/source/library/iOS/platform.o
IOS_DOWNLOAD_OBJECTS := $(DOWNLOAD_SOURCES:%.c=$(IOS_INT_DIR)/%.o)
IOS_BINARY := $(IOS_BUILD_DIR)/$(PROGRAM)
IOS_QUICKJS_INT_DIR := $(IOS_INT_DIR)/QuickJS
IOS_QUICKJS_OBJECTS := $(addprefix $(IOS_QUICKJS_INT_DIR)/, \
	$(IOS_QUICKJS_SOURCE_NAMES:.c=.o)) \
	$(IOS_QUICKJS_INT_DIR)/quickjs_compat.o

IOS_ARMV7_LSMASH_INT_DIR := $(IOS_INT_DIR)/armv7/L-SMASH
IOS_ARM64_LSMASH_INT_DIR := $(IOS_INT_DIR)/arm64/L-SMASH
IOS_ARMV7_LSMASH_OBJECTS := $(addprefix $(IOS_ARMV7_LSMASH_INT_DIR)/, \
	$(LSMASH_SOURCE_NAMES:.c=.o))
IOS_ARM64_LSMASH_OBJECTS := $(addprefix $(IOS_ARM64_LSMASH_INT_DIR)/, \
	$(LSMASH_SOURCE_NAMES:.c=.o))
IOS_ARMV7_LSMASH_LIBRARY := $(IOS_INT_DIR)/armv7/liblsmash.a
IOS_ARM64_LSMASH_LIBRARY := $(IOS_INT_DIR)/arm64/liblsmash.a
IOS_LSMASH_LIBRARY := $(IOS_INT_DIR)/liblsmash.a
IOS_ARMV7_LSMASH_ARCH_FLAGS := -target armv7-apple-ios$(IOS_MIN_ARMV7) \
	-arch armv7 -miphoneos-version-min=$(IOS_MIN_ARMV7)
IOS_ARM64_LSMASH_ARCH_FLAGS := -target arm64-apple-ios$(IOS_MIN_ARM64) \
	-arch arm64 -miphoneos-version-min=$(IOS_MIN_ARM64)

$(IOS_LIBRARY): $(IOS_CORE_OBJECTS) $(IOS_QUICKJS_OBJECTS)
	@echo "  > archiving universal iOS resolver library"
	@mkdir -p $(dir $@)
	@$(LIBTOOL_MODERN) -static -o $@ $^

$(IOS_DOWNLOAD_LIBRARY): $(IOS_DOWNLOAD_OBJECTS) $(IOS_LSMASH_LIBRARY)
	@echo "  > archiving universal iOS optional download library"
	@mkdir -p $(dir $@)
	@$(LIBTOOL_MODERN) -static -o $@ $^

$(IOS_BINARY): $(IOS_OBJECTS) $(IOS_DOWNLOAD_LIBRARY) $(IOS_LIBRARY) \
		$(IOS_ALTIVECCORE)
	@echo "--- Building retro-dlp iOS Release (-O3) ---"
	@echo " [2/2] Linking universal iOS binary (armv7, arm64)..."
	@mkdir -p $(dir $@)
	@$(COMPILER_IOS) $(IOS_ARCH_FLAGS) $(IOS_TOOLCHAIN_FLAGS) \
		$(LDFLAGS) $(IOS_OBJECTS) $(IOS_DOWNLOAD_LIBRARY) $(IOS_LIBRARY) \
		$(IOS_LIBRARIES) \
		$(IOS_QUICKJS_LIBRARIES) $(LDLIBS) -o $@
	@echo "  > $@"

$(IOS_INT_DIR)/%.o: %.c
	@echo " [1/2] Compiling universal iOS: $<"
	@mkdir -p $(dir $@)
	@$(COMPILER_IOS) $(IOS_ARCH_FLAGS) $(IOS_TOOLCHAIN_FLAGS) \
		$(IOS_CPPFLAGS) $(IOS_CFLAGS) $(SOURCE_WARNING_FLAGS) \
		-MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(IOS_QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(COMPILER_IOS) $(IOS_ARCH_FLAGS) $(IOS_TOOLCHAIN_FLAGS) \
		$(IOS_QUICKJS_CPPFLAGS) $(IOS_QUICKJS_CFLAGS) -c $< -o $@

$(IOS_QUICKJS_INT_DIR)/quickjs_compat.o: \
		$(IOS_QUICKJS_COMPAT_DIR)/quickjs_compat.c
	@mkdir -p $(dir $@)
	@$(COMPILER_IOS) $(IOS_ARCH_FLAGS) $(IOS_TOOLCHAIN_FLAGS) \
		$(IOS_QUICKJS_CFLAGS) -I$(IOS_QUICKJS_COMPAT_DIR) -c $< -o $@

$(IOS_LSMASH_LIBRARY): $(IOS_ARMV7_LSMASH_LIBRARY) \
		$(IOS_ARM64_LSMASH_LIBRARY)
	@echo "  > merging universal iOS L-SMASH static library"
	@$(LIPO) -create $^ -output $@

$(IOS_ARMV7_LSMASH_LIBRARY): $(IOS_ARMV7_LSMASH_OBJECTS)
	@echo "  > archiving armv7 L-SMASH static library"
	@$(AR_MODERN) rcs $@ $^

$(IOS_ARM64_LSMASH_LIBRARY): $(IOS_ARM64_LSMASH_OBJECTS)
	@echo "  > archiving arm64 L-SMASH static library"
	@$(AR_MODERN) rcs $@ $^

$(IOS_ARMV7_LSMASH_INT_DIR)/%.o: $(LSMASH_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(COMPILER_IOS) $(IOS_ARMV7_LSMASH_ARCH_FLAGS) $(IOS_TOOLCHAIN_FLAGS) \
		$(LSMASH_CPPFLAGS) $(LSMASH_CFLAGS) \
		-Wno-unused-command-line-argument -Wno-sign-conversion \
		-Wno-shorten-64-to-32 -MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(IOS_ARM64_LSMASH_INT_DIR)/%.o: $(LSMASH_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(COMPILER_IOS) $(IOS_ARM64_LSMASH_ARCH_FLAGS) $(IOS_TOOLCHAIN_FLAGS) \
		$(LSMASH_CPPFLAGS) $(LSMASH_CFLAGS) \
		-Wno-unused-command-line-argument -Wno-sign-conversion \
		-Wno-shorten-64-to-32 -MMD -MP -MF $(@:.o=.d) -c $< -o $@
