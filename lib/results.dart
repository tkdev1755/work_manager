/// Result types shared between the CLI (text output) and the MCP server
/// (structured output). Business-logic functions in work_manager.dart return
/// these instead of printing directly, so both consumers work off the same
/// source of truth instead of the MCP server having to parse human-readable
/// text.
library;

/// Outcome of an operation that can either succeed with a value of type [T]
/// or fail with a human-readable error message.
sealed class OperationResult<T> {
  const OperationResult();
}

class Ok<T> extends OperationResult<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends OperationResult<T> {
  final String message;
  const Err(this.message);
}

/// A single template file that was copied into an application's folder.
class CreatedTemplateFile {
  final String templateKey;
  final String path;
  final bool isAsset;

  const CreatedTemplateFile({
    required this.templateKey,
    required this.path,
    required this.isAsset,
  });
}

class CreateApplicationResult {
  final String id;
  final String name;
  final String preset;
  final List<CreatedTemplateFile> files;

  const CreateApplicationResult({
    required this.id,
    required this.name,
    required this.preset,
    required this.files,
  });
}

/// A single template file that was exported and copied to the export folder.
class ExportedTemplateFile {
  final String templateKey;
  final String exportedPath;

  const ExportedTemplateFile({
    required this.templateKey,
    required this.exportedPath,
  });
}

class ExportResult {
  final String applicationId;
  final List<ExportedTemplateFile> exported;

  const ExportResult({
    required this.applicationId,
    required this.exported,
  });
}

/// Outcome of running a template's `open_command`.
class OpenResult {
  final String templateKey;
  final String command;

  const OpenResult({
    required this.templateKey,
    required this.command,
  });
}

class CurrentApplicationInfo {
  final String id;
  final String name;
  final String folder;
  final String? preset;

  const CurrentApplicationInfo({
    required this.id,
    required this.name,
    required this.folder,
    this.preset,
  });
}
