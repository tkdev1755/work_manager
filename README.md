# WorkManager

A command-line tool for automating your job application creation and export process

# **Work Manager (wmanager)**

**Work Manager** is a flexible command-line tool that automates the repetitive parts of applying for jobs or internships.

It creates application folders from your templates (CV, cover letter, assets), opens files with your preferred tools, and exports final artifacts ready to upload or print — all driven by a single conf.yml.

Focus on writing great applications; let wmanager handle the copying, naming and exporting.

----

## **Features**

- Create a new application folder from reusable templates.
- Load an application to operate on (so open / export act on the current application).
- Open any template with the command you configured (editor, word processor, previewer).
- Export files by running custom export commands (Typst, LaTeX, Pandoc, custom bash script, etc.) and copy results to a dedicated export folder.
- Full flexibility over your workflow when creating job applications

----

## **Quickstart**

```other
# create + load a new application called "Acme Corp Internship"
wmanager create "Acme Corp Internship"

# list and load an existing application interactively
wmanager load

# open the template named "resume" for the currently loaded application
wmanager open resume


# Shows the information about the loaded application
wmanager current

# exports all the files associated to an application to the dedicated export folder
wmanager export
```
----
## **Installation**
- Either download a release or compile the project from scratch (see the wiki for [Compiling the sources](https://github.com/tkdev1755/work_manager/wiki/Compiling-from-source))
- run the `install.sh` script provided in the archive from the github release (or in the buildAssets folder from the repo)
- Create your config file in your installation folder (~/work_manager/) by following the example file in docs/exampleConf.yml or reading [the guide in the wiki](https://github.com/tkdev1755/work_manager/wiki/Writing-a-conf.yml-file)
----

## **Configuration (conf.yml)**

All behavior is driven by a single conf.yml (schema version 1). Below is a minimal example; adapt it to your toolchain.

```other
version: 1
default_preset:
  template_files:
    resume:
      name: "CV.typ"
      path: "/Users/johnDoe/work_manager/templates/"
      output_name: "CV_${wname}.typ"
      export_name: "CV_${wname}.pdf"
      export_command: "typst compile ${self.path}/${self.output_name}"
      open_command: "open ${self.path}/${self.output_name}"

    cover_letter:
      name: "letter.md"
      path: "/Users/johnDoe/work_manager/templates/"
      output_name: "Letter_${wname}.md"
      export_name: "Letter_${wname}.pdf"
      export_command: "pandoc ${self.path}/${self.output_name} -o ${self.path}/${self.export_name}"
      open_command: "code ${self.path}/${self.output_name}"

    logo:
      name: "company_logo.png"
      path: "/Users/johnDoe/work_manager/templates/"
      is_asset: true

presets:
  student_job:
    path: "/Users/johnDoe/work_manager/presets/student_job/"

paths:
  applications_path: "/Users/johnDoe/work_manager/applications/"
  export_path: "/Users/johnDoe/work_manager/jobExport/"
```

A conf.yml written before presets existed (no `version` key) is auto-migrated the first time it's loaded - see `wmanager migrate`.

### **Presets**

A preset is an alternate set of templates for a different kind of application (student job, technical internship, full-time role, etc). Each entry under `presets` points to a folder containing that preset's own `template.yml`:

```other
# /Users/johnDoe/work_manager/presets/student_job/template.yml
template_files:
  resume:
    name: "CV_student.typ"
    output_name: "CV_${wname}.typ"
    export_name: "CV_${wname}.pdf"
    export_command: "typst compile ${self.path}/${self.output_name}"
    open_command: "open ${self.path}/${self.output_name}"
```

A preset's own template files live alongside its `template.yml`, which is why entries there have no `path` (unlike `default_preset`, whose templates each carry an absolute `path`). Manage presets with:

```other
wmanager preset list
wmanager preset add student_job "/Users/johnDoe/work_manager/presets/student_job" --from default
wmanager preset remove student_job
```

`--from default` copies each of `default_preset`'s template files into the new preset folder and strips their `path` field automatically. `--from <existing_preset>` copies that preset's folder wholesale instead. Without `--from`, an empty preset skeleton is created for you to fill in by hand.

To use a preset when creating an application: `wmanager create "Acme Inc" --preset student_job`. Omit `--preset` (or pass `--preset default`) to use the default preset.

### **Key concepts**

- **${wname}** — the application name (sanitized for filenames). Example: "Acme Incorporated » → "ACMEINC » (sanitization transforms spaces/accents to a filesystem-friendly form).
- **${self.<field>}** — reference the current template’s field (e.g. ${self.output_name}).
- **${<templateKey>.<field>}** — reference another template’s field.
- **is_asset: true** — file is copied with the application but excluded from export steps.
- **Use absolute paths** — prefer /full/path/... (tilde ~ expansion is not assumed). Trailing slashes on paths are recommended.
- **Commands are arbitrary shell commands** — open_command and export_command run in your shell environment with variables substituted. This enables maximum flexibility.

  You can check the docs/exampleConf.yml for an explanation of each field
----

## **Commands & behavior**

- `wmanager create "Application Name" [--preset <name>]`

  Creates a sanitized application folder under applications_path, copies templates & assets with their configured output_name, and loads this application. Uses the default preset unless `--preset <name>` is given.

- `wmanager load`

  Shows a list of existing applications and lets you choose one to mark as active.

- `wmanager open <templateKey>`

  Runs the template’s open_command (after variable substitution) for the active application.

- `wmanager export`

  For each template that is **not** an asset:

    1. Runs the configured export_command (e.g., compile the file).
    2. Copies `export_name` (or the expected export artifact) to `export_path`.

- `wmanager preset list`

  Lists all registered presets (excluding the default) with their names and paths.

- `wmanager preset add <name> <path> [--from <existing_preset>]`

  Adds a new preset.  If `--from` is provided, copies all files (template files + template.yml) from the existing preset into the new preset's folder, then registers the new preset in conf.yml.

- `wmanager preset remove <name>`

  Removes a preset by deleting its folder and unregistering it from conf.yml.

- `wmanager migrate`

  Migrates an old-format conf.yml (without `version`, `default_preset`, or `presets` keys) to the latest schema.  Creates a backup before modifying the original file.

- `wmanager current`

  Shows the info on the current loaded application
- 
----

## **Typical workflow**

1. Create a new application:

```other
wmanager create "Acme Inc - SRE Internship"
```

1. Open the resume (or any configured template):

```other
wmanager open resume
```

1. Edit the files in your editor.
2. Export the application:

```other
wmanager export
```

1. Find ready-to-upload files in your configured export_path.

----

## **Example export command recipes**

These are short example commands you can adapt and paste into conf.yml:

- **Typst**

```other
export_command: "typst compile ${self.path}/${self.output_name}"
```

- **Pandoc (Markdown → PDF)**

```other
export_command: "pandoc ${self.path}/${self.output_name} -o ${self.path}/${self.export_name}"
```

- **LaTeX (pdflatex, run twice)**

```other
export_command: "pdflatex -interaction=nonstopmode -output-directory=${self.path} ${self.path}/${self.output_name} && pdflatex -interaction=nonstopmode -output-directory=${self.path} ${self.path}/${self.output_name}"
```

- **LibreOffice (convert .docx/.odt → PDF)**

```other
export_command: "libreoffice --headless --convert-to pdf --outdir ${self.path} ${self.path}/${self.output_name}"
```


> Note: Adjust quoting if your paths contain spaces. If an export command fails, run the same command manually to view error output.

----

## **Tips & troubleshooting**

- Use absolute paths in conf.yml.
- Test open_command and export_command manually from the shell to ensure they work.
- If exports don’t appear in export_path, check the export_name and whether the export command actually produces that filename.
- Use is_asset: true for logos, images, or reference configs that you don’t want in your exported package.
- When in doubt, simplify the command and ensure variable substitutions (like ${self.path}) resolve to correct absolute locations.

----

## **MCP Server**

`work_manager` ships a companion [Model Context Protocol](https://modelcontextprotocol.io) server (`work_manager_mcp`, built with the official [dart_mcp](https://pub.dev/packages/dart_mcp) SDK) so AI agents can drive the same create / open / export / preset workflow through structured tool calls instead of shelling out to the CLI and parsing text. It talks stdio, imports `package:work_manager` directly as a library, and resolves *where things live* rather than reading or writing template file contents itself - an agent uses its own file tools against the paths it returns.

### Running it

Like `work_manager` itself, `work_manager_mcp` resolves `conf.yml`/`metadata.json` relative to its own executable's location, so **the binary must sit in the same folder as your `conf.yml`** (typically `~/work_manager/`).

Declare it in your MCP client's config, e.g. for Claude Code / Claude Desktop:

```json
{
  "mcpServers": {
    "work_manager": {
      "command": "/Users/johnDoe/work_manager/work_manager_mcp"
    }
  }
}
```

### Tools

| Tool | Purpose |
| --- | --- |
| `list_presets` | List registered presets (name + path). |
| `get_preset_info` | Describe a preset's templates (key, file name, asset flag, open/export command presence). Pass `'default'` for the default preset. |
| `list_applications` | List every known application (id, name, creation date, preset). |
| `get_current_application` | Get the currently loaded application. |
| `create_application` | Create (and load) a new application, optionally from a specific preset. |
| `load_application` | Load an existing application by id. |
| `resolve_template_path` | Get the on-disk path of a template file for an application, to read/write with your own file tools. |
| `open_template` | Run a template's `open_command`. |
| `export_application` | Run every non-asset template's `export_command` and copy results to the export folder. |
| `add_preset` | Register a new preset, optionally copied from `'default'` or an existing preset. |
| `remove_preset` | Unregister a preset and delete its folder (irreversible). |

It also exposes a `workmanager://config-schema` resource documenting the `conf.yml` structure and the `${wname}` / `${self.<field>}` / `${<templateKey>.<field>}` variable system, so an agent that has never seen a work_manager config before can learn the model without it being explained in the prompt.

----

## **Roadmap (possible future features)**

- Shell completion scripts for bash / zsh.
- Packaged installers (Homebrew formula, macOS bundle).
- wmanager init to scaffold a starter conf.yml and sample templates.

----

## **Contributing**

Contributions and suggestions are welcome. Good first contributions:

- Improve README clarity or add troubleshooting examples.
- Add small scripts (e.g., Pages → PDF helper for macOS).

When opening a PR, please:

1. Provide a short description of the change.
2. Keep changes focused and well-documented.
3. Include tests or manual reproduction steps for non-trivial features.

