#!/usr/bin/env Rscript
# 15_funding_threshold_rd.R — Regression discontinuity at the 100%-of-goal line.
#
# Kickstarter is ALL-OR-NOTHING: a project that reaches 100% of its goal collects
# the money; one that ends at 99% collects nothing. Two creators who finish at
# 99.5% vs 100.5% are, to a few dollars, indistinguishable in demand — but one is
# "funded" and one is not. That sharp cutoff is a regression-discontinuity design:
# crossing the line is as-good-as-random in a narrow window, so any jump in a
# creator's LATER behavior is a clean causal estimate of "what getting funded does."
#
# Question: does barely getting funded change a creator's future trajectory?
#   y1  relaunch    — does the creator launch ANOTHER tabletop project afterwards?
#   y2  next_funded — conditional on relaunching, does that next project get funded?
#
# Data: ICPSR 38050 tabletop (includes FAILURES -> running var spans both sides;
#       has UID creator id -> can link a creator's later projects). Web Robots is
#       funded-biased (almost no sub-100% projects) so it CANNOT support this RD;
#       ICPSR is the only source with the left side of the cutoff.
#
# Identification caveats handled here:
#   - Manipulation: creators can self-pledge to nudge over 100% -> bunching just
#     above the cutoff would break the design. We run the McCrary/rddensity test.
#   - Censoring: a project launched in 2023 has no time to "relaunch" before the
#     panel ends. We restrict focal launches to <=2021 (>=~2yr follow-up).
#   - Known creator only: relaunch is undefined without a creator id (uid).
#
# Out: tables/rd_funding_threshold.csv, figures/rd_*.png
suppressPackageStartupMessages({
  library(tidyverse); library(rdrobust); library(rddensity)
})
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

d <- read_csv(file.path(proj, "data", "processed", "icpsr_tabletop.csv.gz"),
              show_col_types = FALSE) %>%
  filter(!is.na(uid), !is.na(pct_of_goal), !is.na(launched), terminal) %>%
  mutate(launched = as.Date(launched))

# ---- build creator-forward outcomes (later tabletop project by same uid) ----
d <- d %>% arrange(uid, launched)
later <- d %>% select(uid, launched, funded) %>% rename(l_launch = launched, l_funded = funded)

# for each focal project, find same-uid projects launched strictly later
fwd <- d %>%
  select(pid, uid, launched) %>%
  inner_join(later, by = "uid", relationship = "many-to-many") %>%
  filter(l_launch > launched) %>%
  group_by(pid) %>%
  summarise(relaunch = 1L,
            next_funded = l_funded[which.min(l_launch)],   # outcome of the very next one
            .groups = "drop")

d <- d %>%
  left_join(fwd, by = "pid") %>%
  mutate(relaunch = replace_na(relaunch, 0L),
         r = pct_of_goal - 1)                              # running var, cutoff 0

# focal restriction: enough follow-up time (panel ends 2023)
foc <- d %>% filter(launch_year <= 2021)
cat(sprintf("focal projects (uid known, terminal, <=2021): %d  | relaunch rate %.3f\n",
            nrow(foc), mean(foc$relaunch)))
cat(sprintf("  just below cutoff [-.1,0): %d   just above [0,.1): %d\n",
            sum(foc$r >= -.1 & foc$r < 0), sum(foc$r >= 0 & foc$r < .1)))

# ---- McCrary / rddensity manipulation test --------------------------------
dens <- rddensity(foc$r, c = 0)
mc_p <- dens$test$p_jk
cat(sprintf("\nManipulation (rddensity) test p = %.4f  (low p => bunching => RD suspect)\n", mc_p))

rdpd <- rdplotdensity(dens, foc$r, plotRange = c(-1, 1.5), plotN = 50,
                      CItype = "all")
p_dens <- rdpd$Estplot +
  labs(title = "Manipulation test: density of pledged/goal around the funding line",
       subtitle = sprintf("sharp spike just above 0 = bunching over 100%% (rddensity p = %.3g)", mc_p),
       x = "pledged/goal - 1   (0 = exactly met goal)", y = "density")
ggsave(file.path(figd, "rd_density_mccrary.png"), p_dens, width = 8, height = 4.6, dpi = 130)

# ---- RD estimates ----------------------------------------------------------
rd_one <- function(y, lbl, p = 1) {
  m <- rdrobust(y = y, x = foc$r, c = 0, p = p, kernel = "triangular",
                bwselect = "mserd", cluster = foc$uid)
  tibble(outcome = lbl, poly = p,
         rd = m$coef["Conventional", 1],
         se_rb = m$se["Robust", 1],
         p_rb = m$pv["Robust", 1],
         ci_lo = m$ci["Robust", 1], ci_hi = m$ci["Robust", 2],
         bw = m$bws["h", 1], n_left = m$N_h[1], n_right = m$N_h[2])
}

res <- bind_rows(
  rd_one(foc$relaunch, "relaunch (any later project)", 1),
  rd_one(foc$relaunch, "relaunch (any later project)", 2),
  # next_funded defined only for relaunchers
  {
    sub <- foc %>% filter(relaunch == 1L)
    m <- rdrobust(y = sub$next_funded, x = sub$r, c = 0, p = 1,
                  kernel = "triangular", bwselect = "mserd", cluster = sub$uid)
    tibble(outcome = "next project funded | relaunched", poly = 1,
           rd = m$coef["Conventional", 1], se_rb = m$se["Robust", 1],
           p_rb = m$pv["Robust", 1], ci_lo = m$ci["Robust", 1],
           ci_hi = m$ci["Robust", 2], bw = m$bws["h", 1],
           n_left = m$N_h[1], n_right = m$N_h[2])
  }
)
res <- res %>% mutate(mccrary_p = mc_p)
write_csv(res, file.path(tabd, "rd_funding_threshold.csv"))
cat("\n=== RD estimates (effect of crossing 100% of goal) ===\n")
print(as.data.frame(res %>% mutate(across(where(is.numeric), ~round(.x, 4)))))

# ---- RD plot for the headline outcome (relaunch) ---------------------------
rdp <- rdplot(y = foc$relaunch, x = foc$r, c = 0, p = 1, kernel = "triangular",
       x.lim = c(-1, 1.5), binselect = "esmv", hide = TRUE,
       title = "Does barely getting funded make a creator launch again?",
       x.label = "pledged/goal - 1   (0 = exactly met goal)",
       y.label = "P(creator launches another tabletop project)")
ggsave(file.path(figd, "rd_relaunch.png"), rdp$rdplot, width = 8.5, height = 5, dpi = 130)

# ---- cleaner binned-means RD figure (shows BOTH sides honestly) ------------
bins <- foc %>%
  filter(r >= -1, r <= 1) %>%
  mutate(rb = floor(r / 0.05) * 0.05 + 0.025,
         side = if_else(r >= 0, "funded", "fell short")) %>%
  group_by(rb, side) %>%
  summarise(relaunch = mean(relaunch), n = n(), .groups = "drop")
p_bin <- ggplot(bins, aes(rb, relaunch, colour = side)) +
  geom_vline(xintercept = 0, linewidth = .4, colour = "grey40") +
  geom_point(aes(size = n), alpha = .6) +
  geom_smooth(method = "lm", se = TRUE, linewidth = .8,
              data = bins, aes(weight = n)) +
  scale_color_manual(values = c("funded" = "#2c7fb8", "fell short" = "#d95f0e"), name = NULL) +
  scale_size_area(max_size = 6, guide = "none") +
  labs(title = "Closer-to-goal failures relaunch more; crossing the line adds little",
       subtitle = "binned means (point size = n); the gradient is smooth, the cutoff jump is not robust",
       x = "pledged/goal - 1   (0 = exactly met goal)",
       y = "P(creator launches another tabletop project)")
ggsave(file.path(figd, "rd_relaunch_binned.png"), p_bin, width = 8.5, height = 5, dpi = 130)

cat("\nFigures -> figures/rd_density_mccrary.png, figures/rd_relaunch.png, figures/rd_relaunch_binned.png\n")
cat("Table   -> tables/rd_funding_threshold.csv\n")
