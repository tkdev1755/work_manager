import 'dart:io';
import 'package:work_manager/extensions.dart';
import 'package:yaml/yaml.dart';
import 'package:work_manager/work_manager.dart' as wm;


/// ---------------------------------------------------------------------------
/// Preset management module.
///
/// Handles loading presets from the main conf.yml, listing/registering/
/// removing presets, and copying presets via the `--from` flag.
/// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Preset data structures
// ---------------------------------------------------------------------------

/// Represents a single preset entry from the `presets` section of conf.yml.
class PresetEntry {
  final String name;
  final String path;

  const PresetEntry({required this.name, required this.path});

  @override
  String toString() => 'PresetEntry(name: $name, path: $path)';
}

/// Represents the full preset configuration (template definitions).
/// Loaded from a preset's `template.yml` file.
class PresetConfig {
  final String presetName;
  final String presetFolderPath;
  final YamlMap templateFiles;

  const PresetConfig({
    required this.presetName,
    required this.presetFolderPath,
    required this.templateFiles,
  });
}

// ---------------------------------------------------------------------------
// Loading presets from conf.yml
// ---------------------------------------------------------------------------

/// Returns all preset entries registered in the main conf.yml.
///
/// Excludes the default preset (which is handled separately).
List<PresetEntry> listPresets(YamlMap confFile) {
  final List<PresetEntry> presets = [];

  if (!confFile.containsKey('presets')) {
    return presets;
  }

  final YamlMap presetsMap = confFile['presets'];
  if (presetsMap.isEmpty) {
    return presets;
  }

  for (final entry in presetsMap.entries) {
    final String name = entry.key.toString();
    final dynamic value = entry.value;

    if (value is YamlMap && value.containsKey('path')) {
      presets.add(PresetEntry(
        name: name,
        path: value['path'].toString(),
      ));
    }
  }

  return presets;
}

/// Returns the path of a specific preset by name, or `null` if not found.
String? getPresetPath(YamlMap confFile, String presetName) {
  if (!confFile.containsKey('presets')) return null;
  final YamlMap presetsMap = confFile['presets'];
  logger("preset map ${presetsMap}");
  if (!presetsMap.containsKey(presetName)) return null;
  final dynamic value = presetsMap[presetName];
  if (value is YamlMap && value.containsKey('path')) {
    return value['path'].toString();
  }
  return null;
}

// ---------------------------------------------------------------------------
// Loading a preset's template definitions
// ---------------------------------------------------------------------------

/// Loads a preset's `template.yml` from its folder and returns its config.
///
/// Validates that:
/// - The preset folder exists.
/// - A `template.yml` file exists inside the folder.
/// - The `template.yml` contains a valid `template_files` key.
///
/// Throws a [StateError] if validation fails.
PresetConfig loadPresetConfig(String presetName, String presetFolderPath) {
  final Directory presetDir = Directory(presetFolderPath);
  if (!presetDir.existsSync()) {
    throw StateError(
        "Preset '$presetName' folder does not exist at $presetFolderPath.");
  }

  final File templateFile = File('${presetFolderPath}/template.yml');
  if (!templateFile.existsSync()) {
    throw StateError(
        "Preset '$presetName' is missing its template.yml file at ${templateFile.path}.");
  }

  YamlMap templateYaml;
  try {
    templateYaml = loadYaml(templateFile.readAsStringSync());
  } catch (e) {
    throw StateError(
        "Failed to parse template.yml for preset '$presetName'. "
        "Check syntax.");
  }

  // Handle empty template_files (presets created from scratch).
  dynamic templateFilesValue = templateYaml.containsKey('template_files')
      ? templateYaml['template_files']
      : null;
  // If template_files is null (empty), treat as empty map.
  if (templateFilesValue == null) {
    templateFilesValue = YamlMap();
  }

  return PresetConfig(
    presetName: presetName,
    presetFolderPath: presetFolderPath,
    templateFiles: templateFilesValue is YamlMap ? templateFilesValue : YamlMap(),
  );
}

/// Loads the default preset's template definitions from the main conf.yml.
///
/// Returns a [PresetConfig] with the default preset's templates.
/// The default preset's templates have absolute `path` values, so we use
/// them as-is.
PresetConfig loadDefaultPresetConfig(YamlMap confFile, String confDirPath) {
  if (!confFile.containsKey('default_preset')) {
    throw StateError(
        "No default_preset defined in conf.yml at $confDirPath.");
  }

  final YamlMap defaultPreset = confFile['default_preset'];
  if (!defaultPreset.containsKey('template_files')) {
    throw StateError(
        "default_preset in conf.yml must contain a 'template_files' key.");
  }

  return PresetConfig(
    presetName: 'default',
    presetFolderPath: confDirPath,
    templateFiles: defaultPreset['template_files'],
  );
}

// ---------------------------------------------------------------------------
// Preset management commands
// ---------------------------------------------------------------------------

/// Lists all registered presets (excluding the default preset).
///
/// Prints a formatted table to stdout.
void presetListCommand(YamlMap confFile) {
  final List<PresetEntry> presets = listPresets(confFile);

  if (presets.isEmpty) {
    print("No presets registered. Use 'wmanager preset add' to create one.");
    return;
  }

  // Find the longest name and path for column alignment.
  int maxNameLen = 0;
  int maxPathLen = 0;
  for (final p in presets) {
    if (p.name.length > maxNameLen) maxNameLen = p.name.length;
    if (p.path.length > maxPathLen) maxPathLen = p.path.length;
  }

  final String namePad = '  ';
  final String pathPad = '  ';
  print('Registered presets:');
  print('${namePad}${'Name'.padRight(maxNameLen)}  ${pathPad}Path');
  print('${'-' * (maxNameLen + 2)}  ${'-' * (maxPathLen + 2)}');
  for (final p in presets) {
    print('${namePad}${p.name.padRight(maxNameLen)}  ${pathPad}${p.path}');
  }
}

/// Adds a new preset by copying from an existing preset.
///
/// Usage: `wmanager preset add <name> <path> --from <existing_preset_name>`
///
/// Steps:
/// 1. Validates the source preset exists and is loadable.
/// 2. Creates the destination folder (if it doesn't exist).
/// 3. Copies all files from the source preset folder to the destination.
/// 4. Updates the main conf.yml to register the new preset.
void presetAddCommand(
    YamlMap confFile,
    String newName,
    String newPath, {
    String? fromPresetName,
  }) {
  Directory sourceDir;
  String sourceFolderPath;

  if (fromPresetName != null) {
    // Copy from an existing preset.
    final String? existingPath = getPresetPath(confFile, fromPresetName);
    if (existingPath == null) {
      // Check if it's the default preset.
      if (fromPresetName == 'default' && confFile.containsKey('default_preset')) {
        // The default preset's templates live in the templates/ subdirectory.
        sourceFolderPath = '${wm.confDirPath}${wm.slash}templates';
      } else {
        print("Error: Preset '$fromPresetName' not found in conf.yml.");
        return;
      }
    } else {
      sourceFolderPath = existingPath;
    }
    sourceDir = Directory(sourceFolderPath);
    if (!sourceDir.existsSync()) {
      print("Error: Source preset '$fromPresetName' folder does not exist at $sourceFolderPath.");
      return;
    }
  } else {
    // Create a new preset from scratch (no source).
    print("Creating a new preset from scratch. "
        "Place your template files and template.yml in $newPath.");
    sourceDir = Directory(newPath);
    sourceFolderPath = newPath;
  }

  // Create the destination folder.
  final Directory destDir = Directory(newPath);
  if (!destDir.existsSync()) {
    try {
      destDir.createSync(recursive: true);
    } catch (e) {
      print("Error: Could not create directory $newPath: $e");
      return;
    }
  }

  if (fromPresetName != null) {
    if (fromPresetName == "default"){
      final File templateFile = File('${newPath}/template.yml');
      YamlMap templates = confFile["default_preset"]["template_files"];
      if (!templateFile.existsSync()) {
        
        templateFile.writeAsStringSync('template_files:${_serializeYaml(templates)}');
        print("Created template.yml at $newPath/template.yml. "
            "Edit it to define your templates.");
      }

    }
    // Copy all files from the source preset folder to the destination.
    _copyDirectoryContents(sourceDir, destDir);

    // If the source has a template.yml, copy it (already copied above).
    // If the source doesn't have a template.yml, create an empty one.
    final File destTemplateFile = File('${newPath}/template.yml');
    if (!destTemplateFile.existsSync()) {
      destTemplateFile.writeAsStringSync('template_files:\n');
      print("Created empty template.yml at $newPath/template.yml. "
          "Edit it to define your templates.");
    }

    print("Preset '$newName' created at $newPath (copied from '$fromPresetName').");
  } else {
    // Create an empty template.yml.
    final File templateFile = File('${newPath}/template.yml');
    if (!templateFile.existsSync()) {
      templateFile.writeAsStringSync('template_files:\n');
      print("Created empty template.yml at $newPath/template.yml. "
          "Edit it to define your templates.");
    }
    print("Preset '$newName' created at $newPath.");
  }

  // Register the new preset in conf.yml.
  _registerPresetInConfFile(confFile, newName, newPath);
}

/// Removes a preset from conf.yml and deletes its folder.
void presetRemoveCommand(YamlMap confFile, String presetName) {
  if (!confFile.containsKey('presets')) {
    print("Error: No presets defined in conf.yml.");
    return;
  }

  final YamlMap presetsMap = confFile['presets'];
  if (!presetsMap.containsKey(presetName)) {
    print("Error: Preset '$presetName' not found.");
    return;
  }

  final String presetPath = presetsMap[presetName]['path'].toString();

  // Delete the preset folder.
  final Directory presetDir = Directory(presetPath);
  if (presetDir.existsSync()) {
    try {
      presetDir.deleteSync(recursive: true);
    } catch (e) {
      print("Warning: Could not delete preset folder at $presetPath: $e");
    }
  }

  // Remove from conf.yml.
  presetsMap.remove(presetName);

  // Write back to conf.yml.
  _updateConfFile(confFile, wm.confFilePath);

  print("Preset '$presetName' removed.");
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Copies all contents from [sourceDir] to [destDir].
void _copyDirectoryContents(Directory sourceDir, Directory destDir) {
  for (final entity in sourceDir.listSync(recursive: true)) {
    final String relativePath = entity.path.substring(sourceDir.path.length + 1);
    final String destPath = '${destDir.path}/$relativePath';

    if (entity is File) {
      try {
        entity.copySync(destPath);
      } catch (e) {
        print("Warning: Could not copy ${entity.path}: $e");
      }
    }
  }
}

/// Registers a preset in the main conf.yml under the `presets` key.
void _registerPresetInConfFile(YamlMap confFile, String name, String path) {
  // Convert the entire confFile to a plain Map, update presets, then write back.
  final Map<String, dynamic> plainConf = _toPlainMap(confFile);
  final Map<String, dynamic> presetsMap = plainConf['presets'] is Map<String, dynamic>
      ? Map<String, dynamic>.from(plainConf['presets'] as Map<String, dynamic>)
      : <String, dynamic>{};
  presetsMap[name] = {'path': path};
  plainConf['presets'] = presetsMap;

  try {
    File(wm.confFilePath).writeAsStringSync(_serializeYamlMap(plainConf));
    print("Preset '$name' registered in conf.yml.");
  } catch (e) {
    throw Exception("Failed to write updated conf.yml to ${wm.confFilePath}: $e");
  }
}

/// Writes the updated conf.yml back to disk.
void _updateConfFile(YamlMap confFile, String configPath) {
  try {
    // Convert to plain Map and serialize (handles empty maps correctly).
    final Map<String, dynamic> plainMap = _toPlainMap(confFile);
    File(configPath).writeAsStringSync(_serializeYamlMap(plainMap));
  } catch (e) {
    throw Exception("Failed to write updated conf.yml to $configPath: $e");
  }
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

/// Serializes a YamlMap back to a YAML string.
String _serializeYaml(YamlMap yaml) {
  final StringBuffer sb = StringBuffer();
  _serializeNode(sb, yaml, indent: 0);
  return sb.toString();
}

void _serializeNode(StringBuffer sb, dynamic node, {int indent = 0}) {
  final String pad = '  ' * indent;

  if (node is YamlMap) {
    if (node.isEmpty) {
      sb.write('{}');
      return;
    }
    for (final entry in node.entries) {
      sb.writeln('${pad}${_toYamlKey(entry.key)}:');
      _serializeNode(sb, entry.value, indent: indent + 1);
    }
  } else if (node is YamlList) {
    if (node.isEmpty) {
      sb.write('[]');
      return;
    }
    for (final item in node) {
      sb.writeln('${pad}-');
      _serializeNode(sb, item, indent: indent + 1);
    }
  } else {
    sb.write(_toYamlValue(node));
  }
}

/// Serializes a plain Map to a YAML string (handles empty maps inline).
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
