#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
hook="$repository_root/ci_scripts/ci_post_xcodebuild.sh"
temporary_directory=$(mktemp -d)
fixture_root="$temporary_directory/project with spaces"
fixture_bin="$temporary_directory/bin"
signed_app="$temporary_directory/signed app"
notes_directory="$fixture_root/TestFlight"
response_file="$temporary_directory/response.json"
output_file="$temporary_directory/output.txt"
log_file="$temporary_directory/curl.log"
expected_file="$temporary_directory/expected.txt"
commit_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
other_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
repository_url=https://github.com/ttakanawa/notification-ios

trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

# Only these tools are available to the hook. HTTP never reaches the network,
# while real jq exercises response parsing and selection rather than a mock.
mkdir -p "$fixture_root" "$fixture_bin" "$signed_app"
ln -s "$(command -v jq)" "$fixture_bin/jq"
ln -s /bin/mkdir "$fixture_bin/mkdir"
cat > "$fixture_bin/curl" <<'STUB'
#!/bin/sh
set -eu
printf '%s\n' "$@" >> "$MOCK_LOG"
[ "${MOCK_CURL_STATUS:-0}" -eq 0 ] || exit "$MOCK_CURL_STATUS"
response_destination=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output|-o)
            shift
            response_destination=$1
            ;;
    esac
    shift
done
if [ -n "$response_destination" ]; then
    /bin/cat "$MOCK_RESPONSE_FILE" > "$response_destination"
else
    /bin/cat "$MOCK_RESPONSE_FILE"
fi
STUB
chmod +x "$fixture_bin/curl"
printf '[]\n' > "$response_file"

run_hook() {
    : > "$log_file"
    if (
        cd "$temporary_directory"
        /usr/bin/env -i \
            PATH="$fixture_bin" \
            MOCK_LOG="$log_file" \
            MOCK_RESPONSE_FILE="$response_file" \
            CI_XCODE_CLOUD=TRUE \
            CI_XCODEBUILD_ACTION=archive \
            CI_XCODEBUILD_EXIT_CODE=0 \
            CI_APP_STORE_SIGNED_APP_PATH="$signed_app" \
            CI_PRIMARY_REPOSITORY_PATH="$fixture_root" \
            CI_COMMIT="$commit_sha" \
            CI_BRANCH=feature/reminders \
            "$@" /bin/sh "$hook"
    ) > "$output_file" 2>&1; then
        hook_status=0
    else
        hook_status=$?
    fi
}

fail_test() {
    echo "TestFlight notes test failed: $scenario ($1)" >&2
    cat "$output_file" "$log_file" >&2
    exit 1
}

expect_notes() {
    scenario=$1
    expected_pr=$2
    shift 2
    run_hook "$@"
    [ "$hook_status" -eq 0 ] || fail_test "unexpected failure"
    printf 'Commit: %s/commit/%s\n' "$repository_url" "$commit_sha" > "$expected_file"
    if [ -n "$expected_pr" ]; then
        printf 'PR: %s/pull/%s\n' "$repository_url" "$expected_pr" >> "$expected_file"
    fi
    notes_file="$notes_directory/WhatToTest.en-US.txt"
    [ -f "$notes_file" ] || fail_test "missing notes"
    diff -u "$expected_file" "$notes_file" || fail_test "incorrect notes"
    [ ! -e "$notes_directory/WhatToTest.ja.txt" ] || fail_test "unexpected Japanese notes"
}

expect_no_request() {
    [ ! -s "$log_file" ] || fail_test "HTTP ran unexpectedly"
}

expect_skipped() {
    scenario=$1
    shift
    rm -rf "$notes_directory"
    run_hook "$@"
    [ "$hook_status" -eq 0 ] || fail_test "unexpected failure"
    [ ! -e "$notes_directory" ] || fail_test "notes generated for skipped action"
    expect_no_request
}

expect_rejected() {
    scenario=$1
    shift
    rm -rf "$notes_directory"
    run_hook "$@"
    [ "$hook_status" -ne 0 ] || fail_test "invalid metadata accepted"
    expect_no_request
}

cat > "$response_file" <<EOF
[{"number":12,"html_url":"$repository_url/pull/12","head":{"ref":"feature/reminders","sha":"$commit_sha"}}]
EOF
expect_notes "successful archive from another working directory" 12

# Verify request identity, public access, and finite time bounds without pinning
# a specific timeout duration.
request_arguments=$(cat "$log_file")
case "$request_arguments" in
    *"https://api.github.com/repos/ttakanawa/notification-ios/commits/$commit_sha/pulls"*) ;;
    *) fail_test "request did not use the exact build commit" ;;
esac
case "$request_arguments" in
    *application/vnd.github+json*) ;;
    *) fail_test "missing GitHub Accept header" ;;
esac
case "$request_arguments" in
    *X-GitHub-Api-Version:*) ;;
    *) fail_test "missing GitHub API version header" ;;
esac
case "$request_arguments" in
    *--connect-timeout*) ;;
    *) fail_test "missing connection timeout" ;;
esac
case "$request_arguments" in
    *--max-time*) ;;
    *) fail_test "missing total timeout" ;;
esac
case "$request_arguments" in
    *[Aa]uthorization:*|*--user*|*--oauth2-bearer*) fail_test "public request included credentials" ;;
esac

# The source branch is more relevant than another PR containing the same commit.
# A PR remains associated even when its head advances after the selected build.
cat > "$response_file" <<EOF
[
 {"number":2,"html_url":"$repository_url/pull/2","head":{"ref":"another-branch","sha":"$commit_sha"}},
 {"number":10,"html_url":"$repository_url/pull/10","head":{"ref":"feature/reminders","sha":"$other_sha"}},
 {"number":3,"html_url":"$repository_url/pull/3","head":{"ref":"feature/reminders","sha":"$other_sha"}}
]
EOF
expect_notes "prefer source branch and sort ties numerically" 3

cat > "$response_file" <<EOF
[
 {"number":1,"html_url":"$repository_url/pull/1","head":{"ref":"","sha":"$other_sha"}},
 {"number":7,"html_url":"$repository_url/pull/7","head":{"ref":"old-name","sha":"$commit_sha"}}
]
EOF
expect_notes "exact commit when branch is unavailable" 7 CI_BRANCH=

cat > "$response_file" <<EOF
[
 {"number":1,"html_url":"$repository_url/pull/1","head":{"sha":"$other_sha"}},
 {"number":7,"html_url":"$repository_url/pull/7","head":{"sha":"$commit_sha"}},
 {"number":3,"html_url":"$repository_url/pull/3","state":"closed","merged_at":"2026-11-01T00:00:00Z","merge_commit_sha":"$commit_sha","head":{"sha":"$other_sha"}}
]
EOF
expect_notes "merged commit and exact head share numeric tie break" 3

cat > "$response_file" <<EOF
[
 {"number":10,"html_url":"$repository_url/pull/10","head":{"sha":"$other_sha"}},
 {"number":2,"html_url":"$repository_url/pull/2","head":{"sha":"$other_sha"}}
]
EOF
expect_notes "other associated PRs use numeric tie break" 2

for response in '[]' '{}' 'null' '"not an array"' '[true,1]' '{"message":"API rate limit exceeded"}' 'not json' ''; do
    printf '%s\n' "$response" > "$response_file"
    expect_notes "commit-only fallback for response: $response" ''
done

for invalid_url in \
    https://example.com/ttakanawa/notification-ios/pull/1 \
    https://github.com/another/repository/pull/1 \
    "$repository_url/pull/not-a-number" \
    "$repository_url/pull/1/extra"; do
    printf '[{"number":1,"html_url":"%s"}]\n' "$invalid_url" > "$response_file"
    expect_notes "reject noncanonical PR URL: $invalid_url" ''
done

printf '[]\n' > "$response_file"
for curl_status in 22 28 6; do
    expect_notes "HTTP, timeout, or DNS failure: $curl_status" '' MOCK_CURL_STATUS="$curl_status"
done

rm "$fixture_bin/jq"
expect_notes "missing optional jq" ''
ln -s "$(command -v jq)" "$fixture_bin/jq"
mv "$fixture_bin/curl" "$temporary_directory/curl-stub"
expect_notes "missing optional curl" ''
expect_no_request
mv "$temporary_directory/curl-stub" "$fixture_bin/curl"

cat > "$response_file" <<EOF
[{"number":12,"html_url":"$repository_url/pull/12"}]
EOF
expect_notes "first run writes a PR URL" 12
printf '[]\n' > "$response_file"
expect_notes "rerun removes stale PR URL" ''

lowercase_commit=$commit_sha
commit_sha=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
expect_notes "uppercase hexadecimal commit" ''
commit_sha=$lowercase_commit

for invalid_commit in '' abc aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa gggggggggggggggggggggggggggggggggggggggg; do
    expect_rejected "missing or invalid commit: $invalid_commit" CI_COMMIT="$invalid_commit"
done
expect_rejected "missing repository path" CI_PRIMARY_REPOSITORY_PATH=

# All skips must happen before requiring source metadata or optional tools.
for cloud_marker in '' true FALSE; do
    expect_skipped "outside Xcode Cloud: $cloud_marker" \
        CI_XCODE_CLOUD="$cloud_marker" CI_PRIMARY_REPOSITORY_PATH= CI_COMMIT= PATH=/nonexistent
done
for action in '' analyze build build-for-testing test-without-building; do
    expect_skipped "nonarchive action: $action" \
        CI_XCODEBUILD_ACTION="$action" CI_PRIMARY_REPOSITORY_PATH= CI_COMMIT= PATH=/nonexistent
done
for build_status in '' 1 65; do
    expect_skipped "unsuccessful archive: $build_status" \
        CI_XCODEBUILD_EXIT_CODE="$build_status" CI_PRIMARY_REPOSITORY_PATH= CI_COMMIT= PATH=/nonexistent
done
for signed_path in '' "$temporary_directory/missing" "$response_file"; do
    expect_skipped "missing signed archive directory: $signed_path" \
        CI_APP_STORE_SIGNED_APP_PATH="$signed_path" CI_PRIMARY_REPOSITORY_PATH= CI_COMMIT= PATH=/nonexistent
done

echo "TestFlight notes generation, PR selection, fallback, and archive guards passed."
