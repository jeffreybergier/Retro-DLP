BUILD_MAKEFILE := source/make/Makefile

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
