ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/../../..)
APP_NAME = RetroDLP
SOURCES = main.m RDLPLibrary+iOS.m RDLPAppDelegate.m RDLPLibraryViewController.m RDLPLibraryActions.m RDLPLibrarySections.m RDLPUIKit.m RDLPDownloadPolicy.m RDLPStatusBarView.m RDLPSettingsViewController.m RDLPPlaylistsViewController.m RDLPPlaylistViewController.m RDLPVideoListViewController.m RDLPDownloadsViewController.m RDLPQueueViewController.m
SHARED_DIR = ../shared
BUNDLE_LOCALIZATION_DIRS = $(SHARED_DIR)/Resources
SOURCES += RDLPDownloadedPlayerViewController.m
SOURCES += RDLPPlayerControls.m RDLPPlayerViewController.m RDLPPlayerQueue.m RDLPPlayerNavigationController.m
SOURCE_DIRS = $(SHARED_DIR) player
EXTRA_SOURCES = rdapp_strings.c rdapp_store.c rdapp_service.c rdlp_thread.c RDLPLibrary.m RDLPVideoRows.m RDLPDownloadSections.m RDLP_Foundation.m
INFO_PLIST = Info.plist
RES_DIR = Resources
include $(PROJECT_ROOT)/make/apple-sources.mk
PRODUCTS = RetroDLP retro-dlp retrodlp retrodlp-download
PACKAGE_PRODUCTS = RetroDLP retro-dlp retrodlp
VERSION := $(shell python3 -c 'import plistlib; print(plistlib.load(open("$(PROJECT_ROOT)/source/library/shared/Info.plist","rb"))["CFBundleShortVersionString"])')
BUILD_FLAGS = -I$(PROJECT_ROOT)/source/library/shared/include -I$(PROJECT_ROOT)/source/library/shared -I$(PROJECT_ROOT)/source/cli -I$(QUICKJS_DIR) -I$(LSMASH_DIR) -DRETRO_DLP_VERSION=\"$(VERSION)\"
retrodlp_TYPE = static
retrodlp_ARCHIVE_NAME = retro-dlp-library
retrodlp_PACKAGE_MAIN_PATH = lib/libretrodlp.a
retrodlp_SOURCES = $(CORE_SOURCES) $(PROJECT_ROOT)/source/library/iOS/platform.c
retrodlp_GROUPS = quickjs
retrodlp_CORE = static
retrodlp_FLAGS = -Wno-unused-parameter
retrodlp-download_TYPE = static
retrodlp-download_SOURCES = $(DOWNLOAD_SOURCES)
retrodlp-download_GROUPS = lsmash
retrodlp-download_CORE = static
GROUP_lsmash_SOURCES = $(addprefix $(LSMASH_DIR)/,$(LSMASH_SOURCE_NAMES))
GROUP_lsmash_FLAGS = -Wno-unused-parameter
GROUP_quickjs_FLAGS = -I$(QUICKJS_COMPAT) -include $(QUICKJS_COMPAT)/quickjs_compat.h -D_GNU_SOURCE -DCONFIG_VERSION=\"$(QUICKJS_VERSION)\" -funsigned-char -fwrapv -Wno-sign-compare -Wno-missing-field-initializers -Wno-unused-parameter
retro-dlp_TYPE = executable
retro-dlp_PACKAGE_RESOURCES = $(ALTIVECCORE_DIR)/lib/cacert.pem=cacert.pem
retrodlp_PACKAGE_RESOURCES = $(PROJECT_ROOT)/source/library/shared/include=include $(PROJECT_ROOT)/LICENSE=LICENSE $(PROJECT_ROOT)/source/library/shared/examples=examples
retrodlp_PACKAGE_RESOURCES += $(call product,retrodlp-download)=lib/libretrodlp-download.a
retro-dlp_SOURCES = $(CLI_SOURCES)
retro-dlp_DEPS = retrodlp-download retrodlp
retro-dlp_CORE = static
retro-dlp_STATIC_LIBS = $(ALTIVECCORE_DIR)/lib/libcrypto.a
retro-dlp_LDFLAGS = -framework Foundation -framework CoreFoundation -framework SystemConfiguration -lobjc -lm -lpthread
RetroDLP_TYPE = app
RetroDLP_SOURCES = $(SOURCES) $(EXTRA_SOURCES)
RetroDLP_FLAGS = -I$(SHARED_DIR)
RetroDLP_DEPS = retrodlp-download retrodlp
RetroDLP_CORE = static
RetroDLP_COCOA = static
RetroDLP_STATIC_LIBS = $(ALTIVECCORE_DIR)/lib/libcrypto.a
RetroDLP_PLIST = Info.plist
RetroDLP_LOCALIZATIONS = $(BUNDLE_LOCALIZATION_DIRS)
RetroDLP_RESOURCES = $(filter-out Resources/Info.plist,$(wildcard Resources/*)) $(BUILD_ROOT)/generated/ejs
QUICKJS_COMPAT = $(PROJECT_ROOT)/source/library/iOS/clang/QuickJS
GROUP_quickjs_SOURCES = $(addprefix $(QUICKJS_DIR)/,$(filter-out quickjs-libc.c,$(QUICKJS_SOURCE_NAMES))) $(QUICKJS_COMPAT)/quickjs_compat.c
GROUP_quickjs_FLAGS += -std=gnu11
RetroDLP_ENTITLEMENTS = Entitlements.plist
RetroDLP_SANDBOX = container
RetroDLP_RESOURCE_BUNDLES = player/RDLPPlayer.bundle
RetroDLP_LDFLAGS = -framework UIKit -framework Foundation -framework CoreGraphics -framework CoreFoundation -framework SystemConfiguration -framework Security -framework MediaPlayer -framework AVFoundation -framework CoreMedia -framework QuartzCore -lpthread
retro-dlp_LDFLAGS += -framework Security
retro-dlp_SIGN = 1
include $(ALTIVEC_ROOT)/altivec_common_phone.mk
app: package
.PHONY: app
endif
