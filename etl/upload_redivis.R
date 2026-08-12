#!/usr/bin/env Rscript
# Upload a staged parquet directory to Redivis as the next version of
# datapages.metalab. Creates the dataset on first run; afterwards creates the
# next version, replaces all tables, verifies row counts, and (only with
# --release) releases.
#
# Usage: Rscript etl/upload_redivis.R <staging_dir> "release notes" [--release]
#
# Requires REDIVIS_API_TOKEN in .secrets (KEY=VALUE format, gitignored).
# Traps handled per the datapage playbook: upload_merge_strategy must be set
# via tb$update() EVERY run (create() ignores it); replace_on_conflict makes
# interrupted runs resumable; release only after count verification.

suppressMessages({
  library(redivis)
  library(arrow)
  library(purrr)
})

if (file.exists(".secrets")) readRenviron(".secrets")
if (Sys.getenv("REDIVIS_API_TOKEN") == "") stop("REDIVIS_API_TOKEN not set")

args <- commandArgs(trailingOnly = TRUE)
do_release <- "--release" %in% args
args <- setdiff(args, "--release")
stopifnot(length(args) >= 1)
stage_dir <- args[[1]]
notes <- if (length(args) > 1) args[[2]] else
  paste("MetaLab data upload,", Sys.Date())

parquets <- list.files(stage_dir, pattern = "\\.parquet$", full.names = TRUE)
stopifnot(length(parquets) > 0)

table_descriptions <- c(
  effect_sizes = "One row per effect size across all MetaLab meta-analytic datasets (join to datasets on short_name). Raw coded fields are defined in the fields table; derived columns (d_calc, g_calc, r_calc, z_calc, log_odds_calc and variances, es_method, corr_imputed, mean_age [days], mean_age_months, n, same_infant_calc, unique_row, year) in fields_derived. Ages are in days unless the column says months.",
  datasets = "One row per meta-analytic dataset: registry metadata (name, domain, short_name, citation, curator, systematic search info) plus summary counts (num_experiments, num_papers, num_subjects). moderators and subset are JSON-array strings listing dataset-specific moderator/subset columns in effect_sizes.",
  fields = "Definitions of the coded (raw) columns in effect_sizes, from metadata/spec.yaml: type (string/numeric/options), allowed options (JSON), nullable, required.",
  fields_derived = "Definitions of the derived columns computed by the MetaLab effect-size pipeline."
)

ds <- redivis$organization("datapages")$dataset("metalab")
if (!ds$exists()) {
  message("creating dataset datapages.metalab")
  ds$create(public_access_level = "data",
            description = "MetaLab: community-augmented meta-analysis of language acquisition and cognitive development. One row per effect size across 30+ curated meta-analytic datasets. See metalab.stanford.edu and langcog/metalab.")
} else {
  message("creating next version of datapages.metalab")
  ds <- ds$create_next_version(if_not_exists = TRUE)
}

expected <- list()
for (path in parquets) {
  name <- sub("\\.parquet$", "", basename(path))
  expected[[name]] <- nrow(read_parquet(path))
  tb <- ds$table(name)
  if (!tb$exists()) {
    message("creating table ", name)
    tb$create(description = unname(table_descriptions[name]))
  }
  # must be set every run: create() does not persist it and the default
  # (append) silently doubles data on re-release
  tb$update(upload_merge_strategy = "replace")
  message("uploading ", basename(path), " (", expected[[name]], " rows)")
  tb$upload(basename(path))$create(content = path, type = "parquet",
                                   replace_on_conflict = TRUE)
}

message("\nverifying draft row counts...")
ok <- TRUE
for (name in names(expected)) {
  props <- ds$table(name)$get()$properties
  n <- as.numeric(props$numRows)
  status <- if (identical(n, as.numeric(expected[[name]]))) "OK" else {ok <- FALSE; "MISMATCH"}
  message(sprintf("  %-16s parquet=%-6d redivis=%-6d %s",
                  name, expected[[name]], n, status))
}
if (!ok) stop("row count verification FAILED -- not releasing")

if (do_release) {
  message("releasing version (notes: ", notes, ")")
  ds$release(release_notes = notes)
  message("released: ", ds$get()$properties$qualifiedReference)
} else {
  message("draft staged; re-run with --release to release")
}
