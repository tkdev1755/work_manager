#!/bin/bash
# Runs the MCP server test suite against a fresh, throwaway fixture directory.
#
# mcp_server_test.dart reads conf.yml/metadata.json paths from -DconfPath/
# -DdbPath (compile-time defines), then creates the fixture files there
# itself in setUpAll and deletes them in tearDownAll - this script's only
# job is picking a fresh temp directory and wiring it through those defines.
set -e

FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

dart \
  -DDEBUG=true \
  -DconfPath="$FIXTURE_DIR/conf.yml" \
  -DdbPath="$FIXTURE_DIR/metadata.json" \
  test \
  test/mcp_server_manual.dart
