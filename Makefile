APP_NAME := Blitz
BUNDLE_ID := research.reversedir.blitz
ROOT := $(abspath .)
BUILD := $(ROOT)/build
DIST := $(ROOT)/dist
APP := $(DIST)/$(APP_NAME).app
SOURCES := $(wildcard $(ROOT)/Sources/*.swift)
SWIFTC ?= swiftc
MACOSX_DEPLOYMENT_TARGET ?= 14.0
# Prefer a stable local identity so Accessibility TCC survives rebuilds.
CODESIGN_IDENTITY ?= Blitz Dev

.PHONY: all app run install clean doctor signing-cert ensure-identity signing-allow-codesign unlock-keychain dist-ci

all: app

# CI / GitHub Release: ad-hoc sign (no Apple Developer ID). Zip for upload.
# Local daily use still prefers `make install` + Blitz Dev for stable Accessibility.
dist-ci: $(BUILD)/$(APP_NAME)
	@rm -rf $(APP)
	@mkdir -p $(DIST) $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BUILD)/$(APP_NAME) $(APP)/Contents/MacOS/$(APP_NAME)
	@cp $(ROOT)/Info.plist $(APP)/Contents/Info.plist
	@cp $(ROOT)/Resources/AppIcon.icns $(APP)/Contents/Resources/
	@cp $(ROOT)/Resources/StatusItem.png $(ROOT)/Resources/StatusItem-2x.png $(APP)/Contents/Resources/
	@echo 'APPL????' > $(APP)/Contents/PkgInfo
	@codesign --force --deep --sign - \
		--entitlements "$(ROOT)/Blitz.entitlements" \
		$(APP)
	@ditto -c -k --sequesterRsrc --keepParent $(APP) $(DIST)/Blitz-macos-arm64.zip
	@echo "CI artifact: $(DIST)/Blitz-macos-arm64.zip"
	@shasum -a 256 $(DIST)/Blitz-macos-arm64.zip | tee $(DIST)/Blitz-macos-arm64.zip.sha256

doctor:
	@echo "swiftc: $$(command -v $(SWIFTC))"
	@$(SWIFTC) --version | head -1
	@echo "sources: $(words $(SOURCES))"
	@echo "codesign identity:"
	@security find-identity -p codesigning -v 2>/dev/null | grep -F "$(CODESIGN_IDENTITY)" \
		|| echo "  MISSING — run: make signing-cert"
	@if [ -f "$(HOME)/Library/Keychains/blitz-codesign.keychain-db" ]; then \
		echo "blitz-codesign.keychain: present"; \
	else \
		echo "blitz-codesign.keychain: absent (identity may be in login.keychain — password prompts possible)"; \
		echo "  one-time fix: make signing-allow-codesign"; \
	fi

$(BUILD)/$(APP_NAME): $(SOURCES)
	@mkdir -p $(BUILD)
	$(SWIFTC) -O \
		-target arm64-apple-macosx$(MACOSX_DEPLOYMENT_TARGET) \
		-sdk $$(xcrun --show-sdk-path) \
		-framework AppKit -framework Carbon -framework ApplicationServices -framework ServiceManagement -framework Vision \
		-lsqlite3 \
		$(SOURCES) \
		-o $@

unlock-keychain:
	@if [ -f "$(HOME)/Library/Keychains/blitz-codesign.keychain-db" ]; then \
		$(ROOT)/scripts/unlock-signing-keychain.sh; \
	fi

ensure-identity: unlock-keychain
	@if ! security find-identity -p codesigning -v 2>/dev/null | grep -F "$(CODESIGN_IDENTITY)" >/dev/null; then \
		echo "Creating stable codesign identity '$(CODESIGN_IDENTITY)'…"; \
		$(ROOT)/scripts/create-signing-cert.sh "$(CODESIGN_IDENTITY)"; \
	fi
	@security find-identity -p codesigning -v 2>/dev/null | grep -F "$(CODESIGN_IDENTITY)" >/dev/null \
		|| (echo "ERROR: no valid '$(CODESIGN_IDENTITY)' identity — Accessibility will reset on every install."; exit 1)

app: ensure-identity $(BUILD)/$(APP_NAME)
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BUILD)/$(APP_NAME) $(APP)/Contents/MacOS/$(APP_NAME)
	@cp $(ROOT)/Info.plist $(APP)/Contents/Info.plist
	@cp $(ROOT)/Resources/AppIcon.icns $(APP)/Contents/Resources/
	@cp $(ROOT)/Resources/StatusItem.png $(ROOT)/Resources/StatusItem-2x.png $(APP)/Contents/Resources/
	@echo 'APPL????' > $(APP)/Contents/PkgInfo
	@$(MAKE) unlock-keychain
	@codesign --force --deep \
		--entitlements "$(ROOT)/Blitz.entitlements" \
		--sign "$(CODESIGN_IDENTITY)" $(APP)
	@echo "Signed with identity: $(CODESIGN_IDENTITY)"
	@codesign -dv $(APP) 2>&1 | grep -E 'Authority|Identifier' || true
	@echo "Built $(APP)"

run: app
	@open $(APP)

# Install preserves TCC when signed with the same Blitz Dev identity across rebuilds.
# Uses ditto into place when app already exists (same path + same signing identity).
# ditto preserves the signature from `app` — do NOT codesign again (that was double
# password prompts on login.keychain). Only re-sign if verification fails.
install: app
	@mkdir -p "$(HOME)/Applications"
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@if [ -d "$(HOME)/Applications/$(APP_NAME).app" ]; then \
		ditto "$(APP)" "$(HOME)/Applications/$(APP_NAME).app"; \
	else \
		cp -R "$(APP)" "$(HOME)/Applications/$(APP_NAME).app"; \
	fi
	@if ! codesign --verify --deep --strict "$(HOME)/Applications/$(APP_NAME).app" 2>/dev/null; then \
		echo "Signature missing after copy — re-signing once…"; \
		$(MAKE) unlock-keychain; \
		codesign --force --deep \
			--entitlements "$(ROOT)/Blitz.entitlements" \
			--sign "$(CODESIGN_IDENTITY)" "$(HOME)/Applications/$(APP_NAME).app"; \
	fi
	@echo "Installed (signature reused from build) · $(CODESIGN_IDENTITY)"
	@codesign -dv "$(HOME)/Applications/$(APP_NAME).app" 2>&1 | grep -E 'Authority|Identifier' || true
	@echo "Installed ~/Applications/$(APP_NAME).app"
	@echo "Accessibility permission persists across rebuilds while signed as '$(CODESIGN_IDENTITY)'."
	@echo "If codesign asks for a password: make signing-allow-codesign  (one-time)"

signing-cert:
	@$(ROOT)/scripts/create-signing-cert.sh "$(CODESIGN_IDENTITY)"

# One-time: stop password prompts when identity is in login.keychain (existing installs).
signing-allow-codesign:
	@$(ROOT)/scripts/allow-codesign-no-prompt.sh "$(CODESIGN_IDENTITY)"

clean:
	@rm -rf $(BUILD) $(DIST)
