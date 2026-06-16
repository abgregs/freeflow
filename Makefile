APP_NAME := River
BUNDLE_ID := com.river.app
SIGN_IDENTITY := River Dev
BUILD_DIR := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
# Extra flags forwarded to `swift build`. Empty for local builds; the release
# workflow passes `-Xswiftc -DRIVER_RELEASE` to compile out dev-only UI.
SWIFT_FLAGS ?=
INFO_PLIST := Sources/River/Resources/Info.plist
ENTITLEMENTS := Sources/River/Resources/River.entitlements
INSTALL_DIR := /Applications

.PHONY: build bundle sign verify install clean test

build:
	swift build -c release --arch arm64 $(SWIFT_FLAGS)

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/arm64-apple-macosx/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist

sign: bundle
	codesign --force --options runtime \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_IDENTITY)" \
		$(APP_BUNDLE)

verify: sign
	@echo "--- codesign -dv output ---"
	@codesign -dv $(APP_BUNDLE) 2>&1 | tee /tmp/river-codesign.txt
	@grep -q "Identifier=$(BUNDLE_ID)" /tmp/river-codesign.txt || \
		(echo "FAIL: bundle identifier is not $(BUNDLE_ID)"; exit 1)
	@echo "--- entitlements ---"
	@codesign -d --entitlements - --xml $(APP_BUNDLE) 2>/dev/null | plutil -p - || true
	@echo "OK: bundle identifier matches"

install: verify
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_NAME).app
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

test:
	swift test

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
