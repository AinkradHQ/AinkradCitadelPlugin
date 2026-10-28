DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
# `<cacheRoot>/DevPlugins`, scanned by Debug hosts only (AppEnvironment+BootstrapStores,
# PluginTrust.scansDevPluginsDirectory); cacheRoot is AinkradHome.defaultCacheRoot.
DEV_PLUGINS ?= $(HOME)/Library/Application Support/com.ainkrad.app/Cache/DevPlugins
# DERIVED_DATA: where Xcode builds. `build` (in the worktree) by default; a Citadel runner sets a persistent per-runner
# directory (e.g. $HOME/.cache/ainkrad-dd/citadel-plugin) so a fresh issue worktree builds incrementally, not from scratch.
DERIVED_DATA ?= build
XCODEBUILD := xcodebuild -scheme CitadelPlugin -derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS'

generate: ; xcodegen generate
build: lint generate ; $(XCODEBUILD) -configuration Debug build
test: lint generate ; $(XCODEBUILD) -configuration Debug test
releasebuild: generate ; $(XCODEBUILD) -configuration Release build
# The default DEV_PLUGINS is the DAILY app's folder: a bundle built for a newer AppKit there stops it opening.
# Point DEV_PLUGINS at a fixture folder, or pass CONFIRM_DAILY=1 to overwrite the daily app's copy on purpose.
sideload: build
	@case "$(DEV_PLUGINS)" in "$(HOME)/Library/Application Support/com.ainkrad.app/"*) \
		[ "$(CONFIRM_DAILY)" = 1 ] || { echo "refusing: DEV_PLUGINS is the daily app's folder (set DEV_PLUGINS=<fixture>/DevPlugins or CONFIRM_DAILY=1)"; exit 1; };; esac
	mkdir -p "$(DEV_PLUGINS)"
	rm -rf "$(DEV_PLUGINS)/CitadelPlugin.bundle"
	cp -R $(DERIVED_DATA)/Build/Products/Debug/CitadelPlugin.bundle "$(DEV_PLUGINS)/CitadelPlugin.bundle"
# Publishing goes through `ainkrad publish` and nowhere else: it validates the
# bundle as the store does, signs it ($SIGN_IDENTITY, or --sign-identity in
# PUBLISH_FLAGS), creates the GitHub Release and lists it in AinkradCatalog.
#   SIGN_IDENTITY="Developer ID Application: ..." make release V=v1.0.0
#   make release V=v1.0.0 PUBLISH_FLAGS="--dry-run --sign-identity -"   # plan only
AINKRAD ?= ainkrad
release: releasebuild ; $(AINKRAD) publish $(DERIVED_DATA)/Build/Products/Release/CitadelPlugin.bundle $(V) $(PUBLISH_FLAGS)

# The generated client (Packages/CitadelClient): `make contract [REV=<citadel-rev>]` pins the Citadel spec and
# regenerates; `make contract-check` fails when the committed client or the pin is stale. Both need
# GENERATOR=<swift-openapi-generator 1.14.2 binary>; see scripts/contract.sh.
contract: ; ./scripts/contract.sh regen $(REV)
contract-check: ; ./scripts/contract.sh check

.PHONY: generate build test releasebuild sideload release contract contract-check

include scripts/guardrails.mk
