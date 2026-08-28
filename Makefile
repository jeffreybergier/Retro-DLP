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

macOS iOS linux validate validate-iOS clean-macOS clean-iOS clean-linux:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) $@

.PHONY: release macOS iOS linux test sanitize validate validate-iOS clean \
	clean-macOS clean-iOS clean-linux
