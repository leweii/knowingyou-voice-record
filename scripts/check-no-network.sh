#!/bin/sh
# Zero-network is a structural constraint (see CLAUDE.md), not just a feature flag.
# Fails the build if any networking API shows up in the app source.
set -eu

PATTERN='URLSession|NWConnection|Network\.framework|import Network|CFNetwork|NSURLConnection|WKWebView'

if grep -rEn "$PATTERN" KnowingYou --include='*.swift'; then
	echo "check-no-network: found forbidden networking API above; KnowingYou must link no network code." >&2
	exit 1
fi

echo "check-no-network: OK"
