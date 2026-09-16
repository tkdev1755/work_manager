import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:work_manager/mcp_server.dart';

void main() {
  WorkManagerMCPServer(stdioChannel(input: io.stdin, output: io.stdout));
}
