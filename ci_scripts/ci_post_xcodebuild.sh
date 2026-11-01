#!/bin/sh

set -eu

# Xcode Cloud also invokes this hook for tests and failed builds.
[ "${CI_XCODE_CLOUD:-}" = TRUE ] || exit 0
[ "${CI_XCODEBUILD_ACTION:-}" = archive ] || exit 0
[ "${CI_XCODEBUILD_EXIT_CODE:-}" = 0 ] || exit 0
[ -d "${CI_APP_STORE_SIGNED_APP_PATH:-}" ] || exit 0

fail() {
    echo "TestFlight notes error: $1" >&2
    exit 1
}

[ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] || fail "CI_PRIMARY_REPOSITORY_PATH is missing"
case "${CI_COMMIT:-}" in
    ''|*[!0-9a-fA-F]*) fail "CI_COMMIT must be a full commit SHA" ;;
esac
[ "${#CI_COMMIT}" -eq 40 ] || fail "CI_COMMIT must be a full commit SHA"

github_repository=ttakanawa/notification-ios
repository_url="https://github.com/$github_repository"
notes_directory="$CI_PRIMARY_REPOSITORY_PATH/TestFlight"
notes_file="$notes_directory/WhatToTest.en-US.txt"
mkdir -p "$notes_directory"

# Write the exact build's commit before the optional, unauthenticated lookup.
# https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app
printf 'Commit: %s/commit/%s\n' "$repository_url" "$CI_COMMIT" > "$notes_file"

if response=$(curl --disable --fail --silent --show-error \
    --connect-timeout 5 --max-time 15 \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2026-03-10' \
    "https://api.github.com/repos/$github_repository/commits/$CI_COMMIT/pulls?per_page=100") &&
    pr_url=$(printf '%s' "$response" | jq -r \
        --arg repository_url "$repository_url" \
        --arg branch "${CI_BRANCH:-}" \
        --arg commit "$CI_COMMIT" '
        if type != "array" then error("expected a pull request array") else
            map(select(.html_url | type == "string")
                | select(.html_url | startswith($repository_url + "/pull/"))
                | select(.html_url | ltrimstr($repository_url + "/pull/") | test("^[1-9][0-9]*$")))
            | sort_by(
                if $branch != "" and .head.ref == $branch then 0
                elif .head.sha == $commit or .merge_commit_sha == $commit then 1
                else 2 end,
                .number)
            | .[0].html_url // empty
        end'); then
    if [ -n "$pr_url" ]; then
        printf 'PR: %s\n' "$pr_url" >> "$notes_file"
    fi
else
    echo "PR lookup unavailable; keeping commit-only TestFlight notes." >&2
fi
