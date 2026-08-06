#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
catalog="$repository_root/NotificationManager/Resources/Localizable.xcstrings"
validator="$repository_root/Scripts/validate-localizations.swift"
fixtures="$script_directory/Fixtures/LocalizationSourceCoverage"

swift "$validator" "$catalog" --source-root "$fixtures/valid"

failure_output_file=$(mktemp)
if swift "$validator" "$catalog" --source-root "$fixtures/missing" \
    >"$failure_output_file" 2>&1
then
    echo "Expected the same-line missing localization key fixture to fail." >&2
    exit 1
fi

failure_output=$(cat "$failure_output_file")
case "$failure_output" in
    *"settings.same-line-missing: referenced by app source but missing from the catalog."*) ;;
    *)
        echo "Missing-key diagnostic was not emitted." >&2
        echo "$failure_output" >&2
        exit 1
        ;;
esac

case "$failure_output" in
    *"settings.fixture-control"*)
        echo "Accessibility identifier was incorrectly treated as a localization key." >&2
        echo "$failure_output" >&2
        exit 1
        ;;
esac

echo "Localization source coverage fixtures passed."
