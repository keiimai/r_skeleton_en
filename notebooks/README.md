# notebooks/ — analysis notebooks

The folder for [Quarto](https://quarto.org/) `.qmd` files (rendering and outputs: below).

## Contents

| File | Contents |
|---|---|
| `_metadata.yml` | Shared Quarto settings (they apply to the `.qmd` files directly in this folder. The author is read from `_project_author.yml` (Quarto's [metadata includes](https://quarto.org/docs/projects/quarto-projects.html#metadata-includes)). Quarto's [per-directory metadata](https://quarto.org/docs/projects/quarto-projects.html#directory-metadata)) |
| `_project_author.yml` | The report's authors and affiliations (the project rewrites it) |
| `styles.css` | The look of the HTML (read by `_metadata.yml`) |

## How to render

Start R in the repository root, load the recording layer, then render (install Quarto in the environment).

```r
source("R/repro.R")
repro_render("notebooks/<name>.qmd")
repro_render("notebooks/<name>.qmd", params = c("name:value"))
```

In `params`, list `name:value` pairs. They override, for that render only, the defaults written under `params:` in the `.qmd` YAML (Quarto's [explanation of parameters](https://quarto.org/docs/computations/parameters.html)). Values changed with `params` are not recorded, so write values that affect results going into a paper in the config file.

Render notebooks one at a time (if you render two at once, the one that finishes first deletes Quarto's working folder `notebooks/.quarto/`, and the other may stop).

## Handling outputs

| Location | Output | git |
|---|---|---|
| `notebooks/` | `.qmd` (rendering with [Render] in RStudio also puts the HTML next to it) | Only `.qmd` and the files listed in Contents above are tracked (what is excluded: `.gitignore`) |
| `outputs/reports/<run_id>/` | HTML rendered by `repro_render()` (self-contained in one file). `run_id` is the same as the record of `repro_run()` inside the `.qmd` (its form: see [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) §2). It is also shown in the title banner of the HTML (with other ways of rendering, the banner says "shown when rendered with repro_render()") | Not tracked |

## Conventions

- Notebooks that are not wrapped in chunks that start and finish the record are for exploration and for reading results (the conditions for numbers that go into a paper: see [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) §4)
- Pass the data files the notebook reads and the `.qmd` itself to `inputs` of `repro_run()` (their SHA-256 is recorded)
- Several notebooks may read the same config file (the name part of the run ID and the `experiment_name` in the record: see [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) §2)
- Write paths from the repository root (the `setup` chunk sets the working folder to the root with knitr's [`root.dir`](https://yihui.org/knitr/options/))
- Put [`#| label: name`](https://quarto.org/docs/reference/cells/cells-knitr.html) at the top of each chunk (it is used for Quarto's cross-references to figures and tables, and as a marker in the render log. If you cross-reference a figure, start it with `fig-`)
- Insert recorded figures with [`knitr::include_graphics(file.path("..", path), rel_path = FALSE, error = FALSE)`](https://search.r-project.org/CRAN/refmans/knitr/html/include_graphics.html)
- Read received data in its original format, without converting it to CSV or similar
- How to write CSV files that people open: see [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) §4
- If you load packages with `library()`, also load [conflicted](https://conflicted.r-lib.org/), and right after `library()`, use [`conflicts_prefer()`](https://conflicted.r-lib.org/reference/conflicts_prefer.html) to decide which of two functions with the same name to use (otherwise, which function gets called depends on the loading order. Install `conflicted` in the environment)
- Formatting is set by `_metadata.yml` and `styles.css`, so do not write it in the `.qmd`
- Start headings with `#` (`_metadata.yml` numbers them with [`number-sections`](https://quarto.org/docs/output-formats/html-basics.html#section-numbering), so a `##` before the first `#` is numbered 0.1)
- While exploring, do not record (how to set it, and when records stay at `failed` or `running`: see [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) §2)
- In notebooks that keep a record, do not use knitr's cache (`execute: cache: true`, `#| cache: true`) (cached chunks do not run, so the record and outputs drift from the HTML; `repro_run()` stops it)

Write the `.qmd` in the following form (the flow of the record: see [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) §2). Keep the chunk name `setup` (when you run chunks by hand in RStudio, `root.dir` takes effect only in a chunk with this name; see the [R Markdown guide](https://bookdown.org/yihui/rmarkdown/notebook.html)). `setup` finds the repository root before sourcing (when you send chunks from VS Code, R runs in the repository root).

````markdown
```{r}
#| label: setup
root <- normalizePath(if (file.exists("R/repro.R")) "." else "..")
knitr::opts_knit$set(root.dir = root)
for (path in list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) source(path)
cfg <- repro_config_load(file.path(root, "configs/experiment/<config name>.yaml"))
repro_set_seed(cfg$seed)
```

```{r}
#| label: begin
state <- repro_run(cfg, inputs = c("data/raw/<received file>", "notebooks/<name>.qmd"))
```

```{r}
#| label: analysis
result <- my_analysis(cfg, state$run_id)
```

```{r}
#| label: finish
state$artifacts <- result$paths
state$ledger <- list(n_analysis = result$n)
repro_finish(state)
```
````
