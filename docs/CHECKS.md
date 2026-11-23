# Pre-commit checks and lint

---

## 1. Pre-commit checks

`.githooks/pre-commit` checks the staged files before each commit, and stops the commit if there are problems (git's [githooks documentation](https://git-scm.com/docs/githooks)). Enable the hook once at the repository root each time you copy or clone the repository (if it is not enabled, nothing is stopped).

```bash
chmod +x .githooks/pre-commit
git config --local core.hooksPath .githooks
```

With git 2.54 or later, the following 2 lines apply the same checks to merge commits too ([git hook](https://git-scm.com/docs/git-hook)).

```bash
git config --local hook.precommit-checks.command .githooks/pre-commit
git config --local --replace-all hook.precommit-checks.event pre-merge-commit
```

To run the same checks on all tracked files, run `bash .githooks/pre-commit --all`.

The top 7 checks in the table run with bash and git only. The bottom 3 (`tools/precommit_checks.R`) run with the `Rscript` of the place where you commit (it starts with `--vanilla`, so it does not read `.Rprofile` or the renv library). If `Rscript` is not found, the bottom 3 are skipped with a note, and only problems from the top 7 stop the commit. The syntax of YAML and JSON is checked only when [yaml](https://yaml.r-lib.org/) and [jsonlite](https://cran.r-project.org/package=jsonlite) can be loaded.

| Check | What it stops |
|---|---|
| `renv.lock` is tracked | Commits that forgot to add `renv.lock` while it is at the root |
| Under `data/`, `outputs/`, `models/` | Data and outputs (`data/README.md` and `.gitkeep` pass) |
| `.env` | Files that hold secrets (`.env.example` passes) |
| Data formats outside `data/` | CSV, Excel, SPSS, Stata, SAS, RDS, Parquet, pickle, compressed files (zip, gz, tar and so on) and so on (`docs/definition/`, `configs/` and `tests/testthat/` pass) |
| Files that `.gitignore` excludes | Tracked files that `.gitignore` matches: files added with `git add -f`, and files tracked before a line was added to `.gitignore` (data formats in `docs/definition/`, `configs/` and `tests/testthat/` pass) |
| Names that differ only in case | Collisions between macOS or Windows and Linux |
| Conflict markers | Merges, cherry-picks and reverts finished with `<<<<<<<` and the like left in (`git rebase --continue` is not covered, because git does not call the hook) |
| Files over 2 MB, private keys, well-known tokens, values written to secret-looking names (in code, values inside quotes) | Secrets and data slipping in |
| Syntax of R, YAML (including `CITATION.cff`) and JSON, and files in `R/` other than `repro.R` calling `repro_run()`, `repro_finish()` or `repro_fail()` | Broken files, and analysis functions taking over the recording flow (see [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §2) |
| Trailing whitespace and final newline | Formatting drift (trailing whitespace in Markdown and tabular data is not checked; if the working tree matches the stage, it fixes the file and then stops, so `git add` again) |

---

## 2. Lint

`.lintr` sets the [lintr](https://lintr.r-lib.org/) rules (lines up to 100 characters, snake_case names, and stopping CSV writers that add no BOM (`write.csv()`, `readr::write_csv()` and so on; see [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §4)). Run lint with R at the repository root.

```r
lintr::lint_dir(".")
```
