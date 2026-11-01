#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
hook="$repository_root/ci_scripts/ci_post_clone.sh"
temporary_directory=$(mktemp -d)
fixture_root="$temporary_directory/project with spaces"
fixture_bin="$temporary_directory/bin"
output_file="$temporary_directory/output.txt"
log_file="$temporary_directory/tools.log"
expected_file="$temporary_directory/expected.log"

trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

# A deliberately isolated PATH prevents these tests from installing anything or
# consuming the developer's real mise configuration, Homebrew, or make targets.
mkdir -p "$fixture_root" "$fixture_bin"
printf 'fixture\n' > "$fixture_root/Makefile"
printf 'fixture\n' > "$fixture_root/mise.toml"

cat > "$fixture_bin/mise" <<'STUB'
#!/bin/sh
set -eu
{
    printf 'mise cwd=<%s>' "$PWD"
    for argument in "$@"; do printf ' <%s>' "$argument"; done
    printf '\n'
} >> "$MOCK_LOG"
case "$1" in
    trust) exit "${MOCK_TRUST_STATUS:-0}" ;;
    install) exit "${MOCK_INSTALL_STATUS:-0}" ;;
    exec)
        shift
        [ "$1" = -- ] || exit 90
        shift
        "$@"
        ;;
    *) exit 91 ;;
esac
STUB

cat > "$fixture_bin/make" <<'STUB'
#!/bin/sh
set -eu
{
    printf 'make cwd=<%s>' "$PWD"
    for argument in "$@"; do printf ' <%s>' "$argument"; done
    printf '\n'
} >> "$MOCK_LOG"
exit "${MOCK_MAKE_STATUS:-0}"
STUB

cat > "$fixture_bin/brew" <<'STUB'
#!/bin/sh
set -eu
{
    printf 'brew auto-update=<%s>' "${HOMEBREW_NO_AUTO_UPDATE:-}"
    for argument in "$@"; do printf ' <%s>' "$argument"; done
    printf '\n'
} >> "$MOCK_LOG"
[ "${MOCK_BREW_STATUS:-0}" -eq 0 ] || exit "$MOCK_BREW_STATUS"
case "$2" in
    jq) installed_command=jq ;;
    ripgrep) installed_command=rg ;;
    *) exit 92 ;;
esac
printf '#!/bin/sh\nexit 0\n' > "$MOCK_BIN/$installed_command"
/bin/chmod +x "$MOCK_BIN/$installed_command"
STUB

for tool in jq rg; do
    printf '#!/bin/sh\nexit 0\n' > "$fixture_bin/$tool"
done
chmod +x "$fixture_bin"/*

run_hook() {
    : > "$log_file"
    if /usr/bin/env -i \
        PATH="$fixture_bin" \
        MOCK_LOG="$log_file" \
        MOCK_BIN="$fixture_bin" \
        CI_XCODE_CLOUD=TRUE \
        CI_START_CONDITION=manual \
        CI_XCODEBUILD_ACTION=build-for-testing \
        CI_PRIMARY_REPOSITORY_PATH="$fixture_root" \
        "$@" /bin/sh "$hook" > "$output_file" 2>&1; then
        hook_status=0
    else
        hook_status=$?
    fi
}

fail_test() {
    echo "Xcode Cloud hook test failed: $scenario ($1)" >&2
    cat "$output_file" "$log_file" >&2
    exit 1
}

expect_rejection() {
    scenario=$1
    diagnostic=$2
    shift 2
    run_hook "$@"
    [ "$hook_status" -ne 0 ] || fail_test "unexpected success"
    output=$(cat "$output_file")
    case "$output" in
        *"$diagnostic"*) ;;
        *) fail_test "missing diagnostic: $diagnostic" ;;
    esac
    [ ! -s "$log_file" ] || fail_test "tools ran before rejection"
}

expect_checks() {
    scenario=$1
    shift
    run_hook "$@"
    [ "$hook_status" -eq 0 ] || fail_test "unexpected failure"
    cat > "$expected_file" <<EOF
mise cwd=<$fixture_root> <trust> <$fixture_root/mise.toml>
mise cwd=<$fixture_root> <install>
mise cwd=<$fixture_root> <exec> <--> <make> <ci-check>
make cwd=<$fixture_root> <ci-check>
EOF
    diff -u "$expected_file" "$log_file" || fail_test "wrong tool calls or working directory"
}

expect_tool_failure() {
    scenario=$1
    expected_status=$2
    expected_last_call=$3
    shift 3
    run_hook "$@"
    [ "$hook_status" -eq "$expected_status" ] || fail_test "failure status was not propagated"
    last_call=$(tail -n 1 "$log_file")
    [ "$last_call" = "$expected_last_call" ] || fail_test "execution continued after tool failure"
}

expect_rejection "missing Xcode Cloud marker" "run local checks" CI_XCODE_CLOUD=
expect_rejection "invalid Xcode Cloud marker" "run local checks" CI_XCODE_CLOUD=true
expect_rejection "missing primary repository" "CI_PRIMARY_REPOSITORY_PATH is missing" CI_PRIMARY_REPOSITORY_PATH=
expect_rejection "invalid primary repository" "must contain Makefile and mise.toml" CI_PRIMARY_REPOSITORY_PATH="$temporary_directory"

for action in archive build-for-testing test-without-building; do
    for start_condition in '' unknown push pr_open pr_update schedule tag; do
        expect_rejection "nonmanual distribution: $action / $start_condition" "must be started manually" \
            CI_START_CONDITION="$start_condition" CI_XCODEBUILD_ACTION="$action"
    done
done

for start_condition in manual manual_rebuild; do
    for action in archive build-for-testing; do
        expect_checks "manual distribution in repository with spaces: $action / $start_condition" \
            CI_START_CONDITION="$start_condition" CI_XCODEBUILD_ACTION="$action"
    done
done

# Test runners can lack a checkout and build tools, but cannot bypass policy.
for start_condition in manual manual_rebuild; do
    scenario="test runner skips repository and tools: $start_condition"
    run_hook CI_START_CONDITION="$start_condition" \
        CI_XCODEBUILD_ACTION=test-without-building CI_PRIMARY_REPOSITORY_PATH= PATH=/nonexistent
    [ "$hook_status" -eq 0 ] || fail_test "unexpected failure"
    [ ! -s "$log_file" ] || fail_test "test runner invoked tools"
done
expect_rejection "test runner still requires Cloud" "run local checks" \
    CI_XCODEBUILD_ACTION=test-without-building CI_XCODE_CLOUD=

expect_tool_failure "mise trust failure" 31 "mise cwd=<$fixture_root> <trust> <$fixture_root/mise.toml>" MOCK_TRUST_STATUS=31
expect_tool_failure "mise install failure" 32 "mise cwd=<$fixture_root> <install>" MOCK_INSTALL_STATUS=32
expect_tool_failure "make failure" 33 "make cwd=<$fixture_root> <ci-check>" MOCK_MAKE_STATUS=33

rm "$fixture_bin/jq"
expect_tool_failure "Homebrew failure" 34 "brew auto-update=<1> <install> <jq>" MOCK_BREW_STATUS=34

# Missing dependencies must use the correct Homebrew package, then continue.
rm "$fixture_bin/rg"
scenario="install missing jq and ripgrep"
run_hook
[ "$hook_status" -eq 0 ] || fail_test "unexpected failure"
cat > "$expected_file" <<EOF
brew auto-update=<1> <install> <jq>
brew auto-update=<1> <install> <ripgrep>
mise cwd=<$fixture_root> <trust> <$fixture_root/mise.toml>
mise cwd=<$fixture_root> <install>
mise cwd=<$fixture_root> <exec> <--> <make> <ci-check>
make cwd=<$fixture_root> <ci-check>
EOF
diff -u "$expected_file" "$log_file" || fail_test "wrong dependency installation or tool calls"

echo "Xcode Cloud hook policy, tool isolation, and failure propagation tests passed."
