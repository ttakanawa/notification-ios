#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
info_plist="$repository_root/NotificationManager/SupportingFiles/Info.plist"
entitlements="$repository_root/NotificationManager/SupportingFiles/NotificationManager.entitlements"
widget_info_plist="$repository_root/NotificationManagerWidget/SupportingFiles/Info.plist"
widget_entitlements="$repository_root/NotificationManagerWidget/SupportingFiles/NotificationManagerWidget.entitlements"
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
widget_info_json=$(plutil -convert json -o - "$widget_info_plist")
widget_entitlements_json=$(plutil -convert json -o - "$widget_entitlements")
project_json=$(plutil -convert json -o - "$project_file")

assert_equal "Punctual" "$(printf '%s' "$info_json" | jq -r '.CFBundleDisplayName')" "CFBundleDisplayName"
assert_equal '$(MARKETING_VERSION)' "$(printf '%s' "$info_json" | jq -r '.CFBundleShortVersionString')" "CFBundleShortVersionString"
assert_equal '$(CURRENT_PROJECT_VERSION)' "$(printf '%s' "$info_json" | jq -r '.CFBundleVersion')" "CFBundleVersion"
assert_equal '$(MARKETING_VERSION)' "$(printf '%s' "$widget_info_json" | jq -r '.CFBundleShortVersionString')" "Widget CFBundleShortVersionString"
assert_equal '$(CURRENT_PROJECT_VERSION)' "$(printf '%s' "$widget_info_json" | jq -r '.CFBundleVersion')" "Widget CFBundleVersion"

printf '%s' "$info_json" | jq -e '.UIBackgroundModes == ["remote-notification"]' >/dev/null \
    || fail "UIBackgroundModes must contain only remote-notification for CloudKit sync"
printf '%s' "$info_json" | jq -e '
    .CFBundleURLTypes == [{
        "CFBundleTypeRole": "Editor",
        "CFBundleURLName": "org.tknw.punctual.reminders",
        "CFBundleURLSchemes": ["punctual"]
    }]
' >/dev/null || fail "app must declare only the exact punctual reminder URL type"

assert_equal "development" "$(printf '%s' "$entitlements_json" | jq -r '."aps-environment"')" "source aps-environment"

printf '%s' "$entitlements_json" | jq -e \
    '."com.apple.developer.icloud-container-identifiers" == ["$(CLOUDKIT_CONTAINER_IDENTIFIER)"]' >/dev/null \
    || fail "CloudKit container entitlement must use CLOUDKIT_CONTAINER_IDENTIFIER"
printf '%s' "$entitlements_json" | jq -e \
    '."com.apple.developer.icloud-services" == ["CloudKit"]' >/dev/null \
    || fail "iCloud services entitlement must contain only CloudKit"
printf '%s' "$entitlements_json" | jq -e \
    '."com.apple.security.application-groups" == ["group.org.tknw.punctual"]' >/dev/null \
    || fail "app App Group entitlement must contain only group.org.tknw.punctual"
printf '%s' "$entitlements_json" | jq -e '
    (keys | sort) == [
        "aps-environment",
        "com.apple.developer.icloud-container-identifiers",
        "com.apple.developer.icloud-services",
        "com.apple.security.application-groups"
    ]
' >/dev/null || fail "app entitlements must preserve APS and CloudKit plus the App Group"

printf '%s' "$widget_entitlements_json" | jq -e '
    . == {
        "com.apple.security.application-groups": ["group.org.tknw.punctual"]
    }
' >/dev/null || fail "Widget entitlements must contain only group.org.tknw.punctual"
printf '%s' "$widget_info_json" | jq -e '
    .NSExtension == {
        "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
    }
    and (.NSExtension | has("NSExtensionPrincipalClass") | not)
' >/dev/null || fail "Widget Info.plist must declare only the WidgetKit extension point"

assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual;')" "app bundle setting count"
assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual\.tests;')" "unit-test bundle setting count"
assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual\.integrationtests;')" "integration-test bundle setting count"
assert_equal "2" "$(count_project_setting 'PRODUCT_BUNDLE_IDENTIFIER = org\.tknw\.punctual\.uitests;')" "UI-test bundle setting count"
assert_equal "2" "$(count_project_setting 'CLOUDKIT_CONTAINER_IDENTIFIER = iCloud\.org\.tknw\.punctual;')" "CloudKit build setting count"
assert_equal "2" "$(count_project_setting 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')" "AppIcon build setting count"

app_target_count=$(printf '%s' "$project_json" | jq -r '
    . as $project
    | $project.objects as $objects
    | [
        $objects[$project.rootObject].targets[]?
        | select($objects[.].productType == "com.apple.product-type.application")
    ]
    | length
')
assert_equal "1" "$app_target_count" "application target count"

widget_target_count=$(printf '%s' "$project_json" | jq -r '
    . as $project
    | $project.objects as $objects
    | [
        $objects[$project.rootObject].targets[]?
        | select($objects[.].productType == "com.apple.product-type.app-extension")
    ]
    | length
')
assert_equal "1" "$widget_target_count" "app-extension target count"

app_target_id=$(printf '%s' "$project_json" | jq -r '
    . as $project
    | $project.objects as $objects
    | [
        $objects[$project.rootObject].targets[]?
        | select(
            $objects[.].productType == "com.apple.product-type.application"
            and $objects[.].name == "NotificationManager"
        )
    ]
    | if length == 1 then .[0] else empty end
')
[ -n "$app_target_id" ] || fail "project must contain one NotificationManager app target"

printf '%s' "$project_json" | jq -e \
    --arg app_target_id "$app_target_id" \
    --arg expected_alternate_icon_names "$alternate_icon_names" '
    .objects as $objects
    | $objects[$app_target_id].buildConfigurationList as $configuration_list_id
    | $objects[$configuration_list_id].buildConfigurations as $configuration_ids
    | ($configuration_ids | length) == 2
    and all(
        $configuration_ids[];
        (
            $objects[.].buildSettings.ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES
            | if type == "string" then split(" ") elif type == "array" then . else [] end
        ) == ($expected_alternate_icon_names | split(" "))
    )
' >/dev/null || fail "app Debug and Release alternate AppIcon build settings must be exact"

widget_target_id=$(printf '%s' "$project_json" | jq -r '
    . as $project
    | $project.objects as $objects
    | [
        $objects[$project.rootObject].targets[]?
        | select(
            $objects[.].productType == "com.apple.product-type.app-extension"
            and $objects[.].name == "NotificationManagerWidget"
        )
    ]
    | if length == 1 then .[0] else empty end
')
[ -n "$widget_target_id" ] || fail "project must contain one NotificationManagerWidget target"

printf '%s' "$project_json" | jq -e \
    --arg app_target_id "$app_target_id" \
    --arg widget_target_id "$widget_target_id" '
    . as $project
    | $project.objects as $objects
    | $objects[$project.rootObject].attributes.TargetAttributes as $attributes
    | $attributes[$app_target_id].SystemCapabilities == {
        "com.apple.ApplicationGroups.iOS": {"enabled": "1"},
        "com.apple.BackgroundModes": {"enabled": "1"},
        "com.apple.CloudKit": {"enabled": "1"},
        "com.apple.Push": {"enabled": "1"}
    }
    and $attributes[$widget_target_id].SystemCapabilities == {
        "com.apple.ApplicationGroups.iOS": {"enabled": "1"}
    }
' >/dev/null || fail "target capability metadata must preserve app services and Widget App Groups"

printf '%s' "$project_json" | jq -e \
    --arg app_target_id "$app_target_id" \
    --arg widget_target_id "$widget_target_id" '
    .objects as $objects
    | [$app_target_id, $widget_target_id] as $target_ids
    | all(
        $target_ids[];
        $objects[.].buildConfigurationList as $configuration_list_id
        | $objects[$configuration_list_id].buildConfigurations as $configuration_ids
        | ($configuration_ids | type) == "array"
        and ($configuration_ids | length) == 2
        and ([$configuration_ids[]? | $objects[.].name] | sort) == ["Debug", "Release"]
    )
    and (
        [
            $target_ids[]
            | $objects[.].buildConfigurationList as $configuration_list_id
            | $objects[$configuration_list_id].buildConfigurations[]?
            | $objects[.].buildSettings.CURRENT_PROJECT_VERSION
        ] as $versions
        | ($versions | length) == 4
        and all($versions[]; if type == "string" then test("^[1-9][0-9]*$") else false end)
        and ($versions | unique | length) == 1
    )
' >/dev/null || fail "app and Widget Debug and Release build numbers must be matching positive integers"

printf '%s' "$project_json" | jq -e \
    --arg app_target_id "$app_target_id" \
    --arg widget_target_id "$widget_target_id" '
    .objects as $objects
    | [
        [$app_target_id, $widget_target_id][]
        | $objects[.].buildConfigurationList as $configuration_list_id
        | $objects[$configuration_list_id].buildConfigurations[]
        | $objects[.].buildSettings.MARKETING_VERSION
    ] as $versions
    | all($versions[]; if type == "string" then test("^[0-9]+(\\.[0-9]+){0,2}$") else false end)
    and ($versions | unique | length) == 1
' >/dev/null || fail "app and Widget Debug and Release marketing versions must match and use one to three numeric components"

printf '%s' "$project_json" | jq -e --arg widget_target_id "$widget_target_id" '
    .objects as $objects
    | $objects[$widget_target_id].buildConfigurationList as $configuration_list_id
    | $objects[$configuration_list_id].buildConfigurations as $configuration_ids
    | ($configuration_ids | length) == 2
    and ([$configuration_ids[] | $objects[.].name] | sort) == ["Debug", "Release"]
    and all(
        $configuration_ids[];
        $objects[.].buildSettings.APPLICATION_EXTENSION_API_ONLY == "YES"
        and $objects[.].buildSettings.SKIP_INSTALL == "YES"
        and $objects[.].buildSettings.IPHONEOS_DEPLOYMENT_TARGET == "18.0"
        and $objects[.].buildSettings.SUPPORTED_PLATFORMS == "iphoneos iphonesimulator"
        and $objects[.].buildSettings.SWIFT_VERSION == "6.0"
        and $objects[.].buildSettings.TARGETED_DEVICE_FAMILY == "1,2"
        and $objects[.].buildSettings.CODE_SIGN_ENTITLEMENTS
            == "NotificationManagerWidget/SupportingFiles/NotificationManagerWidget.entitlements"
        and $objects[.].buildSettings.INFOPLIST_FILE
            == "NotificationManagerWidget/SupportingFiles/Info.plist"
        and $objects[.].buildSettings.GENERATE_INFOPLIST_FILE == "NO"
        and $objects[.].buildSettings.CODE_SIGN_STYLE == "Automatic"
        and $objects[.].buildSettings.PRODUCT_BUNDLE_IDENTIFIER
            == "org.tknw.punctual.widget"
    )
' >/dev/null || fail "Widget Debug and Release build settings are incomplete"

printf '%s' "$project_json" | jq -e '
    [
        .objects[]
        | select(
            .isa == "XCBuildConfiguration"
            and .buildSettings.PRODUCT_BUNDLE_IDENTIFIER == "org.tknw.punctual.widget"
        )
    ]
    | length == 2
' >/dev/null || fail "Widget bundle identifier must appear in exactly two target configurations"

widget_target_edge_count=$(printf '%s' "$project_json" | jq -r \
    --arg app_target_id "$app_target_id" \
    --arg widget_target_id "$widget_target_id" '
    .objects as $objects
    | [
        $objects[$app_target_id].dependencies[]? as $dependency_id
        | $objects[$dependency_id] as $dependency
        | $objects[$dependency.targetProxy] as $proxy
        | select(
            $dependency.target == $widget_target_id
            or $proxy.remoteGlobalIDString == $widget_target_id
        )
    ]
    | length
')
assert_equal "1" "$widget_target_edge_count" "app-to-Widget target dependency edge count"

widget_target_dependency_id=$(printf '%s' "$project_json" | jq -r \
    --arg app_target_id "$app_target_id" \
    --arg widget_target_id "$widget_target_id" '
    .objects as $objects
    | [
        $objects[$app_target_id].dependencies[]? as $dependency_id
        | $objects[$dependency_id] as $dependency
        | $objects[$dependency.targetProxy] as $proxy
        | select(
            $dependency.target == $widget_target_id
            or $proxy.remoteGlobalIDString == $widget_target_id
        )
        | $dependency_id
    ]
    | .[0]
')

printf '%s' "$project_json" | jq -e \
    --arg dependency_id "$widget_target_dependency_id" \
    --arg widget_target_id "$widget_target_id" '
    . as $project
    | $project.objects as $objects
    | $objects[$dependency_id] as $dependency
    | $objects[$dependency.targetProxy] as $proxy
    | $dependency.isa == "PBXTargetDependency"
    and $dependency.target == $widget_target_id
    and $proxy.isa == "PBXContainerItemProxy"
    and $proxy.containerPortal == $project.rootObject
    and $proxy.remoteGlobalIDString == $widget_target_id
    and $proxy.remoteInfo == "NotificationManagerWidget"
    and $proxy.proxyType == "1"
' >/dev/null || fail "app must have one matching target dependency and container proxy for Widget"

destination_13_phase_count=$(printf '%s' "$project_json" | jq -r \
    --arg app_target_id "$app_target_id" '
    .objects as $objects
    | [
        $objects[$app_target_id].buildPhases[]? as $phase_id
        | $objects[$phase_id] as $phase
        | select(
            $phase.isa == "PBXCopyFilesBuildPhase"
            and $phase.dstSubfolderSpec == "13"
        )
        | $phase_id
    ]
    | length
')
assert_equal "1" "$destination_13_phase_count" "destination-13 copy phase count"

destination_13_phase_id=$(printf '%s' "$project_json" | jq -r \
    --arg app_target_id "$app_target_id" '
    .objects as $objects
    | [
        $objects[$app_target_id].buildPhases[]? as $phase_id
        | select(
            $objects[$phase_id].isa == "PBXCopyFilesBuildPhase"
            and $objects[$phase_id].dstSubfolderSpec == "13"
        )
        | $phase_id
    ]
    | .[0]
')

printf '%s' "$project_json" | jq -e \
    --arg phase_id "$destination_13_phase_id" \
    --arg widget_target_id "$widget_target_id" '
    .objects as $objects
    | $objects[$widget_target_id].productReference as $widget_product_id
    | $objects[$phase_id] as $phase
    | $objects[$phase.files[0]] as $build_file
    | $phase.isa == "PBXCopyFilesBuildPhase"
    and $phase.name == "Embed App Extensions"
    and $phase.dstSubfolderSpec == "13"
    and ($phase.files | length) == 1
    and $build_file.isa == "PBXBuildFile"
    and $build_file.fileRef == $widget_product_id
    and $build_file.settings.ATTRIBUTES == ["RemoveHeadersOnCopy"]
' >/dev/null || fail "Embed App Extensions must contain only the Widget with RemoveHeadersOnCopy"

local_package_reference_count=$(printf '%s' "$project_json" | jq -r '
    . as $project
    | $project.objects as $objects
    | [
        $objects[$project.rootObject].packageReferences[]?
        | select($objects[.].isa == "XCLocalSwiftPackageReference")
    ]
    | length
')
assert_equal "1" "$local_package_reference_count" "root local package reference count"

notification_manager_core_package_id=$(printf '%s' "$project_json" | jq -r '
    . as $project
    | $project.objects as $objects
    | [
        $objects[$project.rootObject].packageReferences[]?
        | select($objects[.].isa == "XCLocalSwiftPackageReference")
    ]
    | .[0]
')
printf '%s' "$project_json" | jq -e \
    --arg package_id "$notification_manager_core_package_id" '
    .objects[$package_id].isa == "XCLocalSwiftPackageReference"
    and .objects[$package_id].relativePath == "Packages/NotificationManagerCore"
' >/dev/null || fail "root local package reference must use Packages/NotificationManagerCore"

app_widget_support_dependency_count=$(printf '%s' "$project_json" | jq -r \
    --arg target_id "$app_target_id" '
    .objects as $objects
    | [
        $objects[$target_id].packageProductDependencies[]?
        | select($objects[.].productName == "NotificationManagerWidgetSupport")
    ]
    | length
')
assert_equal \
    "1" \
    "$app_widget_support_dependency_count" \
    "app NotificationManagerWidgetSupport dependency count"

app_widget_support_dependency_id=$(printf '%s' "$project_json" | jq -r \
    --arg target_id "$app_target_id" '
    .objects as $objects
    | [
        $objects[$target_id].packageProductDependencies[]?
        | select($objects[.].productName == "NotificationManagerWidgetSupport")
    ]
    | .[0]
')

widget_support_dependency_count=$(printf '%s' "$project_json" | jq -r \
    --arg target_id "$widget_target_id" '
    .objects as $objects
    | [
        $objects[$target_id].packageProductDependencies[]?
        | select($objects[.].productName == "NotificationManagerWidgetSupport")
    ]
    | length
')
assert_equal \
    "1" \
    "$widget_support_dependency_count" \
    "Widget NotificationManagerWidgetSupport dependency count"

widget_support_dependency_id=$(printf '%s' "$project_json" | jq -r \
    --arg target_id "$widget_target_id" '
    .objects as $objects
    | [
        $objects[$target_id].packageProductDependencies[]?
        | select($objects[.].productName == "NotificationManagerWidgetSupport")
    ]
    | .[0]
')
[ "$app_widget_support_dependency_id" != "$widget_support_dependency_id" ] \
    || fail "app and Widget must use separate Widget-support dependency objects"

printf '%s' "$project_json" | jq -e \
    --arg app_dependency_id "$app_widget_support_dependency_id" \
    --arg widget_dependency_id "$widget_support_dependency_id" \
    --arg package_id "$notification_manager_core_package_id" '
    .objects as $objects
    | $objects[$app_dependency_id].isa == "XCSwiftPackageProductDependency"
    and $objects[$app_dependency_id].productName == "NotificationManagerWidgetSupport"
    and $objects[$app_dependency_id].package == $package_id
    and $objects[$widget_dependency_id].isa == "XCSwiftPackageProductDependency"
    and $objects[$widget_dependency_id].productName == "NotificationManagerWidgetSupport"
    and $objects[$widget_dependency_id].package == $package_id
' >/dev/null || fail "app and Widget support dependencies must reference the root local package"

printf '%s' "$project_json" | jq -e \
    --arg target_id "$app_target_id" \
    --arg dependency_id "$app_widget_support_dependency_id" '
    .objects as $objects
    | [
        $objects[$target_id].buildPhases[]? as $phase_id
        | select($objects[$phase_id].isa == "PBXFrameworksBuildPhase")
        | $objects[$phase_id].files[]? as $build_file_id
        | select(
            $objects[$build_file_id].isa == "PBXBuildFile"
            and $objects[$build_file_id].productRef == $dependency_id
        )
    ]
    | length == 1
' >/dev/null || fail "app Frameworks phase must link its Widget-support dependency once"

printf '%s' "$project_json" | jq -e \
    --arg target_id "$widget_target_id" \
    --arg dependency_id "$widget_support_dependency_id" '
    .objects as $objects
    | [
        $objects[$target_id].buildPhases[]? as $phase_id
        | select($objects[$phase_id].isa == "PBXFrameworksBuildPhase")
        | $objects[$phase_id].files[]? as $build_file_id
        | select(
            $objects[$build_file_id].isa == "PBXBuildFile"
            and $objects[$build_file_id].productRef == $dependency_id
        )
    ]
    | length == 1
' >/dev/null || fail "Widget Frameworks phase must link its Widget-support dependency once"

# The file-system-synchronized app group automatically includes resources. Keep the
# target Info.plist out of that membership: Xcode must process it only through
# INFOPLIST_FILE, while still discovering legitimate resources automatically.

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

widget_info_plist_membership_exception_count=$(printf '%s' "$project_json" | jq -r \
    --arg widget_target_id "$widget_target_id" '
    [
        .objects
        | to_entries[]
        | select(
            .value.isa == "PBXFileSystemSynchronizedBuildFileExceptionSet"
            and .value.target == $widget_target_id
        )
    ]
    | length
')
assert_equal \
    "1" \
    "$widget_info_plist_membership_exception_count" \
    "Widget synchronized membership exception count"

widget_info_plist_membership_exception_id=$(printf '%s' "$project_json" | jq -r \
    --arg widget_target_id "$widget_target_id" '
    [
        .objects
        | to_entries[]
        | select(
            .value.isa == "PBXFileSystemSynchronizedBuildFileExceptionSet"
            and .value.target == $widget_target_id
        )
    ]
    | .[0].key
')
printf '%s' "$project_json" | jq -e \
    --arg widget_target_id "$widget_target_id" \
    --arg exception_id "$widget_info_plist_membership_exception_id" '
    .objects as $objects
    | $objects[$exception_id].isa == "PBXFileSystemSynchronizedBuildFileExceptionSet"
    and $objects[$exception_id].target == $widget_target_id
    and $objects[$exception_id].membershipExceptions == ["SupportingFiles/Info.plist"]
' >/dev/null || fail "Widget synchronized exception must exclude only SupportingFiles/Info.plist"

printf '%s' "$project_json" | jq -e \
    --arg widget_target_id "$widget_target_id" \
    --arg exception_id "$widget_info_plist_membership_exception_id" '
    .objects as $objects
    | $objects[$widget_target_id].fileSystemSynchronizedGroups as $group_ids
    | ($group_ids | length) == 1
    and $objects[$group_ids[0]].isa == "PBXFileSystemSynchronizedRootGroup"
    and $objects[$group_ids[0]].path == "NotificationManagerWidget"
    and $objects[$group_ids[0]].exceptions == [$exception_id]
' >/dev/null || fail "Widget synchronized root group must reference only its Info.plist exception"

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
