#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

./generate.sh --ignore-xcodeproj
swift build --build-tests "$@"
bin_path="$(swift build "$@" --show-bin-path)"

rm -rf .debug && mkdir .debug
cp -r "$bin_path/airspace" .debug
cp -r "$bin_path/AirSpaceApp" .debug
cp -r "$bin_path/AirSpacePackage_AppBundle.bundle" .debug

############
### Done ###
############
echo
printf '%s\n' "$PWD"/.debug/*
