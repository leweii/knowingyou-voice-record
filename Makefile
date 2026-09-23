SCHEME := KnowingYou
DESTINATION := platform=macOS

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	./scripts/check-no-network.sh
	xcodebuild -quiet -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' build

test: gen
	xcodebuild test -quiet -scheme $(SCHEME) -destination '$(DESTINATION)'

run: build
	open $$(xcodebuild -scheme $(SCHEME) -configuration Debug -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2; exit}')/KnowingYou.app

clean:
	rm -rf build DerivedData KnowingYou.xcodeproj
