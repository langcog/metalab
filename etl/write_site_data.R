#!/usr/bin/env Rscript
# Build the committed site data artifacts from the staged release parquet:
#   slices/stats.json          headline totals for the home page
#   slices/datasets.json       registry + summary counts (drives selectors/cards)
#   slices/es/<short_name>.json lean per-dataset effect-size slices (drive plots)
#   resources/csv/<filename>.csv full-width per-dataset CSVs (download buttons)
#
# These are committed to git so the Quarto render (local and CI) needs no R
# and no Redivis token. Re-run after each data release.

suppressMessages({
  library(dplyr)
  library(purrr)
  library(arrow)
  library(jsonlite)
})

stage_dir <- file.path("etl", "staging", "v2026")
es <- read_parquet(file.path(stage_dir, "effect_sizes.parquet"))
datasets <- read_parquet(file.path(stage_dir, "datasets.parquet"))

dir.create("slices/es", recursive = TRUE, showWarnings = FALSE)
dir.create("resources/csv", recursive = TRUE, showWarnings = FALSE)

## ---- stats.json ----
n_subjects <- sum(datasets$num_subjects, na.rm = TRUE)
stats <- list(
  n_datasets = nrow(datasets),
  n_effect_sizes = nrow(es),
  n_papers = es %>% distinct(short_name, study_ID) %>% nrow(),
  n_subjects = round(n_subjects),
  source_release = fromJSON("etl/versions.json")$current,
  data_as_of = max(datasets$data_as_of)
)
write_json(stats, "slices/stats.json", auto_unbox = TRUE, pretty = TRUE)

## ---- datasets.json ----
registry <- datasets %>%
  mutate(moderators = map(moderators, fromJSON),
         subset = map(subset, \(j) {
           v <- fromJSON(j)
           if (length(v) == 0) list() else v
         }),
         across(c(num_experiments, num_papers, num_subjects), ~ round(.x))) %>%
  select(short_name, name, domain, filename, short_desc, description,
         full_citation, citation, curator, systematic, moderators, subset,
         longitudinal, sheet_status, data_as_of,
         num_experiments, num_papers, num_subjects, link)
write_json(registry, "slices/datasets.json", auto_unbox = TRUE, pretty = FALSE,
           null = "null", na = "null")

## ---- spec.json (drives the client-side validator + field documentation) ----
fields <- read_parquet(file.path(stage_dir, "fields.parquet")) %>%
  mutate(options = map(options, \(j) if (is.na(j)) NULL else fromJSON(j)))
write_json(fields, "slices/spec.json", auto_unbox = TRUE, na = "null")
fields_derived <- read_parquet(file.path(stage_dir, "fields_derived.parquet"))
write_json(fields_derived, "slices/spec_derived.json", auto_unbox = TRUE, na = "null")

## ---- per-dataset slices + full CSVs ----
core_cols <- c("unique_row", "study_ID", "short_cite", "expt_num",
               "expt_condition", "same_infant_calc", "peer_reviewed", "year",
               "n", "mean_age", "mean_age_months", "response_mode", "exposure_phase",
               "method", "dependent_measure", "participant_design",
               "native_lang", "infant_type", "coder", "es_method",
               "d_calc", "d_var_calc", "g_calc", "g_var_calc",
               "r_calc", "r_var_calc", "log_odds_calc", "log_odds_var_calc")

for (i in seq_len(nrow(registry))) {
  sn <- registry$short_name[i]
  extra <- unlist(c(registry$moderators[[i]], registry$subset[[i]]))
  cols <- intersect(unique(c(core_cols, extra)), names(es))
  slice <- es %>% filter(short_name == sn) %>% select(all_of(cols))
  write_json(slice, file.path("slices", "es", paste0(sn, ".json")),
             auto_unbox = TRUE, dataframe = "rows", na = "null", digits = NA)

  full <- es %>% filter(short_name == sn)
  write.csv(full, file.path("resources", "csv",
                            paste0(registry$filename[i], ".csv")),
            row.names = FALSE, quote = TRUE, na = "")
}

## ---- artifacts served for metalabr ----
## get_current_metalab_data() loads this Rdata (same object contract as the
## legacy blob: metalab_data + dataset_info, plus metalab_release for the
## version message); versions.json maps source releases to Redivis tags
env <- new.env()
load(file.path(stage_dir, "metalab_2026.Rdata"), envir = env)
metalab_data <- env$metalab_data
dataset_info <- env$dataset_info
metalab_release <- fromJSON("etl/versions.json")$current
save(metalab_data, dataset_info, metalab_release,
     file = file.path("resources", "metalab.Rdata"), version = 2)
file.copy("etl/versions.json", file.path("resources", "versions.json"),
          overwrite = TRUE)

cat(sprintf("wrote %d dataset slices (%s total), %d csvs, stats + registry + Rdata\n",
            nrow(registry),
            format(structure(sum(file.size(list.files("slices/es", full.names = TRUE))),
                             class = "object_size"), units = "MB"),
            length(list.files("resources/csv"))))
