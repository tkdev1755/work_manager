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
- Full flexibility over your workflow when importing your code

----

## **Quickstart**

```other
# create + load a new application called "Acme Corp Internship"
wmanager create "Acme Corp Internship"

# list and load an existing application interactively
wmanager load

# open the template named "resume" for the currently loaded application
wmanager open resume

# exports all the files associated to an application to the dedicated export folder
wmanager export
```
----
## **Installation**
  
- Either download a release or compile the project from scratch
- run the install.sh script provided in the archive
- Create your config file in your installation folder (~/work_manager/) by following the guide in the wiki
----

## **Configuration (conf.yml)**

All behavior is driven by a single conf.yml. Below is a minimal example; adapt it to your toolchain.

```other
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

paths:
  applications_path: "/Users/johnDoe/work_manager/applications/"
  export_path: "/Users/johnDoe/work_manager/jobExport/"
```


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

- `wmanager create "Application Name"`

  Creates a sanitized application folder under applications_path, copies templates & assets with their configured output_name, and loads this application.

- `wmanager load`

  Shows a list of existing applications and lets you choose one to mark as active.

- `wmanager open <templateKey>`

  Runs the template’s open_command (after variable substitution) for the active application.

- `wmanager export`

  For each template that is **not** an asset:

    1. Runs the configured export_command (e.g., compile the file).
    2. Copies `export_name` (or the expected export artifact) to `export_path`.

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

