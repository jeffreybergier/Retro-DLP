APP_NAME = RetroDLP
SOURCES = main.m RDLPLibrary+macOS.m RDLPAppDelegate.m RDLPLibraryWindowController.m RDLPAppKit.m RDLPToolbarButton.m RDLPLibraryViews.m RDLPDownloadPolicy.m RDLPLibraryMenus.m
SHARED_DIR = ../shared
SOURCE_DIRS = $(SHARED_DIR)
vpath %.c $(SHARED_DIR)
vpath %.m $(SHARED_DIR)
EXTRA_SOURCES = rdapp_store.c rdapp_service.c RDLPLibrary.m RDLPVideoRows.m RDLP_Foundation.m
INFO_PLIST = Info.plist
MAC_ICON = Resources/RetroDLP.icns
ALTIVECCORE_REQUIRED = 1
ALTIVECCORE_LINKAGE = static
ALTIVECCOCOA_REQUIRED = 1
ALTIVECCOCOA_LINKAGE = static
ROOT = $(abspath ../../..)
BUILD_DIR = $(ROOT)/build/apps/macOS
ANALYZE_OUTPUT_DIR = $(BUILD_DIR)/analyze
include /altivec/altivec_common_mac.mk
MAC_FLAGS += -I$(SHARED_DIR) -I$(ROOT)/source/library/shared/include
LEGACY_GCC_FLAGS += -D_NONSTD_SOURCE
# The application consumes only public Retro-DLP static archives.
MAC_LIBS := $(ROOT)/build/macOS/libretrodlp-download.a $(ROOT)/build/macOS/libretrodlp.a $(MAC_LIBS) $(ALTIVECCORE_DIR)/lib/libcrypto.a -framework Foundation -framework CoreFoundation -framework SystemConfiguration -lpthread
EXTRA_BUNDLE_STEPS = @set -e; cp $(ALTIVECCORE_DIR)/lib/cacert.pem $@/Contents/Resources/cacert.pem; cp -R $(ROOT)/build/apps/resources/ejs $@/Contents/Resources/; chmod 755 $@/Contents/Resources/ejs; chmod 644 $@/Contents/Resources/ejs/*; touch "$@"

.DEFAULT_GOAL := app
app: validate $(ZIP_FILE)
$(BUNDLE): Info.plist Makefile $(MAC_ICON) $(ALTIVECCORE_DIR)/lib/cacert.pem $(wildcard $(ROOT)/build/apps/resources/ejs/*)
$(INT_DIR)/ppc.bin $(INT_DIR)/x86.bin $(INT_DIR)/x64.bin $(INT_DIR)/arm.bin: $(ROOT)/build/macOS/libretrodlp-download.a $(ROOT)/build/macOS/libretrodlp.a
.PHONY: app
