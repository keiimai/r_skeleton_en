# --- Tests of the recording layer (REPRODUCIBILITY.md §2) ---

# --- Fixing the random seed also restores sample.kind and normal.kind (REPRODUCIBILITY.md §2) ---
test_that("repro_set_seed fixes RNGkind down to sample.kind and normal.kind", {
  repro_set_seed(42L)
  first_sample <- sample.int(1000L, 5L)
  first_normal <- stats::rnorm(3L)
  suppressWarnings(RNGkind(sample.kind = "Rounding", normal.kind = "Box-Muller"))
  repro_set_seed(42L)
  expect_identical(sample.int(1000L, 5L), first_sample)
  expect_identical(stats::rnorm(3L), first_normal)
  expect_equal(RNGkind()[2], "Inversion")
})

# --- Environment snapshot: thread counts, time zone, locale and so on (REPRODUCIBILITY.md §2) ---
test_that("environment snapshot records determinism variables; renv.lock SHA-256 is NA if absent", {
  snapshot <- repro_environment_snapshot()
  expect_named(snapshot$env, c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                               "TZ", "LANG", "LC_ALL"))
  expect_true(is.na(snapshot$renv_lock_sha256))
  expect_length(snapshot$rng$kind, 3L)
  versions <- unlist(snapshot[c("r_version", "blas", "lapack", "lapack_version")])
  expect_length(Filter(nzchar, versions), 4L)
})

# --- Inside the image, the build record is included (REPRODUCIBILITY.md §2) ---
test_that("inside the image, the environment snapshot includes the build record as it is", {
  skip_if_not(file.exists("/opt/build-info.json"), "outside the image (no build record)")
  expect_identical(repro_environment_snapshot()$build_info,
                   jsonlite::read_json("/opt/build-info.json"))
})

# --- Missing keys take the defaults; unknown keys and nulls are kept (REPRODUCIBILITY.md §2) ---
test_that("missing keys get defaults; keys unknown to the recording layer or null are kept", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c("seed: 7", "analysis:", "  outcome: death", "  models: [a, b]",
               "repro:", "  quiet: null"), path)
  cfg <- repro_config_load(path)
  expect_equal(cfg[c("seed", "experiment_name")], list(seed = 7L, experiment_name = "default"))
  expect_equal(cfg$analysis, list(outcome = "death", models = c("a", "b")))
  expect_equal(cfg$repro, list(enabled = TRUE, quiet = NULL))
  writeLines("", path)
  expect_identical(repro_config_load(path), repro_config_defaults())
})

# --- A non-integer seed stops at load time (REPRODUCIBILITY.md §2) ---
test_that("a non-integer (or too large) seed stops at load time, and 42.0 is read as an integer", {
  path <- withr::local_tempfile(fileext = ".yaml")
  for (line in c("seed: 1.5", "seed: \"42\"", "seed: null", "seed: 3000000000.0")) {
    writeLines(line, path)
    expect_error(repro_config_load(path), ": set seed to an integer", fixed = TRUE, info = line)
  }
  writeLines("seed: 42.0", path)
  expect_identical(repro_config_load(path)$seed, 42L)
})

# --- Unquoted logical words stop as keys or values; the rest is read (REPRODUCIBILITY.md §4) ---
test_that("unquoted logical words stop; true/false, quoted, Japanese, 1.0e-6 read; 1e-6 warns", {
  path <- withr::local_tempfile(fileext = ".yaml")
  stops <- list("n: 5", c("analysis:", "  on: 1"), c("No: 1", "OFF: 2"),
                "yname: y", "flag: yes", "mode: Off", "answer: N")
  for (lines in stops) {
    writeLines(lines, path)
    expect_error(repro_read_yaml(path), ": unquoted \"", fixed = TRUE,
                 info = paste(lines, collapse = " / "))
  }
  writeLines(c("analysis:", "  True: 1"), path)
  expect_error(repro_read_yaml(path), "as keys: y, n, yes, no, on, off, true, false", fixed = TRUE)
  writeLines("a: [1, 2", path)
  expect_error(repro_read_yaml(path))
  writeLines(enc2utf8(c("yname: \"y\"", "on_off: true", "other: False", "\"n\": 5", "tol: 1.0e-6",
                        "label: 死亡")), path, useBytes = TRUE)
  expect_identical(repro_read_yaml(path), list(yname = "y", on_off = TRUE, other = FALSE, n = 5L,
                                               tol = 1e-6, label = enc2utf8("死亡")))
  writeLines(c("a: 1e-6", "b: \"2E3\""), path)
  expect_warning(read <- repro_read_yaml(path), "1e-6, 2E3 are text in YAML", fixed = TRUE)
  expect_identical(read, list(a = "1e-6", b = "2E3"))
})

# --- Make an empty project for tests in a temporary directory (REPRODUCIBILITY.md §2) ---
local_repro_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", .local_envir = env)
  withr::local_dir(root, .local_envir = env)
  cfg <- repro_config_defaults()
  cfg$experiment_name <- "unit"
  cfg$repro$quiet <- TRUE
  cfg
}

# --- One JSON, full at start; config reloads; missing input warns, null (REPRODUCIBILITY.md §2) ---
test_that("one JSON, full at start; config reloads; bad inputs warn or stop; quiet is silent", {
  cfg <- local_repro_project()
  expect_error(repro_run(cfg, inputs = "."), "one at a time, not folders", fixed = TRUE)
  cfg$analysis <- list(label = "死亡", models = c("a", "b"), alpha = 0.123456789012)
  input <- "input.csv"
  writeLines(c("a,b", "1,2"), input)
  expect_no_message(expect_warning(state <- repro_run(cfg, inputs = c(input, "missing.csv")),
                                   "missing.csv", fixed = TRUE))
  running <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  repro_finish(state)

  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_equal(c(running$status, payload$status), c("running", "success"))
  expect_equal(c(running$schema_version, payload$schema_version), c(1L, 1L))
  expect_equal(payload$inputs[[1]]$path, input)
  expect_equal(nchar(payload$inputs[[1]]$sha256), 64L)
  expect_null(payload$inputs[[2]]$sha256)
  expect_equal(payload[c("run_id", "data_mode", "seed", "git_commit", "git_dirty")],
               list(run_id = state$run_id, data_mode = "dummy", seed = 42L, git_commit = NULL,
                    git_dirty = NULL))
  stable <- c("run_id", "seed", "data_mode", "git_commit", "git_dirty", "inputs", "environment")
  expect_equal(running[stable], payload[stable])
  expect_null(running$finished_at)
  expect_match(payload$started_at, "[+-][0-9]{4}$")
  expect_match(payload$finished_at, "[+-][0-9]{4}$")
  expect_true(nzchar(payload$environment$r_version))
  expect_setequal(list.files("outputs/repro", recursive = TRUE),
                  file.path(state$run_id, paste0(state$run_id, c("_run.json", ".config.yaml"))))
  config <- file.path("outputs/repro", state$run_id, paste0(state$run_id, ".config.yaml"))
  expect_equal(c(running$config, payload$config), c(config, config))
  expect_identical(repro_config_load(config), cfg)
})

# --- Artifact SHA-256, size; missing ones warn, drop; unpassed unlisted (REPRODUCIBILITY.md §2) ---
test_that("artifacts keep SHA-256/size; missing warn, drop; unpassed unlisted; no run ID warns", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  output <- paste0("outputs/tables/", state$run_id, "_t.csv")
  writeLines(c("a,b", "1,2"), output)
  state$artifacts <- c(output, "outputs/tables/missing.csv", "outputs/tables")
  expect_warning(repro_finish(state), "outputs/tables/missing.csv, outputs/tables", fixed = TRUE)

  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_length(payload$inputs, 0L)
  expect_equal(payload$artifacts, list(list(
    path = output, sha256 = digest::digest(output, algo = "sha256", file = TRUE),
    bytes = file.info(output)$size
  )))
  expect_equal(suppressMessages(repro_runs())$n_artifacts, 1L)
  state$artifacts <- output
  expect_no_warning(repro_finish(state))
  state$artifacts <- "outputs/tables/t.csv"
  file.copy(output, state$artifacts)
  expect_warning(repro_finish(state), "do not have the run ID", fixed = TRUE)
})

# --- A failed render becomes failed; partial outputs move to partial/ (REPRODUCIBILITY.md §2) ---
test_that("a failed render becomes failed; only partial outputs with the run ID move to partial/", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  id <- state$run_id
  dir.create(file.path("outputs/figures", id))
  made <- c(paste0("outputs/tables/", id, "_t.csv"), file.path("outputs/figures", id, "a.txt"))
  for (file in c(made, "outputs/tables/other.csv")) writeLines("x", file)
  .repro_mark_failed(id)
  record <- jsonlite::read_json(state$meta_path)
  expect_identical(record$status, "failed")
  expect_match(record$error, "Moved 2 partial outputs to partial/", fixed = TRUE)
  partial <- file.path(dirname(state$meta_path), "partial")
  expect_true(all(file.exists(file.path(partial, sub("^outputs/", "", made)))))
  expect_true(file.exists("outputs/tables/other.csv"))
})

# --- A render failing after success becomes failed; else no change (REPRODUCIBILITY.md §2) ---
test_that("success becomes failed (finished_at kept); a 2nd call or unknown ID changes nothing", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  repro_finish(state)
  finished <- jsonlite::read_json(state$meta_path)$finished_at
  .repro_mark_failed(state$run_id)
  record <- jsonlite::read_json(state$meta_path)
  expect_identical(record[c("status", "error", "finished_at")],
                   list(status = "failed", error = "repro_render() failed (there is no HTML)",
                        finished_at = finished))
  before <- readLines(state$meta_path)
  .repro_mark_failed(state$run_id)
  expect_identical(readLines(state$meta_path), before)
  expect_null(.repro_mark_failed("no_such_run"))
})

# --- Numbers are written without rounding (REPRODUCIBILITY.md §2) ---
test_that("record and ledger numbers are not rounded, whether small or with many digits", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  state$ledger <- list(p_value = 1.2e-5, estimate = 4.37382441673398)
  repro_finish(state)
  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_equal(payload$ledger$estimate, 4.37382441673398)
  expect_equal(suppressMessages(repro_runs())$p_value, 1.2e-5)
})

# --- run_id (.qmd name in render); REPRO_RUN_ID never overwrites; TZ (REPRODUCIBILITY.md §2) ---
test_that("run_id <datetime>_<name>_<4 digits> keeps RNG, redraws if used; new REPRO_RUN_ID wins", {
  cfg <- local_repro_project()
  withr::local_envvar(REPRO_RUN_ID = NA)
  withr::local_envvar(TZ = NA)
  expect_match(.repro_timestamp(), "[+]0900$")
  repro_set_seed(42L)
  expected <- stats::runif(3L)
  repro_set_seed(42L)
  first <- repro_run(cfg)
  second <- repro_run(cfg)
  expect_identical(stats::runif(3L), expected)
  repro_finish(first)
  repro_finish(second)
  expect_match(first$run_id, "^[0-9]{8}_[0-9]{6}_unit_[0-9]{4}$")
  expect_false(identical(first$run_id, second$run_id))
  for (name in list(NULL, "", "a/b", c("a", "b"))) {
    expect_error(repro_run(modifyList(cfg, list(experiment_name = name), keep.null = TRUE)),
                 "a single name without /", fixed = TRUE)
  }
  expect_length(Sys.glob("outputs/repro/*/*_run.json"), 2L)
  writeLines(c("```{r}", "writeLines(repro_finish(repro_run(cfg))$run_id, 'id.txt')", "```"),
             "step_a.Rmd")
  knitr::knit("step_a.Rmd", quiet = TRUE, envir = environment())
  expect_match(readLines("id.txt"), "^[0-9]{8}_[0-9]{6}_step_a_[0-9]{4}$")
  withr::local_envvar(REPRO_RUN_ID = "given_run")
  state <- repro_run(cfg)
  repro_finish(state)
  expect_equal(state$run_id, "given_run")
  expect_true(file.exists("outputs/repro/given_run/given_run_run.json"))
  expect_error(repro_run(cfg), "A record for REPRO_RUN_ID=given_run already exists", fixed = TRUE)
  withr::local_envvar(REPRO_RUN_ID = "a/b")
  expect_error(repro_run(cfg), "REPRO_RUN_ID is used as the prefix of the record", fixed = TRUE)
  frozen <- as.POSIXct("2026-09-26 09:30:00", tz = "Asia/Tokyo")
  pid <- 0L
  list2env(list(Sys.time = function() frozen, Sys.getpid = function() pid <<- pid + 1L),
           globalenv())
  withr::defer(rm("Sys.time", "Sys.getpid", envir = globalenv()))
  dir.create("outputs/repro/20260926_093000_unit_0001")
  file.create("outputs/repro/20260926_093000_unit_0001/20260926_093000_unit_0001_run.json")
  expect_equal(.repro_new_run_id("unit", "outputs/repro"), "20260926_093000_unit_0002")
  withr::local_envvar(TZ = "UTC")
  expect_equal(.repro_timestamp(), "2026-09-26T00:30:00+0000")
  expect_equal(.repro_new_run_id("unit", "outputs/repro"), "20260926_003000_unit_0003")
  withr::local_envvar(TZ = "JST-9")
  expect_error(.repro_timestamp(), "TZ=JST-9 is not a time zone name", fixed = TRUE)
})

# --- Time zone: .env TZ, then env var TZ, then Asia/Tokyo (REPRODUCIBILITY.md §2) ---
test_that(".env TZ comes before env var TZ; empty means env var; neither means Asia/Tokyo", {
  local_repro_project()
  withr::local_envvar(TZ = "UTC")
  expect_equal(.repro_tz(), "UTC")
  writeLines(c("# note", "OMP_NUM_THREADS=1", "TZ = \"America/New_York\"  # keep it"), ".env")
  expect_equal(.repro_tz(), "America/New_York")
  expect_equal(repro_environment_snapshot()$env$TZ, "America/New_York")
  writeLines("TZ=", ".env")
  expect_equal(.repro_tz(), "UTC")
  withr::local_envvar(TZ = NA)
  expect_equal(.repro_tz(), "Asia/Tokyo")
  writeLines("TZ=JST-9", ".env")
  expect_error(.repro_timestamp(), "TZ=JST-9 is not a time zone name", fixed = TRUE)
})

# --- Using knitr's cache in a recording notebook stops without a record (notebooks/README.md) ---
test_that("using knitr's cache (globally or per chunk) makes repro_run stop without a record", {
  cfg <- local_repro_project()
  withr::defer(knitr::opts_chunk$set(cache = FALSE))
  heads <- list(c("```{r, include=FALSE}", "knitr::opts_chunk$set(cache = TRUE)", "```"),
                c("```{r first, cache=TRUE}", "x <- 1", "```"))
  for (head in heads) {
    writeLines(c(head, "```{r, error=FALSE, cache=FALSE}", "repro_run(cfg)", "```"), "cached.Rmd")
    expect_error(suppressMessages(knitr::knit("cached.Rmd", quiet = TRUE, envir = environment())),
                 "Do not use knitr's cache when recording", fixed = TRUE)
  }
  expect_false(dir.exists("outputs/repro"))
})

# --- Unless quiet, show the run ID and so on at the start and end (REPRODUCIBILITY.md §2) ---
test_that("unless quiet, repro_run shows the run ID and seed, and repro_finish shows the result", {
  cfg <- local_repro_project()
  cfg$repro$quiet <- FALSE
  expect_message(state <- repro_run(cfg), "data_mode=dummy seed=42", fixed = TRUE)
  expect_output(repro_finish(state), paste0(state$run_id, " (success)"), fixed = TRUE)
})

# --- Warn if the thread count is not 1 (REPRODUCIBILITY.md §4) ---
test_that("repro_run warns with names and values if a thread count is not 1, silent if all are 1", {
  cfg <- local_repro_project()
  expect_no_warning(repro_finish(repro_run(cfg)))
  withr::local_envvar(OMP_NUM_THREADS = "4", OPENBLAS_NUM_THREADS = NA)
  expect_warning(state <- repro_run(cfg),
                 "OMP_NUM_THREADS=4, OPENBLAS_NUM_THREADS=(unset)", fixed = TRUE)
  repro_finish(state)
})

# --- Hint if none; skip meta/; full ledger, fixed columns, BOM; running (REPRODUCIBILITY.md §3) ---
test_that("hint if empty; skips meta/; runs.csv whole, fixed columns, with BOM; unfinished count", {
  cfg <- local_repro_project()
  expect_output(suppressMessages(repro_runs(show = TRUE)), "No run records yet", fixed = TRUE)
  repro_finish(repro_run(cfg))
  cfg$experiment_name <- "other"
  repro_finish(repro_run(cfg))
  dir.create("outputs/repro/meta")
  file.copy(Sys.glob("outputs/repro/*/*_run.json"), "outputs/repro/meta")
  ledger <- repro_settings()$ledger_path
  read_ledger <- function() utils::read.csv(ledger, fileEncoding = "UTF-8-BOM")
  expect_equal(suppressMessages(repro_runs(experiment = "other"))$experiment, "other")
  expect_identical(readBin(ledger, "raw", 3L), as.raw(c(0xef, 0xbb, 0xbf)))
  expect_equal(nrow(read_ledger()), 2L)
  expect_named(read_ledger(),
               c("run_id", "status", "experiment", "data_mode", "seed", "started_at", "finished_at",
                 "git_commit", "git_dirty", "n_inputs", "n_artifacts", "error"))
  expect_equal(nrow(suppressMessages(repro_runs(limit = 1L))), 1L)
  expect_equal(nrow(read_ledger()), 2L)
  expect_equal(nrow(suppressMessages(repro_runs(experiment = "", limit = ""))), 2L)
  repro_run(cfg)
  expect_output(suppressMessages(repro_runs(show = TRUE)), "(status = running): 1", fixed = TRUE)
})

# --- Ledger newest first, 12-char commits; broken stops; empty tells (REPRODUCIBILITY.md §3) ---
test_that("ledger is newest first, git_commit 12 chars; broken record stops; empty filter tells", {
  cfg <- local_repro_project()
  old <- repro_run(cfg)
  repro_finish(old)
  new <- repro_run(cfg)
  repro_finish(new)
  record <- jsonlite::read_json(old$meta_path)
  record$started_at <- "2000-01-01T00:00:00+0900"
  record$git_commit <- strrep("a", 40L)
  jsonlite::write_json(record, old$meta_path, auto_unbox = TRUE, null = "null")
  table <- suppressMessages(repro_runs())
  expect_equal(table$run_id, c(new$run_id, old$run_id))
  expect_equal(table$git_commit[2], strrep("a", 12L))
  expect_output(suppressMessages(repro_runs(experiment = "none", show = TRUE)),
                "No run records for experiment none.", fixed = TRUE)
  dir.create("outputs/repro/broken")
  writeLines("{", "outputs/repro/broken/broken_run.json")
  expect_error(suppressMessages(repro_runs()), "broken_run.json cannot be read", fixed = TRUE)
})

# --- CSV as UTF-8 with a BOM; Japanese reads back; smoke output too (REPRODUCIBILITY.md §4) ---
test_that("repro_write_csv writes UTF-8 with a BOM, Japanese and NA read back; smoke output too", {
  local_repro_project()
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  table <- data.frame(label = c(enc2utf8("死亡"), "a,\"b\""), n = c(1L, NA))
  repro_write_csv(table, "t.csv", na = "")
  bytes <- readBin("t.csv", "raw", file.info("t.csv")$size)
  expect_identical(bytes[1:3], bom)
  expect_true(validUTF8(rawToChar(bytes[-(1:3)])))
  expect_equal(utils::read.csv("t.csv", fileEncoding = "UTF-8-BOM"), table)
  expect_output(suppressMessages(repro_smoke()), "_smoke.csv", fixed = TRUE)
  output <- Sys.glob("outputs/tables/*_smoke.csv")
  expect_length(output, 1L)
  expect_identical(readBin(output, "raw", 3L), bom)
  expect_named(utils::read.csv(output, fileEncoding = "UTF-8-BOM"), c("x", "y"))
})

# --- CSV writing refuses the fixed arguments and stops before writing (REPRODUCIBILITY.md §4) ---
test_that("repro_write_csv refuses sep, qmethod, row.names and append and creates no file", {
  local_repro_project()
  table <- data.frame(x = 1)
  expect_error(repro_write_csv(table, "t.csv", row.names = TRUE), "does not accept row.names")
  expect_error(repro_write_csv(table, "t.csv", sep = ";", append = TRUE), "not accept sep, append")
  expect_false(file.exists("t.csv"))
})

# --- Failures stay in ledger (condition or string); common columns win (REPRODUCIBILITY.md §3) ---
test_that("failed runs stay in ledger as status=failed (condition or string); common columns win", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  state$ledger <- list(status = "looks fine", n_analysis = 3L, models = c("a", "b"))
  repro_fail(state, simpleError("failed on purpose"))
  table <- suppressMessages(repro_runs())
  expect_equal(as.list(table[c("status", "error", "n_analysis")]),
               list(status = "failed", error = "failed on purpose", n_analysis = 3L))
  expect_false("models" %in% names(table))
  repro_fail(repro_run(cfg), "failed with a string")
  expect_true("failed with a string" %in% suppressMessages(repro_runs())$error)
})

# --- Recording off: no writes (even repro_fail); run ID, folders made (REPRODUCIBILITY.md §2) ---
test_that("if disabled nothing is written (even repro_fail); repro_run makes run ID and folders", {
  cfg <- local_repro_project()
  cfg$repro$enabled <- FALSE
  expect_warning(state <- repro_run(cfg), "this run is not recorded", fixed = TRUE)
  expect_match(state$run_id, "^[0-9]{8}_[0-9]{6}_unit_")
  repro_finish(state)
  repro_fail(state, "failed")
  expect_true(all(dir.exists(repro_settings()$output_dirs)))
  expect_false(file.exists("outputs/figures/.gitkeep"))
  expect_false(dir.exists("outputs/repro"))
})

# --- Outside git: parents or mount point, not a broken .git (REPRODUCIBILITY.md §2) ---
test_that("outside git: parent-folder and mount-point messages; a broken .git is not outside", {
  parents <- "fatal: not a git repository (or any of the parent directories): .git"
  mount <- c("fatal: not a git repository (or any parent up to mount point /)",
             "Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).")
  expect_true(.repro_outside_git(parents))
  expect_true(.repro_outside_git(mount))
  expect_false(.repro_outside_git("fatal: not a git repository: /nonexistent/.git/worktrees/a"))
  expect_false(.repro_outside_git("fatal: invalid gitfile format: .git"))
})

# --- Record commit/dirty, NA if unreadable; also /app of another owner (REPRODUCIBILITY.md §2) ---
test_that("no git: silent NA; unreadable: warned NA; records commit, dirty (warns); others' /app", {
  cfg <- local_repro_project()
  unknown <- list(commit = NA_character_, dirty = NA)
  expect_identical(expect_no_warning(.repro_git_version()), unknown)
  file.create(".git")
  expect_warning(version <- .repro_git_version(), "git_commit is NA", fixed = TRUE)
  expect_identical(version, unknown)
  writeLines("gitdir: /nonexistent/.git/worktrees/a", ".git")
  expect_warning(version <- .repro_git_version(), "git_commit is NA", fixed = TRUE)
  expect_identical(version, unknown)
  unlink(".git")
  git <- function(...) {
    system2("git", c("-c", "user.name=t", "-c", "user.email=t@t", ...),
            stdout = FALSE, stderr = FALSE)
  }
  git("init", "-q")
  writeLines("x <- 1", "a.R")
  git("add", "a.R")
  git("commit", "-q", "-m", "a")
  expect_match(.repro_git_version()$commit, "^[0-9a-f]{40}$")
  expect_identical(.repro_git_version()$dirty, FALSE)
  writeLines("x <- 2", "a.R")
  expect_identical(.repro_git_version()$dirty, TRUE)
  git("checkout", "-q", "--", "a.R")
  writeLines("y <- 1", "b.R")
  expect_identical(.repro_git_version()$dirty, TRUE)
  expect_warning(state <- repro_run(cfg), "git_dirty = TRUE", fixed = TRUE)
  repro_finish(state)
  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_match(payload$git_commit, "^[0-9a-f]{40}$")
  expect_true(payload$git_dirty)
  skip_if_not(dir.exists("/app/.git"),
              "no .git in /app (outside the container, or a folder from the Zip)")
  withr::local_dir("/app")
  expect_match(.repro_git_version()$commit, "^[0-9a-f]{40}$")
})

# --- Lock match: record SHA-256; else stop, no writes; no dir: stop too (REPRODUCIBILITY.md §2) ---
test_that("renv.lock match records SHA-256; wrong/missing version stops, no writes; no dir stops", {
  cfg <- local_repro_project()
  lock <- function(package, version) {
    record <- stats::setNames(list(list(Package = package, Version = version)), package)
    jsonlite::write_json(list(Packages = record), "renv.lock", auto_unbox = TRUE)
  }
  lock("jsonlite", utils::packageDescription("jsonlite")$Version)
  expect_no_error(.repro_check_lock_versions())
  expect_equal(repro_environment_snapshot()$renv_lock_sha256,
               digest::digest("renv.lock", algo = "sha256", file = TRUE))
  lock("jsonlite", "0.0.1")
  expect_error(.repro_check_lock_versions(), "jsonlite: renv.lock has 0.0.1, but", fixed = TRUE)
  lock("reproNoSuchPackage", "1.0")
  expect_error(.repro_check_lock_versions(), "reproNoSuchPackage: renv.lock has 1.0, not installed",
               fixed = TRUE)
  expect_error(repro_run(cfg), "Rebuild it to match renv.lock", fixed = TRUE)
  expect_false(dir.exists("outputs"))
  unlink("renv.lock")
  file.create("outputs")
  expect_error(suppressWarnings(repro_run(cfg)), "cannot open", fixed = TRUE)
})

# --- run_id argument before REPRO_RUN_ID; repro_new_run_id() (REPRODUCIBILITY.md §2) ---
test_that("run_id comes before REPRO_RUN_ID; repro_new_run_id makes one", {
  cfg <- local_repro_project()
  run_id <- repro_new_run_id("unit")
  expect_match(run_id, "^[0-9]{8}_[0-9]{6}_unit_[0-9]{4}$")
  withr::local_envvar(REPRO_RUN_ID = "from_env_0000")
  expect_equal(repro_finish(repro_run(cfg, run_id = run_id))$run_id, run_id)
  expect_error(repro_run(cfg, run_id = run_id),
               paste0("A record for run_id=", run_id, " already exists"), fixed = TRUE)
  expect_error(repro_run(cfg, run_id = "a/b"),
               "run_id is used as the prefix of the record file names", fixed = TRUE)
  expect_equal(repro_finish(repro_run(cfg))$run_id, "from_env_0000")
  for (name in list("", "a/b", c("a", "b"), 1)) {
    expect_error(repro_new_run_id(name), "so use one name without /", fixed = TRUE)
  }
})
