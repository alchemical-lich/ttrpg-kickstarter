#!/usr/bin/env Rscript
# 12_did_5e.R — DiD / event study around the D&D 5th Edition release (mid-2014),
# Kaggle tabletop 2010-2018 (has FAILURES + name-based TTRPG split). Treated = RPG
# (name-flagged ttrpg); control = non-RPG tabletop (board/card games). Outcomes:
# success rate, log10 pledged (real, among funded), and entry counts.
#
# Event study (LPM): funded ~ i(year, ttrpg, ref=2013) | year — the year-by-year
# TTRPG-vs-control differential. PRE-2014 coefficients ≈ 0 would support parallel
# trends; a jump at/after 2014 is the 5e effect.
#
# HONESTY: 5e is a GRADUAL, partly-anticipated cultural shift (not a sharp shock),
# and the control (board/card games) may itself be lifted by D&D's popularity.
# Read as SUGGESTIVE. TTRPG flag is name-only (~61% recall). If pre-trends are
# non-parallel (the TTRPG premium was already widening), the effect is NOT cleanly
# attributable to 5e — we report that verdict honestly.
#
# Out: tables/did5e_*.csv, figures/did5e_*.png

suppressPackageStartupMessages({ library(tidyverse); library(fixest); library(scales) })
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

d <- read_csv(file.path(proj, "data", "processed", "kaggle_tabletop.csv.gz"),
              show_col_types = FALSE) %>%
  filter(state %in% c("successful", "failed"), ttrpg_label %in% c("ttrpg", "nontt"),
         launch_year >= 2010, launch_year <= 2017,          # 2018 partial; 2009 sparse
         goal_usd_real > 0, duration_days > 0, duration_days < 120) %>%
  mutate(funded = as.integer(state == "successful"),
         ttrpg = as.integer(ttrpg_label == "ttrpg"),
         post2014 = as.integer(launch_year >= 2014),
         log10_goal = log10(goal_usd_real),
         group = if_else(ttrpg == 1, "RPG", "non-RPG tabletop"))

# ---- event study (LPM): TTRPG-vs-control success differential by year ------
es <- feols(funded ~ i(launch_year, ttrpg, ref = 2013) | launch_year, data = d, vcov = "hetero")
esc <- as.data.frame(coeftable(es))
es_tbl <- tibble(term = rownames(esc), coef = esc[, 1], se = esc[, 2]) %>%
  filter(str_detect(term, "launch_year")) %>%
  mutate(year = as.integer(str_extract(term, "\\d{4}")),
         lo = coef - 1.96 * se, hi = coef + 1.96 * se)
write_csv(es_tbl, file.path(tabd, "did5e_eventstudy_success.csv"))

p_es <- ggplot(es_tbl, aes(year, coef)) +
  annotate("rect", xmin = 2014, xmax = 2017.5, ymin = -Inf, ymax = Inf, fill = "grey85", alpha = .5) +
  geom_hline(yintercept = 0, color = "grey50") +
  geom_vline(xintercept = 2013.5, linetype = "dashed") +
  geom_pointrange(aes(ymin = lo, ymax = hi), color = "#2c7fb8") +
  scale_x_continuous(breaks = 2010:2017) +
  labs(title = "5e event study: RPG-vs-control success differential by year",
       subtitle = "LPM i(year, ttrpg, ref=2013); grey = post-5e. Pre-2014 ≈0 = parallel trends.",
       x = "launch year", y = "Δ success prob. (RPG − control), vs 2013")
ggsave(file.path(figd, "did5e_eventstudy.png"), p_es, width = 9.5, height = 4.8, dpi = 130)

# ---- DiD headline: success, pledged (funded), and a raw success-by-year fig
did_succ <- feols(funded ~ ttrpg * post2014 + log10_goal + duration_days | launch_year,
                  data = d, vcov = "hetero")
did_pled <- feols(log10(pledged_usd_real) ~ ttrpg * post2014 + log10_goal + duration_days | launch_year,
                  data = filter(d, funded == 1), vcov = "hetero")
grab <- function(m, lbl) { c <- as.data.frame(coeftable(m));
  tibble(model = lbl, term = rownames(c), coef = c[, 1], se = c[, 2], p = c[, 4]) }
did_tbl <- bind_rows(grab(did_succ, "success (LPM)"), grab(did_pled, "log10 pledged|funded")) %>%
  filter(str_detect(term, "ttrpg"))
write_csv(did_tbl, file.path(tabd, "did5e_did_coefs.csv"))

rate_year <- d %>% group_by(launch_year, group) %>%
  summarise(success = mean(funded), n = n(), .groups = "drop")
p_rate <- ggplot(rate_year, aes(launch_year, success, color = group)) +
  annotate("rect", xmin = 2014, xmax = 2017.5, ymin = -Inf, ymax = Inf, fill = "grey85", alpha = .5) +
  geom_line() + geom_point() +
  scale_y_continuous(labels = percent) + scale_x_continuous(breaks = 2010:2017) +
  scale_color_manual(values = c("RPG" = "#2c7fb8", "non-RPG tabletop" = "#d7191c"), name = NULL) +
  labs(title = "Tabletop success rate by year: RPG vs control (5e released mid-2014)",
       x = "launch year", y = "success rate")
ggsave(file.path(figd, "did5e_success_by_year.png"), p_rate, width = 9.5, height = 4.8, dpi = 130)

# ---- console ---------------------------------------------------------------
cat("######## 5e DiD (Kaggle tabletop 2010-2017) ########\n")
cat(sprintf("n=%d (RPG=%d, control=%d)\n", nrow(d), sum(d$ttrpg), sum(1 - d$ttrpg)))
cat("\n=== Event-study coefficients (RPG-vs-control success diff, vs 2013) ===\n")
print(as.data.frame(es_tbl %>% select(year, coef, se) %>% mutate(across(c(coef, se), ~round(.x, 3)))))
cat("\n=== DiD headline (ttrpg x post2014) ===\n")
print(as.data.frame(did_tbl %>% mutate(across(c(coef, se), ~round(.x, 3)), p = signif(p, 2))))
cat("\nVERDICT depends on pre-trends: if the pre-2014 event-study coefs are already\n")
cat("rising/non-zero, the post-2014 'effect' is not cleanly attributable to 5e.\n")
cat("\nFigures -> figures/did5e_*.png ; tables -> tables/did5e_*.csv\n")
