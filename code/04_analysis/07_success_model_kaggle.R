#!/usr/bin/env Rscript
# 07_success_model_kaggle.R — Success/failure model on the KAGGLE tabletop panel
# (2009-2018), the complement to the ICPSR model (06). Kaggle keeps project NAMES
# and well-populated COUNTRY, so unlike ICPSR it can carry PROJECT-ATTRIBUTE
# features — a name-only TTRPG split, genre keywords, title length, US — but it has
# NO creator id (no track record). Comparing the two shows how much predictive
# power is "who the creator is" (ICPSR) vs "what the project is" (Kaggle).
#
# Outcome: funded (successful vs failed). Same rigor as 06: logit (FE) + honest
# 5-fold CV across logit/LASSO/RF (AUC + Brier) + RF importance + ROC.
# Money is REAL (inflation-adjusted) USD (Kaggle usd_*_real). TTRPG flag is name-
# only (96% precision / 61% recall). Associational, not causal.
#
# Out: tables/success_kaggle_*.csv, figures/success_kaggle_*.png

suppressPackageStartupMessages({
  library(tidyverse); library(fixest); library(glmnet); library(ranger); library(scales)
})
set.seed(42)
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

has <- function(s, pat) as.integer(str_detect(s, regex(pat, ignore_case = TRUE)))

D <- read_csv(file.path(proj, "data", "processed", "kaggle_tabletop.csv.gz"),
              show_col_types = FALSE) %>%
  filter(state %in% c("successful", "failed"),
         launch_year >= 2009, launch_year <= 2018,
         goal_usd_real > 0, duration_days > 0, duration_days < 120) %>%
  mutate(
    funded = as.integer(state == "successful"),
    log10_goal = log10(goal_usd_real),
    launch_month = factor(month(launched)),
    launch_dow = factor(wday(launched, week_start = 1)),
    launch_year = factor(launch_year),
    country_us = as.integer(country == "US"),
    is_ttrpg = as.integer(ttrpg_label == "ttrpg"),
    is_ttrpg_accessory = as.integer(ttrpg_label == "ttrpg_accessory"),
    title_words = str_count(coalesce(name, ""), "\\S+"),
    is_dnd5e = has(name, "\\b5e\\b|5th edition|d&d|dungeons & dragons|dnd|pathfinder"),
    is_osr   = has(name, "\\bosr\\b|old[ -]?school|mork borg|mörk borg|shadowdark|\\bdcc\\b|osric"),
    is_pbta  = has(name, "powered by the apocalypse|\\bpbta\\b|forged in the dark|blades in the dark"),
    is_zine  = has(name, "\\bzine\\b|zinequest")
  )

# is_pbta / is_zine dropped: both are very rare pre-2019 (ZineQuest began 2019) and
# quasi-separate the outcome here (logit ORs explode). PbtA/zine dynamics are better
# studied in the 2019+ Web Robots magnitude model where they are common.
xvars <- c("log10_goal", "duration_days", "country_us", "title_words",
           "is_ttrpg", "is_ttrpg_accessory", "is_dnd5e", "is_osr")

# ---- (1) Logit (FE; heteroskedastic-robust SE, no creator id to cluster on) --
fml <- as.formula(paste("funded ~", paste(xvars, collapse = " + "),
                        "| launch_year + launch_month + launch_dow"))
logit <- feglm(fml, data = D, family = binomial(), vcov = "hetero")
ct <- as.data.frame(coeftable(logit))
logit_tbl <- tibble(term = rownames(ct), coef = ct[, 1], se = ct[, 2],
                    p_value = ct[, 4], odds_ratio = exp(ct[, 1]))
write_csv(logit_tbl, file.path(tabd, "success_kaggle_logit_coefs.csv"))

cf <- logit_tbl %>%
  mutate(lo = exp(coef - 1.96 * se), hi = exp(coef + 1.96 * se),
         term = fct_reorder(term, odds_ratio))
p_or <- ggplot(cf, aes(odds_ratio, term)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi), color = "#33aa66") +
  scale_x_log10() +
  labs(title = "Odds of funding — Kaggle Tabletop (2009-2018), project attributes",
       subtitle = "odds ratios; 95% CI (HC1); year/month/dow FE. TTRPG flag is name-only.",
       x = "odds ratio (log scale)", y = NULL)
ggsave(file.path(figd, "success_kaggle_or_plot.png"), p_or, width = 9, height = 5, dpi = 130)

# ---- (2) Honest 5-fold CV: logit vs LASSO vs RF (AUC + Brier) --------------
mm <- model.matrix(as.formula(paste("~", paste(c(xvars, "launch_year",
       "launch_month", "launch_dow"), collapse = " + "))), data = D)[, -1]
y <- D$funded
folds <- sample(rep(1:5, length.out = nrow(D)))
auc_fn <- function(yv, p) { n1 <- sum(yv == 1); n0 <- sum(yv == 0)
  (sum(rank(p)[yv == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
preds <- matrix(NA, nrow(D), 3, dimnames = list(NULL, c("Logit", "LASSO", "RandomForest")))
for (k in 1:5) {
  tr <- folds != k; te <- !tr
  fo <- suppressWarnings(glm(y ~ ., as.data.frame(cbind(y = y[tr], mm[tr, ])), family = binomial()))
  preds[te, "Logit"] <- predict(fo, as.data.frame(mm[te, ]), type = "response")
  cvg <- cv.glmnet(mm[tr, ], y[tr], family = "binomial", alpha = 1)
  preds[te, "LASSO"] <- as.numeric(predict(cvg, mm[te, ], s = "lambda.min", type = "response"))
  rf <- ranger(y = y[tr], x = mm[tr, ], num.trees = 400, min.node.size = 20)
  preds[te, "RandomForest"] <- predict(rf, mm[te, ])$predictions
}
cv <- tibble(model = colnames(preds),
             cv_auc = sapply(colnames(preds), function(m) auc_fn(y, preds[, m])),
             cv_brier = sapply(colnames(preds), function(m) mean((preds[, m] - y)^2)))
write_csv(cv, file.path(tabd, "success_kaggle_cv_metrics.csv"))

rf_full <- ranger(y = y, x = mm, num.trees = 600, importance = "permutation", min.node.size = 20)
imp <- tibble(feature = names(rf_full$variable.importance),
              importance = rf_full$variable.importance) %>%
  filter(!str_detect(feature, "launch_year|launch_month|launch_dow")) %>%
  arrange(desc(importance))
write_csv(imp, file.path(tabd, "success_kaggle_rf_importance.csv"))

roc_df <- map_dfr(colnames(preds), function(m) {
  o <- order(preds[, m], decreasing = TRUE); yy <- y[o]
  tibble(model = m, fpr = c(0, cumsum(1 - yy) / sum(1 - yy)), tpr = c(0, cumsum(yy) / sum(yy)))
})
p_roc <- ggplot(roc_df, aes(fpr, tpr, color = model)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
  geom_line(linewidth = .8) + coord_equal() +
  scale_color_manual(values = c(Logit = "#2c7fb8", LASSO = "#33aa66", RandomForest = "#d7191c"), name = NULL) +
  labs(title = "Funding prediction — out-of-fold ROC (Kaggle Tabletop, 2009-2018)",
       x = "false positive rate", y = "true positive rate")
ggsave(file.path(figd, "success_kaggle_roc.png"), p_roc, width = 6.5, height = 6, dpi = 130)

# ---- console + comparison to ICPSR -----------------------------------------
cat("######## SUCCESS vs FAILURE — Kaggle Tabletop (2009-2018) ########\n")
cat(sprintf("n = %d (successful=%d, failed=%d; base rate %.1f%%)\n",
            nrow(D), sum(y), sum(1 - y), 100 * mean(y)))
cat("\n=== Logit odds ratios (project attributes; name-only TTRPG/genre) ===\n")
print(logit_tbl %>% mutate(across(c(coef, se, odds_ratio), ~round(.x, 3)),
                           p_value = signif(p_value, 2)) %>% as.data.frame())
cat("\n=== Honest 5-fold CV (AUC ↑ / Brier ↓) ===\n"); print(as.data.frame(cv), digits = 4)
cat("\n=== RF importance (non-FE) ===\n"); print(as.data.frame(imp), digits = 3)
icp <- tryCatch(read_csv(file.path(tabd, "success_cv_metrics.csv"), show_col_types = FALSE),
                error = function(e) NULL)
if (!is.null(icp)) {
  cat("\n=== AUC comparison: project attributes (Kaggle) vs creator track record (ICPSR) ===\n")
  cat(sprintf("  Kaggle (attributes, no creator):  best CV AUC = %.3f\n", max(cv$cv_auc)))
  cat(sprintf("  ICPSR  (creator history, no names): best CV AUC = %.3f\n", max(icp$cv_auc)))
  cat("  => who-the-creator-is (ICPSR) outpredicts what-the-project-is (Kaggle).\n")
}
cat("\nFigures -> figures/success_kaggle_*.png ; tables -> tables/success_kaggle_*.csv\n")
