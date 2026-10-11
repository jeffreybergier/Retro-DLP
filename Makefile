ALTIVEC_ROOT ?= /altivec
-include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
PLATFORMS = macOS iOS
PROJECT_macOS_DIR = source/gui/macOS
PROJECT_iOS_DIR = source/gui/iOS
TEST_HOST_COMMAND = $(MAKE) -C $(PROJECT_ROOT) -f make/Makefile test
# Portable Linux targets remain usable without the Apple container installed.
_host_goals := linux linux-debug linux-release test test-host sanitize install examples validate-examples validate-linux-package clean-linux app-test
ifeq ($(strip $(MAKECMDGOALS)),)
include $(ALTIVEC_ROOT)/make/projects.mk
else ifneq ($(strip $(filter-out $(_host_goals),$(MAKECMDGOALS))),)
include $(ALTIVEC_ROOT)/make/projects.mk
else
test-host: test
endif
macOS app-macOS: macOS-release
iOS app-iOS: iOS-release
apps: release
linux-debug linux-release:
	+$(MAKE) -C $(PROJECT_ROOT) -f make/Makefile linux CONFIG=$(patsubst linux-%,%,$@)
linux test sanitize install examples validate-examples:
	+$(MAKE) -C $(PROJECT_ROOT) -f make/Makefile $@
app-test:
	+$(MAKE) -C $(PROJECT_ROOT) -f make/Makefile linux
	python3 source/gui/shared/tests/test_localization.py
	python3 source/gui/shared/tests/test_c_strings.py
	python3 source/gui/shared/tests/test_store.py
	python3 source/gui/shared/tests/test_service.py
app-validate: release
	python3 source/gui/shared/tests/test_artifacts.py
validate-apple-artifacts: validate-package
package-libraries: release
	+$(MAKE) -C $(PROJECT_ROOT) -f make/Makefile package-libraries
validate-linux-package:
	+$(MAKE) -C $(PROJECT_ROOT) -f make/Makefile validate-package
clean-linux:
	+$(MAKE) -C $(PROJECT_ROOT) -f make/Makefile clean-linux
clean-macOS: macOS-clean
clean-iOS: iOS-clean
app-clean: clean
endif
