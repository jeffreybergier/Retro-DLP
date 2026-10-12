ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/../../..)
APP_NAME = RetroDLP
SOURCES = main.m RDLPLibrary+macOS.m RDLPAppDelegate.m RDLPLibraryWindowController.m RDLPQueueWindowController.m RDLPAppKit.m RDLPToolbarButton.m RDLPLibraryViews.m RDLPDownloadPolicy.m RDLPLibraryMenus.m
SHARED_DIR = ../shared
BUNDLE_LOCALIZATION_DIRS = $(SHARED_DIR)/Resources
SOURCE_DIRS = $(SHARED_DIR)
EXTRA_SOURCES = rdapp_strings.c rdapp_store.c rdapp_service.c rdlp_thread.c RDLPLibrary.m RDLPVideoRows.m RDLPListLoader.m RDLPDownloadSections.m RDLP_Foundation.m
INFO_PLIST = Info.plist
MAC_ICON = Resources/RetroDLP.icns
include $(PROJECT_ROOT)/make/apple-sources.mk
PRODUCTS = RetroDLP retro-dlp retrodlp retrodlp-download
PACKAGE_PRODUCTS = RetroDLP retro-dlp retrodlp
VERSION := $(shell python3 -c 'import plistlib; print(plistlib.load(open("$(PROJECT_ROOT)/source/library/shared/Info.plist","rb"))["CFBundleShortVersionString"])')
BUILD_FLAGS = -I$(PROJECT_ROOT)/source/library/shared/include -I$(PROJECT_ROOT)/source/library/shared -I$(PROJECT_ROOT)/source/cli -I$(QUICKJS_DIR) -I$(LSMASH_DIR) -DRETRO_DLP_VERSION=\"$(VERSION)\"
retrodlp_TYPE = static
retrodlp_ARCHIVE_NAME = retro-dlp-library
retrodlp_PACKAGE_MAIN_PATH = lib/libretrodlp.a
retrodlp_SOURCES = $(CORE_SOURCES) $(PROJECT_ROOT)/source/library/macOS/platform.c
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
RetroDLP_SQLITE = 1
RetroDLP_STATIC_LIBS = $(ALTIVECCORE_DIR)/lib/libcrypto.a
RetroDLP_PLIST = Info.plist
RetroDLP_LOCALIZATIONS = $(BUNDLE_LOCALIZATION_DIRS)
RetroDLP_RESOURCES = $(filter-out Resources/Info.plist,$(wildcard Resources/*)) $(BUILD_ROOT)/generated/ejs
ARCHS ?= ppc i386
QUICKJS_COMPAT = $(PROJECT_ROOT)/source/library/macOS/apple-gcc4/QuickJS
GROUP_quickjs_SOURCES = $(addprefix $(QUICKJS_DIR)/,$(QUICKJS_SOURCE_NAMES)) $(QUICKJS_COMPAT)/quickjs_compat.c
GROUP_quickjs_FLAGS += -std=gnu99 -Wno-uninitialized
GROUP_lsmash_SOURCES += $(PROJECT_ROOT)/source/library/macOS/apple-gcc4/L-SMASH/stdio_compat.c
RetroDLP_FLAGS += -D_NONSTD_SOURCE
retro-dlp_FLAGS = -D_NONSTD_SOURCE
retrodlp_FLAGS += -D_NONSTD_SOURCE
GROUP_quickjs_FLAGS += -U_NONSTD_SOURCE
GROUP_lsmash_FLAGS += -U_NONSTD_SOURCE
RetroDLP_LDFLAGS = -framework AppKit -framework Foundation -framework CoreFoundation -framework SystemConfiguration -lobjc -lpthread
include $(ALTIVEC_ROOT)/altivec_common_mac.mk
app: package
.PHONY: app
endif
