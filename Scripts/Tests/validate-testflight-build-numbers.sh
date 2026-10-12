#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
temporary_directory=$(mktemp -d)
fixture_root="$temporary_directory/project"
fixture_project="$fixture_root/NotificationManager.xcodeproj/project.pbxproj"
validator="$fixture_root/Scripts/validate-testflight-configuration.sh"
output_file="$temporary_directory/validator-output.txt"

trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

# Exercise the complete distribution validator with real plutil, jq, and assets.
# Mutations only affect this temporary copy, never the working project.
mkdir -p "$fixture_root/Scripts" "$fixture_root/NotificationManager.xcodeproj" \
    "$fixture_root/Packages/NotificationManagerCore"
cp "$repository_root/Scripts/validate-testflight-configuration.sh" "$validator"
for directory in NotificationManager NotificationManagerWidget; do
    cp -R "$repository_root/$directory" "$fixture_root/$directory"
done
cp -R "$repository_root/Packages/NotificationManagerCore/Sources" \
    "$fixture_root/Packages/NotificationManagerCore/Sources"
cp "$repository_root/NotificationManager.xcodeproj/project.pbxproj" "$fixture_project"
cp "$fixture_project" "$temporary_directory/original.pbxproj"
plutil -convert json -o "$temporary_directory/original.json" "$fixture_project"

configuration_ids() {
    target_name=$1
    jq -r --arg target_name "$target_name" '
        .objects as $objects
        | $objects[]
        | select(.isa == "PBXNativeTarget" and .name == $target_name)
        | .buildConfigurationList as $list_id
        | $objects[$list_id].buildConfigurations[]
    ' "$temporary_directory/original.json"
}

app_ids=$(configuration_ids NotificationManager)
widget_ids=$(configuration_ids NotificationManagerWidget)
app_debug_id=$(printf '%s\n' "$app_ids" | head -n 1)
widget_release_id=$(printf '%s\n' "$widget_ids" | tail -n 1)

reset_project() {
    cp "$temporary_directory/original.pbxproj" "$fixture_project"
}

mutate_setting() {
    selected_id=$1
    setting=$2
    replacement=$3
    # OpenStep project objects have stable IDs. Select the configuration object,
    # then change or remove only its requested build setting.
    awk -v selected_id="$selected_id" -v setting="$setting" -v replacement="$replacement" '
        /^[ \t]*[A-F0-9]+ .* = \{/ { current_id = $1 }
        (selected_id == "all" || current_id == selected_id) && $1 == setting && $2 == "=" {
            if (replacement == "missing") next
            sub(/=.*/, "= " replacement ";")
        }
        { print }
    ' "$fixture_project" > "$temporary_directory/mutated.pbxproj"
    mv "$temporary_directory/mutated.pbxproj" "$fixture_project"
}

expect_success() {
    scenario=$1
    if ! sh "$validator" > "$output_file" 2>&1; then
        echo "Distribution validation unexpectedly failed: $scenario" >&2
        cat "$output_file" >&2
        exit 1
    fi
}

expect_failure() {
    scenario=$1
    diagnostic=$2
    if sh "$validator" > "$output_file" 2>&1; then
        echo "Distribution validation unexpectedly passed: $scenario" >&2
        exit 1
    fi
    if ! rg -F "$diagnostic" "$output_file" >/dev/null; then
        echo "Expected distribution diagnostic was not emitted: $scenario" >&2
        cat "$output_file" >&2
        exit 1
    fi
}

build_diagnostic="build numbers must be matching positive integers"
marketing_diagnostic="marketing versions must match"

expect_success "current project"
mutate_setting all CURRENT_PROJECT_VERSION 123
expect_success "incremented app and Widget build numbers"
mutate_setting all MARKETING_VERSION 2.1.3
expect_success "matching updated marketing versions"

for invalid_number in 0 -1 1.5 abc 01; do
    reset_project
    mutate_setting all CURRENT_PROJECT_VERSION "$invalid_number"
    expect_failure "invalid build number $invalid_number" "$build_diagnostic"
done

for configuration_id in $app_ids $widget_ids; do
    reset_project
    mutate_setting "$configuration_id" CURRENT_PROJECT_VERSION missing
    expect_failure "missing build number in $configuration_id" "$build_diagnostic"
    reset_project
    mutate_setting "$configuration_id" CURRENT_PROJECT_VERSION 3
    expect_failure "mismatched build number in $configuration_id" "$build_diagnostic"
    reset_project
    mutate_setting "$configuration_id" MARKETING_VERSION missing
    expect_failure "missing marketing version in $configuration_id" "$marketing_diagnostic"
done

reset_project
mutate_setting "$widget_release_id" MARKETING_VERSION 1.1
expect_failure "Widget marketing version differs from app" "$marketing_diagnostic"
reset_project
mutate_setting "$app_debug_id" MARKETING_VERSION invalid
expect_failure "invalid marketing version" "$marketing_diagnostic"

for configuration_id in "$app_debug_id" "$widget_release_id"; do
    reset_project
    awk -v selected_id="$configuration_id" '
        $1 == selected_id && /, *$/ { next }
        { print }
    ' "$fixture_project" > "$temporary_directory/mutated.pbxproj"
    mv "$temporary_directory/mutated.pbxproj" "$fixture_project"
    # Missing app configurations fail the pre-existing icon check first.
    expect_failure "missing configuration $configuration_id" "TestFlight configuration error:"
done

echo "TestFlight build-number and marketing-version mutation tests passed."
