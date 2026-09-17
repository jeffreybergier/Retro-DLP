BUILD_MAKEFILE := make/Makefile

.DEFAULT_GOAL := release

clean:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) clean

release:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) release

test:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) test

sanitize:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) sanitize

install:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) install

package-libraries:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) package-libraries

validate-package:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) validate-package

examples validate-examples:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) $@

validate-apple-artifacts:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) validate-apple-artifacts

macOS iOS linux validate validate-iOS clean-macOS clean-iOS clean-linux:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) $@

.PHONY: release macOS iOS linux test sanitize install package-libraries \
	examples validate-examples validate-package validate-apple-artifacts \
	validate validate-iOS clean clean-macOS clean-iOS clean-linux

# Cocoa frontends share a portable store/service and Objective-C bridge.
apps: app-macOS app-iOS
app-macOS: macOS app-assets
	@$(MAKE) --no-print-directory -C source/gui/macOS app
app-iOS: iOS app-assets
	@$(MAKE) --no-print-directory -C source/gui/iOS app
app-assets: linux
	@mkdir -p build/apps
	@$(CC) -std=c99 -Wall -Wextra -Werror -Isource/library/shared/include source/gui/shared/prepare_assets.c \
		build/linux/libretrodlp.a -lcurl -lcrypto -lm -ldl -lpthread -o build/apps/prepare-assets
	@build/apps/prepare-assets $(abspath build/apps/resources/ejs) /altivec/libs/core/build-mac/lib/cacert.pem
app-test: linux
	@python3 source/gui/shared/tests/test_store.py
	@python3 source/gui/shared/tests/test_service.py
app-clean:
	@python3 source/gui/shared/scripts/clean.py
.PHONY: apps app-macOS app-iOS app-assets app-test app-clean

app-validate:
	@python3 source/gui/shared/tests/test_artifacts.py
.PHONY: app-validate
