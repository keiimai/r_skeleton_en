# Changelog

This file keeps the **record of decisions** for this research project. Git holds what was changed. Why it was changed, what was dropped, and what the dummy data was made from are recorded only here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

- Template the project was started from: `<version or commit>` of `<where the template is>`
- Environment used: `<where the environment was built>` (the R version, and how package versions are pinned (renv, etc.). Rewrite this when it changes, and write why below)

## [Unreleased]

### Added

- The time zone of the records is decided by `TZ` in `.env` at the root (`TZ` in `.env`, then the environment variable `TZ`, then `Asia/Tokyo`; no other line of `.env` is read). Added the example `.env.example`, which `setup.R` copies only when `.env` is missing. The record's environment keeps the time zone used (2026-11-23)
- Added the argument `run_id` to `repro_run()` (argument, then the environment variable `REPRO_RUN_ID`, then a new one), and `repro_new_run_id(name)`, which makes a run ID in advance (2026-11-24)
