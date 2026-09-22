#!/bin/sh
# Runs every test from the repo root. Needs lua5.1; test_sha.lua also needs lua-bitop.
set -e
cd "$(dirname "$0")/.."
lua5.1 tests/test.lua > /tmp/painledger-test.txt 2>&1 || { grep -v "^ok" /tmp/painledger-test.txt | tail -5; exit 1; }
echo "main harness: $(grep -c '^ok' /tmp/painledger-test.txt) checks, $(tail -1 /tmp/painledger-test.txt)"
lua5.1 tests/test_events.lua | tail -1
if lua5.1 -e 'require("bit")' 2>/dev/null; then lua5.1 tests/test_sha.lua | tail -1; else echo "test_sha.lua skipped: install lua-bitop"; fi
sh tests/run_classes.sh | tail -1
