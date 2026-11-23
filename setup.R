# --- Create the directory structure (only what is missing) (README.md "Contents") ---

# --- Work in the folder that holds this file (the repository root) (README.md "Contents") ---
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(script) == 1L) setwd(dirname(normalizePath(script)))

# --- Directories to create (the same structure as the template) (README.md "Contents") ---
DIRS <- c(
  ".githooks", ".vscode", "R", "configs",
  "data", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docs", "docs/definition", "models", "notebooks",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables",
  "tests/testthat", "tools"
)

# --- Directories given a .gitkeep when created (contents untracked) (README.md "Contents") ---
KEEP <- c(
  "configs", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docs/definition", "models",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables"
)

# --- Create only missing directories; print what was created or skipped (README.md "Contents") ---
created <- 0L
for (dir in DIRS) {
  if (dir.exists(dir)) {
    cat(sprintf("[setup] exists, skipped: %s\n", dir))
    next
  }
  if (file.exists(dir)) stop(sprintf("%s is a file, not a folder. Rename it, then rerun.", dir))
  dir.create(dir, recursive = TRUE)
  if (dir %in% KEEP) file.create(file.path(dir, ".gitkeep"))
  cat(sprintf("[setup] created: %s\n", dir))
  created <- created + 1L
}
cat(sprintf("[setup] created %d, skipped %d\n", created, length(DIRS) - created))

# --- Copy .env.example to .env if missing (skipped if .env exists) (REPRODUCIBILITY.md §2) ---
if (file.exists(".env")) {
  cat("[setup] already exists, skipped: .env\n")
} else if (file.exists(".env.example")) {
  file.copy(".env.example", ".env")
  cat("[setup] created: .env (copied from .env.example; check the time zone TZ)\n")
}
