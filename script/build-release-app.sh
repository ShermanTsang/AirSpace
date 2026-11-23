#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh
source ./versions.sh

# Keep the Swift package and the Xcode app on the same deployment target. Without this,
# SwiftPM defaults to the host macOS version while the app target uses MACOS_MIN_DEPLOYMENT_TARGET,
# which makes universal builds fail with an incompatible Swift module.
export SWIFTPM_MACOS_MIN_DEPLOYMENT_TARGET="${SWIFTPM_MACOS_MIN_DEPLOYMENT_TARGET:-$MACOS_MIN_DEPLOYMENT_TARGET}"

build_info_file='' # mandatory
build_version="0.0.0-SNAPSHOT"
codesign_identity=''
while test $# -gt 0; do
    case $1 in
        --build-info-file) build_info_file="$2"; shift 2;;
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown arg $1" > /dev/stderr; exit 1;;
    esac
done

if test -z "$build_info_file"; then echo "--build-info-file is mandatory" > /dev/stderr; exit 1; fi
# xcodebuild runs from ./xcode, so the ld -sectcreate path must be absolute
case $build_info_file in
    /*) ;;
    *) build_info_file="$PWD/$build_info_file";;
esac

# A stable signing identity is required for macOS to keep TCC (Accessibility) grants across
# rebuilds. Ad-hoc signing identifies the app by cdhash, which changes on every build.
if test -z "$codesign_identity"; then
    if test -f .codesign-identity; then
        codesign_identity="$(<.codesign-identity)"
    else
        codesign_identity="airspace-codesign-certificate"
    fi
fi

codesign_args=()
if [[ "$codesign_identity" != "-" ]]; then
    # The parenthesized suffix in "Apple Development: Name (XXXXXXXXXX)" is not always the team id;
    # the certificate subject's OU is the team id.
    team_id="$(security find-certificate -c "$codesign_identity" -p 2>/dev/null |
        openssl x509 -noout -subject 2>/dev/null |
        sed -n 's/.*OU=\([A-Z0-9][A-Z0-9]*\).*/\1/p')"
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
