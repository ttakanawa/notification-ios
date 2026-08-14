#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
validator="$repository_root/Scripts/validate-localizations.swift"
fixtures="$script_directory/Fixtures"
temporary_directory=$(mktemp -d)
catalog_root="$temporary_directory/catalogs"
failure_output_file="$temporary_directory/failure-output.txt"
valid_source_root="$temporary_directory/valid-source"

trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

mkdir -p "$catalog_root" "$valid_source_root/NotificationManager"
sed 's/Button("common.retry")/Button(LocalizedStringResource("common.retry", table: "Common"))/' \
    "$fixtures/LocalizationSourceCoverage/valid/NotificationManager/Fixture.swift" \
    > "$valid_source_root/NotificationManager/Fixture.swift"

write_catalog() {
    output_path=$1
    key=$2
    value=$3
    jq -n --arg key "$key" --arg value "$value" '{
      sourceLanguage: "en",
      strings: {
        ($key): {
          comment: ("Fixture text for " + $key + "."),
          extractionState: "manual",
          localizations: {
            en: {stringUnit: {state: "translated", value: $value}},
            ja: {stringUnit: {state: "translated", value: $value}}
          }
        }
      },
      version: "1.0"
    }' > "$output_path"
}

write_tags_catalog() {
    output_path=$1
    jq -n '{
      sourceLanguage: "en",
      strings: {
        "tags.management.count": {
          comment: "Tag count. The %lld placeholder is the number of tags.",
          extractionState: "manual",
          localizations: {
            en: {variations: {plural: {
              one: {stringUnit: {state: "translated", value: "%lld tag"}},
              other: {stringUnit: {state: "translated", value: "%lld tags"}}
            }}},
            ja: {variations: {plural: {
              other: {stringUnit: {state: "translated", value: "%lld件のタグ"}}
            }}}
          }
        }
      },
      version: "1.0"
    }' > "$output_path"
}

write_fixture_catalogs() {
    write_catalog "$catalog_root/Common.xcstrings" common.retry Retry
    write_catalog "$catalog_root/ReminderForm.xcstrings" reminder.form.create.title Create
    write_catalog "$catalog_root/Reminder.xcstrings" reminder.action.save Save
    jq '.strings["reminder.action.back"] = {
      comment: "Navigation action that returns to the previous screen.",
      extractionState: "manual",
      localizations: {
        en: {stringUnit: {state: "translated", value: "Back"}},
        ja: {stringUnit: {state: "translated", value: "戻る"}}
      }
    }' "$catalog_root/Reminder.xcstrings" > "$catalog_root/Reminder.updated.xcstrings"
    mv "$catalog_root/Reminder.updated.xcstrings" "$catalog_root/Reminder.xcstrings"
    write_catalog "$catalog_root/NotificationText.xcstrings" localization.repeat.one-time Once
    write_catalog "$catalog_root/Settings.xcstrings" settings.title Settings
    write_tags_catalog "$catalog_root/Tags.xcstrings"
    write_catalog "$catalog_root/Recovery.xcstrings" recovery.error.data-unavailable Unavailable
}

run_validator() {
    source_root=$1
    swift "$validator" \
        "$catalog_root/Common.xcstrings" \
        "$catalog_root/ReminderForm.xcstrings" \
        "$catalog_root/Reminder.xcstrings" \
        "$catalog_root/NotificationText.xcstrings" \
        "$catalog_root/Settings.xcstrings" \
        "$catalog_root/Tags.xcstrings" \
        "$catalog_root/Recovery.xcstrings" \
        --source-root "$source_root"
}

expect_failure_containing() {
    expected=$1
    shift
    if "$@" >"$failure_output_file" 2>&1
    then
        echo "Expected localization validation to fail: $expected" >&2
        exit 1
    fi

    failure_output=$(cat "$failure_output_file")
    case "$failure_output" in
        *"$expected"*) ;;
        *)
            echo "Expected diagnostic was not emitted: $expected" >&2
            echo "$failure_output" >&2
            exit 1
            ;;
    esac
}

write_fixture_catalogs

success_output=$(run_validator "$valid_source_root")
case "$success_output" in
    *"Validated 8 localization keys across 7 catalogs for English and Japanese."*) ;;
    *)
        echo "Seven-catalog success summary was not emitted." >&2
        echo "$success_output" >&2
        exit 1
        ;;
esac

expect_failure_containing \
    "settings.same-line-missing: referenced by app source but missing from the catalog." \
    run_validator "$fixtures/LocalizationSourceCoverage/missing"

failure_output=$(cat "$failure_output_file")
case "$failure_output" in
    *"settings.fixture-control"*)
        echo "Accessibility identifier was incorrectly treated as a localization key." >&2
        echo "$failure_output" >&2
        exit 1
        ;;
esac

expect_failure_containing \
    "Missing required catalog table Recovery." \
    swift "$validator" \
        "$catalog_root/Common.xcstrings" \
        "$catalog_root/ReminderForm.xcstrings" \
        "$catalog_root/Reminder.xcstrings" \
        "$catalog_root/NotificationText.xcstrings" \
        "$catalog_root/Settings.xcstrings" \
        "$catalog_root/Tags.xcstrings" \
        --source-root "$valid_source_root"

expect_failure_containing \
    "Unknown catalog table Unknown." \
    swift "$validator" \
        "$catalog_root/Common.xcstrings" \
        "$catalog_root/ReminderForm.xcstrings" \
        "$catalog_root/Reminder.xcstrings" \
        "$catalog_root/NotificationText.xcstrings" \
        "$catalog_root/Settings.xcstrings" \
        "$catalog_root/Tags.xcstrings" \
        "$catalog_root/Recovery.xcstrings" \
        "$catalog_root/Unknown.xcstrings" \
        --source-root "$valid_source_root"

expect_failure_containing \
    "Duplicate catalog table Common." \
    swift "$validator" \
        "$catalog_root/Common.xcstrings" \
        "$catalog_root/ReminderForm.xcstrings" \
        "$catalog_root/Reminder.xcstrings" \
        "$catalog_root/NotificationText.xcstrings" \
        "$catalog_root/Settings.xcstrings" \
        "$catalog_root/Tags.xcstrings" \
        "$catalog_root/Recovery.xcstrings" \
        "$catalog_root/Common.xcstrings" \
        --source-root "$valid_source_root"

legacy_source_root="$temporary_directory/legacy-source"
mkdir -p "$legacy_source_root/NotificationManager/Resources"
printf '%s\n' '{}' \
    > "$legacy_source_root/NotificationManager/Resources/Localizable.xcstrings"
expect_failure_containing \
    "Legacy compatibility catalog must not exist at $legacy_source_root/NotificationManager/Resources/Localizable.xcstrings." \
    run_validator "$legacy_source_root"

jq '.strings["settings.wrong-owner"] = .strings["common.retry"]' \
    "$catalog_root/Common.xcstrings" > "$catalog_root/Common.updated.xcstrings"
mv "$catalog_root/Common.updated.xcstrings" "$catalog_root/Common.xcstrings"
expect_failure_containing \
    "settings.wrong-owner: owned by a different catalog, found in Common." \
    run_validator "$valid_source_root"

write_fixture_catalogs
jq --slurpfile common "$catalog_root/Common.xcstrings" \
    '.strings["common.retry"] = $common[0].strings["common.retry"]' \
    "$catalog_root/Settings.xcstrings" > "$catalog_root/Settings.updated.xcstrings"
mv "$catalog_root/Settings.updated.xcstrings" "$catalog_root/Settings.xcstrings"
expect_failure_containing \
    "common.retry: duplicate key in Common and Settings." \
    run_validator "$valid_source_root"

write_fixture_catalogs
expect_failure_containing \
    "settings.title: source declares table Common, expected Settings." \
    run_validator "$fixtures/LocalizationValidation/WrongExplicitTable"

localized_resource_default_root="$temporary_directory/localized-resource-default"
mkdir -p "$localized_resource_default_root/NotificationManager"
sed 's/table: "Common"/defaultValue: "Settings", table: "Common"/' \
    "$fixtures/LocalizationValidation/WrongExplicitTable/NotificationManager/Fixture.swift" \
    > "$localized_resource_default_root/NotificationManager/Fixture.swift"
expect_failure_containing \
    "settings.title: source declares table Common, expected Settings." \
    run_validator "$localized_resource_default_root"

string_localized_default_root="$temporary_directory/string-localized-default"
mkdir -p "$string_localized_default_root/NotificationManager"
printf '%s\n' \
    'import Foundation' \
    'let title = String(localized: "settings.title", defaultValue: "Settings", table: "Common")' \
    > "$string_localized_default_root/NotificationManager/Fixture.swift"
expect_failure_containing \
    "settings.title: source declares table Common, expected Settings." \
    run_validator "$string_localized_default_root"

nested_table_root="$temporary_directory/nested-table"
mkdir -p "$nested_table_root/NotificationManager"
printf '%s\n' \
    'import Foundation' \
    'let title = String(' \
    '    localized: "settings.title",' \
    '    defaultValue: fallback(table: "Settings"),' \
    '    table: "Common"' \
    ')' \
    > "$nested_table_root/NotificationManager/Fixture.swift"
expect_failure_containing \
    "settings.title: source declares table Common, expected Settings." \
    run_validator "$nested_table_root"

expect_failure_containing \
    "reminder.form.capacity-confirmation.message: interpolated semantic key must use an explicit catalog format entry." \
    run_validator "$fixtures/LocalizationValidation/ImplicitInterpolatedKey"

commented_source_root="$temporary_directory/commented-source"
mkdir -p "$commented_source_root/NotificationManager"
printf '%s\n' \
    'import SwiftUI' \
    '// LocalizedStringResource("settings.title", table: "Common")' \
    '// Text("reminder.form.capacity-confirmation.message \(capacity)")' \
    > "$commented_source_root/NotificationManager/Fixture.swift"
if ! run_validator "$commented_source_root" >"$failure_output_file" 2>&1
then
    echo "Commented localization calls were treated as executable source." >&2
    cat "$failure_output_file" >&2
    exit 1
fi

user_data_source_root="$temporary_directory/user-data-source"
mkdir -p "$user_data_source_root/NotificationManager"
printf '%s\n' \
    'import SwiftUI' \
    'let verbatim = Text(verbatim: "settings.user-data")' \
    'let multilineUserData = """' \
    'A quoted token in user data: "settings.multiline-user-data"' \
    '"""' \
    'let explicit = LocalizedStringResource(' \
    '    "settings.title",' \
    '    table: "Settings"' \
    ')' \
    > "$user_data_source_root/NotificationManager/Fixture.swift"
if ! run_validator "$user_data_source_root" >"$failure_output_file" 2>&1
then
    echo "Verbatim or multiline user data was treated as a catalog reference." >&2
    cat "$failure_output_file" >&2
    exit 1
fi

multiline_implicit_root="$temporary_directory/multiline-implicit"
mkdir -p "$multiline_implicit_root/NotificationManager"
printf '%s\n' \
    'import SwiftUI' \
    'let retry = Text(' \
    '    "common.retry"' \
    ')' \
    > "$multiline_implicit_root/NotificationManager/Fixture.swift"
expect_failure_containing \
    "common.retry: implicit Text localization lookup must declare an explicit table." \
    run_validator "$multiline_implicit_root"

implicit_lookup_root="$temporary_directory/implicit-lookups"
mkdir -p "$implicit_lookup_root/NotificationManager"
printf '%s\n' \
    'import SwiftUI' \
    'struct Fixture: View {' \
    '    var body: some View {' \
    '        Text("common.retry")' \
    '        Label("reminder.action.save", systemImage: "checkmark")' \
    '        Button("settings.title") {}' \
    '        Section("tags.management.count") {}' \
    '        Toggle("common.retry", isOn: .constant(true))' \
    '        Picker("common.retry", selection: .constant(0)) {}' \
    '        TextField("common.retry", text: .constant(""))' \
    '        NavigationLink("common.retry", value: 0)' \
    '        Text(verbatim: "Unlocalized user data")' \
    '            .accessibilityLabel("common.retry")' \
    '            .badge("common.retry")' \
    '            .searchable(text: .constant(""), prompt: "common.retry")' \
    '            .searchable(text: .constant(""), prompt: "common.retry \(count)")' \
    '            .navigationTitle("recovery.error.data-unavailable")' \
    '    }' \
    '}' \
    'let localized = String(localized: "localization.repeat.one-time")' \
    'let resource = LocalizedStringResource("common.retry")' \
    '// Text("reminder.not-a-real-comment-key")' \
    'let explicit = LocalizedStringResource("reminder.action.back", table: "Reminder")' \
    'let identifier = AccessibilityIdentifierContainer(identifier: "settings.not-a-real-identifier")' \
    > "$implicit_lookup_root/NotificationManager/Fixture.swift"

if run_validator "$implicit_lookup_root" >"$failure_output_file" 2>&1
then
    echo "Expected implicit semantic localization lookups to fail validation." >&2
    exit 1
fi

failure_output=$(cat "$failure_output_file")
for expected in \
    "common.retry: implicit Text localization lookup must declare an explicit table." \
    "reminder.action.save: implicit Label localization lookup must declare an explicit table." \
    "settings.title: implicit Button localization lookup must declare an explicit table." \
    "tags.management.count: implicit Section localization lookup must declare an explicit table." \
    "common.retry: implicit Toggle localization lookup must declare an explicit table." \
    "common.retry: implicit Picker localization lookup must declare an explicit table." \
    "common.retry: implicit TextField localization lookup must declare an explicit table." \
    "common.retry: implicit NavigationLink localization lookup must declare an explicit table." \
    "common.retry: implicit accessibilityLabel localization lookup must declare an explicit table." \
    "common.retry: implicit badge localization lookup must declare an explicit table." \
    "common.retry: implicit searchable(prompt:) localization lookup must declare an explicit table." \
    "common.retry: interpolated semantic key must use an explicit catalog format entry." \
    "recovery.error.data-unavailable: implicit navigationTitle localization lookup must declare an explicit table." \
    "localization.repeat.one-time: implicit String(localized:) localization lookup must declare an explicit table." \
    "common.retry: implicit LocalizedStringResource localization lookup must declare an explicit table."
do
    case "$failure_output" in
        *"$expected"*) ;;
        *)
            echo "Expected diagnostic was not emitted: $expected" >&2
            echo "$failure_output" >&2
            exit 1
            ;;
    esac
done

case "$failure_output" in
    *"reminder.not-a-real-comment-key"*|*"settings.not-a-real-identifier"*|*"Unlocalized user data"*)
        echo "Ignored source text was incorrectly treated as an implicit localization lookup." >&2
        echo "$failure_output" >&2
        exit 1
        ;;
esac

echo "Localization source coverage fixtures passed."
