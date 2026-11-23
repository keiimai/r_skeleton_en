# --- Reproducibility recording layer (REPRODUCIBILITY.md §2) ---

# --- Use the default if NULL (REPRODUCIBILITY.md §2) ---
`%||%` <- function(x, default) if (is.null(x)) default else x # nolint: object_name_linter.

# --- Time zone (.env TZ, then env var TZ, then Asia/Tokyo) (REPRODUCIBILITY.md §2) ---
.repro_tz <- function() {
  tz <- ""
  if (file.exists(".env")) {
    lines <- readLines(".env", warn = FALSE, encoding = "UTF-8")
    lines <- grep("^[[:space:]]*TZ[[:space:]]*=", lines, value = TRUE)
    if (length(lines) > 0L) {
      tz <- sub("^[[:space:]]*TZ[[:space:]]*=", "", lines[length(lines)])
      tz <- gsub("^[\"']|[\"']$", "", trimws(sub("[[:space:]]+#.*$", "", tz)))
    }
  }
  if (!nzchar(tz)) tz <- Sys.getenv("TZ")
  if (!nzchar(tz)) tz <- "Asia/Tokyo"
  tz
}

# --- Time (the time zone from .repro_tz()) (REPRODUCIBILITY.md §2) ---
.repro_timestamp <- function(fmt = "%Y-%m-%dT%H:%M:%S%z") {
  tz <- .repro_tz()
  if (!tz %in% OlsonNames()) {
    stop("TZ=", tz, " is not a time zone name. Set TZ in .env (or the environment variable TZ) ",
         "to a name such as Asia/Tokyo (see docs/REPRODUCIBILITY.md §2)", call. = FALSE)
  }
  format(Sys.time(), fmt, tz = tz)
}

# --- New run_id (last 4 digits: time + PID, not R's RNG; redo if taken) (REPRODUCIBILITY.md §2) ---
.repro_new_run_id <- function(tag, repro_dir) {
  for (attempt in seq_len(20L)) {
    suffix <- (as.integer((as.numeric(Sys.time()) * 1e6) %% 1e6) + Sys.getpid()) %% 10000L
    run_id <- sprintf("%s_%s_%04d", .repro_timestamp("%Y%m%d_%H%M%S"), tag, suffix)
    if (!file.exists(file.path(repro_dir, run_id, paste0(run_id, "_run.json")))) break
  }
  run_id
}

# --- Read YAML as UTF-8 without relying on the locale (REPRODUCIBILITY.md §4) ---
repro_read_yaml <- function(path) {
  text <- rawToChar(readBin(path, what = "raw", n = file.info(path)$size))
  Encoding(text) <- "UTF-8"
  unquoted <- character(0)
  as_logical <- function(word) {
    if (!tolower(word) %in% c("true", "false")) unquoted <<- c(unquoted, word)
    tolower(word) %in% c("true", "yes", "y", "on")
  }
  number_like <- character(0)
  as_text <- function(word) {
    exponent <- grepl("^[-+]?[0-9][0-9_]*([.][0-9_]*)?[eE][-+]?[0-9]+$", word)
    if (exponent) number_like <<- c(number_like, word)
    word
  }
  handlers <- list("bool#yes" = as_logical, "bool#no" = as_logical, str = as_text)
  parsed <- tryCatch(yaml::yaml.load(text, handlers = handlers), error = function(e) e)
  if (length(unquoted) > 0L) {
    stop(path, ": unquoted \"", unquoted[1], "\" is read by YAML as a logical (TRUE/FALSE). ",
         "Do not use unquoted y, n, yes, no, on, off (in any case) as keys or values. ",
         "To use it as text, quote it (\"", unquoted[1], "\"); for a logical, write true or false",
         " (see docs/REPRODUCIBILITY.md §4)", call. = FALSE)
  }
  if (inherits(parsed, "error")) stop(parsed)
  if (length(number_like) > 0L) {
    warning(path, ": ", paste(unique(number_like), collapse = ", "), " are text in YAML. ",
            "For numbers, add a point and a sign (1.0e-6, 1.0e+5; see docs/REPRODUCIBILITY.md §4)",
            call. = FALSE)
  }
  check_keys <- function(node) {
    if (any(names(node) %in% c("TRUE", "FALSE"))) {
      stop(path, ": do not use these as keys: y, n, yes, no, on, off, true, false (in any case). ",
           "YAML reads them as logicals and the name becomes TRUE or FALSE. Rename the key or ",
           "quote it (see docs/REPRODUCIBILITY.md §4)", call. = FALSE)
    }
    for (child in Filter(is.list, node)) check_keys(child)
  }
  if (is.list(parsed)) check_keys(parsed)
  parsed
}

# --- Fix the random seed and RNGkind (REPRODUCIBILITY.md §2) ---
repro_set_seed <- function(seed = 42L) {
  set.seed(as.integer(seed), kind = "Mersenne-Twister", normal.kind = "Inversion",
           sample.kind = "Rejection")
}

# --- Default config (REPRODUCIBILITY.md §2) ---
repro_config_defaults <- function() {
  list(
    seed = 42L,
    experiment_name = "default",
    data = list(mode = "dummy"),
    repro = list(enabled = TRUE, quiet = FALSE)
  )
}

# --- Overlay the config file on the defaults (unknown keys are kept) (REPRODUCIBILITY.md §2) ---
repro_config_load <- function(path) {
  cfg <- utils::modifyList(repro_config_defaults(), repro_read_yaml(path) %||% list(),
                           keep.null = TRUE)
  seed <- cfg$seed
  if (!is.numeric(seed) || length(seed) != 1L || is.na(seed) || seed != round(seed) ||
        abs(seed) > .Machine$integer.max) {
    shown <- if (is.character(seed)) dQuote(seed, FALSE) else format(seed %||% "null")
    stop(path, ": set seed to an integer (currently: ", paste(shown, collapse = ", "),
         "; see docs/REPRODUCIBILITY.md §2)", call. = FALSE)
  }
  cfg$seed <- as.integer(seed)
  cfg
}

# --- Where records and outputs go (REPRODUCIBILITY.md §2) ---
repro_settings <- function() {
  list(
    repro_dir = "outputs/repro",
    ledger_path = "outputs/repro/runs.csv",
    output_dirs = c("outputs", "outputs/figures", "outputs/metrics", "outputs/tables",
                    "outputs/reports")
  )
}

# --- Outside git (none up to the parents or the mount point) (REPRODUCIBILITY.md §2) ---
.repro_outside_git <- function(lines) {
  any(grepl("not a git repository (or any", lines, fixed = TRUE))
}

# --- Code version (git commit and whether the working tree has changed) (REPRODUCIBILITY.md §2) ---
.repro_git_version <- function() {
  safe <- tempfile(fileext = ".gitconfig")
  on.exit(unlink(safe))
  writeLines(c("[safe]", "\tdirectory = *"), safe)
  env <- c("LC_ALL=C", paste0("GIT_CONFIG_GLOBAL=", shQuote(safe)))
  git <- function(args, stderr) {
    tryCatch(suppressWarnings(system2("git", c("--no-optional-locks", args), stdout = TRUE,
                                      stderr = stderr, env = env)),
             error = function(e) character(0))
  }
  commit <- git(c("rev-parse", "HEAD"), stderr = TRUE)
  if (!is.null(attr(commit, "status")) || length(commit) != 1L || !nzchar(commit)) {
    outside <- .repro_outside_git(commit)
    if (length(commit) > 0L && !outside) {
      warning("Cannot get the git commit (git_commit is NA): ", commit[1], call. = FALSE)
    }
    commit <- NA_character_
  }
  status <- git(c("status", "--porcelain"), stderr = FALSE)
  list(commit = commit, dirty = if (is.null(attr(status, "status"))) length(status) > 0L else NA)
}

# --- Whether the loaded package versions match renv.lock (REPRODUCIBILITY.md §2) ---
.repro_check_lock_versions <- function() {
  if (!file.exists("renv.lock")) return(invisible(NULL))
  records <- jsonlite::read_json("renv.lock")$Packages
  problems <- unlist(lapply(records, function(record) {
    path <- find.package(record$Package, quiet = TRUE)
    if (length(path) == 0L) {
      return(sprintf("%s: renv.lock has %s, not installed", record$Package, record$Version))
    }
    found <- read.dcf(file.path(path[1], "DESCRIPTION"), fields = "Version")[[1]]
    if (identical(found, record$Version)) return(NULL)
    sprintf("%s: renv.lock has %s, but %s is loaded (%s)",
            record$Package, record$Version, found, dirname(path[1]))
  }))
  if (length(problems) == 0L) return(invisible(NULL))
  stop("Stopping the run: package versions that differ from renv.lock would be loaded:\n  ",
       paste(problems, collapse = "\n  "),
       "\nThis happens when the environment is older than renv.lock. ",
       "Rebuild it to match renv.lock, then run again (see docs/REPRODUCIBILITY.md §2)",
       call. = FALSE)
}

# --- Snapshot of the runtime environment (TZ: the zone used) (REPRODUCIBILITY.md §2) ---
repro_environment_snapshot <- function() {
  list(
    r_version = R.version.string,
    platform = R.version$platform,
    rng = list(kind = RNGkind()),
    locale = Sys.getlocale(),
    env = utils::modifyList(as.list(Sys.getenv(c(
      "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "TZ", "LANG", "LC_ALL"
    ))), list(TZ = .repro_tz())),
    blas = extSoftVersion()[["BLAS"]],
    lapack = La_library(),
    lapack_version = La_version(),
    build_info = if (file.exists("/opt/build-info.json")) {
      jsonlite::read_json("/opt/build-info.json")
    },
    renv_lock_sha256 = .repro_describe_files("renv.lock")[[1]]$sha256
  )
}

# --- Describe files read and written (path, SHA-256, size) (REPRODUCIBILITY.md §2) ---
.repro_describe_files <- function(paths) {
  lapply(as.character(paths), function(path) {
    exists <- file.exists(path)
    list(
      path = path,
      sha256 = if (exists) digest::digest(path, algo = "sha256", file = TRUE) else NA_character_,
      bytes = if (exists) file.info(path)$size else NA_real_
    )
  })
}

# --- Write a CSV as UTF-8 with a BOM (REPRODUCIBILITY.md §4) ---
repro_write_csv <- function(table, path, ...) {
  fixed <- intersect(...names(), c("sep", "qmethod", "row.names", "append"))
  if (length(fixed) > 0) {
    stop("repro_write_csv() does not accept ", paste(fixed, collapse = ", "),
         " (if you need row names, make them a column first)")
  }
  writeBin(as.raw(c(0xef, 0xbb, 0xbf)), path)
  con <- file(path, open = "a", encoding = "UTF-8")
  on.exit(close(con))
  utils::write.table(table, con, sep = ",", qmethod = "double", row.names = FALSE, ...)
  invisible(path)
}

# --- Write the record JSON (REPRODUCIBILITY.md §2) ---
.repro_write_record <- function(state, status, error = NULL, artifacts = list()) {
  payload <- list(
    schema_version = 1L,
    run_id = state$run_id,
    status = status,
    error = error,
    experiment_name = state$cfg$experiment_name,
    started_at = state$started_at,
    finished_at = if (identical(status, "running")) NULL else .repro_timestamp(),
    data_mode = state$cfg$data$mode,
    seed = state$cfg$seed,
    git_commit = state$git_commit,
    git_dirty = state$git_dirty,
    inputs = state$inputs,
    environment = state$environment,
    config = state$config_path,
    artifacts = artifacts,
    ledger = state$ledger
  )
  jsonlite::write_json(payload, state$meta_path, auto_unbox = TRUE, pretty = TRUE, null = "null",
                       na = "null", digits = NA)
}

# --- Start the record (REPRODUCIBILITY.md §2) ---
repro_run <- function(cfg, inputs = NULL) {
  .repro_check_lock_versions()
  settings <- repro_settings()
  tag <- cfg$experiment_name
  if (length(tag) != 1L || !nzchar(tag) || grepl("/", tag, fixed = TRUE)) {
    stop("experiment_name is used as the prefix of the run ID and the record file names, ",
         "so make it a single name without / (see docs/REPRODUCIBILITY.md §2)", call. = FALSE)
  }
  folders <- as.character(inputs)[dir.exists(as.character(inputs))]
  if (length(folders) > 0L) {
    stop(paste(folders, collapse = ", "), ": pass files to inputs one at a time, not folders",
         " (see docs/REPRODUCIBILITY.md §2)", call. = FALSE)
  }
  notebook <- if (isNamespaceLoaded("knitr")) knitr::current_input()
  label <- if (length(notebook) == 1L) tools::file_path_sans_ext(basename(notebook)) else tag
  run_id <- Sys.getenv("REPRO_RUN_ID", unset = "")
  if (!nzchar(run_id)) {
    run_id <- .repro_new_run_id(label, settings$repro_dir)
  } else if (grepl("/", run_id, fixed = TRUE)) {
    stop("REPRO_RUN_ID is used as the prefix of the record file names, so use a name without /",
         " (see docs/REPRODUCIBILITY.md §2)", call. = FALSE)
  } else if (file.exists(file.path(settings$repro_dir, run_id, paste0(run_id, "_run.json")))) {
    stop("A record for REPRO_RUN_ID=", run_id, " already exists. Call repro_run() only",
         " once per render (see docs/REPRODUCIBILITY.md §2)", call. = FALSE)
  }
  state <- list(
    run_id = run_id, cfg = cfg, artifacts = character(0), ledger = list(),
    started_at = .repro_timestamp(), enabled = isTRUE(cfg$repro$enabled)
  )
  for (path in settings$output_dirs) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (!state$enabled) {
    warning("repro.enabled=false, so this run is not recorded (run_id=", run_id, ")",
            call. = FALSE)
    return(state)
  }
  if (isNamespaceLoaded("knitr") && (isTRUE(knitr::opts_chunk$get("cache") > 0) ||
                                        length(knitr::all_labels(isTRUE(cache))) > 0L)) {
    stop("Do not use knitr's cache when recording (cached chunks do not run, so the record and ",
         "outputs drift from the HTML; see \"Conventions\" in notebooks/README.md)", call. = FALSE)
  }
  threads <- Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS"), unset = "")
  threads <- threads[threads != "1"]
  if (length(threads) > 0L) {
    warning("Thread count is not 1 (",
            paste0(names(threads), "=", ifelse(nzchar(threads), threads, "(unset)"),
                   collapse = ", "), "). Set it to 1 for runs that produce final results ",
            "(if you changed it, revert it; see docs/REPRODUCIBILITY.md §4)", call. = FALSE)
  }
  run_dir <- file.path(settings$repro_dir, run_id)
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  git <- .repro_git_version()
  state$git_commit <- git$commit
  state$git_dirty <- git$dirty
  if (isTRUE(state$git_dirty)) {
    warning("The working tree has uncommitted changes (git_dirty = TRUE). ",
            "The recorded git_commit may differ from the code that ran. ",
            "Commit before runs that produce results (see docs/REPRODUCIBILITY.md §2)",
            call. = FALSE)
  }
  state$environment <- repro_environment_snapshot()
  state$inputs <- .repro_describe_files(inputs)
  absent <- as.character(inputs)[!file.exists(as.character(inputs))]
  if (length(absent) > 0L) {
    warning("Some inputs do not exist (their SHA-256 is recorded as null): ",
            paste(absent, collapse = ", "), call. = FALSE)
  }
  state$meta_path <- file.path(run_dir, paste0(run_id, "_run.json"))
  state$config_path <- file.path(run_dir, paste0(run_id, ".config.yaml"))
  yaml::write_yaml(cfg, state$config_path, precision = 15L,
                   handlers = list(logical = yaml::verbatim_logical))
  .repro_write_record(state, "running")

  if (!isTRUE(cfg$repro$quiet)) {
    message(sprintf("run_id=%s data_mode=%s seed=%s", run_id, cfg$data$mode, cfg$seed))
  }
  state
}

# --- Finish the record (REPRODUCIBILITY.md §2) ---
repro_finish <- function(state, status = "success", error = NULL) {
  if (!isTRUE(state$enabled)) return(invisible(state))
  paths <- as.character(state$artifacts)
  is_file <- utils::file_test("-f", paths)
  if (!all(is_file)) {
    warning("Some artifacts are missing or are folders (not recorded): ",
            paste(paths[!is_file], collapse = ", "), call. = FALSE)
  }
  unnamed <- paths[is_file & grepl("(^|/)outputs/", paths) &
                     !grepl(state$run_id, paths, fixed = TRUE)]
  if (length(unnamed) > 0L) {
    warning("Some artifacts in outputs/ do not have the run ID (the next run overwrites them, ",
            "and they will no longer match this record): ", paste(unnamed, collapse = ", "),
            " (see docs/REPRODUCIBILITY.md §2)", call. = FALSE)
  }
  artifacts <- .repro_describe_files(paths[is_file])
  .repro_write_record(state, status, error, artifacts)

  if (!isTRUE(state$cfg$repro$quiet)) {
    cat(sprintf("\n[repro] run_id      : %s (%s)\n", state$run_id, status))
    cat(sprintf("[repro] data_mode   : %s\n", state$cfg$data$mode))
    cat(sprintf("[repro] git commit  : %s\n", substr(state$git_commit, 1, 12)))
    cat(sprintf("[repro] artifacts   : %d\n", length(artifacts)))
    cat(sprintf("[repro] record      : %s\n\n", state$meta_path))
  }
  invisible(state)
}

# --- Finish the record as failed (REPRODUCIBILITY.md §2) ---
repro_fail <- function(state, error) {
  message_text <- if (inherits(error, "condition")) conditionMessage(error) else as.character(error)
  repro_finish(state, status = "failed", error = message_text)
}

# --- Failed repro_render(): mark it failed, move partial outputs (REPRODUCIBILITY.md §2) ---
.repro_mark_failed <- function(run_id) {
  path <- file.path(repro_settings()$repro_dir, run_id, paste0(run_id, "_run.json"))
  record <- if (file.exists(path)) jsonlite::read_json(path)
  if (is.null(record)) return(invisible(NULL))
  outputs <- dirname(repro_settings()$repro_dir)
  hits <- list.files(outputs, recursive = TRUE, include.dirs = TRUE)
  hits <- hits[grepl(run_id, basename(hits), fixed = TRUE) & !grepl("^(repro|reports)/", hits) &
                 !grepl(run_id, dirname(hits), fixed = TRUE)]
  for (hit in hits) {
    dest <- file.path(dirname(path), "partial", hit)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.rename(file.path(outputs, hit), dest)
  }
  if (identical(record$status, "failed") && length(hits) == 0L) return(invisible(NULL))
  if (!identical(record$status, "failed")) {
    record[c("status", "error")] <- list("failed", "repro_render() failed (there is no HTML)")
    record$finished_at <- record$finished_at %||% .repro_timestamp()
  }
  if (length(hits) > 0L) {
    record$error <- paste0(record$error, ". Moved ", length(hits), " partial outputs to partial/")
  }
  jsonlite::write_json(record, path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null",
                       digits = NA)
}

# --- Render to outputs/reports/<run_id>/; record failed on error (REPRODUCIBILITY.md §2) ---
repro_render <- function(qmd, params = character(0)) {
  if (!file.exists(qmd)) {
    stop(qmd, " does not exist (write the path from the repository root)", call. = FALSE)
  }
  run_id <- .repro_new_run_id(tools::file_path_sans_ext(basename(qmd)), repro_settings()$repro_dir)
  work <- file.path(dirname(qmd), ".quarto")
  if (!dir.exists(work) || nzchar(Sys.readlink(work))) {
    unlink(work)
    scratch <- tempfile("quarto")
    dir.create(scratch)
    suppressWarnings(file.symlink(scratch, work))
  }
  out <- tempfile("render")
  dir.create(out)
  previous <- Sys.getenv("REPRO_RUN_ID", unset = NA)
  on.exit({
    if (is.na(previous)) Sys.unsetenv("REPRO_RUN_ID") else Sys.setenv(REPRO_RUN_ID = previous)
  })
  Sys.setenv(REPRO_RUN_ID = run_id)
  args <- c("render", qmd, "--output-dir", out, as.vector(rbind(rep("-P", length(params)), params)))
  status <- system2("quarto", shQuote(args))
  if (!identical(status, 0L)) {
    .repro_mark_failed(run_id)
    stop("Rendering failed (see the Quarto output above): ", qmd, call. = FALSE)
  }
  dest <- file.path(dirname(repro_settings()$repro_dir), "reports", run_id)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  rendered <- list.files(out, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  file.copy(rendered, dest, recursive = TRUE)
  message("Rendered: ", dest, "/")
  invisible(dest)
}

# --- Rebuild the run ledger (REPRODUCIBILITY.md §3) ---
repro_runs <- function(experiment = NULL, limit = NULL, show = FALSE) {
  if (identical(experiment, "")) experiment <- NULL
  if (identical(limit, "")) limit <- NULL
  settings <- repro_settings()
  files <- Sys.glob(file.path(settings$repro_dir, "*", "*_run.json"))
  files <- files[basename(dirname(files)) == sub("_run\\.json$", "", basename(files))]
  rows <- lapply(files, function(path) {
    payload <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) {
      stop(path, " cannot be read (", conditionMessage(e), "). Fix or delete it", call. = FALSE)
    })
    row <- lapply(c(run_id = "run_id", status = "status", experiment = "experiment_name",
                    data_mode = "data_mode", seed = "seed", started_at = "started_at",
                    finished_at = "finished_at", git_commit = "git_commit",
                    git_dirty = "git_dirty"),
                  function(field) payload[[field]] %||% NA)
    row$git_commit <- substr(payload$git_commit %||% "", 1, 12)
    row$n_inputs <- length(payload$inputs)
    row$n_artifacts <- length(payload$artifacts)
    row$error <- as.character(payload$error %||% NA)[1]
    ledger <- payload$ledger
    for (name in setdiff(names(ledger), names(row))) {
      value <- ledger[[name]]
      if (length(value) == 1L && is.atomic(value)) row[[name]] <- value
    }
    row
  })
  columns <- unique(unlist(lapply(rows, names)))
  table <- as.data.frame(lapply(stats::setNames(nm = columns), function(column) {
    unlist(lapply(rows, function(row) row[[column]] %||% NA))
  }), stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(table) > 0L) {
    table <- table[order(table$started_at, decreasing = TRUE), , drop = FALSE]
  }
  dir.create(dirname(settings$ledger_path), recursive = TRUE, showWarnings = FALSE)
  repro_write_csv(table, settings$ledger_path)
  message(sprintf("[repro] %d runs -> %s", nrow(table), settings$ledger_path))
  if (!is.null(experiment)) table <- table[table$experiment %in% experiment, , drop = FALSE]
  if (!is.null(limit)) table <- utils::head(table, as.integer(limit))
  rownames(table) <- NULL
  if (show && nrow(table) == 0L) {
    cat(if (is.null(experiment)) "[repro] No run records yet (run repro_smoke() once).\n"
        else paste0("[repro] No run records for experiment ", experiment, ".\n"))
  } else if (show) {
    print(table, row.names = FALSE, right = FALSE)
    running <- sum(table$status == "running", na.rm = TRUE)
    if (running > 0L) {
      cat("[repro] Unfinished records (status = running): ", running, ". ",
          "They stopped midway or are still running (see docs/REPRODUCIBILITY.md §2).\n", sep = "")
    }
  }
  invisible(table)
}

# --- Run once through the recording layer (REPRODUCIBILITY.md §2) ---
repro_smoke <- function() {
  cfg <- repro_config_defaults()
  cfg$experiment_name <- "smoke"
  cfg$data$mode <- "synthetic"
  repro_set_seed(cfg$seed)

  input <- file.path(tempdir(), "smoke_input.csv")
  repro_write_csv(data.frame(x = 1:5, y = stats::rnorm(5)), input)

  state <- repro_run(cfg, inputs = input)
  result <- tryCatch({
    frame <- utils::read.csv(input, fileEncoding = "UTF-8-BOM")
    output <- file.path("outputs/tables", sprintf("%s_smoke.csv", state$run_id))
    repro_write_csv(frame, output)
    output
  }, error = function(e) {
    repro_fail(state, e)
    stop(e)
  })

  state$artifacts <- result
  state$ledger <- list(n_rows = 5L)
  repro_finish(state)
  cat("Artifact:\n  ", result, "\n", sep = "")
}
