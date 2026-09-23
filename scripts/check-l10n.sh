#!/bin/sh
# Every key in Localizable.xcstrings must have a non-empty English
# translation — the source language (zh-Hans) is the key itself, so this is
# the only language that can actually go missing. See docs/specs/S19.
set -eu

CATALOG="KnowingYou/Resources/Localizable.xcstrings"

if ! command -v jq >/dev/null 2>&1; then
	echo "check-l10n: jq is required (brew install jq)" >&2
	exit 1
fi

if [ ! -f "$CATALOG" ]; then
	echo "check-l10n: $CATALOG not found" >&2
	exit 1
fi

MISSING=$(jq -r '
	.strings
	| to_entries[]
	| select((.value.localizations.en.stringUnit.value // "") == "")
	| .key
' "$CATALOG")

if [ -n "$MISSING" ]; then
	echo "check-l10n: missing English translation for:" >&2
	echo "$MISSING" >&2
	exit 1
fi

TOTAL=$(jq '.strings | length' "$CATALOG")
echo "check-l10n: OK ($TOTAL keys, all have English translations)"
