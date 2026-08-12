#!/usr/bin/env Rscript
# Extract the published model artifacts of Cao et al. (2025, Developmental
# Science) "Estimating Age-Related Change ... Using (Meta-)Meta-Analysis"
# from the paper's companion repo (anjiecao/metalabr_exp, cloned locally)
# into JSON slices for the site's age-curves page.
#
# Everything here is "as published": fitted trajectories with CIs
# (full_age_pred_df), AICc model comparison (age_models_df), and linear age
# slopes (all_slope_estimates) come from the paper's cached model objects,
# not from refitting. (The paper's 25-dataset corpus involved merges/splits
# and an updated IDS dataset, and several source sheets no longer exist, so
# the cached fits are the canonical record.)
#
# Usage: Rscript etl/extract_cao.R <path-to-metalabr_exp>

suppressMessages({
  library(dplyr)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
repo <- if (length(args) >= 1) args[[1]] else "../metalabr_exp"
stopifnot(dir.exists(file.path(repo, "cached_data")))
dir.create("slices/cao", recursive = TRUE, showWarnings = FALSE)

## ---- fitted trajectories (Figure 1) ----
pred <- readRDS(file.path(repo, "cached_data", "full_age_pred_df.RDS"))
# identify the functional form from the design columns present per row
form_of <- function(df) {
  dplyr::case_when(
    !is.na(df[["X.const.mean_age_months"]]) ~ "Constant",
    !is.na(df[["X.I.mean_age_months.2."]]) ~ "Quadratic",
    !is.na(df[["X.log.mean_age_months."]]) ~ "Log",
    TRUE ~ "Linear"
  )
}
# age grid: linear rows carry it directly; log rows carry log(age); quadratic
# rows carry age; const rows carry a 0..1 dummy grid scaled later? -> keep
# the x provided per row type
pred$form_v <- form_of(pred)
curves <- pred %>%
  mutate(form = form_v,
         age_months = dplyr::case_when(
           form == "Linear" ~ X.mean_age_months,
           # the quadratic prediction frame stores the age^2 design values
           form == "Quadratic" ~ sqrt(`X.I.mean_age_months.2.`),
           form == "Log" ~ exp(`X.log.mean_age_months.`),
           form == "Constant" ~ X.const.mean_age_months
         )) %>%
  select(dataset = ds_name, form, age_months, pred, ci_lb = ci.lb,
         ci_ub = ci.ub) %>%
  filter(is.finite(age_months))
write_json(curves, "slices/cao/curves.json", dataframe = "rows", digits = 6,
           na = "null")
cat(sprintf("curves: %d rows, %d datasets, forms: %s\n",
            nrow(curves), dplyr::n_distinct(curves$dataset),
            paste(sort(unique(curves$form)), collapse = ", ")))

## ---- AICc model comparison (Table 2) ----
aic <- readRDS(file.path(repo, "cached_data", "age_models_df.Rds")) %>%
  filter(ic == "AICc") %>%
  transmute(dataset, form = model_spec_clean, aicc = REML) %>%
  group_by(dataset) %>%
  mutate(delta = aicc - min(aicc)) %>%
  ungroup()
write_json(aic, "slices/cao/aic.json", dataframe = "rows", digits = 4)
cat(sprintf("aic: %d rows (%d datasets)\n", nrow(aic),
            dplyr::n_distinct(aic$dataset)))

## ---- linear age slopes (Figure 2) ----
slopes <- readRDS(file.path(repo, "cached_data", "all_slope_estimates.Rds")) %>%
  filter(model_spec_clean == "Linear", term == "mean_age_months") %>%
  transmute(dataset, estimate, ci_lb = conf.low, ci_ub = conf.high,
            p = p.value, significant = p.value < 0.05)
write_json(slopes, "slices/cao/slopes.json", dataframe = "rows", digits = 6)
cat(sprintf("slopes: %d datasets, %d significant\n", nrow(slopes),
            sum(slopes$significant)))
