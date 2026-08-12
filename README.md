# MetaLab datapage

A static rebuild of [metalab.stanford.edu](https://metalab.stanford.edu) on the
datapages pattern: data hosted on [Redivis](https://redivis.com/datasets/81tq-9ewzpdvz0)
(versioned, citable), site built with Quarto, visualization in-browser with
Observable Plot. Supersedes the Hugo site + Posit Connect Shiny apps (which
went offline when the `metalab-shiny.com` server died).

This branch (`datapage`) is developed in a worktree and will replace `main` +
`gh-pages` at cutover.

## Architecture

```
32 curator Google Sheets --etl/fetch_fresh.R--> etl/staging/v*/  (parquet)
etl/staging              --etl/upload_redivis.R--> Redivis: datapages.metalab (versioned release)
etl/staging              --etl/write_site_data.R--> slices/*.json + resources/csv/*  (committed)
slices/                  --quarto render (no R!)--> _site/  (GitHub Pages)
```

- **The render needs no R and no tokens**: all site data is committed as JSON
  slices (~2 MB) rebuilt by `etl/write_site_data.R` after each data release.
- **Data releases** are two-phase: `etl/fetch_fresh.R` (fetch + validate +
  compute effect sizes via the legacy metalabr pipeline, archive raw sheets)
  → `etl/upload_redivis.R <staging_dir> "notes" [--release]`. Release names
  ("2023.1", "2026.1") map to Redivis version tags in `etl/versions.json`.
- 7 datasets' upstream sheets were deleted at some point after 2023
  (HTTP 410): their rows are carried forward verbatim from the 2023 snapshot,
  marked by `datasets.sheet_status = "unavailable_upstream"`.

## Redivis tables

| table | grain |
|---|---|
| `effect_sizes` | one row per effect size (all datasets; raw coded fields + derived ES columns) |
| `datasets` | one row per dataset (registry + summary counts + provenance) |
| `fields` | spec for coded columns (from metadata/spec.yaml) |
| `fields_derived` | spec for pipeline-derived columns |

## Local development

```
Rscript etl/write_site_data.R   # only after a new data release
quarto render                    # -> _site/
```

Note: pages hang in *hidden* browser tabs by design of the Observable
runtime (requestAnimationFrame never fires); a shim in `_quarto.yml` falls
back to a timer scheduler when a page loads hidden.
