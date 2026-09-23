SCHEME := KnowingYou
DESTINATION := platform=macOS

.PHONY: gen build test run clean release

gen:
	xcodegen generate

build: gen
	./scripts/check-no-network.sh
	xcodebuild -quiet -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' build

test: gen
	./scripts/check-l10n.sh
	xcodebuild test -quiet -scheme $(SCHEME) -destination '$(DESTINATION)'

run: build
	open $$(xcodebuild -scheme $(SCHEME) -configuration Debug -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2; exit}')/KnowingYou.app

clean:
	rm -rf build DerivedData KnowingYou.xcodeproj

# One command from source to a signed, notarized, stapled DMG. Every
# pre-flight check runs before anything gets signed or tagged — see
# scripts/check-release-readiness.sh and docs/specs/S21's decision record.
# Requires KY_SIGN_IDENTITY, KY_TEAM_ID, KY_NOTARY_PROFILE in the
# environment (never committed to the repo); see docs/testing/release-checklist.md.
release: gen
	@if [ -z "$(VERSION)" ]; then echo "usage: make release VERSION=x.y.z"; exit 1; fi
	./scripts/check-no-network.sh
	./scripts/check-l10n.sh
	./scripts/check-release-readiness.sh $(VERSION)
	./scripts/sign-and-notarize.sh $(VERSION)
	./scripts/make-dmg.sh $(VERSION)
	git tag v$(VERSION)
	@echo "release: tagged v$(VERSION) — push with 'git push origin v$(VERSION)' when ready"
