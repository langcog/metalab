#!/usr/bin/env Rscript
# Validate the in-browser stats implementations (components/_stats.qmd)
# against R's, by evaluating the same JS in a V8-free way: we re-implement
# the JS formulas here in R and compare BOTH to R's reference functions.
# (The JS is a line-for-line transcription of these formulas; this script
# guards the formulas' accuracy, and the JS is checked in-browser by the
# power page's table against pwr::pwr.p.test spot values below.)

suppressMessages({library(pwr)})

fail <- 0
check <- function(name, got, want, tol) {
  d <- max(abs(got - want))
  ok <- d <= tol
  if (!ok) fail <<- fail + 1
  cat(sprintf("%-38s max|diff| = %.2e %s\n", name, d, if (ok) "OK" else "FAIL"))
}

# erf-based pnorm approximation (A&S 7.1.26), as in JS
pnorm_js <- function(x) {
  t <- 1 / (1 + 0.3275911 * abs(x) / sqrt(2))
  y <- 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
    0.284496736) * t + 0.254829592) * t * exp(-(x^2) / 2)
  ifelse(x >= 0, 0.5 * (1 + y), 0.5 * (1 - y))
}
xs <- seq(-4, 4, by = 0.05)
check("pnorm (A&S erf approx)", pnorm_js(xs), pnorm(xs), 1e-6)

# power of two-sided one-sample prop test as in pwr.p.test / JS power_z
power_js <- function(h, n)
  pnorm_js(sqrt(n) * abs(h) - qnorm(0.975)) + pnorm_js(-sqrt(n) * abs(h) - qnorm(0.975))
hs <- c(0.1, 0.3, 0.5, 0.8, 1.2); ns <- c(5, 16, 40, 120)
grid <- expand.grid(h = hs, n = ns)
check("power_z vs pwr.p.test",
      mapply(power_js, grid$h, grid$n),
      mapply(function(h, n) pwr.p.test(h = h, n = n, sig.level = .05)$power,
             grid$h, grid$n), 2e-6)

# N for 80% power (bisection in JS) vs pwr.p.test solve
n_for_power_js <- function(h, target = 0.8) {
  lo <- 2; hi <- 4
  while (power_js(h, hi) < target && hi < 1e5) { lo <- hi; hi <- hi * 2 }
  for (i in 1:60) { mid <- (lo + hi) / 2
    if (power_js(h, mid) < target) lo <- mid else hi <- mid }
  hi
}
check("n_for_power vs pwr.p.test",
      sapply(hs, n_for_power_js),
      sapply(hs, function(h) pwr.p.test(h = h, power = .8, sig.level = .05)$n), 1e-3)

# two-sided t p-value via incomplete beta (Lentz), as in JS
ibeta_js <- function(x, a, b) {
  if (x <= 0) return(0); if (x >= 1) return(1)
  if (x > (a + 1) / (a + b + 2)) return(1 - ibeta_js(1 - x, b, a))
  front <- exp(a * log(x) + b * log(1 - x) - lbeta(a, b)) / a
  h <- 1; c <- 1; d <- 0
  for (i in 0:300) {
    m <- i %/% 2
    numerator <- if (i == 0) 1 else if (i %% 2 == 0)
      (m * (b - m) * x) / ((a + 2 * m - 1) * (a + 2 * m)) else
      -((a + m) * (a + b + m) * x) / ((a + 2 * m) * (a + 2 * m + 1))
    d <- 1 + numerator * d; if (abs(d) < 1e-30) d <- 1e-30; d <- 1 / d
    c <- 1 + numerator / c; if (abs(c) < 1e-30) c <- 1e-30
    h <- h * c * d
    if (abs(1 - c * d) < 1e-9) break
  }
  front * (h - 1)
}
t_p_js <- function(t, df) ibeta_js(df / (df + t^2), df / 2, 0.5)
ts <- c(0.5, 1, 2.1, 3.5); dfs <- c(5, 15, 30, 119)
grid <- expand.grid(t = ts, df = dfs)
check("t p-value vs pt", mapply(t_p_js, grid$t, grid$df),
      mapply(function(t, df) 2 * pt(-abs(t), df), grid$t, grid$df), 1e-7)

f_p_js <- function(F, df1, df2) ibeta_js(df2 / (df2 + df1 * F), df2 / 2, df1 / 2)
check("F p-value vs pf", mapply(f_p_js, c(0.5, 1.5, 4, 10), 1, c(12, 28, 60, 124)),
      mapply(function(F, df2) pf(F, 1, df2, lower.tail = FALSE),
             c(0.5, 1.5, 4, 10), c(12, 28, 60, 124)), 1e-7)

if (fail > 0) stop(fail, " check(s) failed") else cat("\nall stats checks passed\n")
