# Open-issue triage (2026-08-11, datapage migration)

Status of every open issue against the rebuilt site (`datapage` branch),
Redivis releases, and metalabr 1.0.0. "Close" recommendations are for the
maintainers to action at cutover.

## langcog/metalabr

| # | Issue | Verdict |
|---|---|---|
| 6 | `bind_rows` not found | **Fixed in 1.0.0** — namespace imports declared; close |
| 8 | Provide version when data are retrieved | **Fixed in 1.0.0** — `version=` argument + release message on every call; close |
| 12 | Complete roxygen documentation | **Fixed in 1.0.0** — all exports documented, `R CMD check` clean; close |
| 13 | Move shiny apps into package | **Obsolete** — apps superseded by the static site (`viz_app()` deprecated); close |
| 10 | Too many public functions? | **Addressed** — API reduced to data access + plots + versions; close with summary |
| 9 | Rename `compute_es` | Internal function now; suggest close (name kept for pipeline continuity) |
| 7 | Meta-analytic visualization functions | **Fixed in 1.0.0** — four working plot functions + `metalab_funnel_test()`; close |

## langcog/metalab

**Resolved by the rebuild (close at cutover):**

| # | Issue | Verdict |
|---|---|---|
| 4 | Visualizations don't load | New in-browser visualizations; no app server to die |
| 12 | Search not working | Quarto site search works |
| 99 | Fix visualization link on front page | New front page |
| 17 | Downloading data | CSV downloads on every page + versioned Redivis archive |
| 44 | Version control of datasets | Redivis releases (2023.1, 2026.1) + `metalabr::get_metalab_data(version=)` |
| 6 | Move Documentation under About | Done — About is tabbed (About/Team/Changelog) |
| 37 | Bug in power app | Power tools rewritten; simulation duplication bug fixed (see site changelog) |
| 81 | metafor update broke rma.mv random effects | Model grid fits with current metafor (4.8); site no longer runs legacy app code |
| 73 | Adapt metafor reporter() for rma.mv | Superseded by the model-summary tab (coefficients, σ², CIs) |

**Dataset content (curator work; unaffected by migration):**
117 (prosocial papers), 114/113 (mutual exclusivity updates), 97 (phonotactics
dataset), 10 (missing cross-situational lines), 68 (ES not computed from
F/t in some rows — worth a data audit against the decision tree; the
pipeline does compute from t and F when inputs are present).

**Format / coding policy (community decisions):**
96 (longitudinal format), 93 (neuro coding instructions), 39 (effect
direction in habituation), 22 (recode looking/eye-tracking), 8 (derive
correlation from SD — note the pipeline already recovers within-subject r
from SDs + t where possible), 5 (spec.yaml column updates), 67 (new
datasets.yaml fields).

**Docs / site content (easy follow-ups on the new site):**
107 (publications list — new page exists; extend), 106 (ESMARConf talk),
7 (tutorial restructure).

**Feature ideas (possible on the new architecture):**
98 (method as a default moderator in the explorer — trivial now),
91 (show preregistered/in-progress MAs), 92 (metapower tool),
110 (risk-of-bias tool), 90 (validate other metadata files),
84 (extra tabular dataset?), 109 (migrate metalab2 issues — admin).
