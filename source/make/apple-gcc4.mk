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
	$(LEGACY_MACOS_EXTRA_CPPFLAGS)
LEGACY_MACOS_CFLAGS := $(COMMON_CFLAGS) -fno-stack-protector \
	-fno-common -fno-zero-initialized-in-bss $(LEGACY_MACOS_EXTRA_CFLAGS)
LEGACY_MACOS_LIBRARIES := $(MACOS_BASE_LIBRARIES) \
	$(LEGACY_MACOS_EXTRA_LIBRARIES)

PPC_OBJECTS := $(LEGACY_MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/ppc/%.o)
I386_OBJECTS := $(LEGACY_MACOS_SOURCES:%.c=$(MACOS_INT_DIR)/i386/%.o)

PPC_BINARY := $(MACOS_INT_DIR)/ppc/$(PROGRAM)
I386_BINARY := $(MACOS_INT_DIR)/i386/$(PROGRAM)

$(PPC_BINARY): $(PPC_OBJECTS) $(ALTIVECCORE)
	@echo "  > linking ppc binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		-arch ppc -isysroot $(SDK_PPC_PATH) $(PPC_OBJECTS) \
		$(LEGACY_MACOS_LIBRARIES) -lgcc_s.10.4 -o $@

$(I386_BINARY): $(I386_OBJECTS) $(ALTIVECCORE)
	@echo "  > linking i386 binary"
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		-arch i386 -isysroot $(SDK_X86_PATH) $(I386_OBJECTS) \
		$(LEGACY_MACOS_LIBRARIES) -lgcc_s.10.4 -o $@

$(MACOS_INT_DIR)/ppc/%.o: %.c
	@echo " [1/5] Compiling ppc: $<"
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_PPC) \
		$(LEGACY_MACOS_CPPFLAGS) $(LEGACY_MACOS_CFLAGS) -arch ppc \
		-isysroot $(SDK_PPC_PATH) -c $< -o $@

$(MACOS_INT_DIR)/i386/%.o: %.c
	@echo " [2/5] Compiling i386: $<"
	@mkdir -p $(dir $@)
	@MACOSX_DEPLOYMENT_TARGET=$(MAC_MIN_OLD) $(COMPILER_X86) \
		$(LEGACY_MACOS_CPPFLAGS) $(LEGACY_MACOS_CFLAGS) -arch i386 \
		-isysroot $(SDK_X86_PATH) -c $< -o $@
