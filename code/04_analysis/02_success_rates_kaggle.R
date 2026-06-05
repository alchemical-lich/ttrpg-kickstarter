#!/usr/bin/env Rscript
# 02_success_rates_kaggle.R — True success rates and a funded-vs-not model for
# Tabletop Kickstarters, 2009-2018, using the Kaggle panel (which INCLUDES
# failures, unlike Web Robots). This is the analysis the Web Robots data cannot
# support because of its survivorship bias.
#
# Modeling sample: terminal binary outcome successful vs failed (canceled &
# suspended excluded as ambiguous; reported separately). Predictors are all
# PRE-outcome: goal (real USD), campaign duration, launch year, US dummy, and a
# TTRPG flag (name-only: 96% precision / 61% recall — moderate-recall, so the
# TTRPG coefficient is a selected-subsample view, not the full TTRPG population).
#
# Outputs: tables/kaggle_*.csv and figures/kaggle_*.png

suppressPackageStartupMessages({ library(tidyverse); library(scales) })

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

d <- read_csv(file.path(proj, "data", "processed", "kaggle_tabletop.csv.gz"),
              show_col_types = FALSE) %>%
  filter(launch_year >= 2009, launch_year <= 2018, goal_usd_real > 0)

# ---- 1. True success rate over time (overall + TTRPG subset) ---------------
rate_year <- bind_rows(
  d %>% filter(state %in% c("successful", "failed")) %>%
    group_by(launch_year) %>%
    summarise(group = "all tabletop", n = n(),
              success_rate = mean(state == "successful"), .groups = "drop"),
  d %>% filter(state %in% c("successful", "failed"), is_ttrpg) %>%
    group_by(launch_year) %>%
    summarise(group = "TTRPG (name-only)", n = n(),
              success_rate = mean(state == "successful"), .groups = "drop")
)
write_csv(rate_year, file.path(tabd, "kaggle_success_by_year.csv"))

p_year <- ggplot(rate_year, aes(launch_year, success_rate, color = group)) +
  geom_line() + geom_point() +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  scale_x_continuous(breaks = 2009:2018) +
  scale_color_manual(values = c("all tabletop" = "#2c7fb8",
                                "TTRPG (name-only)" = "#d7191c"), name = NULL) +
  labs(title = "True Tabletop success rate by launch year (Kaggle, incl. failures)",
       subtitle = "Web Robots cannot show this — it captures ~no failures",
       x = "launch year", y = "success rate (successful / [successful+failed])")
ggsave(file.path(figd, "kaggle_success_by_year.png"), p_year, width = 10, height = 4.8, dpi = 130)

# ---- 2. Success rate by goal size (the modest-goal hypothesis) -------------
bk <- c(0, 500, 1e3, 2e3, 5e3, 1e4, 2.5e4, 1e5, Inf)
lab <- c("<$500", "$500-1k", "$1-2k", "$2-5k", "$5-10k", "$10-25k", "$25-100k", "$100k+")
goal_tbl <- d %>%
  filter(state %in% c("successful", "failed")) %>%
  mutate(goal_bucket = cut(goal_usd_real, bk, lab, right = FALSE)) %>%
  group_by(goal_bucket) %>%
  summarise(n = n(), success_rate = mean(state == "successful"), .groups = "drop")
write_csv(goal_tbl, file.path(tabd, "kaggle_success_by_goalbucket.csv"))

p_goal <- ggplot(goal_tbl, aes(goal_bucket, success_rate)) +
  geom_col(fill = "#2c7fb8") +
  geom_text(aes(label = percent(success_rate, 1)), vjust = -0.3, size = 3) +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  labs(title = "Tabletop success rate by funding goal (real USD), 2009-2018",
       x = "goal (real USD)", y = "success rate") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
ggsave(file.path(figd, "kaggle_success_by_goalbucket.png"), p_goal, width = 9, height = 4.8, dpi = 130)

# ---- 3. Funded-vs-not logit -------------------------------------------------
m <- d %>%
  filter(state %in% c("successful", "failed"),
         duration_days > 0, duration_days < 120) %>%
  transmute(funded = as.integer(state == "successful"),
            log10_goal = log10(goal_usd_real),
            duration_days, launch_year = factor(launch_year),
            us = as.integer(country == "US"),
            is_ttrpg = as.integer(is_ttrpg))

fit  <- glm(funded ~ log10_goal + duration_days + launch_year + us + is_ttrpg,
            data = m, family = binomial())
null <- glm(funded ~ 1, data = m, family = binomial())
mcfadden <- as.numeric(1 - logLik(fit) / logLik(null))

co <- summary(fit)$coefficients
res <- tibble(term = rownames(co),
              estimate = co[, 1], std_error = co[, 2], p_value = co[, 4],
              odds_ratio = exp(co[, 1]))
write_csv(res, file.path(tabd, "kaggle_funded_logit.csv"))

cat("######## TRUE SUCCESS RATES (Kaggle Tabletop, 2009-2018) ########\n")
overall <- d %>% filter(state %in% c("successful", "failed"))
cat(sprintf("All tabletop: %.1f%% funded (n=%d, successful vs failed)\n",
            100 * mean(overall$state == "successful"), nrow(overall)))
tt <- overall %>% filter(is_ttrpg)
cat(sprintf("TTRPG (name-only, 96%%prec/61%%rec): %.1f%% funded (n=%d)\n",
            100 * mean(tt$state == "successful"), nrow(tt)))
cat(sprintf("(For reference, Web Robots union shows ~98%% — pure survivorship artifact.)\n"))
cat("\n=== Success rate by goal bucket ===\n"); print(as.data.frame(goal_tbl), digits = 3)
cat(sprintf("\n=== Funded logit (n=%d, McFadden pseudo-R2=%.3f) ===\n", nrow(m), mcfadden))
cat("Key coefficients (odds ratios):\n")
print(res %>% filter(!str_detect(term, "launch_year")) %>%
        mutate(across(where(is.numeric), ~round(.x, 4))) %>% as.data.frame())
cat("\nInterpretation: OR<1 for log10_goal means each 10x larger goal multiplies\n")
cat("the odds of funding by that factor (the modest-goal advantage).\n")
cat("\nFigures -> figures/kaggle_*.png ; tables -> tables/kaggle_*.csv\n")
