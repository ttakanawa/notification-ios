#!/bin/sh

set -eu

fail() {
    echo "Xcode Cloud configuration error: $1" >&2
    exit 1
}

[ "${CI_XCODE_CLOUD:-}" = "TRUE" ] || fail "run local checks with make ci-check"

case "${CI_START_CONDITION:-}" in
    manual|manual_rebuild) ;;
    *) fail "TestFlight distribution must be started manually for a selected branch" ;;
esac

# Test runners consume the test products from build-for-testing. They do not
# necessarily have a source checkout, and the build action has run these gates.
if [ "${CI_XCODEBUILD_ACTION:-}" = "test-without-building" ]; then
    echo "Using test products validated by the build-for-testing action."
    exit 0
fi

[ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] || fail "CI_PRIMARY_REPOSITORY_PATH is missing"
cd "$CI_PRIMARY_REPOSITORY_PATH"
[ -f Makefile ] && [ -f mise.toml ] || fail "the primary repository must contain Makefile and mise.toml"

export HOMEBREW_NO_AUTO_UPDATE=1
for ci_dependency in jq rg mise; do
    if ! command -v "$ci_dependency" >/dev/null 2>&1; then
        case "$ci_dependency" in
            rg) brew install ripgrep ;;
            *) brew install "$ci_dependency" ;;
        esac
    fi
done

# Use the same pinned SwiftLint version as local development.
mise trust "$CI_PRIMARY_REPOSITORY_PATH/mise.toml"
mise install
mise exec -- make ci-check
