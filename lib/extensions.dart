import 'package:work_manager/work_manager.dart';
import 'package:io/io.dart';
List<String> parseCommand(String command) {
  return shellSplit(command);
}

extension SafeMap<K, V> on Map<K, V> {

  V require(K key, [String? message]) {
    if (!containsKey(key)) {
      throw StateError(message ?? 'Unknown key : $key');
    }
    return this[key] as V;
  }

  V requireNotNull(K key, [String? message]) {
    if (!containsKey(key) || this[key] == null) {
      throw StateError(message ?? 'Non-existent key or null value for said key : $key');
    }
    return this[key] as V;
  }
}

void logger(value){
  if (DEBUG){
    print(value);
  }
}