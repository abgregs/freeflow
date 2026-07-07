APP_NAME := FreeFlow
BUNDLE_ID := com.freeflow.app
SIGN_IDENTITY := Free Flow Dev
BUILD_DIR := .build
RELEASE_BIN_DIR := $(BUILD_DIR)/arm64-apple-macosx/release
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
# Sparkle ships as a dynamic framework the app links at @rpath (planning 0009).
# SwiftPM drops it next to the release products; the bundle embeds it.
SPARKLE_FRAMEWORK := $(RELEASE_BIN_DIR)/Sparkle.framework
SPARKLE_EMBEDDED := $(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework
# Extra flags forwarded to `swift build`. Empty for local builds; the release
# workflow passes `-Xswiftc -DFREEFLOW_RELEASE` to compile out dev-only UI.
SWIFT_FLAGS ?=
INFO_PLIST := Sources/FreeFlow/Resources/Info.plist
ENTITLEMENTS := Sources/FreeFlow/Resources/FreeFlow.entitlements
INSTALL_DIR := /Applications

.PHONY: build bundle sign verify install clean test

build:
	swift build -c release --arch arm64 $(SWIFT_FLAGS)

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	cp $(RELEASE_BIN_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	# Embed Sparkle.framework and point the binary's rpath at Contents/Frameworks
	# so @rpath/Sparkle.framework resolves at launch. `ditto` preserves the
	# framework's version symlinks; without the embed the app fails to launch.
	ditto $(SPARKLE_FRAMEWORK) $(SPARKLE_EMBEDDED)
	install_name_tool -add_rpath @executable_path/../Frameworks $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

sign: bundle
	# Sign inside-out (planning 0009): codesign requires every nested Mach-O
	# bundle signed before the framework, and the framework before the app.
	# --options runtime (hardened runtime) is mandatory for notarization; the
	# Downloader XPC keeps its shipped entitlements.
	codesign --force --options runtime --preserve-metadata=entitlements \
		--sign "$(SIGN_IDENTITY)" \
		$(SPARKLE_EMBEDDED)/Versions/B/XPCServices/Downloader.xpc
	codesign --force --options runtime \
		--sign "$(SIGN_IDENTITY)" \
		$(SPARKLE_EMBEDDED)/Versions/B/XPCServices/Installer.xpc
	codesign --force --options runtime \
		--sign "$(SIGN_IDENTITY)" \
		$(SPARKLE_EMBEDDED)/Versions/B/Autoupdate
	codesign --force --options runtime \
		--sign "$(SIGN_IDENTITY)" \
		$(SPARKLE_EMBEDDED)/Versions/B/Updater.app
	codesign --force --options runtime \
		--sign "$(SIGN_IDENTITY)" \
		$(SPARKLE_EMBEDDED)
	codesign --force --options runtime \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_IDENTITY)" \
		$(APP_BUNDLE)

verify: sign
	@echo "--- codesign -dv output ---"
	@codesign -dv $(APP_BUNDLE) 2>&1 | tee /tmp/freeflow-codesign.txt
	@grep -q "Identifier=$(BUNDLE_ID)" /tmp/freeflow-codesign.txt || \
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
