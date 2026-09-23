#!/bin/sh
# Hard gate for `make release VERSION=x.y.z` — see docs/specs/S21 and
# docs/01-implementation-plan.md §12 items 5 and 11. These two placeholders
# (feedback email, logo) are explicitly called out there as "must replace
# before release", so this is a build failure, not a reminder comment
# someone can scroll past.
set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
	echo "check-release-readiness: usage: $0 <version, e.g. 1.0.0 or 1.0.0-beta.1>" >&2
	exit 1
fi

FAILED=0

fail() {
	echo "check-release-readiness: $1" >&2
	FAILED=1
}

# 1. project.yml's MARKETING_VERSION must match the version being released.
PROJECT_VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*MARKETING_VERSION: *"?([^"[:space:]]*)"?.*/\1/')
if [ "$PROJECT_VERSION" != "$VERSION" ]; then
	fail "project.yml MARKETING_VERSION is '$PROJECT_VERSION', expected '$VERSION' — update project.yml and re-run 'make gen'"
fi

# 2. KYFeedbackEmail must no longer be the placeholder, and must look like an email.
FEEDBACK_EMAIL=$(/usr/libexec/PlistBuddy -c 'Print :KYFeedbackEmail' KnowingYou/Resources/Info.plist 2>/dev/null || echo "")
case "$FEEDBACK_EMAIL" in
	""|*@example.invalid)
		fail "KYFeedbackEmail in Info.plist is still the placeholder ('$FEEDBACK_EMAIL') — set it to a real feedback address before release"
		;;
	*@*.*)
		: # looks like an email, good enough for a build gate
		;;
	*)
		fail "KYFeedbackEmail in Info.plist ('$FEEDBACK_EMAIL') doesn't look like an email address"
		;;
esac

# 3. The logo must no longer be the placeholder SF Symbol.
if grep -q 'placeholderSymbolName = "waveform.circle"' KnowingYou/UI/DesignSystem/Brand.swift 2>/dev/null; then
	fail "KYBrand.placeholderSymbolName in Brand.swift is still the placeholder SF Symbol 'waveform.circle' — wire in the real logo asset before release"
fi

# 4. KYIsPrerelease must agree with whether VERSION carries a pre-release
# suffix (semver: a hyphen after the x.y.z core, e.g. 1.0.0-beta.1).
IS_PRERELEASE_PLIST=$(/usr/libexec/PlistBuddy -c 'Print :KYIsPrerelease' KnowingYou/Resources/Info.plist 2>/dev/null || echo "")
case "$VERSION" in
	*-*) VERSION_IS_PRERELEASE=true ;;
	*) VERSION_IS_PRERELEASE=false ;;
esac
if [ "$IS_PRERELEASE_PLIST" != "$VERSION_IS_PRERELEASE" ]; then
	fail "KYIsPrerelease in Info.plist is '$IS_PRERELEASE_PLIST' but version '$VERSION' implies '$VERSION_IS_PRERELEASE' — update Info.plist"
fi

if [ "$FAILED" -ne 0 ]; then
	echo "check-release-readiness: FAILED — fix the above before 'make release' will tag anything" >&2
	exit 1
fi

echo "check-release-readiness: OK ($VERSION)"
