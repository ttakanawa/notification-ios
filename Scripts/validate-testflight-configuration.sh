#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
info_plist="$repository_root/NotificationManager/SupportingFiles/Info.plist"
entitlements="$repository_root/NotificationManager/SupportingFiles/NotificationManager.entitlements"
project_file="$repository_root/NotificationManager.xcodeproj/project.pbxproj"
asset_catalog="$repository_root/NotificationManager/Resources/Assets.xcassets"
app_icon_set="$asset_catalog/AppIcon.appiconset"
app_icon="$app_icon_set/AppIcon-1024.png"
alternate_icon_names="AppIcon-Ocean AppIcon-Sunset"
preview_names="AppIconPreview-Default AppIconPreview-Ocean AppIconPreview-Sunset"
privacy_manifest="$repository_root/NotificationManager/Resources/PrivacyInfo.xcprivacy"

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
project_json=$(plutil -convert json -o - "$project_file")

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
assert_equal "2" "$(count_project_setting 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')" "AppIcon build setting count"
assert_equal "2" \
    "$(count_project_setting 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \(')" \
    "alternate AppIcon build setting count"
assert_equal "2" \
    "$(count_project_setting '"AppIcon-Ocean",')" \
    "Ocean build setting entry count"
assert_equal "2" \
    "$(count_project_setting '"AppIcon-Sunset",')" \
    "Sunset build setting entry count"

# The file-system-synchronized app group automatically includes resources. Keep the
# target Info.plist out of that membership: Xcode must process it only through
# INFOPLIST_FILE, while still discovering legitimate resources automatically.
app_target_id=$(printf '%s' "$project_json" | jq -r '
    .objects
    | to_entries
    | map(select(.value.isa == "PBXNativeTarget" and .value.name == "NotificationManager"))
    | if length == 1 then .[0].key else empty end
')
[ -n "$app_target_id" ] || fail "project must contain one NotificationManager target"

info_plist_membership_exception_id=$(printf '%s' "$project_json" | jq -r --arg app_target_id "$app_target_id" '
    .objects
    | to_entries
    | map(select(
        .value.isa == "PBXFileSystemSynchronizedBuildFileExceptionSet"
        and .value.target == $app_target_id
        and .value.membershipExceptions == ["SupportingFiles/Info.plist"]
    ))
    | if length == 1 then .[0].key else empty end
')
[ -n "$info_plist_membership_exception_id" ] || fail "app Info.plist must be excluded from file-system-synchronized resource membership"

printf '%s' "$project_json" | jq -e \
    --arg app_target_id "$app_target_id" \
    --arg info_plist_membership_exception_id "$info_plist_membership_exception_id" '
    .objects as $objects
    | [
        $objects[$app_target_id].fileSystemSynchronizedGroups[]? as $group_id
        | $objects[$group_id]
        | select(
            .isa == "PBXFileSystemSynchronizedRootGroup"
            and .path == "NotificationManager"
            and .exceptions == [$info_plist_membership_exception_id]
        )
    ]
    | length == 1
' >/dev/null || fail "NotificationManager synchronized group must reference the Info.plist membership exception"

printf '%s' "$project_json" | jq -e '
    .objects as $objects
    | [
        $objects
        | to_entries[]
        | select(
            .value.isa == "PBXNativeTarget"
            and .value.productType == "com.apple.product-type.bundle.unit-test"
        )
        | [
            .value.buildPhases[]? as $build_phase_id
            | select($objects[$build_phase_id].isa == "PBXFrameworksBuildPhase")
        ]
        | length == 1
    ]
    | length > 0 and all
' >/dev/null || fail "each hosted unit-test target must contain one Frameworks build phase"

printf '%s' "$project_json" | jq -e '
    .objects as $objects
    | $objects
    | to_entries[]
    | select(
        .value.isa == "PBXNativeTarget"
        and .value.productType == "com.apple.product-type.bundle.unit-test"
    )
    | .value.buildPhases[]? as $build_phase_id
    | $objects[$build_phase_id]
    | select(.isa == "PBXFrameworksBuildPhase")
    | .files[]? as $build_file_id
    | $objects[$build_file_id].productRef? as $product_reference_id
    | $objects[$product_reference_id]
    | select(.isa == "XCSwiftPackageProductDependency")
' >/dev/null && fail "hosted unit-test Frameworks phases must not link Swift package products"

printf '%s' "$project_json" | jq -e '
    .objects as $objects
    | $objects
    | to_entries[]
    | select(
        .value.isa == "PBXNativeTarget"
        and .value.productType == "com.apple.product-type.bundle.unit-test"
    )
    | .value.packageProductDependencies[]? as $product_reference_id
    | $objects[$product_reference_id]
    | select(.isa == "XCSwiftPackageProductDependency")
' >/dev/null && fail "hosted unit-test targets must resolve Swift package products through their app host"

[ -f "$asset_catalog/Contents.json" ] || fail "Assets.xcassets/Contents.json is missing"
[ -f "$app_icon_set/Contents.json" ] || fail "AppIcon.appiconset/Contents.json is missing"
[ -f "$app_icon" ] || fail "AppIcon-1024.png is missing"

app_icon_json=$(plutil -convert json -o - "$app_icon_set/Contents.json")
printf '%s' "$app_icon_json" | jq -e \
    '.images == [{"filename":"AppIcon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}]' >/dev/null \
    || fail "AppIcon Contents.json must contain one standard iOS 1024x1024 image"

icon_metadata=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$app_icon")
printf '%s' "$icon_metadata" | rg 'pixelWidth: 1024' >/dev/null || fail "AppIcon width must be 1024"
printf '%s' "$icon_metadata" | rg 'pixelHeight: 1024' >/dev/null || fail "AppIcon height must be 1024"
printf '%s' "$icon_metadata" | rg 'hasAlpha: no' >/dev/null || fail "AppIcon must not have an alpha channel"

for alternate_name in $alternate_icon_names; do
    alternate_set="$asset_catalog/$alternate_name.appiconset"
    alternate_image="$alternate_set/$alternate_name-1024.png"
    [ -f "$alternate_set/Contents.json" ] \
        || fail "$alternate_name Contents.json is missing"
    [ -f "$alternate_image" ] \
        || fail "$alternate_name 1024 image is missing"

    alternate_json=$(plutil -convert json -o - "$alternate_set/Contents.json")
    printf '%s' "$alternate_json" | jq -e --arg filename "$alternate_name-1024.png" \
        '.images == [{"filename":$filename,"idiom":"universal","platform":"ios","size":"1024x1024"}]' \
        >/dev/null || fail "$alternate_name Contents.json is invalid"

    alternate_metadata=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$alternate_image")
    printf '%s' "$alternate_metadata" | rg 'pixelWidth: 1024' >/dev/null \
        || fail "$alternate_name width must be 1024"
    printf '%s' "$alternate_metadata" | rg 'pixelHeight: 1024' >/dev/null \
        || fail "$alternate_name height must be 1024"
    printf '%s' "$alternate_metadata" | rg 'hasAlpha: no' >/dev/null \
        || fail "$alternate_name must not have an alpha channel"
done

for preview_name in $preview_names; do
    preview_set="$asset_catalog/$preview_name.imageset"
    preview_image="$preview_set/$preview_name.png"
    [ -f "$preview_set/Contents.json" ] \
        || fail "$preview_name Contents.json is missing"
    [ -f "$preview_image" ] \
        || fail "$preview_name image is missing"

    preview_json=$(plutil -convert json -o - "$preview_set/Contents.json")
    printf '%s' "$preview_json" | jq -e --arg filename "$preview_name.png" \
        '.images == [{"filename":$filename,"idiom":"universal","scale":"1x"}]' \
        >/dev/null || fail "$preview_name Contents.json is invalid"

    preview_metadata=$(sips -g pixelWidth -g pixelHeight "$preview_image")
    printf '%s' "$preview_metadata" | rg 'pixelWidth: 256' >/dev/null \
        || fail "$preview_name width must be 256"
    printf '%s' "$preview_metadata" | rg 'pixelHeight: 256' >/dev/null \
        || fail "$preview_name height must be 256"
done

[ -f "$privacy_manifest" ] || fail "PrivacyInfo.xcprivacy is missing"
privacy_json=$(plutil -convert json -o - "$privacy_manifest")
printf '%s' "$privacy_json" | jq -e '.NSPrivacyTracking == false' >/dev/null \
    || fail "privacy manifest must declare tracking false"
printf '%s' "$privacy_json" | jq -e '.NSPrivacyTrackingDomains == []' >/dev/null \
    || fail "privacy manifest must not declare tracking domains"
printf '%s' "$privacy_json" | jq -e '.NSPrivacyCollectedDataTypes == []' >/dev/null \
    || fail "privacy manifest must not declare collected data"
printf '%s' "$privacy_json" | jq -e \
    '.NSPrivacyAccessedAPITypes == [{"NSPrivacyAccessedAPIType":"NSPrivacyAccessedAPICategoryUserDefaults","NSPrivacyAccessedAPITypeReasons":["CA92.1"]}]' >/dev/null \
    || fail "privacy manifest must declare only UserDefaults reason CA92.1"

if rg -n 'registerForRemoteNotifications|didRegisterForRemoteNotifications|didFailToRegisterForRemoteNotifications' \
    "$repository_root/NotificationManager" "$repository_root/Packages" >/dev/null; then
    fail "remote-notification registration code is not allowed"
fi

echo "Punctual distribution identity and capability checks passed."
