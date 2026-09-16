/// MCP server exposing work_manager's application/preset lifecycle to AI
/// agents. Imports `package:work_manager` directly as a library (no
/// subprocess, no stdout text parsing) - see docs/mcp_implementation_plan.md.
///
/// Important: this process talks MCP over stdio, so stdout is the protocol
/// channel. Every function called from here must be free of `print()` -
/// that's why work_manager.dart/presets.dart's business-logic functions
/// return typed `OperationResult`s instead of printing.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:yaml/yaml.dart';

import 'package:work_manager/presets.dart' as presets;
import 'package:work_manager/results.dart';
import 'package:work_manager/work_manager.dart' as wm;

base class WorkManagerMCPServer extends MCPServer with ToolsSupport, ResourcesSupport {
  YamlMap confFile;
  Map<String, dynamic> metadataFile;
  MapEntry<String, dynamic>? selectedApplication;

  WorkManagerMCPServer(super.channel)
      : confFile = wm.loadConfFile(),
        metadataFile = wm.loadMetdataFile(),
        super.fromStreamChannel(
          implementation: Implementation(name: 'work_manager', version: '1.2.0'),
          instructions:
              'Tools to drive work_manager, a job-application manager driven by '
              "conf.yml (templates, presets, paths). This server resolves *where* "
              "things live and runs the configured open/export commands - it does "
              "not read or write template file contents itself; use "
              "resolve_template_path to get a path, then read/edit it with your "
              "own file tools. Read the 'config-schema' resource first if you "
              "haven't seen a work_manager conf.yml before.",
        ) {
    selectedApplication = wm.getLoadedApplication(metadataFile);

    registerTool(listPresetsTool, _listPresets);
    registerTool(getPresetInfoTool, _getPresetInfo);
    registerTool(listApplicationsTool, _listApplications);
    registerTool(getCurrentApplicationTool, _getCurrentApplication);
    registerTool(createApplicationTool, _createApplication);
    registerTool(loadApplicationTool, _loadApplication);
    registerTool(resolveTemplatePathTool, _resolveTemplatePath);
    registerTool(openTemplateTool, _openTemplate);
    registerTool(exportApplicationTool, _exportApplication);
    registerTool(addPresetTool, _addPreset);
    registerTool(removePresetTool, _removePreset);

    addResource(
      Resource(
        uri: 'workmanager://config-schema',
        name: 'config-schema',
        description: "work_manager's conf.yml structure and variable system.",
      ),
      (request) => ReadResourceResult(
        contents: [TextResourceContents(text: _configSchemaDoc, uri: request.uri)],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  final listPresetsTool = Tool(
    name: 'list_presets',
    description:
        'Lists every registered preset (excluding "default") with its name '
        'and folder path.',
    inputSchema: Schema.object(),
  );

  FutureOr<CallToolResult> _listPresets(CallToolRequest request) {
    final list = presets.listPresets(confFile);
    return _ok(list.map((p) => {'name': p.name, 'path': p.path}).toList());
  }

  final getPresetInfoTool = Tool(
    name: 'get_preset_info',
    description:
        "Describes a preset's templates: for each one, its key, file name, "
        "whether it's an asset (copied but never exported), and whether it "
        "defines an open/export command. Pass 'default' for the default preset.",
    inputSchema: Schema.object(
      properties: {
        'preset': Schema.string(description: "Preset name, or 'default'."),
      },
      required: ['preset'],
    ),
  );

  FutureOr<CallToolResult> _getPresetInfo(CallToolRequest request) {
    final presetName = request.arguments!['preset'] as String;
    switch (wm.resolveTemplatesForPreset(confFile, presetName)) {
      case Ok(value: final templates):
        final summary = templates.entries.map((entry) {
          final info = entry.value as YamlMap;
          return {
            'key': entry.key.toString(),
            'name': info['name']?.toString(),
            'isAsset': wm.isAsset(info),
            'hasOpenCommand': info.containsKey('open_command'),
            'hasExportCommand': info.containsKey('export_command'),
          };
        }).toList();
        return _ok({'preset': presetName, 'templates': summary});
      case Err(message: final message):
        return _err(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Application lifecycle
  // ---------------------------------------------------------------------------

  final listApplicationsTool = Tool(
    name: 'list_applications',
    description: 'Lists every known application: id, name, creation date, preset.',
    inputSchema: Schema.object(),
  );

  FutureOr<CallToolResult> _listApplications(CallToolRequest request) {
    final apps = wm.listApplications(metadataFile);
    return _ok(apps
        .map((a) => {'id': a.id, 'name': a.name, 'creationDate': a.creationDate, 'preset': a.preset})
        .toList());
  }

  final getCurrentApplicationTool = Tool(
    name: 'get_current_application',
    description: 'Returns the currently loaded application, if any.',
    inputSchema: Schema.object(),
  );

  FutureOr<CallToolResult> _getCurrentApplication(CallToolRequest request) {
    switch (wm.currentApplication(metadataFile, confFile, selectedApplication)) {
      case Ok(value: final info):
        return _ok({'id': info.id, 'name': info.name, 'folder': info.folder, 'preset': info.preset});
      case Err(message: final message):
        return _err(message);
    }
  }

  final createApplicationTool = Tool(
    name: 'create_application',
    description:
        'Creates a new application: copies the preset\'s template files into '
        'a fresh application folder and loads it. Omit "preset" to use the '
        'default preset.',
    inputSchema: Schema.object(
      properties: {
        'name': Schema.string(description: 'The application/company name.'),
        'preset': Schema.string(description: "Preset name, or 'default'. Optional."),
      },
      required: ['name'],
    ),
  );

  FutureOr<CallToolResult> _createApplication(CallToolRequest request) {
    final name = request.arguments!['name'] as String;
    final preset = request.arguments!['preset'] as String?;
    switch (wm.createApplication(metadataFile, name, selectedApplication, confFile, preset)) {
      case Ok(value: final result):
        selectedApplication = wm.getLoadedApplication(metadataFile);
        _persistMetadata();
        return _ok({
          'id': result.id,
          'name': result.name,
          'preset': result.preset,
          'files': result.files
              .map((f) => {'templateKey': f.templateKey, 'path': f.path, 'isAsset': f.isAsset})
              .toList(),
        });
      case Err(message: final message):
        return _err(message);
    }
  }

  final loadApplicationTool = Tool(
    name: 'load_application',
    description: 'Loads an existing application by id, making it the current one.',
    inputSchema: Schema.object(
      properties: {'id': Schema.string(description: 'Application id, e.g. CA-XX0123456789.')},
      required: ['id'],
    ),
  );

  FutureOr<CallToolResult> _loadApplication(CallToolRequest request) {
    final id = request.arguments!['id'] as String;
    switch (wm.loadApplicationById(metadataFile, selectedApplication, confFile, id)) {
      case Ok(value: final info):
        selectedApplication = wm.getLoadedApplication(metadataFile);
        _persistMetadata();
        return _ok({'id': info.id, 'name': info.name, 'folder': info.folder, 'preset': info.preset});
      case Err(message: final message):
        return _err(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Files & export
  // ---------------------------------------------------------------------------

  final resolveTemplatePathTool = Tool(
    name: 'resolve_template_path',
    description:
        "Resolves the on-disk path of a template file for an application, "
        "without opening or exporting it. Use this to read/write the file's "
        "content with your own file tools. Defaults to the currently loaded "
        "application if applicationId is omitted.",
    inputSchema: Schema.object(
      properties: {
        'templateKey': Schema.string(description: "Template key, e.g. 'cv' or 'lm'."),
        'applicationId': Schema.string(description: 'Application id. Optional, defaults to the current one.'),
      },
      required: ['templateKey'],
    ),
  );

  FutureOr<CallToolResult> _resolveTemplatePath(CallToolRequest request) {
    final templateKey = request.arguments!['templateKey'] as String;
    final applicationId = request.arguments!['applicationId'] as String?;
    final target = _resolveApplication(applicationId);
    if (target == null) return _err(_noApplicationMessage(applicationId));
    switch (wm.resolveTemplatePath(confFile, target, templateKey)) {
      case Ok(value: final file):
        return _ok({'templateKey': file.templateKey, 'path': file.path, 'isAsset': file.isAsset});
      case Err(message: final message):
        return _err(message);
    }
  }

  final openTemplateTool = Tool(
    name: 'open_template',
    description:
        "Runs a template's configured open_command (e.g. opens it in an "
        "editor or app for human review). Defaults to the currently loaded "
        "application if applicationId is omitted.",
    inputSchema: Schema.object(
      properties: {
        'templateKey': Schema.string(description: "Template key, e.g. 'cv' or 'lm'."),
        'applicationId': Schema.string(description: 'Application id. Optional, defaults to the current one.'),
      },
      required: ['templateKey'],
    ),
  );

  FutureOr<CallToolResult> _openTemplate(CallToolRequest request) {
    final templateKey = request.arguments!['templateKey'] as String;
    final applicationId = request.arguments!['applicationId'] as String?;
    final target = _resolveApplication(applicationId);
    if (target == null) return _err(_noApplicationMessage(applicationId));
    switch (wm.openApplicationFile(metadataFile, confFile, templateKey, target)) {
      case Ok(value: final result):
        return _ok({'templateKey': result.templateKey, 'command': result.command});
      case Err(message: final message):
        return _err(message);
    }
  }

  final exportApplicationTool = Tool(
    name: 'export_application',
    description:
        "Runs every non-asset template's export_command for an application "
        "and copies the results to the export folder. Defaults to the "
        "currently loaded application if applicationId is omitted.",
    inputSchema: Schema.object(
      properties: {
        'applicationId': Schema.string(description: 'Application id. Optional, defaults to the current one.'),
      },
    ),
  );

  FutureOr<CallToolResult> _exportApplication(CallToolRequest request) {
    final applicationId = request.arguments!['applicationId'] as String?;
    final target = _resolveApplication(applicationId);
    if (target == null) return _err(_noApplicationMessage(applicationId));
    switch (wm.exportApplication(metadataFile, confFile, target)) {
      case Ok(value: final result):
        return _ok({
          'applicationId': result.applicationId,
          'exported': result.exported
              .map((f) => {'templateKey': f.templateKey, 'exportedPath': f.exportedPath})
              .toList(),
        });
      case Err(message: final message):
        return _err(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Preset administration
  // ---------------------------------------------------------------------------

  final addPresetTool = Tool(
    name: 'add_preset',
    description:
        "Registers a new preset. If fromPreset is omitted, creates an empty "
        "preset skeleton at path for the user to fill in by hand. If "
        "fromPreset is 'default' or an existing preset name, copies its "
        "template files (and template.yml) into path first.",
    inputSchema: Schema.object(
      properties: {
        'name': Schema.string(description: 'New preset name (not "default").'),
        'path': Schema.string(description: 'Folder to create the preset in.'),
        'fromPreset': Schema.string(description: "Source preset name, or 'default'. Optional."),
      },
      required: ['name', 'path'],
    ),
  );

  FutureOr<CallToolResult> _addPreset(CallToolRequest request) {
    final name = request.arguments!['name'] as String;
    final path = request.arguments!['path'] as String;
    final fromPreset = request.arguments!['fromPreset'] as String?;
    switch (presets.presetAddCommand(confFile, name, path, fromPresetName: fromPreset)) {
      case Ok(value: final preset):
        _reloadConfig();
        return _ok({'name': preset.name, 'path': preset.path});
      case Err(message: final message):
        return _err(message);
    }
  }

  final removePresetTool = Tool(
    name: 'remove_preset',
    description: "Unregisters a preset and deletes its folder from disk. Irreversible.",
    inputSchema: Schema.object(
      properties: {'name': Schema.string(description: 'Preset name to remove.')},
      required: ['name'],
    ),
  );

  FutureOr<CallToolResult> _removePreset(CallToolRequest request) {
    final name = request.arguments!['name'] as String;
    switch (presets.presetRemoveCommand(confFile, name)) {
      case Ok(value: final preset):
        _reloadConfig();
        return _ok({'name': preset.name, 'path': preset.path});
      case Err(message: final message):
        return _err(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Resolves which application a tool call should target: an explicit
  /// [applicationId], or the currently loaded one if omitted.
  MapEntry<String, dynamic>? _resolveApplication(String? applicationId) {
    if (applicationId == null) return selectedApplication;
    final applications = metadataFile['applications'];
    if (applications is! Map || !applications.containsKey(applicationId)) return null;
    return MapEntry(applicationId, applications[applicationId] as Map<String, dynamic>);
  }

  String _noApplicationMessage(String? applicationId) => applicationId != null
      ? "Application '$applicationId' not found."
      : 'No application is currently loaded, and no applicationId was given.';

  /// Persists metadata.json after a tool call that mutated it. conf.yml is
  /// written directly by presets.dart's own functions, so it never needs
  /// this - see _reloadConfig instead.
  void _persistMetadata() {
    wm.dumpChanges(metadataFile, confFile, wm.dbFilePath, wm.confFilePath, needsUpdate: true);
  }

  /// Reloads conf.yml from disk after a preset add/remove call, since those
  /// write straight to disk and YamlMap itself is immutable (can't be patched
  /// in place).
  void _reloadConfig() {
    confFile = wm.loadConfFile();
  }

  CallToolResult _ok(Object? data) => CallToolResult(content: [TextContent(text: jsonEncode(data))]);

  CallToolResult _err(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);
}

const _configSchemaDoc = '''
# work_manager conf.yml (version 1)

version: 1
default_preset:
  template_files:
    <templateKey>:
      name: "source file name, inside `path`"
      path: "absolute folder the source file lives in"
      output_name: "name once copied into an application folder, may use \${wname}"
      export_name: "name of the exported file, may use \${wname}"
      open_command: "shell command run by open_template, may use variables"
      export_command: "shell command run by export_application, may use variables"
      is_asset: true   # optional; assets are copied but never exported, and
                       # have no output_name/export_name/export_command
presets:
  <presetName>:
    path: "folder containing that preset's own template.yml and source files"
paths:
  applications_path: "folder each created application gets its own subfolder in"
  export_path: "folder exported files are copied to"

A preset's own `template.yml` (at `<path>/template.yml`) has the same
`template_files` shape as `default_preset`, minus `path` on each entry - a
preset's source files live alongside its `template.yml`, implicitly.

## Variable substitution (in open_command / export_command)

- `\${wname}`            -> the application name, uppercased, spaces stripped
                            (only valid inside output_name/export_name)
- `\${self.path}`         -> the application's folder on disk
- `\${self.output_name}`  -> this template's own output_name, substituted
- `\${self.export_name}`  -> this template's own export_name, substituted
- `\${<otherKey>.path|output_name|export_name}` -> same, but referencing
  another template in the same preset by its key
''';
