#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="airspace-codesign-certificate"
notarize=false
notarytool_profile=''
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --notarize) notarize=true; shift;;
        --notarytool-profile) notarytool_profile="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

source ./versions.sh
export SWIFTPM_MACOS_MIN_DEPLOYMENT_TARGET=$MACOS_MIN_DEPLOYMENT_TARGET

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh

build_info_file="$PWD/.build-info.txt"
printf '%s\n%s\n%s\n' "$build_version" "$(git rev-parse HEAD)" "$(git rev-parse --short HEAD)" > "$build_info_file"

rm -rf .release && mkdir .release

# Job control puts each build into its own process group, so that the trap kills the whole process tree
set -m

cli_log=$PWD/.release/build-cli.log
app_log=$PWD/.release/build-app.log

echo "$app_log"
echo "$cli_log"

./script/build-release-cli.sh \
    --build-info-file "$build_info_file" \
    --codesign-identity "$codesign_identity" > "$cli_log" 2>&1 &
build_cli_pid=$!

./script/build-release-app.sh \
    --build-info-file "$build_info_file" \
    --build-version "$build_version" \
    --codesign-identity "$codesign_identity" > "$app_log" 2>&1 &
build_app_pid=$!

trap 'kill -- -$build_cli_pid -$build_app_pid 2> /dev/null' EXIT

wait "$build_cli_pid"
wait "$build_app_pid"
trap - EXIT # Remove EXIT trap
set +m

################
### VALIDATE ###
################

./script/validate-release-binaries.sh

############
### PACK ###
############

mkdir -p ".release/AirSpace-v$build_version/manpage" && cp .man/*.1 ".release/AirSpace-v$build_version/manpage"
cp -r ./legal ".release/AirSpace-v$build_version/legal"
cp -r .shell-completion ".release/AirSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "AirSpace-v$build_version/bin" && cp -r airspace "AirSpace-v$build_version/bin"
    cp -r AirSpace.app "AirSpace-v$build_version"
    ditto -c -k --keepParent "AirSpace-v$build_version" "AirSpace-v$build_version.zip"
cd -

#################
### Notarize ####
#################

if $notarize; then
    if [[ "$codesign_identity" == "-" ]]; then
        echo "--notarize requires a Developer ID identity passed via --codesign-identity" > /dev/stderr
        exit 1
    fi
    notarize_args=(
        --zip ".release/AirSpace-v$build_version.zip"
        --app ".release/AirSpace-v$build_version/AirSpace.app"
    )
    if [[ -n "$notarytool_profile" ]]; then
        notarize_args+=(--keychain-profile "$notarytool_profile")
    fi
    ./script/notarize-release.sh "${notarize_args[@]}"

    # Recreate the zip so that it contains the stapled notarization ticket
    cd .release
        rm -f "AirSpace-v$build_version.zip"
        ditto -c -k --keepParent "AirSpace-v$build_version" "AirSpace-v$build_version.zip"
    cd -
fi

#################
### Brew Cask ###
#################
for cask_name in airspace airspace-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AirSpace-v$build_version.zip" \
        --build-version "$build_version"
done

############
### Done ###
############
echo
echo "$PWD"/.release/*.zip
