// This test drives WorkManagerMCPServer in-process, through the same MCP
// protocol a real client speaks, but over an in-memory StreamChannel pair
// instead of a subprocess - no need to spawn/compile a second binary.
//
// It reads conf.yml/metadata.json paths from -DconfPath/-DdbPath, which it
// also uses to WRITE a throwaway fixture in setUpAll (so the test is
// self-contained: whatever those paths are, this test creates and owns the
// files there). Run it with `test/run_mcp_tests.sh`, which picks a fresh
// temp directory and passes it via those defines.
//
// Deliberately NOT named *_test.dart: `dart test`'s default discovery globs
// test/**/*_test.dart, and this file always fails without -DconfPath/-DdbPath
// - naming it this way keeps plain `dart test` (and CI's
// .github/workflows/AnalyzeAndTest.yml) green without those defines.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:work_manager/mcp_server.dart';
import 'package:work_manager/work_manager.dart' as wm;

/// Minimal in-process client/server harness, following the same pattern as
/// dart_mcp's own (package-private) test_utils.dart.
class _TestHarness {
  final _clientController = StreamController<String>();
  final _serverController = StreamController<String>();

  late final MCPClient client;
  late final WorkManagerMCPServer server;
  late final ServerConnection connection;

  Future<void> start() async {
    final clientChannel = StreamChannel<String>.withCloseGuarantee(
      _serverController.stream,
      _clientController.sink,
    );
    final serverChannel = StreamChannel<String>.withCloseGuarantee(
      _clientController.stream,
      _serverController.sink,
    );

    client = MCPClient(Implementation(name: 'test client', version: '0.1.0'));
    server = WorkManagerMCPServer(serverChannel);
    connection = client.connectServer(clientChannel);

    await connection.initialize(InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ));
    connection.notifyInitialized();
  }

  Future<void> stop() async {
    await client.shutdown();
    await _clientController.close();
    await _serverController.close();
  }

  Future<Map<String, dynamic>> call(String name, [Map<String, Object?> args = const {}]) async {
    final result = await connection.callTool(CallToolRequest(name: name, arguments: args));
    final text = (result.content.single as TextContent).text;
    if (result.isError == true) {
      throw StateError('Tool $name failed: $text');
    }
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : {'value': decoded};
  }

  /// Like [call], but returns the raw error message instead of throwing.
  Future<String> callExpectingError(String name, [Map<String, Object?> args = const {}]) async {
    final result = await connection.callTool(CallToolRequest(name: name, arguments: args));
    expect(result.isError, isTrue, reason: '$name($args) was expected to fail');
    return (result.content.single as TextContent).text;
  }
}

void main() {
  final confPath = wm.debugConfFilePath;
  final dbPath = wm.debugDbFilePath;

  if (confPath.isEmpty || dbPath.isEmpty) {
    test('setup', () {
      fail('Run this test via test/run_mcp_tests.sh (it needs -DDEBUG=true '
          '-DconfPath=... -DdbPath=... to point at a throwaway fixture).');
    });
    return;
  }

  final fixtureDir = File(confPath).parent;
  final templatesDir = Directory('${fixtureDir.path}/templates');
  final applicationsDir = Directory('${fixtureDir.path}/applications');
  final exportDir = Directory('${fixtureDir.path}/export');
  final presetsDir = Directory('${fixtureDir.path}/presets');

  late _TestHarness harness;

  setUpAll(() {
    templatesDir.createSync(recursive: true);
    applicationsDir.createSync(recursive: true);
    exportDir.createSync(recursive: true);
    presetsDir.createSync(recursive: true);

    File('${templatesDir.path}/CV.txt').writeAsStringSync('=== FAKE CV ===\nName: \${wname}\n');
    File('${templatesDir.path}/LM.txt').writeAsStringSync('=== FAKE COVER LETTER ===\nI am \${wname}.\n');
    File('${templatesDir.path}/logo.txt').writeAsStringSync('(fake logo)\n');

    File(confPath).writeAsStringSync('''
version: 1
default_preset:
  template_files:
    cv:
      name: CV.txt
      path: ${templatesDir.path}/
      output_name: 'CV_\${wname}.txt'
      export_name: 'CV_\${wname}_export.txt'
      export_command: 'cp \${self.path}/\${self.output_name} \${self.path}/\${self.export_name}'
      open_command: 'cat \${self.path}'
    lm:
      name: LM.txt
      path: ${templatesDir.path}/
      output_name: 'LM_\${wname}.txt'
      export_name: 'LM_\${wname}_export.txt'
      export_command: 'cp \${self.path}/\${self.output_name} \${self.path}/\${self.export_name}'
      open_command: 'cat \${self.path}'
    logo:
      name: logo.txt
      path: ${templatesDir.path}/
      is_asset: true
presets: {}
paths:
  applications_path: ${applicationsDir.path}/
  export_path: ${exportDir.path}/
''');
    File(dbPath).writeAsStringSync('{}');
  });

  tearDownAll(() {
    fixtureDir.deleteSync(recursive: true);
  });

  setUp(() async {
    harness = _TestHarness();
    await harness.start();
  });

  tearDown(() async {
    await harness.stop();
  });

  test('list_presets starts empty', () async {
    final result = await harness.call('list_presets');
    expect(result['value'], isEmpty);
  });

  test('get_preset_info(default) describes the configured templates', () async {
    final result = await harness.call('get_preset_info', {'preset': 'default'});
    expect(result['preset'], 'default');
    final templates = result['templates'] as List;
    expect(templates.map((t) => t['key']), containsAll(['cv', 'lm', 'logo']));
    final logo = templates.firstWhere((t) => t['key'] == 'logo');
    expect(logo['isAsset'], isTrue);
  });

  test('create_application copies template files and loads the application', () async {
    final created = await harness.call('create_application', {'name': 'McpTestApp'});
    expect(created['preset'], 'default');
    final files = created['files'] as List;
    expect(files, hasLength(3));

    final current = await harness.call('get_current_application');
    expect(current['id'], created['id']);
    expect(current['name'], 'McpTestApp');

    final apps = await harness.call('list_applications');
    expect((apps['value'] as List).length, greaterThanOrEqualTo(1));
  });

  test('resolve_template_path points at a real file the app owns', () async {
    final created = await harness.call('create_application', {'name': 'ResolveApp'});
    final resolved = await harness.call('resolve_template_path', {'templateKey': 'cv'});
    expect(File(resolved['path'] as String).existsSync(), isTrue);
    expect(resolved['isAsset'], isFalse);
    expect(created['id'], isNotEmpty);
  });

  test('export_application runs export_command and copies results', () async {
    await harness.call('create_application', {'name': 'ExportApp'});
    final result = await harness.call('export_application');
    final exported = result['exported'] as List;
    expect(exported, hasLength(2)); // cv + lm, logo is an asset (skipped)
    for (final file in exported) {
      expect(File(file['exportedPath'] as String).existsSync(), isTrue);
    }
  });

  test('load_application fails clearly for an unknown id', () async {
    final message = await harness.callExpectingError('load_application', {'id': 'CA-DOES-NOT-EXIST'});
    expect(message, contains('not found'));
  });

  test('add_preset from default, then create_application with it, then remove it', () async {
    final presetPath = '${presetsDir.path}/student';
    final added = await harness.call('add_preset', {
      'name': 'student',
      'path': presetPath,
      'fromPreset': 'default',
    });
    expect(added['name'], 'student');

    final presets = await harness.call('list_presets');
    expect((presets['value'] as List).any((p) => p['name'] == 'student'), isTrue);

    final created = await harness.call('create_application', {'name': 'StudentApp', 'preset': 'student'});
    expect(created['preset'], 'student');

    final removed = await harness.call('remove_preset', {'name': 'student'});
    expect(removed['name'], 'student');
    expect(Directory(presetPath).existsSync(), isFalse);
  });

  test('config-schema resource is readable', () async {
    final resources = await harness.connection.listResources(ListResourcesRequest());
    expect(resources.resources.any((r) => r.uri == 'workmanager://config-schema'), isTrue);

    final content = await harness.connection.readResource(
      ReadResourceRequest(uri: 'workmanager://config-schema'),
    );
    final text = (content.contents.single as TextResourceContents).text;
    expect(text, contains('default_preset'));
    expect(text, contains(r'${wname}'));
  });
}
