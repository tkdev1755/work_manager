# /Users/tahakhetib/devProjects/work_manager/run_debug.sh
#!/bin/bash
set -e

# Paths to your workManager installation
CONF_PATH="/Users/tahakhetib/workManager/conf.yml"
DB_PATH="/Users/tahakhetib/workManager/metadata.json"
OUTPUT_DIR="/tmp/wm_debug"

# Clean previous build
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Compile with debug flags
dart run bin/work_manager.dart \
  --dart-define=DEBUG=true \
  --dart-define=confPath="$CONF_PATH" \
  --dart-define=dbPath="$DB_PATH" \
  -o "$OUTPUT_DIR/work_manager" \
  "$@"

# Run it with any arguments passed to the script
"$OUTPUT_DIR/work_manager" 
