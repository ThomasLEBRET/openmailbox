#!/usr/bin/env bash
# Local disposable mail server for end-to-end IMAP/SMTP testing.
#
#   scripts/greenmail.sh          # download (once) + run in the foreground
#
# Exposes: IMAP 3143, IMAPS 3993, SMTP 3025, REST API http://127.0.0.1:8080/
# Login:  user "test", password "pw" (delivery address test@localhost).
#
# Then, in another shell:  flutter test test/imap_integration_test.dart
set -euo pipefail

VERSION="2.1.3"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAR="$DIR/tools/greenmail-standalone.jar"
URL="https://repo1.maven.org/maven2/com/icegreen/greenmail-standalone/${VERSION}/greenmail-standalone-${VERSION}.jar"

JAVA_BIN="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}/bin/java"
command -v "$JAVA_BIN" >/dev/null 2>&1 || JAVA_BIN="java"

if [ ! -f "$JAR" ]; then
  echo "Downloading GreenMail $VERSION ..."
  mkdir -p "$DIR/tools"
  curl -fsSL -o "$JAR" "$URL"
fi

echo "Starting GreenMail (IMAP 3143 / SMTP 3025 / API 8080). Ctrl-C to stop."
exec "$JAVA_BIN" \
  -Dgreenmail.setup.test.all \
  -Dgreenmail.users=test:pw@localhost \
  -Dgreenmail.auth.disabled \
  -jar "$JAR"
