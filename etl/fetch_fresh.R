#!/usr/bin/env Rscript
# Fetch the current state of all 32 MetaLab Google Sheets and run the legacy
# metalabr pipeline (validation + effect-size computation) to produce the
# 2026.1 release candidate. Uses the unmodified metalabr code (loaded from the
# local clone with its runtime deps attached, exactly as the legacy
# build/update-metalab-data.R did) so this run IS the legacy pipeline, not a
# reimplementation.
#
# Outputs:
#   etl/staging/raw_2026/<short_name>.csv     raw sheet archive (provenance;
#                                             sheets themselves are unversioned)
#   etl/staging/v2026/*.parquet               staged tables for Redivis
#   etl/staging/v2026/metalab_2026.Rdata      metalab_data + dataset_info

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(readr)
  library(jsonlite)
  library(arrow)
})

pkgload::load_all("../metalabr", quiet = TRUE)

raw_dir <- file.path("etl", "staging", "raw_2026")
stage_dir <- file.path("etl", "staging", "v2026")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)

## ---- registry + specs (current main) ----
metadata <- get_metalab_metadata()
specs <- metalabr:::get_metalab_specs()
cat(sprintf("registry: %d datasets; specs: %d fields\n", nrow(metadata), length(specs)))

## ---- archive raw sheets + liveness check ----
## 7 sheets were deleted upstream sometime after the last legacy pipeline run
## (HTTP 410 Gone at the export AND edit endpoints, keys unchanged since 2023):
## those datasets are carried forward verbatim from the 2023 snapshot below.
## Verify by content, not just status: auth/permission failures return HTML.
sheet_alive <- logical(nrow(metadata))
for (i in seq_len(nrow(metadata))) {
  key <- metadata$key[i]
  fn <- file.path(raw_dir, paste0(metadata$short_name[i], ".csv"))
  url <- sprintf("https://docs.google.com/spreadsheets/d/%s/export?id=%s&format=csv", key, key)
  resp <- tryCatch(httr::GET(url), error = function(e) NULL)
  ok <- !is.null(resp) && httr::status_code(resp) == 200
  if (ok) {
    body <- httr::content(resp, as = "raw")
    ok <- length(body) > 100 &&
      !grepl("^\\s*<(!DOCTYPE|html)", rawToChar(body[1:min(50, length(body))]),
             ignore.case = TRUE)
    if (ok) writeBin(body, fn)
  }
  sheet_alive[i] <- ok
  if (!ok) cat(sprintf("sheet UNAVAILABLE (status %s): %s\n",
                       if (is.null(resp)) "no response" else httr::status_code(resp),
                       metadata$short_name[i]))
}
cat(sprintf("archived %d live raw sheets; %d unavailable\n",
            sum(sheet_alive), sum(!sheet_alive)))

live_meta <- metadata[sheet_alive, ]
dead_meta <- metadata[!sheet_alive, ]

## ---- run the legacy pipeline on the live sheets ----
fresh_data <- get_metalab_data(live_meta, specs = specs)

## the critical check: no LIVE dataset silently dropped by validation
got <- unique(fresh_data$short_name)
missing <- setdiff(live_meta$short_name, got)
if (length(missing) > 0) {
  cat("\n!!! DATASETS DROPPED BY VALIDATION:", paste(missing, collapse = ", "), "\n")
  cat("Re-running validation verbosely for each:\n")
  for (sn in missing) {
    cat("\n====", sn, "====\n")
    row <- live_meta[live_meta$short_name == sn, ]
    contents <- metalabr:::fetch_metalab_data(row$key)
    res <- metalabr:::validate_metalab_data(row, contents, specs)
    bad <- map_chr(specs, "field")[!unlist(res)]
    cat("failing fields:", paste(bad, collapse = ", "), "\n")
  }
  stop("validation dropped datasets -- resolve before staging")
}

## ---- carry forward 2023 processed rows for datasets whose sheet is gone ----
## (verbatim from the released v1.0 snapshot: identical values to what the
## legacy site served, and no RNG re-imputation churn for unchanged data)
env23 <- new.env()
load(file.path("etl", "staging", "v2023", "metalab_2023.Rdata"), envir = env23)
frozen_data <- env23$metalab_data %>% filter(short_name %in% dead_meta$short_name)
stopifnot(setequal(unique(frozen_data$short_name), dead_meta$short_name))

col_diff <- union(setdiff(names(fresh_data), names(frozen_data)),
                  setdiff(names(frozen_data), names(fresh_data)))
if (length(col_diff) > 0)
  stop("column mismatch fresh vs 2023: ", paste(col_diff, collapse = ", "))

metalab_data <- bind_rows(fresh_data, frozen_data) %>%
  select(all_of(names(env23$metalab_data))) %>%
  arrange(match(short_name, metadata$short_name))
dataset_info <- metalabr:::add_metalab_summary(metadata, metalab_data) %>%
  mutate(sheet_status = ifelse(short_name %in% dead_meta$short_name,
                               "unavailable_upstream", "live"),
         data_as_of = ifelse(short_name %in% dead_meta$short_name,
                             "2023-04-06", format(Sys.Date())))

cat(sprintf("\n%d datasets total (%d fresh, %d frozen at 2023); %d effect sizes\n",
            length(unique(metalab_data$short_name)), nrow(live_meta),
            nrow(dead_meta), nrow(metalab_data)))

save(metalab_data, dataset_info,
     file = file.path(stage_dir, "metalab_2026.Rdata"), version = 2)

## ---- shape for Redivis (same conventions as the 2023 export) ----
jsonify_list_cols <- function(df) {
  mutate(df, across(where(is.list),
                    ~ map_chr(.x, \(v) as.character(toJSON(v, auto_unbox = FALSE)))))
}
rename_map <- c("rule.type" = "rule_type")
apply_rename <- function(x) ifelse(x %in% names(rename_map), rename_map[x], x)

effect_sizes <- jsonify_list_cols(metalab_data)
names(effect_sizes) <- apply_rename(names(effect_sizes))
datasets <- jsonify_list_cols(dataset_info) %>%
  mutate(moderators = map_chr(moderators, \(j)
    as.character(toJSON(apply_rename(fromJSON(j)), auto_unbox = FALSE))))

write_parquet(effect_sizes, file.path(stage_dir, "effect_sizes.parquet"))
write_parquet(datasets, file.path(stage_dir, "datasets.parquet"))

spec_url <- "https://raw.githubusercontent.com/langcog/metalab/main/metadata/spec.yaml"
spec <- yaml::yaml.load_file(spec_url)
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
write_parquet(fields, file.path(stage_dir, "fields.parquet"))

spec_derived <- yaml::yaml.load_file(
  "https://raw.githubusercontent.com/langcog/metalab/main/metadata/spec_derived.yaml")
fields_derived <- map_dfr(spec_derived, function(f) {
  tibble(field = f$field, description = f$description %||% NA_character_)
})

## the legacy spec_derived.yaml documented only 7 of the pipeline's derived
## columns; document the rest (long-standing gap, cf. metalabr internals)
fields_derived <- bind_rows(fields_derived, tribble(
  ~field, ~description,
  "g_var_calc", "variance of calculated Hedges' g",
  "r_var_calc", "variance of calculated Pearson's r",
  "z_calc", "calculated Fisher's z",
  "z_var_calc", "variance of calculated Fisher's z (1/(n_1-3))",
  "log_odds_calc", "calculated log odds ratio (d * pi/sqrt(3))",
  "log_odds_var_calc", "variance of calculated log odds ratio",
  "es_method", "which branch of the effect-size decision tree produced this row's estimates",
  "mean_age_months", "mean_age converted from days to months (/30.44)",
  "same_infant_calc", "study_ID x same_infant clustering key (statistical independence grouping)",
  "unique_row", "row identifier within dataset (character index)",
  "all_mod", "constant empty string; legacy no-moderator grouping column",
  "year", "publication year extracted from study_ID (Inf if 'submitted')",
  "dataset", "full dataset name (join to datasets.name)",
  "short_name", "dataset short name (join key to datasets.short_name)",
  "domain", "dataset domain (early_language or cognitive_development)"
)) %>% distinct(field, .keep_all = TRUE)
write_parquet(fields_derived, file.path(stage_dir, "fields_derived.parquet"))

cat(sprintf("staged: effect_sizes %d x %d, datasets %d, fields %d, fields_derived %d\n",
            nrow(effect_sizes), ncol(effect_sizes), nrow(datasets),
            nrow(fields), nrow(fields_derived)))
