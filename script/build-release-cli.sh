#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

build_info_file='' # mandatory
codesign_identity=''
while test $# -gt 0; do
    case $1 in
        --build-info-file) build_info_file="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown arg $1" > /dev/stderr; exit 1;;
    esac
done

if test -z "$build_info_file"; then echo "--build-info-file is mandatory" > /dev/stderr; exit 1; fi

if test -z "$codesign_identity"; then
    if test -f .codesign-identity; then
        codesign_identity="$(<.codesign-identity)"
    else
        codesign_identity="airspace-codesign-certificate"
    fi
fi

export SWIFTPM_WARNINGS_AS_ERRORS=1
swift_build_cli=(build -c release --arch arm64 --arch x86_64 --product airspace)
swift "${swift_build_cli[@]}" \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __aero_build \
    -Xlinker "$build_info_file"
cli_bin_path="$(swift "${swift_build_cli[@]}" --show-bin-path)"

cp -r "$cli_bin_path/airspace" .release/airspace

# Binary reproducibility: strip non-portable rpaths
# https://github.com/swiftlang/swift-package-manager/issues/10760
/usr/bin/xcrun objdump --macho --rpaths --no-leading-headers --arch all .release/airspace |
    grep -vE '^(@|/usr/lib/swift$)' |
    sort -u |
    while IFS= read -r rpath; do
        install_name_tool -delete_rpath "$rpath" .release/airspace
    done

if [[ "$codesign_identity" == "-" ]]; then
    codesign -s "$codesign_identity" .release/airspace
else
    # Developer ID signing for notarization: hardened runtime + secure timestamp
    codesign --force --options runtime --timestamp --sign "$codesign_identity" .release/airspace
fi
