PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ALTIVEC_ROOT ?= /altivec
PLATFORMS = macOS iOS
PROJECT_macOS_DIR = source/gui/macOS
PROJECT_iOS_DIR = source/gui/iOS
TEST_HOST_COMMAND = $(MAKE) -f make/Makefile test
# Portable Linux targets remain usable without the Apple container installed.
_host_goals := linux test test-host sanitize install examples validate-examples validate-linux-package clean-linux app-test
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
linux test sanitize install examples validate-examples:
	+$(MAKE) -f make/Makefile $@
app-test:
	+$(MAKE) -f make/Makefile linux
	python3 source/gui/shared/tests/test_localization.py
	python3 source/gui/shared/tests/test_c_strings.py
	python3 source/gui/shared/tests/test_store.py
	python3 source/gui/shared/tests/test_service.py
app-validate: release
	python3 source/gui/shared/tests/test_artifacts.py
validate-apple-artifacts: validate-package
package-libraries: release
	+$(MAKE) -f make/Makefile package-libraries
validate-linux-package:
	+$(MAKE) -f make/Makefile validate-package
clean-linux:
	+$(MAKE) -f make/Makefile clean-linux
clean-macOS: macOS-clean
clean-iOS: iOS-clean
app-clean: clean
