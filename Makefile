BUILD_MAKEFILE := source/make/Makefile

.DEFAULT_GOAL := release

release macOS iOS linux test validate validate-iOS clean:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) $@

.PHONY: release macOS iOS linux test validate validate-iOS clean
