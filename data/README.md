# data/ — where the data goes

**The contents of this folder are not tracked by Git.** Real data may contain personal information, so do not copy it to Git or to the cloud (how it is kept out: `.gitignore` under "Contents" in [`README.md`](../README.md); how it is stopped: [`docs/CHECKS.md`](../docs/CHECKS.md) §1).

| Folder | Contents | Who writes it |
|---|---|---|
| `raw/` | Data exactly as received. **Do not modify** (the starting point for reproduction) | A person |
| `raw/dummy/` | Dummy data whose column names, types and missingness distribution resemble the real data (see below) | A person |
| `interim/` | Intermediate data (joins, type conversions, etc.) | Analysis code |
| `processed/` | Data used directly in the analysis | Analysis code |
| `external/` | Reference data brought in from outside (regional statistics, code tables, etc.) | A person |

**Prepare the dummy data yourself** (the template has no way of making it). Write how you made it in `CHANGELOG.md`. Make outputs produced from dummy data distinguishable from production ones by their names or folders.
