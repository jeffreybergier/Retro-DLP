APP_NAME = RetroDLP
SOURCES = main.m RDLPAppDelegate.m RDLPLibraryViewController.m RDLPLibraryActions.m RDLPLibrarySections.m RDLPUIKit.m RDLPDownloadPolicy.m RDLPStatusBarView.m RDLPSettingsViewController.m RDLPPlaylistsViewController.m RDLPPlaylistViewController.m RDLPVideoListViewController.m RDLPDownloadsViewController.m RDLPQueueViewController.m
SHARED_DIR = ../shared
SOURCE_DIRS = $(SHARED_DIR)
vpath %.c $(SHARED_DIR)
vpath %.m $(SHARED_DIR)
EXTRA_SOURCES = rdapp_store.c rdapp_service.c RDLPLibrary.m RDLPVideoRows.m
INFO_PLIST = Info.plist
RES_DIR = Resources
ALTIVECCORE_REQUIRED = 1
ALTIVECCOCOA_REQUIRED = 1
ROOT = $(abspath ../../..)
BUILD_DIR = $(ROOT)/build/apps/iOS
ANALYZE_OUTPUT_DIR = $(BUILD_DIR)/analyze
EXTRA_FLAGS = -I$(SHARED_DIR) -I$(ROOT)/include
# The IPA has app-owned storage and no private filesystem entitlements.
PHONE_LDID_SIGN ?= 1
include /altivec/altivec_common_phone.mk
IOS_FRAMEWORKS := $(ROOT)/build/iOS/libretrodlp-download.a $(ROOT)/build/iOS/libretrodlp.a $(IOS_FRAMEWORKS) $(ALTIVECCORE_DIR)/lib/libcrypto.a -framework CoreFoundation -framework SystemConfiguration -framework Security -framework MediaPlayer -framework AVFoundation -weak_framework AVKit
EXTRA_BUNDLE_STEPS = @set -e; cp $(ALTIVECCORE_DIR)/lib/cacert.pem $@/cacert.pem; cp -R $(ROOT)/build/apps/resources/ejs $@/; chmod 755 $@/ejs; chmod 644 $@/ejs/*; touch "$@"

.DEFAULT_GOAL := app
# The installed engine's IPA recipe assumes relative paths; package explicitly
# so all app artifacts remain under the repository build directory.
app: validate $(APP_BUNDLE)
	@python3 ../package_ipa.py $(APP_BUNDLE) $(BUILD_DIR)/RetroDLP.ipa
$(APP_BUNDLE): Info.plist Makefile $(wildcard $(RES_DIR)/*.png) $(ALTIVECCORE_DIR)/lib/cacert.pem $(wildcard $(ROOT)/build/apps/resources/ejs/*)
$(INT_DIR)/$(APP_NAME)-bin: $(ROOT)/build/iOS/libretrodlp-download.a $(ROOT)/build/iOS/libretrodlp.a
$(OBJS): $(wildcard *.h $(SHARED_DIR)/*.h)
.PHONY: app
