
import 'package:work_manager/work_manager.dart' as work_manager;



void main(List<String> arguments) {
  print("DEBUG STATUS ${work_manager.DEBUG}");
  print("DEBUG PATHS -  \n${work_manager.confFilePath} • Conf File \n${work_manager.dbFilePath} • DB File");
  work_manager.main(arguments);
}
