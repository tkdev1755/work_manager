## 2.0.0

- Added a preset system: create different kinds of applications (student job, technical internship, full-time role, ...) from the same install via `wmanager create <name> --preset <name>`, managed with `wmanager preset list/add/remove`.
- Added `work_manager_mcp`, a companion MCP server so AI agents can drive work_manager through structured tool calls instead of parsing CLI output.
- Added a confirmation prompt before deleting an application from the `wmanager load` menu.
- Fixed several bugs in preset creation, including `preset add --from default` assuming a shared template folder instead of copying each template's own declared source file.

## 1.2.0

- Added better handling of applications when using the `wmanager load` command.

## 1.1.0

- Added the `current` command to see the info of the loaded application.

## 1.0.0

- Initial version.
