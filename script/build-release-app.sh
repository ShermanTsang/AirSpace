#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

build_info_file='' # mandatory
build_version="0.0.0-SNAPSHOT"
codesign_identity="airspace-codesign-certificate"
while test $# -gt 0; do
    case $1 in
        --build-info-file) build_info_file="$2"; shift 2;;
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown arg $1" > /dev/stderr; exit 1;;
    esac
done

if test -z "$build_info_file"; then echo "--build-info-file is mandatory" > /dev/stderr; exit 1; fi

codesign_args=()
if [[ "$codesign_identity" != "-" ]]; then
    # Developer ID signing for notarization: manual signing, hardened runtime, secure timestamp
    team_id="$(sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\))$/\1/p' <<< "$codesign_identity")"
    codesign_args+=(
        CODE_SIGN_STYLE=Manual
        ENABLE_HARDENED_RUNTIME=YES
        OTHER_CODE_SIGN_FLAGS=--timestamp
        PROVISIONING_PROFILE_SPECIFIER=
    )
    if [[ -n "$team_id" ]]; then
        codesign_args+=(DEVELOPMENT_TEAM="$team_id")
    fi
fi

cd ./xcode
    xcode_configuration="Release"
    /usr/bin/xcrun xcodebuild -version
    /usr/bin/xcrun xcodebuild clean build \
        -scheme AirSpace \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build \
        MARKETING_VERSION="$build_version" \
        AEROSPACE_CODE_SIGN_IDENTITY="$codesign_identity" \
        AEROSPACE_BUILD_INFO_LDFLAGS="-sectcreate __TEXT __aero_build $build_info_file" \
        "${codesign_args[@]}"
cd -

cp -r "xcode/.xcode-build/Build/Products/$xcode_configuration/AirSpace.app" .release

if [[ "$codesign_identity" != "-" ]]; then
    # Xcode signs embedded code, but notarization requires hardened runtime and a secure
    # timestamp on every Mach-O file. Re-sign embedded dylibs first, then the app seal.
    while IFS= read -r -d '' dylib; do
        codesign --force --options runtime --timestamp --sign "$codesign_identity" "$dylib"
    done < <(find .release/AirSpace.app/Contents/Frameworks -type f -name '*.dylib' -print0)
    codesign --force --options runtime --timestamp --sign "$codesign_identity" \
        --entitlements resources/AirSpace.entitlements .release/AirSpace.app
fi
