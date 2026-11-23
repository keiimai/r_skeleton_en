# --- Session defaults at startup (REPRODUCIBILITY.md §1) ---

# --- Startup settings (REPRODUCIBILITY.md §1) ---
local({
  # --- Show warnings immediately and use ASCII quotes (REPRODUCIBILITY.md §1) ---
  options(
    warn = 1,
    useFancyQuotes = FALSE
  )

  # --- In interactive sessions, reset the BLAS and OpenMP thread counts to the environment variables (REPRODUCIBILITY.md §4) ---
  if (interactive() && requireNamespace("RhpcBLASctl", quietly = TRUE)) {
    blas <- suppressWarnings(as.integer(Sys.getenv("OPENBLAS_NUM_THREADS")))
    omp <- suppressWarnings(as.integer(Sys.getenv("OMP_NUM_THREADS")))
    if (!is.na(blas)) RhpcBLASctl::blas_set_num_threads(blas)
    if (!is.na(omp)) RhpcBLASctl::omp_set_num_threads(omp)
  }

  # --- In interactive sessions, show a note if a thread count is not 1 (REPRODUCIBILITY.md §4) ---
  if (interactive()) {
    threads <- Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS"), unset = "")
    threads <- threads[threads != "1"]
    if (length(threads) > 0L) {
      shown <- ifelse(nzchar(threads), threads, "(unset)")
      message(
        "Note: ", paste0(names(threads), "=", shown, collapse = ", "),
        ". Set it to 1 for runs that produce final results (if you changed it, revert it)."
      )
    }
  }
})

# --- Lines added by the project (REPRODUCIBILITY.md §1) ---
