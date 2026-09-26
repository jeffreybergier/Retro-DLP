APP_NAME = RetroDLP
SOURCES = main.m RDLPLibrary+macOS.m RDLPAppDelegate.m RDLPLibraryWindowController.m RDLPQueueWindowController.m RDLPAppKit.m RDLPToolbarButton.m RDLPLibraryViews.m RDLPDownloadPolicy.m RDLPLibraryMenus.m
SHARED_DIR = ../shared
SOURCE_DIRS = $(SHARED_DIR)
vpath %.c $(SHARED_DIR)
vpath %.m $(SHARED_DIR)
EXTRA_SOURCES = rdapp_store.c rdapp_service.c rdlp_thread.c RDLPLibrary.m RDLPVideoRows.m RDLP_Foundation.m
INFO_PLIST = Info.plist
MAC_ICON = Resources/RetroDLP.icns
ALTIVECCORE_REQUIRED = 1
ALTIVECCORE_LINKAGE = static
ALTIVECCOCOA_REQUIRED = 1
ALTIVECCOCOA_LINKAGE = static
ROOT = $(abspath ../../..)
BUILD_DIR = $(ROOT)/build/apps/macOS
ANALYZE_OUTPUT_DIR = $(BUILD_DIR)/analyze
# Select a separate final binary so the shared four-architecture link rule is
# never a build dependency. Keep the shared Clang analyze target and its SDK.
UNIVERSAL_BIN = $(INT_DIR)/$(APP_NAME)-ppc-i386
include /altivec/altivec_common_mac.mk
# Legacy GCC embeds symbols in the executable. Do not regenerate modern dSYMs
# from stale x64/arm intermediates when updating an existing build directory.
DSYMUTIL = :
MAC_FLAGS += -I$(SHARED_DIR) -I$(ROOT)/source/library/shared/include
LEGACY_GCC_FLAGS += -D_NONSTD_SOURCE
# The application consumes only public Retro-DLP static archives.
MAC_LIBS := $(ROOT)/build/macOS/libretrodlp-download.a $(ROOT)/build/macOS/libretrodlp.a $(MAC_LIBS) $(ALTIVECCORE_DIR)/lib/libcrypto.a -framework Foundation -framework CoreFoundation -framework SystemConfiguration -lpthread
EXTRA_BUNDLE_STEPS = @set -e; cp $(ALTIVECCORE_DIR)/lib/cacert.pem $@/Contents/Resources/cacert.pem; cp -R $(ROOT)/build/apps/resources/ejs $@/Contents/Resources/; chmod 755 $@/Contents/Resources/ejs; chmod 644 $@/Contents/Resources/ejs/*; touch "$@"

.DEFAULT_GOAL := app
app: validate $(ZIP_FILE)
$(BUNDLE): Info.plist Makefile $(MAC_ICON) $(ALTIVECCORE_DIR)/lib/cacert.pem $(wildcard $(ROOT)/build/apps/resources/ejs/*)
$(INT_DIR)/ppc.bin $(INT_DIR)/x86.bin: $(ROOT)/build/macOS/libretrodlp-download.a $(ROOT)/build/macOS/libretrodlp.a
.PHONY: app

$(UNIVERSAL_BIN): $(INT_DIR)/ppc.bin $(INT_DIR)/x86.bin Makefile
	@echo "  > merging macOS application (ppc, i386)"
	@$(LIPO) -create $(filter %.bin,$^) -output $@
