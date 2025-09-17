import 'package:work_manager/work_manager.dart';
import 'package:io/io.dart';
List<String> parseCommand(String command) {
  return shellSplit(command);
}