#!/usr/bin/env Rscript
# Export the April-2023 MetaLab data snapshot (the final state served by the
# legacy site and Shiny apps) to parquet for staging as Redivis version 1.
#
# Source of truth: shinyapps/site_data/Rdata/metalab.Rdata on langcog/metalab
# origin/main (last regenerated 2023-04-06, commit 6cf0ed5), which contains the
# two objects every legacy app loaded: `metalab_data` (one row per effect size,
# all raw spec fields + derived ES columns) and `dataset_info` (registry +
# summary counts). Values are exported verbatim -- no recomputation.
#
# Output: etl/staging/v2023/{effect_sizes,datasets,fields,fields_derived}.parquet

suppressMessages({
  library(dplyr)
  library(purrr)
  library(arrow)
  library(jsonlite)
  library(yaml)
})

legacy_repo <- normalizePath(file.path(dirname(getwd()), "metalab"))
stage_dir <- file.path("etl", "staging", "v2023")
dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)

git_show <- function(path, out) {
  status <- system2("git", c("-C", legacy_repo, "show", paste0("origin/main:", path)),
                    stdout = out)
  stopifnot(status == 0)
  out
}

## ---- effect_sizes + datasets from the Rdata blob ----
rdata_file <- git_show("shinyapps/site_data/Rdata/metalab.Rdata",
                       file.path(stage_dir, "metalab_2023.Rdata"))
load(rdata_file)  # -> metalab_data, dataset_info
stopifnot(exists("metalab_data"), exists("dataset_info"))

cat(sprintf("metalab_data: %d rows x %d cols\n", nrow(metalab_data), ncol(metalab_data)))
cat(sprintf("dataset_info: %d rows x %d cols\n", nrow(dataset_info), ncol(dataset_info)))
stopifnot(nrow(dataset_info) == 32)

# list-columns can't live in scalar parquet/Redivis columns -> JSON-encode
jsonify_list_cols <- function(df) {
  mutate(df, across(where(is.list),
                    ~ map_chr(.x, \(v) as.character(toJSON(v, auto_unbox = FALSE)))))
}

# Redivis rejects '.' in column names; snake_case the one offender everywhere
# it appears (column name, spec field name, dataset moderator lists). This is a
# deliberate schema change vs the legacy CSVs -- documented in NEWS.
rename_map <- c("rule.type" = "rule_type")
apply_rename <- function(x) ifelse(x %in% names(rename_map), rename_map[x], x)

effect_sizes <- jsonify_list_cols(metalab_data)
names(effect_sizes) <- apply_rename(names(effect_sizes))
datasets <- jsonify_list_cols(dataset_info) %>%
  mutate(moderators = map_chr(moderators, \(j)
    as.character(toJSON(apply_rename(fromJSON(j)), auto_unbox = FALSE))))

write_parquet(effect_sizes, file.path(stage_dir, "effect_sizes.parquet"))
write_parquet(datasets, file.path(stage_dir, "datasets.parquet"))

## ---- fields / fields_derived from the spec YAMLs (same commit state) ----
spec <- yaml.load_file(git_show("metadata/spec.yaml", file.path(stage_dir, "spec.yaml")))
fields <- map_dfr(spec, function(f) {
  tibble(
    field = apply_rename(f$field),
    description = f$description %||% NA_character_,
    type = f$type %||% NA_character_,
    format = as.character(f$format %||% NA_character_),
    example = as.character(f$example %||% NA_character_),
    options = if (is.null(f$options)) NA_character_ else
      as.character(toJSON(f$options, auto_unbox = TRUE)),
    nullable = isTRUE(f$nullable),
    required = isTRUE(f$required)
  )
})
cat(sprintf("fields: %d rows\n", nrow(fields)))
write_parquet(fields, file.path(stage_dir, "fields.parquet"))

spec_derived <- yaml.load_file(git_show("metadata/spec_derived.yaml",
                                        file.path(stage_dir, "spec_derived.yaml")))
fields_derived <- map_dfr(spec_derived, function(f) {
  tibble(field = f$field, description = f$description %||% NA_character_)
})
cat(sprintf("fields_derived: %d rows\n", nrow(fields_derived)))
write_parquet(fields_derived, file.path(stage_dir, "fields_derived.parquet"))

## ---- summary ----
cat("\nPer-dataset effect size counts (2023 snapshot):\n")
effect_sizes %>% count(short_name) %>% arrange(desc(n)) %>% as.data.frame() %>% print()
cat(sprintf("\nTOTAL: %d effect sizes\n", nrow(effect_sizes)))
