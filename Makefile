# Earnings Ping — common dev & release tasks.
# Run `make help` for the list. See docs/releasing.md for the release runbook.

SCHEME      := EarningsPing
PROJECT     := EarningsPing.xcodeproj
DESTINATION := platform=macOS,arch=arm64

.DEFAULT_GOAL := help

.PHONY: help generate build test version \
        dmg notarize appcast release \
        bump-major bump-minor bump-patch bump-build

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

generate: ## Regenerate EarningsPing.xcodeproj from project.yml
	xcodegen generate

build: generate ## Build the app (Debug)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build

test: generate ## Run the test suite
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)'

version: ## Print the current marketing + build version
	@awk -F'"' '/MARKETING_VERSION:/ {m=$$2} /CURRENT_PROJECT_VERSION:/ {b=$$2} END {printf "Earnings Ping %s (build %s)\n", m, b}' project.yml

dmg: ## Build a .dmg (unsigned unless DEVELOPER_ID_APP is set)
	./scripts/build-dmg.sh

notarize: ## Notarize + staple a built .dmg (needs enrollment): make notarize DMG=path
	./scripts/notarize.sh "$(DMG)"

appcast: ## Generate the Sparkle appcast (deferred to the Sparkle issue)
	./scripts/generate-appcast.sh

release: dmg ## Build + notarize a release (requires Apple Developer enrollment)
	./scripts/notarize.sh "$$(ls -t build/dist/*.dmg | head -1)"

bump-major: ## Bump MAJOR version + build number
	./scripts/bump-version.sh major
bump-minor: ## Bump MINOR version + build number
	./scripts/bump-version.sh minor
bump-patch: ## Bump PATCH version + build number
	./scripts/bump-version.sh patch
bump-build: ## Bump only the build number
	./scripts/bump-version.sh build
