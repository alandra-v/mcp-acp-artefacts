#!/usr/bin/env bash
# Creates the test sandbox used by the adversarial server e2e tests.
# Run once before testing. Safe to re-run (overwrites existing files).

set -euo pipefail

SANDBOX="/tmp/test-sandbox"

mkdir -p "$SANDBOX/subdir"
echo "hello world"  > "$SANDBOX/test.txt"
echo "secret data"  > "$SANDBOX/secret.txt"
echo "nested file"  > "$SANDBOX/subdir/nested.txt"
ln -sf /etc/hosts "$SANDBOX/escape"

echo "Sandbox created at $SANDBOX"
ls -R "$SANDBOX"
