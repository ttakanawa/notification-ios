#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
info_plist="$repository_root/NotificationManager/SupportingFiles/Info.plist"
entitlements="$repository_root/NotificationManager/SupportingFiles/NotificationManager.entitlements"
project_file="$repository_root/NotificationManager.xcodeproj/project.pbxproj"

fail() {
    echo "TestFlight configuration error: $1" >&2
    exit 1
}

assert_equal() {
    expected=$1
    actual=$2
    label=$3
    [ "$actual" = "$expected" ] || fail "$label: expected '$expected', found '$actual'"
}

count_project_setting() {
    pattern=$1
    rg -o "$pattern" "$project_file" | wc -l | tr -d ' '
}

info_json=$(plutil -convert json -o - "$info_plist")
entitlements_json=$(plutil -convert json -o - "$entitlements")

assert_equal "Punctual" "$(printf '%s' "$info_json" | jq -r '.CFBundleDisplayName')" "CFBundleDisplayName"
assert_equal '$(MARKETING_VERSION)' "$(printf '%s' "$info_json" | jq -r '.CFBundleShortVersionString')" "CFBundleShortVersionString"
assert_equal '$(CURRENT_PROJECT_VERSION)' "$(printf '%s' "$info_json" | jq -r '.CFBundleVersion')" "CFBundleVersion"

printf '%s' "$info_json" | jq -e '.UIBackgroundModes == ["remote-notification"]' >/dev/null \
    || fail "UIBackgroundModes must contain only remote-notification for CloudKit sync"

assert_equal "development" "$(printf '%s' "$entitlements_json" | jq -r '."aps-environment"')" "source aps-environment"

printf '%s' "$entitlements_json" | jq -e \
    '."com.apple.developer.icloud-container-identifiers" == ["$(CLOUDKIT_CONTAINER_IDENTIFIER)"]' >/dev/null \
    || fail "CloudKit container entitlement must use CLOUDKIT_CONTAINER_IDENTIFIER"
printf '%s' "$entitlements_json" | jq -e \
    '."com.apple.developer.icloud-services" == ["CloudKit"]' >/dev/null \
    || fail "iCloud services entitlement must contain only CloudKit"

assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual;')" "app bundle setting count"
assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual\.tests;')" "unit-test bundle setting count"
assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual\.integrationtests;')" "integration-test bundle setting count"
assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual\.uitests;')" "UI-test bundle setting count"
assert_equal "2" "$(count_project_setting 'CLOUDKIT_CONTAINER_IDENTIFIER = iCloud\.org\.tknw\.punctual;')" "CloudKit build setting count"

if rg -n 'registerForRemoteNotifications|didRegisterForRemoteNotifications|didFailToRegisterForRemoteNotifications' \
    "$repository_root/NotificationManager" "$repository_root/Packages" >/dev/null; then
    fail "remote-notification registration code is not allowed"
fi

echo "Punctual distribution identity and capability checks passed."
