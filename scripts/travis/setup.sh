#!/bin/bash

set -e

case $( uname -s ) in
  Linux)
    DART_SDK_ZIP=dartsdk-linux-x64-release.zip
    ;;
  Darwin)
    DART_SDK_ZIP=dartsdk-macos-x64-release.zip
    ;;
esac

npm install -g traceur
echo ++++++++++++++++++++++++++++++++++++++++

CHANNEL=`echo $JOB | cut -f 2 -d -`
echo Fetch Dart channel: $CHANNEL

echo http://storage.googleapis.com/dart-archive/channels/$CHANNEL/release/latest/sdk/$DART_SDK_ZIP
curl -L http://storage.googleapis.com/dart-archive/channels/$CHANNEL/release/latest/sdk/$DART_SDK_ZIP > $DART_SDK_ZIP
echo Fetched new dart version $(unzip -p $DART_SDK_ZIP dart-sdk/version)
rm -rf dart-sdk
unzip $DART_SDK_ZIP > /dev/null
rm $DART_SDK_ZIP

. ./scripts/env.sh
$DART --version
$PUB install
