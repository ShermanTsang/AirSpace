#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh
set +x # Never print notarization credentials

zip_path=''
app_path=''
keychain_profile=''
while test $# -gt 0; do
    case $1 in
        --zip) zip_path="$2"; shift 2;;
        --app) app_path="$2"; shift 2;;
        --keychain-profile) keychain_profile="$2"; shift 2;;
        *) echo "Unknown arg $1" > /dev/stderr; exit 1;;
    esac
done

if test -z "$zip_path"; then echo "--zip is mandatory" > /dev/stderr; exit 1; fi
if test -z "$app_path"; then echo "--app is mandatory" > /dev/stderr; exit 1; fi
if ! test -f "$zip_path"; then echo "$zip_path doesn't exist" > /dev/stderr; exit 1; fi
if ! test -d "$app_path"; then echo "$app_path doesn't exist" > /dev/stderr; exit 1; fi

check-developer-id-signature() {
    local path="$1"
    local details
    if ! details="$(codesign -dv --verbose=4 "$path" 2>&1)"; then
        echo "$path is not signed" > /dev/stderr
        exit 1
    fi
    if ! grep -q '^Authority=Developer ID Application' <<< "$details"; then
        echo "$path is not signed with a Developer ID Application certificate" > /dev/stderr
        exit 1
    fi
    if ! grep -q 'runtime' <<< "$details"; then
        echo "$path does not have the hardened runtime enabled" > /dev/stderr
        exit 1
    fi
}

check-developer-id-signature "$app_path"
cli_path="$(dirname "$app_path")/bin/airspace"
if test -f "$cli_path"; then
    check-developer-id-signature "$cli_path"
fi

if [[ -n "$keychain_profile" ]]; then
    auth=(--keychain-profile "$keychain_profile")
else
    : "${APPLE_ID:?APPLE_ID is required when --keychain-profile is not passed}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required when --keychain-profile is not passed}"
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required when --keychain-profile is not passed}"
    auth=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
fi

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

echo "Submitting $zip_path to the Apple notary service..."
xcrun notarytool submit "$zip_path" \
    --wait --timeout 30m --output-format json \
    "${auth[@]}" > "$result_file"

status="$(plutil -extract status raw -o - "$result_file")"
submission_id="$(plutil -extract id raw -o - "$result_file")"
if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed with status: $status" > /dev/stderr
    xcrun notarytool log "$submission_id" "${auth[@]}" > /dev/stderr || true
    exit 1
fi

echo "Notarization accepted: $submission_id"
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"
echo "Stapled and verified: $app_path"
