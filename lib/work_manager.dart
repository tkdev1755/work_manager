import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:uuid/v6.dart';
import 'package:work_manager/extensions.dart';
import 'package:yaml/yaml.dart';
import 'package:dart_console/dart_console.dart';


/// Structure of the conf.yml file
/*
  template_files:
     - resume:
       name: file2.pdf
       path:
       output_name: CV_${wname}_2020.pages
       export_command:
       # By default, if no open_command is specified the "open {path}" command or "start filepath" is used
       open_command: open ${path}
    - file2:
      type: asset
      path:
   - file3:
     type: coverLetter
   paths:
    - applications_path : ""
    - export_path: ""
 */
String slash = Platform.isWindows ? "\\":"/";
bool DEBUG = bool.fromEnvironment('DEBUG', defaultValue: false);
String debugConfFilePath = DEBUG ? String.fromEnvironment("confPath", defaultValue: "") : "";
String debugDbFilePath = DEBUG ? String.fromEnvironment("dbPath", defaultValue: "") : "";
String confFilePath = getConfFilePath();
String dbFilePath = getDBFilePath();
DateFormat dateFormat = DateFormat("dd/MM/yyyy-HH:mm");
bool hasConfChanged = false;
Console console = Console();
RegExp variableRegex = RegExp(r'\$\{([^}]+)\}');

String getDBFilePath(){
  List<String> execPath = Platform.resolvedExecutable.split(slash);
  execPath.removeLast();
  String directory = execPath.join(slash);
  String nonDebugFilePath =  "${directory}${slash}metadata.json";
  return DEBUG ? debugDbFilePath : nonDebugFilePath;
}

String getConfFilePath(){
  List<String> execPath = Platform.resolvedExecutable.split(slash);
  execPath.removeLast();
  String directory = execPath.join(slash);
  String nonDebugFilePath =  "${directory}${slash}conf.yml";
  return DEBUG ? debugConfFilePath : nonDebugFilePath;
}
YamlMap loadConfFile(){
  File confFile = File(confFilePath);
  if (!confFile.existsSync()){
    logger("FILE IS CREATED");
    confFile.createSync(recursive: true);
    return YamlMap();
  }
  YamlMap conf;
  try {
    conf = loadYaml(confFile.readAsStringSync());
  }
  catch(e){
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
  String jsonFile = metadataFile.readAsStringSync();
  try {
    return jsonDecode(jsonFile);
  }
  catch (e){
    if (jsonFile.length == 1 && jsonFile.contains("")){
      return {};
    }
    else{
      throw Exception("Error while parsing the metadata");
    }
  }
}

MapEntry<String,dynamic>? getLoadedApplication(Map<String,dynamic> metadata){
  if (metadata.containsKey("loadedApplication") && metadata["loadedApplication"].containsKey("lastOpened")){
    Map<String,dynamic> loadedApplicationInfo = metadata["loadedApplication"];
    DateTime lastOpened = dateFormat.parse(loadedApplicationInfo["lastOpened"]);
    if (DateTime.now().difference(lastOpened).inDays <= 2 && metadata["applications"].containsKey(loadedApplicationInfo["id"])){
      Map<String,dynamic> applications = metadata["applications"];
      return applications.entries.firstWhere((e) => e.key == loadedApplicationInfo["id"]);
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
  if (!paths.containsKey("applications_path")){
    throw Exception("No application path was specified");
  }
  else{
    return paths["applications_path"];
  }
}

String getExportPath(YamlMap configFile){
  if (!configFile.containsKey("paths")){
    throw Exception("No paths were specified in the configuration file");
  }
  YamlMap paths = configFile["paths"];
  if (!paths.containsKey("export_path")){
    throw Exception("No export path was specified in the configuration file");
  }
  return paths["export_path"];
}

YamlMap getTemplateFiles(YamlMap configFile){
  if (!configFile.containsKey("template_files")){
    throw Exception("No template file was specified in the configuration file");
  }
  return configFile["template_files"];
}

YamlMap getTemplateInfo(YamlMap templateFiles, String templateName){
  logger("Template files -> ${templateFiles["template_files"]}");
  logger("Searched template $templateName");
  if (!(templateFiles["template_files"].containsKey(templateName))){
    throw Exception("The searched template doesn't exist");
  }
  return templateFiles["template_files"][templateName];
}

String getTemplateOpenCommand(YamlMap template){
  if (!template.containsKey("open_command")){
    if (!template.containsKey("path")) throw Exception("The following template doesn't have a path");
    return "open ${template["path"]}" ;
  }
  return template["open_command"];
}

String getTemplateExportCommand(YamlMap template){
  if (!template.containsKey("export_command")) throw Exception("The following template doesn't have an export command");
  return template["export_command"];
}

String getTemplateOutputName(YamlMap template){
  if (!template.containsKey("output_name")) throw Exception("The following template doesn't have an output_name command");
  return template["output_name"];
}

String getTemplateExportName(YamlMap template){
  if (!template.containsKey("export_name")) throw Exception("The following template doesn't have an output_name command");
  return template["export_name"];
}

bool isAsset(YamlMap template){
  if (!template.containsKey("is_asset")){
    return false;
  }
  return template["is_asset"];
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

String getApplicationFilename(String name){
  return name.toUpperCase().replaceAll(" ", "");
}

String getTemplateOutputFilename(YamlMap template, String name){
  bool undefinedVariable = false;
  String applicationTemplateName = getTemplateOutputName(template);
  String applicationGeneratedName = getApplicationFilename(name);
  applicationTemplateName = applicationTemplateName.replaceAllMapped(variableRegex, (match){
    String varName = match.group(1)!;
    switch (varName){
      case "wname":
        return applicationGeneratedName;
      default:
        undefinedVariable = true;
        return "";
    }
  });
  if (undefinedVariable){
    print("Undefined variable for ${template.keys} - please check conf.yml file");
    throw Exception("Undefined variable");
  }
  return applicationTemplateName;
}

String getTemplateExportFilename(YamlMap template, String name){
  bool undefinedVariable = false;
  String applicationTemplateName = getTemplateExportName(template);
  String applicationGeneratedName = getApplicationFilename(name);
  applicationTemplateName = applicationTemplateName.replaceAllMapped(variableRegex, (match){
    String varName = match.group(1)!;
    switch (varName){
      case "wname":
        return applicationGeneratedName;
      default:
        undefinedVariable = true;
        return "";
    }
  });
  if (undefinedVariable){
    print("Undefined variable for ${template.keys} - please check conf.yml file");
    throw Exception("Undefined variable");
  }
  return applicationTemplateName;
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
  if (arguments.isEmpty){
    print("Usage : wmanager <command> <arguments>");
    exit(-1);
  }
  String command = arguments[0];
  String? args = arguments.length > 1 ? arguments[1] : null;
  int exitCode = -1;
  bool needsUpdate = true;
  switch (command){
    case helpCommand:
      print("List of commands for wmanager \n-h                   \t Displays available commands\ncreate <name>     \t Creates a new job application \nopen <template>   \t opens a specific file linked to an application \nexport            \t Exports the application\n");
      needsUpdate = false;
      exitCode = 0;
    case loadCommand:
      exitCode = loadApplicationView(metadataFile, selectedApplication);
      needsUpdate = exitCode == 0;
      break;
    case openCommand:
      exitCode = openApplicationFile(metadataFile,confFile,args,selectedApplication);
      needsUpdate = false;
      break;
    case createCommand:
      exitCode = createApplication(metadataFile, args,selectedApplication,confFile);
      needsUpdate = exitCode == 0;
      break;
    case exportCommand:
      exitCode = exportApplication(metadataFile,confFile,selectedApplication);
      needsUpdate = false;
      break;
    default:
      print("Wrong command, type wmanager -h to see available commands");
      needsUpdate = false;
      exit(-1);
  }
  dumpChanges(metadataFile, confFile, dbFilePath, confFilePath,needsUpdate: needsUpdate);
  exit(exitCode);
}

int loadApplicationView(Map<String,dynamic> metadata, MapEntry<String,dynamic>? selectedApplication){
  bool hasSelectedApplication = false;
  if (!metadata.containsKey("applications")) metadata["applications"] = {};
  Map<String,dynamic> applications = metadata["applications"];
  List applicationsValues = applications.entries.toList();
  int selectedIndex = 0;
  int index = 0;
  int listLength = applicationsValues.length;
  while (!hasSelectedApplication){
    for (MapEntry<String,dynamic> application in applicationsValues){
      index++;
      if ((selectedIndex+1) == index){
        console.setBackgroundColor(ConsoleColor.magenta);
        console.writeLine(">${application.value["name"]}");
        console.resetColorAttributes();
        console.writeLine();
      }
      else{
        console.writeLine(" ${application.value["name"]}");
        console.writeLine();
      }
    }
    Key resultKey  = console.readKey();
    if (resultKey.isControl){
      switch (resultKey.controlChar){
        case ControlCharacter.arrowUp:
          selectedIndex = (selectedIndex -1) % listLength;
          index = 0;
          console.clearScreen();
          break;
        case ControlCharacter.arrowDown:
          logger("ARROW DOWN");
          selectedIndex = (selectedIndex +1) % listLength;
          index = 0;
          console.clearScreen();
          break;
        case ControlCharacter.enter:
          loadApplication(metadata, selectedApplication, applicationsValues[selectedIndex].key);
          index = 0;
          return 0;
        case ControlCharacter.ctrlC:
          return 0;
        default:
          break;
      }
    }
  }
}

int loadApplication(Map<String,dynamic> metadata, MapEntry<String,dynamic>? selectedApplication, applicationID){
  logger(metadata);
  MapEntry<dynamic,dynamic> intermediate = metadata["applications"].entries.firstWhere((e) => e.key == applicationID);
  selectedApplication = MapEntry<String,dynamic>(intermediate.key as String, intermediate.value as Map<String,dynamic>);
  metadata["loadedApplication"] = {
    "id" : applicationID,
    "lastOpened" : dateFormat.format(DateTime.now()),
  };
  return 0;
}

int createApplication(Map<String,dynamic> metadata, String? argument,MapEntry<String,dynamic>? selectedApplication, YamlMap config){
  if (argument == null){
    print("Wrong usage : wmanager create <Application Name>");
    return -1;
  }
  if (!metadata.containsKey("applications")) metadata["applications"] = {};

  Map<dynamic,dynamic> applications = metadata["applications"];
  String applicationID = getApplicationID(metadata.keys.toList(),argument);
  String applicationName = argument;
  metadata["applications"][applicationID] = {
    "name" : applicationName,
    "creationDate" : dateFormat.format(DateTime.now())
  };
  YamlMap templates = getTemplateFiles(config);
  String applicationsPath = getApplicationsPath(config);
  if (!Directory(applicationsPath).existsSync()){
    Directory(applicationsPath).createSync(recursive: true);
  }
  Directory currentApplicationDir = Directory("$applicationsPath$applicationID");
  if (!currentApplicationDir.existsSync()){
    currentApplicationDir.createSync(recursive: true);
  }
  for (MapEntry<dynamic,dynamic> template in templates.entries){
    if (!template.value.containsKey("path") || !template.value.containsKey("name")){
      print("Error in config file, please check ${template.key} paths and name");
      return -1;
    }
    File originalTemplate = File("${template.value["path"]}${template.value["name"]}");
    if (!originalTemplate.existsSync()){
      print("Unable to find ${template.value["name"]} at path ${template.value["path"]}$slash${template.value["name"]}");
      return -1;
    }
    String applicationSpecificTemplateName = isAsset(template.value) ? template.value["name"] : getTemplateOutputFilename(template.value, applicationName);
    originalTemplate.copySync("${currentApplicationDir.path}$slash$applicationSpecificTemplateName");
  }
  loadApplication(metadata, selectedApplication, applicationID);
  return 0;
}

int exportApplication(Map<String,dynamic> metadata,YamlMap config ,MapEntry<String,dynamic>? selectedApplication){
  if (selectedApplication == null){
    print("No applications is loaded, try loading one with : wmanager load");
    return -1;
  }
  YamlMap templates = getTemplateFiles(config);

  for (var template in templates.entries){
    if (template.value.containsKey("is_asset") && template.value["is_asset"]){
      continue;
    }
    String exportCommand = getTemplateExportCommand(template.value);
    print("Exporting template : ${template.key}");
    bool undefinedVariable = false;
    String errorMessage = "";
    exportCommand = exportCommand.replaceAllMapped(variableRegex, (match){
      String varName = match.group(1)!;
      List<String> statement = varName.split(".");
      if (statement.length > 2 || statement.length < 2){
        undefinedVariable = true;
        errorMessage = "Syntax error";
        return "";
      }
      if (statement[0] != "self" && !config["template_files"].keys.contains(statement[0])){
        undefinedVariable = true;
        errorMessage = "Unable to find the referenced template - Please check export_command for ${template.key} in your conf.yaml file at $confFilePath";
      }
      YamlMap referencedTemplate = statement[0] == "self"  ? template.value : config["template_files"][statement[0]];
      String referencedFilename = getTemplateOutputFilename(referencedTemplate, selectedApplication.value["name"]);
      String referencedExportFilename = getTemplateExportFilename(referencedTemplate, selectedApplication.value["name"]);
      String templateFilePath = "${getApplicationsPath(config)}${selectedApplication.key}";
      switch (statement[1]){
        case "output_name":
          return referencedFilename;
        case "path":
          return templateFilePath;
        case "export_name":
          return referencedExportFilename;
        default:
          errorMessage = "Undefined variable name - Please check open_command for ${template.key} in your conf.yml file at $confFilePath";
          undefinedVariable = true;
          return "";
      }
    });
    logger("exportCommand is now ${exportCommand}");
    if (undefinedVariable){
      print(errorMessage);
      return -1;
    }

    List<String> args = parseCommand(exportCommand);
    String applicationPath = "${getApplicationsPath(config)}/${selectedApplication.key}";

    ProcessResult res = Process.runSync(args[0], args.sublist(1), workingDirectory: applicationPath);
    if (res.exitCode != 0){
      print("There was an error while exporting ${template.key}, details :\n${res.stderr}");
      return -1;
    }
    String templateExportFilename = getTemplateExportFilename(template.value, selectedApplication.value["name"]);
    File exportedFile = File("$applicationPath$slash$templateExportFilename");
    if (!exportedFile.existsSync()){
      print("The exported file cannot be found at ${applicationPath}, please check if your command produces a output file with name specified in your config.yml file");
      logger("Filename is ${exportedFile}");
      return -1;
    }
    String exportPath = getExportPath(config);
    logger("Now copying file to $exportPath$templateExportFilename");
    exportedFile.copySync("$exportPath$templateExportFilename");
  }
  return 0;
}

int openApplicationFile(Map<String,dynamic> metadata, YamlMap config, String? args, MapEntry<String,dynamic>? selectedApplication){
  if (args == null){
    print("Missing argument for open command, Usage : wmanager open <template_name>");
    return -1;
  }
  if (selectedApplication == null || !selectedApplication.value.containsKey("name")){
    print("No applications loaded at the moment, please load one with the wmanager load <application name>");
    return -1;
  }
  YamlMap templateInfo = getTemplateInfo(config, args);
  String command = getTemplateOpenCommand(templateInfo);
  bool undefinedVariable = false;


  String errorMessage = "";
  command = command.replaceAllMapped(variableRegex, (match){
    String varName = match.group(1)!;
    List<String> statement = varName.split(".");
    if (statement.length > 2 || statement.length < 2){
      undefinedVariable = true;
      errorMessage = "Syntax error";
      return "";
    }
    if (statement[0] != "self" && !config["template_files"].keys.contains(statement[0])){
      undefinedVariable = true;
      errorMessage = "Unable to find the referenced template - Please check open_command for $args in your conf.yaml file at $confFilePath";
    }
    YamlMap referencedTemplate = statement[0] == "self"  ? templateInfo : config["template_files"][statement[0]];
    logger("REFERENCED TEMPLATE -> $referencedTemplate");
    String referencedFilename = referencedTemplate.containsKey("is_asset") && referencedTemplate["is_asset"]
        ? referencedTemplate["name"] : getTemplateOutputFilename(referencedTemplate, selectedApplication.value["name"]);
    String templateFilePath = "${getApplicationsPath(config)}${selectedApplication.key}${slash}${referencedFilename}";
    switch (statement[1]){
      case "path":
        return templateFilePath;
      default:
        errorMessage = "Undefined variable name - Please check open_command for $args in your conf.yml file at $confFilePath";
        undefinedVariable = true;
        return "";
    }
  });
  if (undefinedVariable){
    print(errorMessage);
    return -1;
  }
  logger("Current command is ${command}");
  List<String> commandAndArgs = command.split(" ");
  ProcessResult res = Process.runSync(commandAndArgs[0], commandAndArgs.sublist(1));
  logger("DEBUG ONLY : ${res.stdout}");
  logger("\t ${res.stderr}");
  if (res.exitCode != 0){
    return -1;
  }
  return 0;
}

void dumpChanges(Map<String,dynamic> metadata, YamlMap config, String metadataPath, String configPath, {bool needsUpdate=true}){
  if (!needsUpdate){
    return;
  }
  File metadataFile = File(metadataPath);
  File configFile = File(configPath);
  if (!metadataFile.existsSync()){
    metadataFile.createSync(recursive: true);
  }

  String serializedMetadata = jsonEncode(metadata);
  metadataFile.writeAsStringSync(serializedMetadata);
  if (hasConfChanged){
    if (!configFile.existsSync()){
      configFile.createSync(recursive: true);
    }
    String serializedConfig = jsonEncode(config);
    metadataFile.writeAsStringSync(serializedConfig);
  }
}