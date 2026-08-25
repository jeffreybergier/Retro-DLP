BUILD_MAKEFILE := source/make/Makefile

.DEFAULT_GOAL := release

release macOS linux test validate clean:
	@$(MAKE) --no-print-directory -f $(BUILD_MAKEFILE) $@

.PHONY: release macOS linux test validate clean
