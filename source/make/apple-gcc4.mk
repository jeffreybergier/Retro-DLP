# PowerPC and i386 rules for Apple GCC 4.2.1 and the Mac OS X 10.5 SDK.
# Keep Tiger-specific sources, compatibility headers, flags, and future
# QuickJS patches in this profile so they cannot affect the Clang build.

LEGACY_MACOS_EXTRA_SOURCES ?=
LEGACY_MACOS_SOURCES := $(MACOS_COMMON_SOURCES) \
	$(LEGACY_MACOS_EXTRA_SOURCES)
LEGACY_MACOS_EXTRA_CPPFLAGS ?=
LEGACY_MACOS_EXTRA_CFLAGS ?=
LEGACY_MACOS_EXTRA_LIBRARIES ?=
LEGACY_MACOS_CPPFLAGS := $(MACOS_BASE_CPPFLAGS) \
	-D_NONSTD_SOURCE $(LEGACY_MACOS_EXTRA_CPPFLAGS)
LEGACY_MACOS_CFLAGS := $(COMMON_CFLAGS) -fno-stack-protector \
	-fno-common -fno-zero-initialized-in-bss $(LEGACY_MACOS_EXTRA_CFLAGS)
LEGACY_MACOS_LIBRARIES := $(MACOS_BASE_LIBRARIES) \
	$(LEGACY_MACOS_EXTRA_LIBRARIES)

LEGACY_QUICKJS_COMPAT_DIR := source/macOS/apple-gcc4/QuickJS
LEGACY_QUICKJS_CPPFLAGS := -I$(LEGACY_QUICKJS_COMPAT_DIR) \
	-include $(LEGACY_QUICKJS_COMPAT_DIR)/quickjs_compat.h \
	-I$(QUICKJS_DIR) -D_GNU_SOURCE \
	-DCONFIG_VERSION=\"$(QUICKJS_VERSION)\"
LEGACY_QUICKJS_CFLAGS := $(CFLAGS) -std=gnu99 -Wall -funsigned-char \
	-fwrapv -Wno-sign-compare -Wno-missing-field-initializers \
	-Wno-unused-parameter -Wno-uninitialized
LEGACY_QUICKJS_LIBRARIES := -lm -lpthread

PPC_OBJECTS := $(LEGACY_MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/ppc/%.o)
I386_OBJECTS := $(LEGACY_MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/i386/%.o)

PPC_BINARY := $(MACOS_INT_DIR)/ppc/$(PROGRAM)
I386_BINARY := $(MACOS_INT_DIR)/i386/$(PROGRAM)

PPC_QUICKJS_INT_DIR := $(MACOS_INT_DIR)/ppc/QuickJS
I386_QUICKJS_INT_DIR := $(MACOS_INT_DIR)/i386/QuickJS
PPC_QUICKJS_OBJECTS := $(addprefix $(PPC_QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o)) $(PPC_QUICKJS_INT_DIR)/quickjs_compat.o
I386_QUICKJS_OBJECTS := $(addprefix $(I386_QUICKJS_INT_DIR)/, \
	$(QUICKJS_SOURCE_NAMES:.c=.o)) $(I386_QUICKJS_INT_DIR)/quickjs_compat.o
PPC_QUICKJS_LIBRARY := $(MACOS_INT_DIR)/ppc/libquickjs.a
I386_QUICKJS_LIBRARY := $(MACOS_INT_DIR)/i386/libquickjs.a

PPC_LSMASH_INT_DIR := $(MACOS_INT_DIR)/ppc/L-SMASH
I386_LSMASH_INT_DIR := $(MACOS_INT_DIR)/i386/L-SMASH
PPC_LSMASH_OBJECTS := $(addprefix $(PPC_LSMASH_INT_DIR)/, \
	$(LSMASH_SOURCE_NAMES:.c=.o)) $(PPC_LSMASH_INT_DIR)/stdio_compat.o
I386_LSMASH_OBJECTS := $(addprefix $(I386_LSMASH_INT_DIR)/, \
	$(LSMASH_SOURCE_NAMES:.c=.o)) $(I386_LSMASH_INT_DIR)/stdio_compat.o
PPC_LSMASH_LIBRARY := $(MACOS_INT_DIR)/ppc/liblsmash.a
I386_LSMASH_LIBRARY := $(MACOS_INT_DIR)/i386/liblsmash.a

$(PPC_BINARY): $(PPC_OBJECTS) $(ALTIVECCORE) $(PPC_QUICKJS_LIBRARY) \
		$(PPC_LSMASH_LIBRARY)
	@echo "  > linking ppc binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		-arch ppc -isysroot $(SDK_PPC_PATH) $(LDFLAGS) $(PPC_OBJECTS) \
		$(LEGACY_MACOS_LIBRARIES) -Wl,-force_load,$(PPC_QUICKJS_LIBRARY) \
		-Wl,-force_load,$(PPC_LSMASH_LIBRARY) \
		$(LEGACY_QUICKJS_LIBRARIES) -lgcc_s.10.4 $(LDLIBS) -o $@
	@if $(NM) -u $@ | grep -E '\$$(UNIX2003|NOCANCEL|INODE64|1050)' \
		>/dev/null; then \
		echo "Tiger-incompatible suffixed symbol in $@" >&2; exit 1; \
	fi

$(I386_BINARY): $(I386_OBJECTS) $(ALTIVECCORE) $(I386_QUICKJS_LIBRARY) \
		$(I386_LSMASH_LIBRARY)
	@echo "  > linking i386 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		-arch i386 -isysroot $(SDK_X86_PATH) $(LDFLAGS) $(I386_OBJECTS) \
		$(LEGACY_MACOS_LIBRARIES) -Wl,-force_load,$(I386_QUICKJS_LIBRARY) \
		-Wl,-force_load,$(I386_LSMASH_LIBRARY) \
		$(LEGACY_QUICKJS_LIBRARIES) -lgcc_s.10.4 $(LDLIBS) -o $@
	@if $(NM) -u $@ | grep -E '\$$(UNIX2003|NOCANCEL|INODE64|1050)' \
		>/dev/null; then \
		echo "Tiger-incompatible suffixed symbol in $@" >&2; exit 1; \
	fi

$(MACOS_INT_DIR)/ppc/%.o: %.c
	@echo " [1/5] Compiling ppc: $<"
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		$(LEGACY_MACOS_CPPFLAGS) $(LEGACY_MACOS_CFLAGS) -arch ppc \
		-isysroot $(SDK_PPC_PATH) $(SOURCE_WARNING_FLAGS) \
		-MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(MACOS_INT_DIR)/i386/%.o: %.c
	@echo " [2/5] Compiling i386: $<"
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		$(LEGACY_MACOS_CPPFLAGS) $(LEGACY_MACOS_CFLAGS) -arch i386 \
		-isysroot $(SDK_X86_PATH) $(SOURCE_WARNING_FLAGS) \
		-MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(PPC_QUICKJS_LIBRARY): $(PPC_QUICKJS_OBJECTS)
	@echo "  > archiving ppc QuickJS static library"
	@$(AR_LEGACY) rcs $@ $^

$(I386_QUICKJS_LIBRARY): $(I386_QUICKJS_OBJECTS)
	@echo "  > archiving i386 QuickJS static library"
	@$(AR_LEGACY) rcs $@ $^

$(PPC_LSMASH_LIBRARY): $(PPC_LSMASH_OBJECTS)
	@echo "  > archiving ppc L-SMASH static library"
	@$(AR_LEGACY) rcs $@ $^

$(I386_LSMASH_LIBRARY): $(I386_LSMASH_OBJECTS)
	@echo "  > archiving i386 L-SMASH static library"
	@$(AR_LEGACY) rcs $@ $^

$(PPC_LSMASH_INT_DIR)/%.o: $(LSMASH_DIR)/%.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		$(LSMASH_CPPFLAGS) $(LSMASH_CFLAGS) -fno-stack-protector \
		-fno-common -arch ppc -isysroot $(SDK_PPC_PATH) \
		-MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(I386_LSMASH_INT_DIR)/%.o: $(LSMASH_DIR)/%.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		$(LSMASH_CPPFLAGS) $(LSMASH_CFLAGS) -fno-stack-protector \
		-fno-common -arch i386 -isysroot $(SDK_X86_PATH) \
		-MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(PPC_LSMASH_INT_DIR)/stdio_compat.o: \
		source/macOS/apple-gcc4/L-SMASH/stdio_compat.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		-D_NONSTD_SOURCE $(CFLAGS) -std=c99 -Wall -Wextra \
		-fno-stack-protector -fno-common -arch ppc \
		-isysroot $(SDK_PPC_PATH) -c $< -o $@

$(I386_LSMASH_INT_DIR)/stdio_compat.o: \
		source/macOS/apple-gcc4/L-SMASH/stdio_compat.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		-D_NONSTD_SOURCE $(CFLAGS) -std=c99 -Wall -Wextra \
		-fno-stack-protector -fno-common -arch i386 \
		-isysroot $(SDK_X86_PATH) -c $< -o $@

$(PPC_QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		$(LEGACY_QUICKJS_CPPFLAGS) $(LEGACY_QUICKJS_CFLAGS) -arch ppc \
		-isysroot $(SDK_PPC_PATH) -c $< -o $@

$(I386_QUICKJS_INT_DIR)/%.o: $(QUICKJS_DIR)/%.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		$(LEGACY_QUICKJS_CPPFLAGS) $(LEGACY_QUICKJS_CFLAGS) -arch i386 \
		-isysroot $(SDK_X86_PATH) -c $< -o $@

$(PPC_QUICKJS_INT_DIR)/quickjs_compat.o: \
		$(LEGACY_QUICKJS_COMPAT_DIR)/quickjs_compat.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		-I$(LEGACY_QUICKJS_COMPAT_DIR) $(LEGACY_QUICKJS_CFLAGS) -arch ppc \
		-isysroot $(SDK_PPC_PATH) -c $< -o $@

$(I386_QUICKJS_INT_DIR)/quickjs_compat.o: \
		$(LEGACY_QUICKJS_COMPAT_DIR)/quickjs_compat.c
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		-I$(LEGACY_QUICKJS_COMPAT_DIR) $(LEGACY_QUICKJS_CFLAGS) -arch i386 \
		-isysroot $(SDK_X86_PATH) -c $< -o $@
