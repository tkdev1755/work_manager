import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:uuid/v6.dart';
import 'package:work_manager/extensions.dart';
import 'package:work_manager/migration.dart' as migration;
import 'package:work_manager/presets.dart' as presets;
import 'package:yaml/yaml.dart';
import 'package:dart_console/dart_console.dart';


/// Structure of the NEW conf.yml file (version 1):
/*
  version: 1
  default_preset:
    template_files:
      cv:
        name: "ATSCV.typ"
        path: "/Users/tahakhetib/workManager/templates/"  ← hardcoded absolute path
        output_name: "CV_${wname}_2025.typ"
        ...
  presets:
    designPreset:
      path: "/Users/tahakhetib/workManager/templates/designPreset"
  paths:
    applications_path: "/Users/tahakhetib/workManager/applications/"
    export_path: "/Users/tahakhetib/workManager/JobExport/"
 */
/// End of the structure of the NEW conf.yml file

/// Variable to separate slashes from windows and unix platforms
String slash = Platform.isWindows ? "\\":"/";
/// Debug variable to enable specific functionalities
bool DEBUG = bool.fromEnvironment('DEBUG', defaultValue: false);
/// Debug filepath for the config file for testing
String debugConfFilePath = DEBUG ? String.fromEnvironment("confPath", defaultValue: "") : "";
/// Debug filepath for the metadata file
String debugDbFilePath = DEBUG ? String.fromEnvironment("dbPath", defaultValue: "") : "";
/// Variable which contains the filepath of the config file
String confFilePath = getConfFilePath();
/// Variable which contains the filepath of the metadata file (json file)
String dbFilePath = getDBFilePath();
/// Variable which contains the directory of the config file (used for preset paths)
String get confDirPath {
  List<String> execPath = Platform.resolvedExecutable.split(slash);
  execPath.removeLast();
  return execPath.join(slash);
}
/// DateFormat object to either parse or format dates in the program
DateFormat dateFormat = DateFormat("dd/MM/yyyy-HH:mm");
/// Bool which indicates if the config file needs updating one the disk
bool hasConfChanged = false;
/// Console object for writing and clearing the screen
Console console = Console();
/// Regex which detects ${} patterns in a string
RegExp variableRegex = RegExp(r'\$\{([^}]+)\}');

/// Function which return the Metadata file path according to the current config the program is being executed in (debug mode or normal mode)
///
/// Returns a string representing the metadata file path
String getDBFilePath(){
  List<String> execPath = Platform.resolvedExecutable.split(slash);
  execPath.removeLast();
  String directory = execPath.join(slash);
  String nonDebugFilePath =  "$directory${slash}metadata.json";
  return DEBUG ? debugDbFilePath : nonDebugFilePath;
}

/// Function which return the Config file path according to the current config the program is being executed in (debug mode or normal mode)
///
/// Returns a string representing the config file path
String getConfFilePath(){
  List<String> execPath = Platform.resolvedExecutable.split(slash);
  execPath.removeLast();
  String directory = execPath.join(slash);
  String nonDebugFilePath =  "$directory${slash}conf.yml";
  return DEBUG ? debugConfFilePath : nonDebugFilePath;
}

/// Loads the config file from the disk into a YamlMap object using the migration system.
///
/// If the file does not exist, creates it and returns an empty YamlMap.
/// If the file exists but has an unsupported version, throws a [StateError]
/// directing the user to run the `migrate` command.
///
/// Returns a YamlMap representing the "deserialized" config file.
YamlMap loadConfFile(){
  File confFile = File(confFilePath);
  if (!confFile.existsSync()){
    logger("FILE IS CREATED");
    confFile.createSync(recursive: true);
    return YamlMap();
  }
  return migration.parseConfFile(confFilePath);
}

/// Loads the metadata file from the disk into a Map&ltString,dynamic&gt object
///
/// Returns a YamlMap representing the "deserialized" metadata file
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

/// Function which returns the currently loaded application according to the content of the "loadedApplication" key in the metadata file
///
/// Takes a Map representing the metadata file
///
/// Returns a Map in case a application is loaded and was opened in the last 2 days, null otherwise
MapEntry<String,dynamic>? getLoadedApplication(Map<String,dynamic> metadata){
  if (metadata.containsKey("loadedApplication") && metadata["loadedApplication"].containsKey("lastOpened") && metadata["loadedApplication"].containsKey("id")){
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

/// Function which parses the config file and returns the application_path value
///
/// Takes a YamlMap representing the config file
///
/// Returns a String containing the path of where the applications should be saved
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

/// Function which parses the config file and returns the export_path value
///
/// Takes a YamlMap representing the config file
///
/// Returns a String containing the path of where the applications should be exported
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

/// Function which parses the config file and returns all of the registered templates in the DEFAULT preset.
///
/// Takes a YamlMap representing the config file.
///
/// Returns a YamlMap object which is a dictionary containing all templates from the default preset.
YamlMap getDefaultTemplateFiles(YamlMap configFile){
  if (!configFile.containsKey("default_preset")){
    throw Exception("No default_preset was specified in the configuration file");
  }
  YamlMap defaultPreset = configFile["default_preset"];
  if (!defaultPreset.containsKey("template_files")){
    throw Exception("No template_files was specified in the default_preset");
  }
  return defaultPreset["template_files"];
}

/// Parses the templates YamlMap and returns the specific info of a requested template.
///
/// Takes a YamlMap representing the configured templates and a String which represents the name of the template.
///
/// Returns a YamlMap object which is the dictionary of a configured template.
YamlMap getTemplateInfo(YamlMap templateFiles, String templateName){

  if (!(templateFiles.containsKey(templateName))){
    throw Exception("The searched template doesn't exist");
  }
  return templateFiles[templateName];
}

/// Function which parses a specific template and returns the open_command value
///
/// Takes a YamlMap representing a configured template
///
/// Returns a String representing the command to execute when calling "wmanager open templateName"
String getTemplateOpenCommand(YamlMap template){
  if (!template.containsKey("open_command")){
    if (!template.containsKey("path")) throw Exception("The following template doesn't have a path");
    return "open ${template["path"]}" ;
  }
  return template["open_command"];
}

/// Function which parses a specific template and returns the export_command value
///
/// Takes a YamlMap representing a configured template
///
/// Returns a String representing the command to execute when calling "wmanager export"
String getTemplateExportCommand(YamlMap template){
  if (!template.containsKey("export_command")) throw Exception("The following template doesn't have an export command");
  return template["export_command"];
}

/// Function which parses a specific template and returns the output_name value
///
/// Takes a YamlMap representing a configured template
///
/// Returns a String representing the output_name when copying the template files to a specific application folder
String getTemplateOutputName(YamlMap template){
  if (!template.containsKey("output_name")) throw Exception("The following template doesn't have an output_name command");
  return template["output_name"];
}
/// Function which parses a specific template and returns the export_name value
///
/// Takes a YamlMap representing a configured template
///
/// Returns a String representing the export_name when exporting the template files to the export folder
String getTemplateExportName(YamlMap template){
  if (!template.containsKey("export_name")) throw Exception("The following template doesn't have an output_name command");
  return template["export_name"];
}

/// Function which parses a specific template and returns the is_asset value
///
/// Takes a YamlMap representing a configured template
///
/// Returns a bool representing if the selected template is an asset or not
bool isAsset(YamlMap template){
  if (!template.containsKey("is_asset")){
    return false;
  }
  return template["is_asset"];
}

/// Function which creates a new application ID for a new application
///
/// Takes a list of String representing the existing ID and the application name entered by the user
///
/// Returns a String representing the ID of the application
String getApplicationID(List<String> ids, String applicationName){
  bool hasFoundID = false;
  String selectedID = "";
  while (!hasFoundID){
    selectedID = "CA-${applicationName.toUpperCase().substring(0, 2)}${UuidV6().generate().substring(0,10)}";
    if (!ids.contains(selectedID)) hasFoundID = true;
  }
  return selectedID;
}

/// Function which return the ${wname} of the application
///
/// Takes a String which is the name of the application
///
/// Returns a String representing the filesystem friendly name of the application
String getApplicationFilename(String name){
  return name.toUpperCase().replaceAll(" ", "");
}

/// Function which parses a specific template and returns its name for a specific application
///
/// Takes a YamlMap representing a configured template and the application name
///
/// Returns a String reprsenting the adapted filename of the template for a specific application
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



String getCurrentApplicationName(Map<String,dynamic> metadata, MapEntry<String,dynamic> loadedApplication){
  print(loadedApplication);
  String applicationName = loadedApplication.value["name"];
  return applicationName;
}

/// Function which parses a specific template and returns its export name for a specific application
///
/// Takes a YamlMap representing a configured template and the application name
///
/// Returns a String reprsenting the adapted export filename of the template for a specific application
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

/// Parses command-line arguments to extract the preset name for the `create` command.
///
/// Returns the preset name, or `null` if no `--preset` / `-p` flag was provided.
String? parsePresetArg(List<String> arguments){
  for (int i = 0; i < arguments.length; i++) {
    if ((arguments[i] == '--preset' || arguments[i] == '-p') && i + 1 < arguments.length) {
      return arguments[i + 1];
    }
  }
  return null;
}

/// Parses command-line arguments to extract the `--from` flag value (used by `preset add`).
///
/// Returns the source preset name, or `null` if not provided.
String? parseFromArg(List<String> arguments) {
  for (int i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--from' && i + 1 < arguments.length) {
      return arguments[i + 1];
    }
  }
  return null;
}

/// Main function of the program
///
/// Takes a List of string representing the arguments
void main(List<String> arguments){

  /// Constants for input arguments
  const String loadCommand = "load";
  const String createCommand = "create";
  const String openCommand = "open";
  const String exportCommand = "export";
  const String currentCommand = "current";
  const String helpCommand = "-h";
  const String presetCommand = "preset";
  const String migrateCommand = "migrate";
  /// Config file in a YamlMap object
  YamlMap confFile = loadConfFile();
  // Loading the metadata file from disk
  Map<String,dynamic> metadataFile =  loadMetdataFile();
  // Getting the loaded application
  MapEntry<String,dynamic>? selectedApplication = getLoadedApplication(metadataFile);
  // Checking if the tool was called correctly with the right arguments
  if (arguments.isEmpty){
    print("Usage : wmanager <command> <arguments>");
    exit(-1);
  }
  String command = arguments[0];
  // Exit code for returning the right exit status to the parent program
  int exitCode = -1;
  // Variable to keep track of the metadata file update on disk
  bool needsUpdate = true;
  // Switch case based on the command passed by the user
  switch (command){
    case helpCommand:
      print("""List of commands for wmanager
-h                        Displays available commands
create <name> [--preset <name>]  Creates a new job application (optionally from a preset)
open <template>           Opens a specific file linked to an application
export                    Exports the application
current                   Shows the currently loaded application
load                      Interactively selects and loads an application
preset list               Lists all registered presets
preset add <name> <path>  Adds a new preset (optionally --from <existing_preset>)
preset remove <name>      Removes a preset
migrate                   Migrates an old conf.yml to the latest schema""");
      needsUpdate = false;
      exitCode = 0;
    case loadCommand:
      exitCode = loadApplicationView(metadataFile, selectedApplication,confFile);
      needsUpdate = exitCode == 0;
      break;
    case openCommand:
      exitCode = openApplicationFile(metadataFile,confFile,argsFrom(arguments),selectedApplication);
      needsUpdate = false;
      break;
    case createCommand:
      String? presetName = parsePresetArg(arguments);
      exitCode = createApplication(metadataFile, argsFrom(arguments), selectedApplication, confFile, presetName);
      needsUpdate = exitCode == 0;
      break;
    case exportCommand:
      exitCode = exportApplication(metadataFile,confFile,selectedApplication);
      needsUpdate = false;
      break;
    case currentCommand:
      exitCode = currentApplication(metadataFile, confFile, selectedApplication);
      needsUpdate = false;
      break;
    case presetCommand:
      // Sub-commands for preset management
      if (arguments.length < 2) {
        print("Usage: wmanager preset <subcommand> [args]");
        print("Subcommands: list, add <name> <path> [--from <preset>], remove <name>");
        needsUpdate = false;
        exit(-1);
      }
      String subCommand = arguments[1];
      switch (subCommand) {
        case 'list':
          presets.presetListCommand(confFile);
          needsUpdate = false;
          exitCode = 0;
          break;
        case 'add':
          if (arguments.length < 4) {
            print("Usage: wmanager preset add <name> <path> [--from <existing_preset>]");
            needsUpdate = false;
            exitCode = -1;
            break;
          }
          String presetName = arguments[2];
          String presetPath = arguments[3];
          String? fromPreset = parseFromArg(arguments);
          presets.presetAddCommand(confFile, presetName, presetPath, fromPresetName: fromPreset);
          needsUpdate = false;
          exitCode = 0;
          break;
        case 'remove':
          if (arguments.length < 3) {
            print("Usage: wmanager preset remove <name>");
            needsUpdate = false;
            exitCode = -1;
            break;
          }
          String removePresetName = arguments[2];
          presets.presetRemoveCommand(confFile, removePresetName);
          needsUpdate = false;
          exitCode = 0;
          break;
        default:
          print("Unknown preset subcommand: $subCommand");
          print("Subcommands: list, add, remove");
          needsUpdate = false;
          exitCode = -1;
          break;
      }
      break;
    case migrateCommand:
      migration.runMigration(confFilePath);
      needsUpdate = false;
      exitCode = 0;
      break;
    default:
      print("Wrong command, type wmanager -h to see available commands");
      needsUpdate = false;
      exit(-1);
  }
  // Writing changes on disk for the metadata file and config file, changed only if needsUpdate is set to true
  dumpChanges(metadataFile, confFile, dbFilePath, confFilePath,needsUpdate: needsUpdate);
  exit(exitCode);
}

/// Extracts the application name argument from the arguments list,
/// skipping any preset flags and the preset value.
String? argsFrom(List<String> arguments) {
  // Find the first non-flag argument (the application name), skipping over
  // `--preset`/`-p` and the value that follows it wherever they appear.
  for (int i = 1; i < arguments.length; i++) {
    if (arguments[i] == '--preset' || arguments[i] == '-p') {
      i++;
      continue;
    }
    return arguments[i];
  }
  return null;
}

/// Function which deletes a specific application
///
/// Takes a String representing the application Id, the application directory and Map representing the metadata file
///
/// Returns an integer representing the status of the operation,0 if the deletion was successful, -1 if not
int deleteApplication(String applicationID, String applicationsDirectory,Map<String,dynamic> metadata){
  Directory applicationDirectory = Directory("$applicationsDirectory$slash$applicationID");
  if (!applicationDirectory.existsSync()){
    print("Application directory doesn't seems to exist");
    return -1;
  }
  try {
    applicationDirectory.deleteSync(recursive: true);
  }
  on FileSystemException catch (e){
    print("Unable to delete the folder because of the following error : ${e.osError} - ${e.message}");
    return -1;
  }
  if (!metadata.containsKey("applications")){
    print("No applications were created");
    return -1;
  }
  if (!metadata["applications"].containsKey(applicationID)){
    print("This application doesn't exist in the metadata file");
    return -1;
  }
  if (metadata.containsKey("loadedApplication")){
    if (metadata["loadedApplication"]?["id"] ==  applicationID){
      metadata.remove("loadedApplication");
    }
  }
  metadata["applications"].remove(applicationID);
  return 0;
}

/// Function which displays the list of created applications to select
///
/// Takes a Map representing the metadata file, the loaded application and the config file
///
/// Returns an int based on the result of the operation, 0 if everything went well, -1 if not
int loadApplicationView(Map<String,dynamic> metadata, MapEntry<String,dynamic>? selectedApplication, YamlMap config){
  bool hasSelectedApplication = false;
  if (!metadata.containsKey("applications")) metadata["applications"] = {};
  Map<String,dynamic> applications = metadata["applications"];
  List applicationsValues = applications.entries.toList();
  int selectedIndex = 0;
  int scrollOffset = 0;
  int listLength = applicationsValues.length;
  final int windowHeight = console.windowHeight;
  final int visibleItemCount = windowHeight - 2;

  while (!hasSelectedApplication){
    console.clearScreen();
    for (int i = 0; i < visibleItemCount && (scrollOffset + i) < listLength; i++) {
      int index = scrollOffset + i;
      MapEntry<String,dynamic> application = applicationsValues[index];
      if (index == selectedIndex){
        console.setBackgroundColor(ConsoleColor.blue);
        console.writeLine(">${application.value["name"]} (Press r to delete)");
        console.resetColorAttributes();
      }
      else{
        console.writeLine(" ${application.value["name"]}");
      }
    }
    console.writeLine();

    Key resultKey  = console.readKey();
    if (resultKey.isControl){
      switch (resultKey.controlChar){
        case ControlCharacter.arrowUp:
          if (selectedIndex > 0) {
            selectedIndex--;
            if (selectedIndex < scrollOffset) {
              scrollOffset = selectedIndex;
            }
          } else {
            selectedIndex = listLength - 1;
            scrollOffset = listLength > visibleItemCount ? listLength - visibleItemCount : 0;
          }
          break;
        case ControlCharacter.arrowDown:
          if (selectedIndex < listLength - 1) {
            selectedIndex++;
            if (selectedIndex >= scrollOffset + visibleItemCount) {
              scrollOffset = selectedIndex - visibleItemCount + 1;
            }
          } else {
            selectedIndex = 0;
            scrollOffset = 0;
          }
          break;
        case ControlCharacter.enter:
          loadApplication(metadata, selectedApplication, applicationsValues[selectedIndex].key);
          return 0;
        case ControlCharacter.ctrlC:
          return 0;
        default:
          break;
      }
    }
    else{
      switch (resultKey.char){
        case "r":
          print("Deleting application");
          int statusCode =  deleteApplication(applicationsValues[selectedIndex].key,getApplicationsPath(config),metadata);
          return statusCode;
        default:
          break;
      }
    }
  }
}

/// Function which loads a specific application and updates the metadata file
///
/// Takes a Map representing the metadata file, a Map representing the loaded application and a YamlMap object representing the config file
///
/// Returns an int based on the result of the operation, 0 if everything went well, -1 if not
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

/// Function which creates an application following passed by the user
///
/// Takes a Map representing the metadata file, a Map representing the loaded application and a YamlMap object representing the config file
///
/// Returns an int based on the result of the operation, 0 if everything went well, -1 if not
int createApplication(Map<String,dynamic> metadata, String? argument,MapEntry<String,dynamic>? selectedApplication, YamlMap config, [String? presetName]){
  if (argument == null){
    print("Wrong usage : wmanager create <Application Name> [--preset <preset_name>]");
    return -1;
  }
  if (!metadata.containsKey("applications")) metadata["applications"] = {};

  String applicationID = getApplicationID(metadata.keys.toList(),argument);
  String applicationName = argument;

  // Determine which preset to use.
  String effectivePreset;
  YamlMap templates;
  String? presetFolderPath;
  String applicationsPath = getApplicationsPath(config);

  if (presetName != null && presetName != 'default') {
    // A specific preset was requested.
    presetFolderPath = presets.getPresetPath(config, presetName);
    if (presetFolderPath == null) {
      print("Error: Preset '$presetName' not found in conf.yml.");
      return -1;
    }

    presets.PresetConfig presetConfig;
    try {
      presetConfig = presets.loadPresetConfig(presetName, presetFolderPath);
    } catch (e) {
      print("Error loading preset '$presetName': $e");
      return -1;
    }

    effectivePreset = presetName;
    templates = presetConfig.templateFiles;
  } else {
    // No preset specified, or explicitly "default" → use the default preset.
    effectivePreset = 'default';
    templates = getDefaultTemplateFiles(config);
  }

  metadata["applications"][applicationID] = {
    "name" : applicationName,
    "creationDate" : dateFormat.format(DateTime.now()),
    "preset" : effectivePreset,  // Store which preset was used
  };

  if (!Directory(applicationsPath).existsSync()){
    Directory(applicationsPath).createSync(recursive: true);
  }
  Directory currentApplicationDir = Directory("$applicationsPath$applicationID");
  if (!currentApplicationDir.existsSync()){
    currentApplicationDir.createSync(recursive: true);
  }

  for (MapEntry<dynamic,dynamic> template in templates.entries){
    YamlMap templateInfo = template.value as YamlMap;
    if (!templateInfo.containsKey("name")){
      print("Error in config file, please check ${template.key} paths and name");
      return -1;
    }
    // For the default preset, templates have hardcoded absolute paths.
    // For other presets, templates don't have a path key (assumed to be in the preset folder).
    String templatePath;
    if (templateInfo.containsKey("path")) {
      templatePath = templateInfo["path"].toString();
    } else if (presetFolderPath != null) {
      templatePath = presetFolderPath;
    } else {
      print("Error: Could not resolve path for preset '$effectivePreset'.");
      return -1;
    }
    String templateName = templateInfo["name"].toString();
    File originalTemplate = File("${templatePath}$slash$templateName");
    if (!originalTemplate.existsSync()){
      print("Unable to find ${templateName} at path ${templatePath}$slash${templateName}");
      return -1;
    }
    String applicationSpecificTemplateName = isAsset(templateInfo) ? templateName : getTemplateOutputFilename(templateInfo, applicationName);
    originalTemplate.copySync("${currentApplicationDir.path}$slash$applicationSpecificTemplateName");
  }
  loadApplication(metadata, selectedApplication, applicationID);
  return 0;
}

/// Function which exports the loaded applications to the export_path
///
/// Takes a Map representing the metadata file, a Map representing the loaded application and a YamlMap object representing the config file
///
/// Returns an int based on the result of the operation, 0 if everything went well, -1 if not
int exportApplication(Map<String,dynamic> metadata,YamlMap config ,MapEntry<String,dynamic>? selectedApplication){
  if (selectedApplication == null){
    print("No applications is loaded, try loading one with : wmanager load");
    return -1;
  }

  // Look up the preset name from the application metadata.
  String presetName;
  if (selectedApplication.value.containsKey("preset") && selectedApplication.value["preset"] != null) {
    presetName = selectedApplication.value["preset"] as String;
  } else {
    // Fallback: no preset stored, use default (backward compatibility with old metadata).
    presetName = 'default';
  }

  YamlMap templates;
  if (presetName == 'default') {
    templates = getDefaultTemplateFiles(config);
  } else {
    // Load templates from the preset's template.yml.
    String? presetPath = presets.getPresetPath(config, presetName);
    if (presetPath == null) {
      print("Error: Preset '$presetName' referenced by this application not found in conf.yml.");
      return -1;
    }
    try {
      presets.PresetConfig presetConfig = presets.loadPresetConfig(presetName, presetPath);
      templates = presetConfig.templateFiles;
    } catch (e) {
      print("Error loading preset '$presetName' for export: $e");
      return -1;
    }
  }

  for (var template in templates.entries){
    YamlMap templateInfo = template.value as YamlMap;
    if (templateInfo.containsKey("is_asset") && templateInfo["is_asset"]){
      continue;
    }
    String exportCommand = getTemplateExportCommand(templateInfo);
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
      if (statement[0] != "self" && !templates.keys.contains(statement[0])){
        undefinedVariable = true;
        errorMessage = "Unable to find the referenced template - Please check export_command for ${template.key} in your preset's template.yml";
      }
      YamlMap referencedTemplate = statement[0] == "self"  ? templateInfo : templates[statement[0]];
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
          errorMessage = "Undefined variable name - Please check open_command for ${template.key}";
          undefinedVariable = true;
          return "";
      }
    });
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
    String templateExportFilename = getTemplateExportFilename(templateInfo, selectedApplication.value["name"]);
    File exportedFile = File("$applicationPath$slash$templateExportFilename");
    if (!exportedFile.existsSync()){
      print("The exported file cannot be found at $applicationPath, please check if your command produces a output file with the name specified in your config.yml file");
      logger("Filename is $exportedFile");
      return -1;
    }
    String exportPath = getExportPath(config);
    logger("Now copying file to $exportPath$templateExportFilename");
    exportedFile.copySync("$exportPath$templateExportFilename");
  }
  return 0;
}

/// Function which opens a specific template based on the user input
///
/// Takes a Map representing the metadata file, a YamlMap representing the config file, a String? which is the template name argument, and MapEntry<String,dynamic>? which is the selected application
///
/// Returns an int based on the result of the operation, 0 if everything went well, -1 if not
int openApplicationFile(Map<String,dynamic> metadata, YamlMap config, String? args, MapEntry<String,dynamic>? selectedApplication){
  if (args == null){
    print("Missing argument for open command, Usage : wmanager open <template_name>");
    return -1;
  }
  if (selectedApplication == null || !selectedApplication.value.containsKey("name")){
    print("No applications loaded at the moment, please load one with the command : \nwmanager load");
    return -1;
  }

  // Look up the preset name from the application metadata.
  String presetName;
  if (selectedApplication.value.containsKey("preset") && selectedApplication.value["preset"] != null) {
    presetName = selectedApplication.value["preset"] as String;
  } else {
    // Fallback: no preset stored, use default (backward compatibility with old metadata).
    presetName = 'default';
  }

  YamlMap templates;
  if (presetName == 'default') {
    templates = getDefaultTemplateFiles(config);
    print("Templates : ${templates}");
  } else {
    // Load templates from the preset's template.yml.
    String? presetPath = presets.getPresetPath(config, presetName);
    if (presetPath == null) {
      print("Error: Preset '$presetName' referenced by this application not found in conf.yml.");
      return -1;
    }
    try {
      presets.PresetConfig presetConfig = presets.loadPresetConfig(presetName, presetPath);
      templates = presetConfig.templateFiles;
    } catch (e) {
      print("Error loading preset '$presetName' for open: $e");
      return -1;
    }
  }

  try {
    YamlMap templateInfo = getTemplateInfo(templates, args);
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
      if (statement[0] != "self" && !templates.keys.contains(statement[0])){
        undefinedVariable = true;
        errorMessage = "Unable to find the referenced template - Please check open_command for $args in your preset's template.yml";
      }
      YamlMap referencedTemplate = statement[0] == "self"  ? templateInfo : templates[statement[0]];
      logger("REFERENCED TEMPLATE -> $referencedTemplate");
      String referencedFilename = referencedTemplate.containsKey("is_asset") && referencedTemplate["is_asset"]
          ? referencedTemplate["name"] : getTemplateOutputFilename(referencedTemplate, selectedApplication.value["name"]);
      String templateFilePath = "${getApplicationsPath(config)}${selectedApplication.key}$slash$referencedFilename";
      switch (statement[1]){
        case "path":
          return templateFilePath;
        default:
          errorMessage = "Undefined variable name - Please check open_command for $args";
          undefinedVariable = true;
          return "";
      }
    });
    if (undefinedVariable){
      print(errorMessage);
      return -1;
    }
    logger("Current command is $command");
    List<String> commandAndArgs = command.split(" ");
    ProcessResult res = Process.runSync(commandAndArgs[0], commandAndArgs.sublist(1));
    logger("DEBUG ONLY : ${res.stdout}");
    logger("\t ${res.stderr}");
    if (res.exitCode != 0){
      return -1;
    }
  }
  catch (e) {
    print("The searched template doesn't exists, linked error : ${e.toString()}");
    return -1;
  }
  return 0;
}

/// Function which displays the loaded application in the app
///
/// Takes a Map representing the metadata file, a YamlMap representing the config file and MapEntry<String,dynamic>? which is the selected application
///
/// Returns an int based on the result of the operation, 0 if everything went well, -1 if not
int currentApplication(Map<String,dynamic> metadata, YamlMap config, MapEntry<String,dynamic>? selectedApplication){
  if (selectedApplication == null){
    print("No applications loaded at the moment, please load one with the command : \nwmanager load");
    return -1;
  }
  String applicationPath = getApplicationsPath(config);
  String applicationName = getCurrentApplicationName(metadata, selectedApplication);
  String presetInfo = "";
  if (selectedApplication.value.containsKey("preset") && selectedApplication.value["preset"] != null) {
    presetInfo = " Preset : ${selectedApplication.value["preset"]}";
  }
  print("Current application info - \n  Name : $applicationName \n  Folder : $applicationPath$slash${selectedApplication.key}$presetInfo");
  return 0;
}

int analyzeApplication(Map<String,dynamic> metadata, YamlMap config, MapEntry<String,dynamic>? selectedApplication){
  return 0;
}

/// Function which dumps any changes made to the metadata file on the disk
///
/// Takes a Map representing the metadata file, a YamlMap representing the config file, paths to the metadata and config files, and a optional bool which represents if there is a need to write on the disk

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