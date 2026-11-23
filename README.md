# Framework for R analysis projects

A template for starting research projects: the directory structure, the license, record templates, and a reproducibility recording layer. It has no runtime environment and does not depend on the R version. Prepare the environment outside this template.

> **It contains neither analysis code nor anything that builds a runtime environment (Docker, package pinning and so on).**
>
> **In a project started from this template, rewrite this file into an overview of the project.**

## How to use

| When | What to do |
|---|---|
| Starting a project | Copy this folder, run `git init`, and rewrite `README.md`, `CITATION.cff`, `CHANGELOG.md` and `notebooks/_project_author.yml` for the project. Create `.env` with `Rscript setup.R` and decide the time zone `TZ` of the records (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) §2). Enable the pre-commit checks (see [`docs/CHECKS.md`](docs/CHECKS.md) §1; also after cloning) |
| Preparing the environment | Prepare it outside this template, and install the packages the recording layer uses (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) §5). Write the environment you used in `CHANGELOG.md` (see "Records" below) |
| Analyzing | Write functions in `R/`, their tests in `tests/`, notebooks (`.qmd`) in `notebooks/` and configs in `configs/` (how to write them: see [`notebooks/README.md`](notebooks/README.md)) |
| Producing results | Commit first, then in R at the repository root run `source("R/repro.R"); repro_render("notebooks/<name>.qmd")`. The HTML goes to `outputs/reports/<run ID>/` |
| If folders are missing | `Rscript setup.R` (creates only the missing folders and `.env`) |
| Checking the recording layer | `testthat::test_dir("tests/testthat")` (tests) and `source("R/repro.R"); repro_smoke()` (one pass through the recording layer) |
| Linting | In R at the repository root, `lintr::lint_dir(".")` (rules: see [`docs/CHECKS.md`](docs/CHECKS.md) §2) |

## Contents

```
configs/          configs (experiment conditions and so on)
data/             raw / raw/dummy / interim / processed / external   ← contents not tracked by Git
docs/definition/  variable definitions, code tables and so on (CSV files are tracked too)
models/           trained models and so on                           ← same as above
notebooks/        analysis entry points (.qmd) and the HTML format
outputs/          tables / figures / metrics / reports / repro       ← same as above
R/                the recording layer repro.R and analysis functions
tests/            tests of the recording layer and analysis functions
tools/            the body of the pre-commit checks
```

How to use the folders inside `data/`: see [`data/README.md`](data/README.md).

| File | Role |
|---|---|
| `README.md` | Overview of the project (rewrite it) |
| `CHANGELOG.md` | The record of decisions (see "Records" below) |
| `CITATION.cff` | Citation information ([Citation File Format](https://citation-file-format.github.io/)) |
| `LICENSE` | [MIT](https://opensource.org/license/mit) |
| `R/repro.R`, `tests/testthat/test-repro.R`, `helper-load.R` | The recording layer, its tests, and the helper that loads `R/` before the tests (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)) |
| `.Rprofile` | What R does at startup (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) §1) |
| `.githooks/pre-commit`, `tools/precommit_checks.R` | Pre-commit checks (stop data, outputs and secrets from slipping in; see [`docs/CHECKS.md`](docs/CHECKS.md) §1) |
| `.lintr` | Lint rules (see [`docs/CHECKS.md`](docs/CHECKS.md) §2) |
| `setup.R` | Creates the folders of the structure above, only those that are missing. Copies `.env.example` to `.env` if `.env` is missing |
| `.env.example` | An example of how to write `.env` (`setup.R` copies it to `.env`). The time zone of the records is decided by `TZ` in `.env` (not tracked by Git) (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) §2) |
| `notebooks/README.md`, `_metadata.yml`, `_project_author.yml`, `styles.css` | How to write notebooks, and the HTML format (see [`notebooks/README.md`](notebooks/README.md)) |
| `.gitignore` | Tracks only what people write ([`.gitignore` documentation](https://git-scm.com/docs/gitignore)). Excludes secrets (`.env`, keys), data, outputs and data formats (CSV, Excel, SPSS, Stata and so on; CSV files in `docs/definition/` are tracked). The `*.key` rule for keys also excludes Keynote slides, so export slides to PDF or similar before sharing them |
| `.editorconfig` | Rules for indentation, line endings and character encoding ([EditorConfig](https://editorconfig.org/)) |
| `.vscode/settings.json` | VS Code [workspace settings](https://code.visualstudio.com/docs/configure/settings#_workspace-settings) (stop the R extension from starting the language server or prompting you to install it) |

## Records

| What to keep | Where |
|---|---|
| What was changed | Git |
| Why it was changed, what was dropped, what the dummy data was made from | `CHANGELOG.md` |
| The environment used (where it was built, the R version, how package versions are pinned (renv, etc.)) | Top of `CHANGELOG.md` |
| The record of each run (commit, SHA-256 of inputs and outputs, environment, config, status) | `outputs/repro/<run ID>/` (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)) |
| The ledger of all runs | `outputs/repro/runs.csv` (rebuilt by `repro_runs()`) |
| Citation information | `CITATION.cff` |

The contents of `data/`, `outputs/` and `models/` are not tracked by Git (the pre-commit checks stop them).

## License and citation

- The code is under [MIT](https://opensource.org/license/mit) (`LICENSE`). A project that gives teaching materials such as instructions or videos to other people puts only those materials under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.en) (add `LICENSE-docs` at the root).
- What you use (R, the R packages, Quarto and so on) is not included in this template. It follows the terms of its own authors.
- To cite this template, use the information in `CITATION.cff`.

## Use of AI

The code and documentation were written with an AI coding assistant ([Claude Opus 5.5](https://www.anthropic.com/claude/opus) by Anthropic, used through [Claude Code](https://code.claude.com/docs/en/overview)) as a tool. The author directed the work and is responsible for the content (the AI is not an author).
