#!/usr/bin/env Rscript
# --- Main body of the pre-commit checks (CHECKS.md §1) ---

# --- Show warnings immediately and treat text as UTF-8 (CHECKS.md §1) ---
options(warn = 1)
invisible(tryCatch(Sys.setlocale("LC_CTYPE", "C.UTF-8"), warning = function(w) NULL,
                   error = function(e) NULL))

# --- Arguments: content location, working tree root, list of targets (CHECKS.md §1) ---
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop("Usage: Rscript tools/precommit_checks.R <content location> <work tree root> <target list>")
}
content_root <- args[1]
work_root <- args[2]
paths <- readLines(args[3], warn = FALSE, encoding = "UTF-8")
paths <- paths[nzchar(paths)]

# --- Size limit (2 MB) (CHECKS.md §1) ---
max_bytes <- 2048 * 1024

# --- Markers of private keys (CHECKS.md §1) ---
key_patterns <- c(
  sprintf("BEGIN %sPRIVATE KEY", c("RSA ", "DSA ", "EC ", "OPENSSH ", "", "ENCRYPTED ", "PGP ",
                                   "SSH2 ENCRYPTED ")),
  paste0("PuTTY-User-Key-", "File-2"),
  paste("BEGIN OpenVPN Static", "key V1")
)

# --- Shapes of well-known tokens (CHECKS.md §1) ---
token_patterns <- c(
  "an AWS access key" = "(?:A3T[A-Z0-9]|ABIA|ACCA|AKIA|ASIA)[0-9A-Z]{16}",
  "an AWS secret key" =
    "(?i)aws.{0,20}?(?:key|pwd|pw|password|pass|token).{0,20}?['\"][0-9a-zA-Z/+]{40}['\"]",
  "an Artifactory token" = "(?m)(?:\\s|=|:|\"|^)AKC[a-zA-Z0-9]{10,}(?:\\s|\"|$)",
  "an Artifactory password" = "(?m)(?:\\s|=|:|\"|^)AP[0-9A-F][a-zA-Z0-9]{8,}(?:\\s|\"|$)",
  "an Azure storage key" = "AccountKey=[a-zA-Z0-9+/=]{88}",
  "a password in a URL" = "://[^:/?#\\[\\]@!$&'()*+,;=\\s]+:[^:/?#\\[\\]@!$&'()*+,;=\\s]+@",
  "a Discord token" = "[MNO][a-zA-Z0-9_-]{23,25}\\.[a-zA-Z0-9_-]{6}\\.[a-zA-Z0-9_-]{27}",
  "a GitHub token" = "(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{36}|github_pat_[A-Za-z0-9_]{82}",
  "a GitLab token" = paste0(
    "(?:(?:glpat|gldt|glft|glsoat|glrt)-[A-Za-z0-9_-]{20,50}|GR1348941[A-Za-z0-9_-]{20,50}|",
    "glcbt-(?:[0-9a-fA-F]{2}_)?[A-Za-z0-9_-]{20,50}|glimt-[A-Za-z0-9_-]{25}|",
    "glptt-[A-Za-z0-9_-]{40}|glagent-[A-Za-z0-9_-]{50,1024}|gloas-[A-Za-z0-9_-]{64})(?!\\w)"
  ),
  "a JWT" = "eyJ[A-Za-z0-9_=-]+\\.eyJ[A-Za-z0-9_=-]+",
  "a Mailchimp key" = "[0-9a-z]{32}-us[0-9]{1,2}",
  "an npm token" = "//.+/:_authToken=\\s*(?:npm_.+|[A-Fa-f0-9-]{36})",
  "an OpenAI key" = "sk-[A-Za-z0-9_-]*[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}",
  "a PyPI token" = "pypi-(?:AgEIcHlwaS5vcmc|AgENdGVzdC5weXBpLm9yZw)[A-Za-z0-9_-]{70,}",
  "a SendGrid key" = "SG\\.[a-zA-Z0-9_-]{22}\\.[a-zA-Z0-9_-]{43}",
  "a Slack token" = "(?i)xox(?:a|b|p|o|s|r)-(?:[0-9]+-)+[a-z0-9]+",
  "a Slack webhook" =
    "https://hooks\\.slack\\.com/services/T[a-zA-Z0-9_]+/B[a-zA-Z0-9_]+/[a-zA-Z0-9_]+",
  "a Square key" = "sq0csp-[0-9A-Za-z\\\\_-]{43}",
  "a Stripe key" = "(?:r|s)k_live_[0-9a-zA-Z]{24}",
  "a Telegram token" = "(?m)^[0-9]{8,10}:[0-9A-Za-z_-]{35}$",
  "a Twilio key" = "(?:AC|SK)[a-z0-9]{32}"
)

# --- Values of secret-looking names (=, <-, YAML :; may be quoted or in [ ]) (CHECKS.md §1) ---
secret_assignment <- paste0(
  "(?i)(?:^|[^\\w.])[\\w.]*(?:access|api|auth|key|credential|creds|passw(?:or)?d|secret|token)",
  "[\\w.]*[\"']?\\]?\\s*(?:=|<-|:)\\s*[\"']?([\\w.=+/-]{10,150})"
)

# --- Functions that own the recording flow (REPRODUCIBILITY.md §2) ---
flow_functions <- c("repro_run", "repro_finish", "repro_fail")

# --- Collect problems and what was fixed (CHECKS.md §1) ---
problems <- character(0)
fixed <- character(0)
note <- function(...) assign("problems", c(problems, sprintf(...)), envir = globalenv())

# --- Packages that read the syntax (without one, skip that syntax and say so) (CHECKS.md §1) ---
has_package <- vapply(c("yaml", "jsonlite"), requireNamespace, logical(1), quietly = TRUE)
skipped <- character(0)

# --- Read a file as raw bytes (CHECKS.md §1) ---
read_raw <- function(path) readBin(path, what = "raw", n = file.info(path)$size)
# --- Treat as text if there is no NUL (CHECKS.md §1) ---
is_text <- function(raw) !any(raw == as.raw(0L))
# --- Take only the first line of an error (CHECKS.md §1) ---
first_line <- function(message) sub("\n.*$", "", message)

# --- Spread of characters (Shannon entropy, in bits per character) (CHECKS.md §1) ---
entropy <- function(value) {
  counts <- table(strsplit(value, "", fixed = TRUE)[[1]])
  shares <- counts / sum(counts)
  -sum(shares * log2(shares))
}

# --- Find values written to secret-looking names (CHECKS.md §1) ---
secret_values <- function(text, quoted) {
  lines <- strsplit(text, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  lines <- lines[!grepl("^\\s*#", lines, useBytes = TRUE)]
  pattern <- if (quoted) sub("?([", "([", secret_assignment, fixed = TRUE) else secret_assignment
  found <- regmatches(lines, gregexec(pattern, lines, perl = TRUE, useBytes = TRUE))
  values <- unlist(lapply(found, function(x) if (length(x) > 0L) x[2, ] else character(0)))
  values <- values[!grepl("^[A-Za-z_.-]+$", values)]
  values[vapply(values, entropy, numeric(1)) >= 3.5]
}

# --- Whether a line is only whitespace (CHECKS.md §1) ---
blank <- function(line, strip_trailing) {
  grepl(if (strip_trailing) "^[ \t\r]*$" else "^\r?$", line, useBytes = TRUE)
}
# --- Make the content with trailing whitespace and trailing blank lines fixed (CHECKS.md §1) ---
tidy <- function(text, strip_trailing) {
  lines <- strsplit(text, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  if (strip_trailing) lines <- sub("[ \t]+$", "", lines, useBytes = TRUE)
  while (length(lines) > 0L && blank(lines[length(lines)], strip_trailing)) {
    lines <- lines[-length(lines)]
  }
  paste0(paste(lines, collapse = "\n"), "\n")
}

# --- Check each file (CHECKS.md §1) ---
for (path in paths) {
  file <- file.path(content_root, path)
  if (!file.exists(file) || dir.exists(file)) next
  # --- Size (CHECKS.md §1) ---
  size <- file.info(file)$size
  if (size > max_bytes) {
    note("%s: %.1f MB (limit 2 MB). If it is data or an output, do not track it (check .gitignore)",
         path, size / 1024^2)
    next
  }

  # --- For empty files and binaries, check only the size (CHECKS.md §1) ---
  if (size == 0) next
  raw <- read_raw(file)
  if (!is_text(raw)) next

  # --- Turn the content into a UTF-8 string (CHECKS.md §1) ---
  text <- rawToChar(raw)
  Encoding(text) <- "UTF-8"

  # --- Strings that look like private keys (CHECKS.md §1) ---
  hit <- key_patterns[vapply(key_patterns, grepl, logical(1), x = text, fixed = TRUE,
                             useBytes = TRUE)]
  if (length(hit) > 0L) note("%s: contains what looks like a private key (%s)", path, hit[1])

  # --- Well-known tokens (CHECKS.md §1) ---
  token <- names(token_patterns)[vapply(token_patterns, grepl, logical(1), x = text, perl = TRUE,
                                        useBytes = TRUE)]
  if (length(token) > 0L) {
    note("%s: seems to contain %s. Remove it and revoke the token (if pushed, treat it as leaked)",
         path, token[1])
  }

  # --- Secret-looking values in .Rprofile, env files, R, notebooks, YAML (CHECKS.md §1) ---
  ext <- tolower(tools::file_ext(path))
  code <- basename(path) == ".Rprofile" || ext %in% c("r", "qmd", "rmd")
  if ((code || basename(path) == ".env.example" ||
         ext %in% c("yaml", "yml", "cff")) &&
        length(secret_values(text, quoted = code)) > 0L) {
    note("%s: a secret-looking name has a value. Use .env (not in Git) and readRenviron(\".env\")",
         path)
  }

  # --- Syntax of R, YAML (including CITATION.cff) and JSON (CHECKS.md §1) ---
  if (ext == "r") {
    err <- tryCatch({
      suppressWarnings(parse(text = text, keep.source = FALSE))
      NULL
    }, error = conditionMessage)
    if (!is.null(err)) note("%s: R syntax error: %s", path, first_line(err))

    # --- Whether functions in R/ call the recording-flow functions (REPRODUCIBILITY.md §2) ---
    if (is.null(err) && grepl("^R/[^/]+$", path) && basename(path) != "repro.R") {
      data <- utils::getParseData(parse(text = text, keep.source = TRUE))
      called <- unique(data$text[data$token == "SYMBOL_FUNCTION_CALL" &
                                   data$text %in% flow_functions])
      if (length(called) > 0L) {
        note(paste0("%s: calls %s. Write repro_run(), repro_finish() and repro_fail() directly",
                    " in the entry notebook, and do not call them from functions in R/"),
             path, paste0(called, "()", collapse = ", "))
      }
    }
  } else if (ext %in% c("yaml", "yml", "cff") && !has_package[["yaml"]]) {
    skipped <- union(skipped, "YAML (no yaml package)")
  } else if (ext == "json" && !has_package[["jsonlite"]]) {
    skipped <- union(skipped, "JSON (no jsonlite package)")
  } else if (ext %in% c("yaml", "yml", "cff")) {
    err <- tryCatch({
      suppressWarnings(yaml::yaml.load(text))
      NULL
    }, error = conditionMessage)
    if (!is.null(err)) note("%s: cannot be read as YAML: %s", path, first_line(err))
  } else if (ext == "json") {
    err <- tryCatch({
      jsonlite::fromJSON(text, simplifyVector = FALSE)
      NULL
    }, error = conditionMessage)
    if (!is.null(err)) note("%s: cannot be read as JSON: %s", path, first_line(err))
  }

  # --- Trailing whitespace, final newline (fix if work tree matches stage) (CHECKS.md §1) ---
  strip_trailing <- !ext %in% c("md", "csv", "csv2", "csvy", "tsv", "psv", "dat", "fwf")
  wanted <- tidy(text, strip_trailing)
  if (!identical(charToRaw(wanted), raw)) {
    lines <- strsplit(text, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
    what <- if (raw[length(raw)] != as.raw(10L)) {
      "no newline at end of file"
    } else if (strip_trailing && any(grepl("[ \t]+$", lines, useBytes = TRUE))) {
      "trailing whitespace"
    } else {
      "too many blank lines at end of file"
    }
    work <- file.path(work_root, path)
    same <- file.exists(work) && identical(read_raw(work), raw)
    if (same) {
      writeBin(charToRaw(wanted), work)
      fixed <- c(fixed, sprintf("%s (%s)", path, what))
    } else {
      note("%s: %s. Not fixed because the working tree has unstaged changes", path, what)
    }
  }
}

# --- List what was fixed and the problems, and stop if there are any (CHECKS.md §1) ---
if (length(skipped) > 0L) {
  cat("[pre-commit] Syntax not checked for: ", paste(skipped, collapse = ", "), "\n",
      sep = "", file = stderr())
}
if (length(fixed) > 0L) {
  cat("[pre-commit] Fixed (git add, then commit again):\n", file = stderr())
  for (item in fixed) cat("  - ", item, "\n", sep = "", file = stderr())
}
if (length(problems) > 0L) {
  cat("[pre-commit] Needs fixing:\n", file = stderr())
  for (item in problems) cat("  - ", item, "\n", sep = "", file = stderr())
}
if (length(fixed) > 0L || length(problems) > 0L) quit(status = 1L)
cat(sprintf("[pre-commit] %d files passed the checks\n", length(paths)))
