#!/usr/bin/env Rscript
# Precompute the multilevel meta-analytic model grid that the visualization
# and power-analysis pages read as JSON. One fit per
#   dataset x subset x ES type x moderator subset (|mods| <= 3),
# replicating the legacy Shiny visualization's model exactly:
#   metafor::rma.mv(yi, V, random = ~1 | short_cite/same_infant_calc/unique_row,
#                   method = "REML"), moderators additive.
#
# Egger's test: the legacy app called regtest() which ALWAYS errored on
# rma.mv objects (silently, hidden by CSS). Here we fit the standard
# multilevel adaptation instead: add sqrt(vi) as a fixed-effect moderator to
# the same model and report its coefficient (z, p).
#
# Row filters replicated from the app: mean_age < 4000 days; subset column
# TRUE (when a subset is chosen); non-NA selected moderators; non-NA ES +
# variance of the selected type. The page's JS re-applies these filters; the
# stored k per combo is the tripwire that both sides agree.
#
# Output: slices/models/<short_name>.json
#   { "<subset>|<es>|<mod1,mod2>": { k, converged, coefs: [...], vcov_lower,
#     sigma2, levels: {col: [level order]}, egger: {z, p}, error? }, ... }

suppressMessages({
  library(dplyr)
  library(purrr)
  library(arrow)
  library(jsonlite)
  library(metafor)
})

stage_dir <- file.path("etl", "staging", "v2026")
es_all <- read_parquet(file.path(stage_dir, "effect_sizes.parquet"))
datasets <- read_parquet(file.path(stage_dir, "datasets.parquet"))
dir.create("slices/models", recursive = TRUE, showWarnings = FALSE)

es_types <- c("g", "d", "r", "log_odds")
standard_mods <- c("mean_age", "response_mode", "exposure_phase")
MAX_MODS <- 3

fit_combo <- function(dat, es_col, var_col, mods) {
  # drop rows with NA in any selected moderator (legacy mod_data())
  for (m in mods) dat <- dat[!is.na(dat[[m]]), ]
  # factor-code categorical moderators with alphabetical levels (R default)
  cat_mods <- mods[!vapply(dat[mods], is.numeric, logical(1))]
  for (m in cat_mods) dat[[m]] <- factor(dat[[m]])
  # degenerate designs: a categorical moderator with < 2 levels
  if (any(vapply(cat_mods, function(m) nlevels(dat[[m]]) < 2, logical(1))))
    return(list(skip = "degenerate"))
  if (nrow(dat) < 3) return(list(skip = "too few rows"))

  yi <- dat[[es_col]]
  V <- dat[[var_col]]
  fml <- if (length(mods) == 0) NULL else
    as.formula(paste("~", paste(mods, collapse = " + ")))

  res <- tryCatch({
    m <- if (is.null(fml)) {
      rma.mv(yi, V,
             random = ~ 1 | short_cite / same_infant_calc / unique_row,
             method = "REML", data = dat, sparse = TRUE)
    } else {
      rma.mv(yi, V, mods = fml,
             random = ~ 1 | short_cite / same_infant_calc / unique_row,
             method = "REML", data = dat, sparse = TRUE)
    }
    vc <- as.matrix(vcov(m))
    egger <- tryCatch({
      dat$sqrt_vi_egger <- sqrt(V)
      efml <- as.formula(paste("~", paste(c(mods, "sqrt_vi_egger"), collapse = " + ")))
      em <- rma.mv(yi, V, mods = efml,
                   random = ~ 1 | short_cite / same_infant_calc / unique_row,
                   method = "REML", data = dat, sparse = TRUE)
      i <- which(rownames(em$b) == "sqrt_vi_egger")
      list(z = unname(em$zval[i]), p = unname(em$pval[i]))
    }, error = function(e) NULL)

    list(
      k = m$k,
      converged = TRUE,
      coefs = data.frame(
        name = rownames(m$b), est = as.numeric(m$b), se = m$se,
        zval = m$zval, pval = m$pval, ci_lb = m$ci.lb, ci_ub = m$ci.ub,
        stringsAsFactors = FALSE),
      vcov_lower = vc[lower.tri(vc, diag = TRUE)],
      sigma2 = as.numeric(m$sigma2),
      levels = if (length(cat_mods) == 0) NULL else
        setNames(lapply(cat_mods, function(mm) levels(dat[[mm]])), cat_mods),
      egger = egger
    )
  }, error = function(e) list(converged = FALSE, error = conditionMessage(e),
                              k = nrow(dat)))
  res
}

t0 <- Sys.time()
n_fit <- 0; n_skip <- 0; n_err <- 0

force <- "--force" %in% commandArgs(trailingOnly = TRUE)

for (i in seq_len(nrow(datasets))) {
  sn <- datasets$short_name[i]
  out_path <- file.path("slices", "models", paste0(sn, ".json"))
  if (file.exists(out_path) && !force) {
    cat(sprintf("%-24s exists, skipping (--force to refit)\n", sn)); next
  }
  custom_mods <- as.character(unlist(fromJSON(datasets$moderators[i])))
  subset_cols <- as.character(unlist(fromJSON(datasets$subset[i])))

  base <- es_all %>%
    filter(short_name == sn, is.na(mean_age) | mean_age < 4000)

  out <- list()
  for (subset_choice in c("All data", subset_cols)) {
    dat_s <- if (subset_choice == "All data") base else
      base[!is.na(base[[subset_choice]]) & base[[subset_choice]] == TRUE, ]

    # moderator pool: standard + dataset-specific, only those with variation
    # (legacy populated checkboxes the same way)
    pool <- unique(c(standard_mods, custom_mods))
    pool <- pool[pool %in% names(dat_s)]
    pool <- pool[vapply(pool, function(m)
      length(unique(dat_s[[m]][!is.na(dat_s[[m]])])) > 1, logical(1))]

    mod_sets <- list(character(0))
    for (size in seq_len(min(MAX_MODS, length(pool))))
      mod_sets <- c(mod_sets, combn(pool, size, simplify = FALSE))

    for (es in es_types) {
      es_col <- paste0(es, "_calc"); var_col <- paste0(es, "_var_calc")
      dat_e <- dat_s[!is.na(dat_s[[es_col]]) & !is.na(dat_s[[var_col]]), ]
      for (mods in mod_sets) {
        key <- paste(subset_choice, es, paste(mods, collapse = ","), sep = "|")
        res <- fit_combo(dat_e, es_col, var_col, mods)
        if (!is.null(res$skip)) { n_skip <- n_skip + 1; next }
        if (isTRUE(res$converged)) n_fit <- n_fit + 1 else n_err <- n_err + 1
        out[[key]] <- res
      }
    }
  }
  write_json(out, out_path, auto_unbox = TRUE, digits = 10, na = "null")
  cat(sprintf("%-24s %4d combos (%.0fs elapsed)\n", sn, length(out),
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

cat(sprintf("\nfits ok: %d, errors: %d, degenerate skips: %d\n", n_fit, n_err, n_skip))
size <- sum(file.size(list.files("slices/models", full.names = TRUE)))
cat(sprintf("slices/models total: %.1f MB\n", size / 1e6))
if (n_err > 0) cat("NOTE: inspect errors before shipping\n")
