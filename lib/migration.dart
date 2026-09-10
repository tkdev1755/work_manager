import 'dart:io';
import 'package:yaml/yaml.dart';

/// Current schema version of the conf.yml format.
const int currentConfVersion = 1;

/// ---------------------------------------------------------------------------
/// Migration system for conf.yml schema upgrades.
///
/// The migration module is intentionally separated from the main business
/// logic so that future schema changes can be added without touching the
/// core create / open / export flow.
/// ---------------------------------------------------------------------------

/// Represents a single migration step: old-version -> new-version.
typedef MigrationStep = Map<String, dynamic> Function(YamlMap oldConfig);

/// All registered migration steps, keyed by the **source** version.
final Map<int, MigrationStep> _migrationSteps = {
  0: _migrateV0toV1,
};

// ---------------------------------------------------------------------------
// Migration v0 -> v1
// ---------------------------------------------------------------------------

/// Migrates a v0 conf.yml (flat `template_files` at top level) to v1:
///   - Adds `version: 1`
///   - Wraps `template_files` under `default_preset.template_files`
///   - Adds empty `presets: {}`
///   - Keeps `paths` at top level
Map<String, dynamic> _migrateV0toV1(YamlMap oldConfig) {
  final dynamic templateFiles = oldConfig.containsKey('template_files')
      ? oldConfig['template_files']
      : <String, dynamic>{};

  final dynamic paths = oldConfig.containsKey('paths')
      ? oldConfig['paths']
      : <String, dynamic>{};

  // Convert to plain Maps (handles nested YamlMap objects from loadYaml).
  final Map<String, dynamic> templateFilesPlain = _toPlainMap(templateFiles);
  final Map<String, dynamic> pathsPlain = _toPlainMap(paths);

  // Build the migrated config as a plain Map.
  final Map<String, dynamic> result = <String, dynamic>{
    'version': currentConfVersion,
    'default_preset': <String, dynamic>{
      'template_files': templateFilesPlain,
    },
    'presets': <String, dynamic>{},
    'paths': pathsPlain,
  };

  // Copy any other top-level keys that might exist (future-proofing).
  for (final entry in oldConfig.entries) {
    if (entry.key != 'template_files' && entry.key != 'paths') {
      result[entry.key.toString()] = _toPlainValue(entry.value);
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Attempts to parse a conf.yml file.
///
/// If the file does not exist, returns an empty YamlMap (caller should
/// create it).  If the file exists but has an unsupported version, throws
/// a [StateError] with a message directing the user to run the `migrate`
/// command.
///
/// Takes the file path as a String so the migration module remains
/// independent of the global [confFilePath] variable.
YamlMap parseConfFile(String filePath) {
  File confFile = File(filePath);
  if (!confFile.existsSync()) {
    return YamlMap();
  }

  late YamlMap rawConfig;
  try {
    rawConfig = loadYaml(confFile.readAsStringSync());
  } catch (e) {
    throw Exception(
        "Unable to parse the YAML file at $filePath. "
        "Check syntax or run 'wmanager migrate' to upgrade.");
  }

  // --- Detect old format (no `version` key) ---
  if (!rawConfig.containsKey('version')) {
    print("Your conf.yml is in an old format. Migrating to the latest schema...");
    final Map<String, dynamic> migrated = _migrateV0toV1(rawConfig);

    try {
      confFile.writeAsStringSync(_serializeYamlMap(migrated));
      print("Migration successful. Your conf.yml has been updated to version $currentConfVersion.");
    } catch (e) {
      throw Exception(
          "Migration succeeded in memory, but failed to write back to $filePath. "
          "Please check permissions.");
    }
    // Re-parse the migrated file to return a valid YamlMap.
    return loadYaml(confFile.readAsStringSync());
  }

  // --- Versioned format ---
  final int version = rawConfig['version'] as int;
  if (version >= currentConfVersion) {
    // Already at the latest version, no migration needed.
    return rawConfig;
  }
  if (!_migrationSteps.containsKey(version)) {
    throw StateError(
        "Unsupported conf.yml version: $version. "
        "Run 'wmanager migrate' to upgrade to version $currentConfVersion.");
  }

  return rawConfig;
}

/// Runs the migration from the current conf.yml version to the latest.
///
/// Backs up the existing conf.yml (if any) before overwriting it.
/// Idempotent: running it multiple times produces the same result.
void runMigration(String filePath) {
  File confFile = File(filePath);
  if (!confFile.existsSync()) {
    print("No conf.yml found at $filePath. Nothing to migrate.");
    return;
  }

  String existingContent;
  try {
    existingContent = confFile.readAsStringSync();
  } catch (e) {
    throw Exception("Unable to read $filePath for migration.");
  }

  YamlMap currentConfig;
  try {
    currentConfig = loadYaml(existingContent);
  } catch (e) {
    throw Exception(
        "Unable to parse the YAML file at $filePath. "
        "Check syntax or run 'wmanager migrate' to upgrade.");
  }

  // Check if already at the latest version.
  if (currentConfig.containsKey('version')) {
    final int version = currentConfig['version'] as int;
    if (version >= currentConfVersion) {
      print("conf.yml is already at the latest version ($currentConfVersion). Nothing to migrate.");
      return;
    }
  }

  // Back up the existing file.
  final String backupPath = '${filePath}.bak.v${_extractVersion(currentConfig)}';
  try {
    File(backupPath).writeAsStringSync(existingContent);
    print("Backed up existing conf.yml to $backupPath");
  } catch (e) {
    throw Exception("Failed to create backup at $backupPath");
  }

  // Perform the migration chain.
  YamlMap migrated = currentConfig;
  int v = _extractVersion(migrated);
  while (_migrationSteps.containsKey(v) && v < currentConfVersion) {
    final Map<String, dynamic> plainResult = _migrationSteps[v]!(migrated);
    // Re-parse the plain result as a YamlMap for the next iteration.
    migrated = loadYaml(_serializeYamlMap(plainResult));
    v = migrated['version'] as int;
  }

  // Write the migrated config back to disk.
  try {
    confFile.writeAsStringSync(_serializeYamlMap(_toPlainMap(migrated)));
    print("Migration successful. conf.yml is now at version $currentConfVersion.");
  } catch (e) {
    throw Exception(
        "Migration succeeded in memory, but failed to write back to $filePath. "
        "Please check permissions.");
  }
}

int _extractVersion(YamlMap config) {
  return config.containsKey('version') ? config['version'] as int : 0;
}

/// Recursively converts a YamlMap to a plain Map<String, dynamic>.
Map<String, dynamic> _toPlainMap(dynamic node) {
  if (node is YamlMap) {
    final Map<String, dynamic> result = <String, dynamic>{};
    for (final entry in node.entries) {
      result[entry.key.toString()] = _toPlainValue(entry.value);
    }
    return result;
  }
  return _toPlainValue(node);
}

dynamic _toPlainValue(dynamic node) {
  if (node is YamlMap) {
    return _toPlainMap(node);
  } else if (node is YamlList) {
    return node.map(_toPlainValue).toList();
  }
  return node;
}

/// Serializes a plain Map to a YAML string.
String _serializeYamlMap(Map<String, dynamic> map) {
  final StringBuffer sb = StringBuffer();
  _serializeMapNode(sb, map, indent: 0);
  return sb.toString();
}

void _serializeMapNode(StringBuffer sb, Map<String, dynamic> map, {int indent = 0}) {
  final String pad = '  ' * indent;

  for (final entry in map.entries) {
    final dynamic value = entry.value;
    if (value is Map<String, dynamic>) {
      if (value.isEmpty) {
        sb.writeln('${pad}${_toYamlKey(entry.key)}: {}');
      } else {
        sb.writeln('${pad}${_toYamlKey(entry.key)}:');
        _serializeMapNode(sb, value, indent: indent + 1);
      }
    } else if (value is List) {
      sb.writeln('${pad}${_toYamlKey(entry.key)}:');
      for (final item in value) {
        sb.writeln('${pad}  -');
        _serializeValueNode(sb, item, indent: indent + 2);
      }
    } else {
      // Scalar value: write inline with the key.
      sb.writeln('${pad}${_toYamlKey(entry.key)}: ${_toYamlValue(value)}');
    }
  }
}

void _serializeValueNode(StringBuffer sb, dynamic value, {int indent = 0}) {
  final String pad = '  ' * indent;

  if (value is Map<String, dynamic>) {
    _serializeMapNode(sb, value, indent: indent);
  } else if (value is List) {
    for (final item in value) {
      sb.writeln('${pad}-');
      _serializeValueNode(sb, item, indent: indent + 1);
    }
  } else {
    sb.writeln(_toYamlValue(value));
  }
}

/// Characters that require quoting in YAML keys.
const String _specialKeyChars = ' [][{],&*?|>!"%';

String _toYamlKey(dynamic key) {
  final String s = key.toString();
  bool needsQuote = s.isEmpty;
  for (int i = 0; i < _specialKeyChars.length; i++) {
    if (s.contains(_specialKeyChars[i])) {
      needsQuote = true;
      break;
    }
  }
  if (needsQuote) {
    return "'$s'";
  }
  return s;
}

/// Characters that require quoting in YAML values.
const String _specialValueChars = '#[][{}"&*?|>%@`';
const String _quoteChar = "'";

String _toYamlValue(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is int) return value.toString();
  final String s = value.toString();

  bool needsQuote = s.isEmpty ||
      s.toLowerCase() == 'true' ||
      s.toLowerCase() == 'false' ||
      s.toLowerCase() == 'null' ||
      s.startsWith(' ') ||
      s.endsWith(' ');

  if (!needsQuote) {
    for (int i = 0; i < _specialValueChars.length; i++) {
      if (s.contains(_specialValueChars[i])) {
        needsQuote = true;
        break;
      }
    }
  }

  if (needsQuote) {
    // Escape internal single quotes by doubling them (YAML spec).
    final String escaped = s.replaceAll(_quoteChar, '$_quoteChar$_quoteChar');
    return "'$escaped'";
  }
  return s;
}
