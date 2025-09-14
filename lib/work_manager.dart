import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/v6.dart';
import 'package:yaml/yaml.dart';
import 'package:dart_console/dart_console.dart';


/// Structure of the conf.yml file
/*
  template_files:
     - file1:
       type: resume
       path:
       output_name: CV_${wname}_2020.pages
       export_command:
       # By default, if no open_command is specified the "open filepath" command or "start filepath" is used
       open_command: open ${file2.path}
    - file2:
      type: asset
      path:
   - file3:
     type: coverLetter
   paths:
    - applications_path : ""
    - export_path: ""
    - template_path : ""
 */
String slash = Platform.isWindows ? "\\":"/";
bool DEBUG = bool.fromEnvironment('DEBUG', defaultValue: false);
String debugConfFilePath = DEBUG ? String.fromEnvironment("confPath", defaultValue: "") : "";
String debugDbFilePath = DEBUG ? String.fromEnvironment("dbPath", defaultValue: "") : "";
String confFilePath = DEBUG ? debugConfFilePath: "${Platform.resolvedExecutable}${slash}conf.yml";
String dbFilePath = DEBUG ? debugDbFilePath : "${Platform.resolvedExecutable}${slash}metadata.json";
DateFormat dateFormat = DateFormat("dd/MM/yyyy-HH:mm");
Console console = Console();
YamlMap loadConfFile(){
  File confFile = File(confFilePath);
  if (!confFile.existsSync()){
    confFile.create(recursive: true);
    return YamlMap();
  }
  YamlMap conf;
  try {
    conf = loadYaml(confFile.readAsStringSync());
  }
  catch(e,s){
    print("");
    throw Exception("Unable to parse the yaml File");
  }
  return conf;
}

Map<String,dynamic> loadMetdataFile(){
  File metadataFile = File(dbFilePath);
  if (!metadataFile.existsSync()){
    metadataFile.createSync(recursive: true);
    metadataFile.writeAsStringSync("{}");
    return {};
  }
  return jsonDecode(metadataFile.readAsStringSync());
}

MapEntry<String,dynamic>? getLoadedApplication(Map<String,dynamic> metadata){
  if (metadata.containsKey("loadedApplication") && metadata["loadedApplication"].containsKey("openedLast")){
    Map<String,dynamic> loadedApplicationInfo = metadata["loadedApplication"];
    DateTime openedLast = dateFormat.parse(loadedApplicationInfo["openedLast"]);
    if (DateTime.now().difference(openedLast).inDays <= 2 && metadata["applications"].containsKey(loadedApplicationInfo["id"])){
      Map<String,dynamic> applications = metadata["applications"];
      return applications.values.firstWhere((e) => e.key == loadedApplicationInfo["id"]);
    }
    else{
      return null;
    }
  }
  else{
    return null;
  }
}

String getApplicationsPath(YamlMap configFile){
  if (!configFile.containsKey("paths")){
    throw Exception("No paths were specified in the configuration file");
  }
  YamlMap paths = configFile["paths"];
  if (!paths.containsKey("applicationsPath")){
    throw Exception("No application path was specified");
  }
  else{
    return paths["applicationsPath"];
  }
}

String getExportPath(YamlMap configFile){
  if (!configFile.containsKey("paths")){
    throw Exception("No paths were specified in the configuration file");
  }
  YamlMap paths = configFile["paths"];
  if (!paths.containsKey("exportPath")){
    throw Exception("No export path was specified in the configuration file");
  }
  return paths["exportPath"];
}

YamlMap getTemplateFiles(YamlMap configFile){
  if (!configFile.containsKey("template_files")){
    throw Exception("No template file was specified in the configuration file");
  }
  return configFile["template_files"];
}

String getApplicationID(List<String> ids, String applicationName){
  bool hasFoundID = false;
  String selectedID = "";
  while (!hasFoundID){
    selectedID = "CA-${applicationName.toUpperCase().substring(0, 2)}${UuidV6().generate().substring(0,10)}";
    if (!ids.contains(selectedID)) hasFoundID = true;
  }
  return selectedID;
}
void main(List<String> arguments){
  const String loadCommand = "load";
  const String createCommand = "create";
  const String openCommand = "open";
  const String exportCommand = "export";
  const String helpCommand = "-h";

  YamlMap confFile = loadConfFile();
  Map<String,dynamic> metadataFile =  loadMetdataFile();
  MapEntry<String,dynamic>? selectedApplication = getLoadedApplication(metadataFile);
  if (arguments.length < 1){
    print("Usage : wmanager <command> <arguments>");
    exit(-1);
  }
  String command = arguments[0];
  String? args = arguments.length > 1 ? arguments[1] : null;
  switch (command){
    case helpCommand:
      print("List of commands for wmanager \n-h \t Displays available commands\ncreate \t Creates a new job application \nopen <argument> \t opens a specific file linked to an application \nexport \t Exports the application\n");
      exit(0);
    case loadCommand:
      int exitCode = loadApplication(metadataFile, selectedApplication);
      exit(exitCode);
      break;
    case openCommand:
      break;
    case createCommand:
      int exitCode = createApplication(metadataFile, args);
      exit(exitCode);
      break;
    case exportCommand:

      break;
    default:
      print("Wrong command, type wmanager -h to see available commands");
      exit(-1);
  }

}

int loadApplication(Map<String,dynamic> metadata, MapEntry<String,dynamic>? selectedApplication){
  bool hasSelectedApplication = false;
  if (!metadata.containsKey("applications")) metadata["applications"] = {};
  Map<String,dynamic> applications = metadata["applications"];
  List applicationsValues = applications.values.toList();
  int selectedIndex = 0;
  int index = 0;
  int listLength = applicationsValues.length;
  while (!hasSelectedApplication){
    for (MapEntry<String,dynamic> application in applicationsValues){
      if (selectedIndex == index){
        console.setBackgroundColor(ConsoleColor.magenta);
        console.writeLine("> ${application.value["name"]}");
        console.writeLine();
        console.resetColorAttributes();
      }
      else{
        console.writeLine(" ${application.value["name"]}");
        console.writeLine();
      }
      index++;
    }
    Key resultKey  = console.readKey();
    if (resultKey.isControl){
      switch (resultKey.controlChar){
        case ControlCharacter.arrowUp:
          selectedIndex = (selectedIndex -1) % listLength;
          break;
        case ControlCharacter.arrowDown:
          selectedIndex = (selectedIndex +1) % listLength;
          break;
        case ControlCharacter.enter:
          selectedApplication = applicationsValues[selectedIndex];
          metadata["loadedApplication"] = {
            "id" : applicationsValues[selectedIndex].key,
            "lastOpened" : dateFormat.format(DateTime.now()),
          };
          hasSelectedApplication = true;
          return 0;
          break;
        default:
          break;
      }
    }
  }
  return -1;
}

int createApplication(Map<String,dynamic> metadata, String? argument){
  if (argument == null){
    print("Wrong usage : wmanager create <Application Name>");
    return -1;
  }
  // TODO - Add code for creating the folders and files
  if (!metadata.containsKey("applications")) metadata["applications"] = {};

  Map<String,dynamic> applications = metadata["applications"];
  String applicationID = getApplicationID(metadata.keys.toList(),argument);
  metadata["applications"][applicationID] = {
    "name" : argument,
    "creationDate" : dateFormat.format(DateTime.now())
  };
  return 0;
}

void exportApplication(){

}

void openApplicationFile(){

}