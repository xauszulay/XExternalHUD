ARCHS := arm64
TARGET := iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TIPA_VERSION := $(shell ./get-version.sh)
APPLICATION_NAME := XExternalHUD

XExternalHUD_USE_MODULES := 0
XExternalHUD_FILES += $(wildcard sources/*.mm sources/*.m)
XExternalHUD_FILES += $(wildcard sources/imgui/*.cpp sources/imgui/*.mm)
XExternalHUD_CFLAGS += -fobjc-arc
XExternalHUD_CFLAGS += -Iheaders -Isources -Isources/imgui
XExternalHUD_CFLAGS += -Wno-unused-function -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-value -Wno-module-import-in-extern-c -Wno-nullability-completeness
XExternalHUD_CCFLAGS += -std=c++17
XExternalHUD_FRAMEWORKS += CoreGraphics QuartzCore UIKit Foundation Metal MetalKit
XExternalHUD_PRIVATE_FRAMEWORKS += BackBoardServices GraphicsServices SpringBoardServices IOKit
XExternalHUD_CODESIGN_FLAGS += -Ssupports/entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

# Repackage the staged .app into a TrollStore-installable .tipa (Payload/<app>).
after-package::
	$(ECHO_NOTHING)mkdir -p packages "$(THEOS_STAGING_DIR)/Payload"$(ECHO_END)
	$(ECHO_NOTHING)cp -rp "$(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app" "$(THEOS_STAGING_DIR)/Payload/"$(ECHO_END)
	$(ECHO_NOTHING)cd "$(THEOS_STAGING_DIR)" && zip -qry "$(APPLICATION_NAME)_$(TIPA_VERSION).tipa" Payload >/dev/null && cd - >/dev/null$(ECHO_END)
	$(ECHO_NOTHING)mv -f "$(THEOS_STAGING_DIR)/$(APPLICATION_NAME)_$(TIPA_VERSION).tipa" "packages/$(APPLICATION_NAME)_$(TIPA_VERSION).tipa"$(ECHO_END)
	$(ECHO_NOTHING)echo "==> packages/$(APPLICATION_NAME)_$(TIPA_VERSION).tipa"$(ECHO_END)
