#!/usr/bin/env Rscript
# Per-dataset comparison of the staged 2026 release candidate against the
# released 2023 snapshot: row counts, added/removed studies, and effect-size
# drift on matched rows. Written to etl/staging/version_diff.md.

suppressMessages({
  library(dplyr)
  library(purrr)
  library(arrow)
})

es23 <- read_parquet("etl/staging/v2023/effect_sizes.parquet")
es26 <- read_parquet("etl/staging/v2026/effect_sizes.parquet")

counts <- full_join(count(es23, short_name, name = "n_2023"),
                    count(es26, short_name, name = "n_2026"),
                    by = "short_name") %>%
  mutate(across(starts_with("n_"), ~ ifelse(is.na(.x), 0L, .x)),
         delta = n_2026 - n_2023) %>%
  arrange(desc(abs(delta)), short_name)

out <- file("etl/staging/version_diff.md", "w")
w <- function(...) cat(..., "\n", file = out, sep = "")

w("# MetaLab 2026.1 vs 2023 snapshot")
w("")
w(sprintf("Totals: 2023 = %d rows; 2026 = %d rows.", nrow(es23), nrow(es26)))
w("")
w("| dataset | n 2023 | n 2026 | delta | studies added | studies removed |")
w("|---|---|---|---|---|---|")

for (sn in counts$short_name) {
  a <- filter(es23, short_name == sn)
  b <- filter(es26, short_name == sn)
  added <- setdiff(unique(b$study_ID), unique(a$study_ID))
  removed <- setdiff(unique(a$study_ID), unique(b$study_ID))
  w(sprintf("| %s | %d | %d | %+d | %s | %s |",
            sn, nrow(a), nrow(b), nrow(b) - nrow(a),
            if (length(added)) paste(added, collapse = ", ") else "",
            if (length(removed)) paste(removed, collapse = ", ") else ""))
}

## effect-size drift on rows matchable by coding identity
key_cols <- c("short_name", "study_ID", "same_infant", "expt_num",
              "expt_condition", "dependent_measure", "group_name_1", "mean_age_1")
a <- es23 %>%
  group_by(across(all_of(key_cols))) %>% filter(n() == 1) %>% ungroup() %>%
  select(all_of(key_cols), d_23 = d_calc)
b <- es26 %>%
  group_by(across(all_of(key_cols))) %>% filter(n() == 1) %>% ungroup() %>%
  select(all_of(key_cols), d_26 = d_calc)
m <- inner_join(a, b, by = key_cols) %>%
  mutate(diff = abs(d_23 - d_26))

w("")
w(sprintf("Matched unique rows (by %s): %d.", paste(key_cols, collapse = "+"), nrow(m)))
w(sprintf("d_calc identical (< 1e-9): %d; changed: %d.",
          sum(m$diff < 1e-9, na.rm = TRUE), sum(m$diff >= 1e-9, na.rm = TRUE)))
changed <- m %>% filter(diff >= 1e-9) %>% count(short_name, sort = TRUE)
if (nrow(changed) > 0) {
  w("")
  w("Datasets with changed d_calc on matched rows (n rows):")
  for (i in seq_len(nrow(changed)))
    w(sprintf("- %s: %d", changed$short_name[i], changed$n[i]))
}
close(out)
cat(readLines("etl/staging/version_diff.md"), sep = "\n")
