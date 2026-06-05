#!/usr/bin/env Rscript
# 03_success_rates_icpsr.R — Authoritative TABLETOP-level success rates, 2009-2023,
# from ICPSR 38050 (42,776 tabletop projects incl. failures). Extends the Kaggle
# panel (2009-2018) to 2023 and cross-validates against it on the overlap.
#
# Scope note: ICPSR public-use NAMES are masked, so this is TABLETOP-GAMES level
# (no clean TTRPG split — that stays the Kaggle name-only analysis, script 02).
# Money is NOMINAL USD here (ICPSR GOAL_IN_USD/PLEDGED_IN_USD are not CPI-adjusted),
# unlike the Kaggle real-USD fields — so compare goal *gradients*, not absolute cuts.
#
# Outputs: tables/icpsr_*.csv and figures/icpsr_*.png

suppressPackageStartupMessages({ library(tidyverse); library(scales) })

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

ic <- read_csv(file.path(proj, "data", "processed", "icpsr_tabletop.csv.gz"),
               show_col_types = FALSE) %>%
  filter(launch_year >= 2009, launch_year <= 2023)
icb <- ic %>% filter(state %in% c("successful", "failed"))  # binary outcome

# ---- 1. success rate by year (2009-2023), with Kaggle cross-check 2009-2018 ----
icr <- icb %>% group_by(launch_year) %>%
  summarise(success_rate = mean(state == "successful"), n = n(), .groups = "drop") %>%
  mutate(source = "ICPSR (2009-2023)")

kg <- read_csv(file.path(proj, "data", "processed", "kaggle_tabletop.csv.gz"),
               show_col_types = FALSE) %>%
  filter(state %in% c("successful", "failed"), launch_year >= 2009, launch_year <= 2018) %>%
  group_by(launch_year) %>%
  summarise(success_rate = mean(state == "successful"), n = n(), .groups = "drop") %>%
  mutate(source = "Kaggle (2009-2018)")

rate_year <- bind_rows(icr, kg)
write_csv(rate_year, file.path(tabd, "icpsr_success_by_year.csv"))

p_year <- ggplot(rate_year, aes(launch_year, success_rate, color = source)) +
  geom_line() + geom_point() +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  scale_x_continuous(breaks = 2009:2023) +
  scale_color_manual(values = c("ICPSR (2009-2023)" = "#2c7fb8",
                                "Kaggle (2009-2018)" = "#d7191c"), name = NULL) +
  labs(title = "True Tabletop success rate by launch year (incl. failures)",
       subtitle = "ICPSR extends to 2023; overlaps Kaggle 2009-2018 as a cross-check",
       x = "launch year", y = "success rate (successful / [successful+failed])") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(figd, "icpsr_success_by_year.png"), p_year, width = 10, height = 4.8, dpi = 130)

# ---- 2. success rate by goal size (nominal USD) ----------------------------
bk  <- c(0, 500, 1e3, 2e3, 5e3, 1e4, 2.5e4, 1e5, Inf)
lab <- c("<$500", "$500-1k", "$1-2k", "$2-5k", "$5-10k", "$10-25k", "$25-100k", "$100k+")
goal_tbl <- icb %>%
  filter(goal_usd > 0) %>%
  mutate(goal_bucket = cut(goal_usd, bk, lab, right = FALSE)) %>%
  group_by(goal_bucket) %>%
  summarise(n = n(), success_rate = mean(state == "successful"), .groups = "drop")
write_csv(goal_tbl, file.path(tabd, "icpsr_success_by_goalbucket.csv"))

p_goal <- ggplot(goal_tbl, aes(goal_bucket, success_rate)) +
  geom_col(fill = "#2c7fb8") +
  geom_text(aes(label = percent(success_rate, 1)), vjust = -0.3, size = 3) +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  labs(title = "Tabletop success rate by goal (nominal USD), ICPSR 2009-2023",
       x = "goal (nominal USD)", y = "success rate") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
ggsave(file.path(figd, "icpsr_success_by_goalbucket.png"), p_goal, width = 9, height = 4.8, dpi = 130)

# ---- 3. funded logit (tabletop level) --------------------------------------
# NOTE: ICPSR PROJECT_PAGE_LOCATION_COUNTRY is missing for ~60% of rows, so we do
# NOT use a country predictor here (it would drop most of the sample); the Kaggle
# model carries the US effect. Predictors are all pre-outcome.
m <- icb %>%
  filter(goal_usd > 0, duration_days > 0, duration_days < 120) %>%
  transmute(funded = as.integer(state == "successful"),
            log10_goal = log10(goal_usd), duration_days,
            launch_year = factor(launch_year))
fit  <- glm(funded ~ log10_goal + duration_days + launch_year, data = m, family = binomial())
null <- glm(funded ~ 1, data = fit$model, family = binomial())  # matched estimation sample
mcf  <- as.numeric(1 - logLik(fit) / logLik(null))
pr   <- predict(fit, type = "response")
auc  <- as.numeric((sum(rank(pr)[m$funded == 1]) - sum(m$funded) * (sum(m$funded) + 1) / 2) /
                   (sum(m$funded) * sum(m$funded == 0)))
co <- summary(fit)$coefficients
res <- tibble(term = rownames(co), estimate = co[, 1], std_error = co[, 2],
              p_value = co[, 4], odds_ratio = exp(co[, 1]))
write_csv(res, file.path(tabd, "icpsr_funded_logit.csv"))

# ---- console -------------------------------------------------------------
cat("######## ICPSR Tabletop success (2009-2023, incl. failures) ########\n")
cat(sprintf("All years: %.1f%% funded (n=%d, succ vs failed)\n",
            100 * mean(icb$state == "successful"), nrow(icb)))
cat(sprintf("2009-2018 subset: %.1f%%  vs Kaggle %.1f%%  (cross-check)\n",
            100 * mean(icb$state[icb$launch_year <= 2018] == "successful"),
            100 * mean(read_csv(file.path(proj,"data","processed","kaggle_tabletop.csv.gz"),
                       show_col_types=FALSE) %>%
                       filter(state %in% c("successful","failed")) %>% pull(state) == "successful")))
cat("\n=== success by year ===\n"); print(as.data.frame(icr), digits = 3)
cat("\n=== success by goal bucket ===\n"); print(as.data.frame(goal_tbl), digits = 3)
cat(sprintf("\n=== Funded logit (n=%d, McFadden=%.3f, AUC=%.3f) ===\n", nrow(m), mcf, auc))
print(res %>% filter(!str_detect(term, "launch_year")) %>%
        mutate(across(where(is.numeric), ~round(.x, 4))) %>% as.data.frame())
cat("\nFigures -> figures/icpsr_*.png ; tables -> tables/icpsr_*.csv\n")
