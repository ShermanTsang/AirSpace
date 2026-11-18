#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

export SWIFTPM_WARNINGS_AS_ERRORS=1
./build-debug.sh
./swift-test.sh

./.debug/airspace -h > /dev/null
./.debug/airspace --help > /dev/null
./.debug/airspace -v | grep -q "0.0.0-SNAPSHOT SNAPSHOT"
./.debug/airspace --version | grep -q "0.0.0-SNAPSHOT SNAPSHOT"

./lint.sh
./generate.sh
./script/check-uncommitted-files.sh

echo
echo "✅ All tests have passed successfully"
