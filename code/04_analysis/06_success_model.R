#!/usr/bin/env Rscript
# 06_success_model.R — Predictive model of SUCCESS vs FAILURE for Tabletop
# Kickstarters, 2009-2023 (ICPSR, which includes failures). Parallels the
# drivers-of-magnitude model in rigor: interpretable logit + honest 5-fold CV
# across logit / LASSO / random forest, with AUC + Brier (not in-sample fit).
#
# Outcome: funded = (state == "successful"); sample = terminal successful vs failed.
# Predictors are PRE-/AT-LAUNCH: goal, duration, launch timing, and CREATOR TRACK
# RECORD (prior funded / failed / success-rate across all categories — incl.
# failures, which the funded-only Web Robots data could not provide).
#
# Scope/caveats: ICPSR is TABLETOP-level (names masked → no clean TTRPG split; that
# stays the Kaggle analysis). No video/text/staff_pick (not in ICPSR). log10_goal is
# endogenous (chosen anticipating demand). Country dropped (~60% missing).
# Associational, not causal.
#
# Out: tables/success_*.csv, figures/success_*.png

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

D <- read_csv(file.path(proj, "data", "processed", "icpsr_tabletop.csv.gz"),
              show_col_types = FALSE) %>%
  filter(state %in% c("successful", "failed"),
         launch_year >= 2009, launch_year <= 2023,
         goal_usd > 0, duration_days > 0, duration_days < 120) %>%
  mutate(
    funded = as.integer(state == "successful"),
    log10_goal = log10(goal_usd),
    launch_month = factor(month(launched)),
    launch_dow = factor(wday(launched, week_start = 1)),
    launch_year = factor(launch_year),
    creator_known = as.integer(!is.na(creator_prior_n)),
    has_prior = as.integer(coalesce(creator_prior_n, 0) > 0),  # creator has >=1 prior project
    cprior_funded = coalesce(creator_prior_funded, 0),
    cprior_failed = coalesce(creator_prior_failed, 0),
    csuccess_rate = coalesce(creator_prior_success_rate, 0),
    log1p_prior_funded = log1p(cprior_funded),
    log1p_prior_failed = log1p(cprior_failed),
    creator_cluster = ifelse(is.na(uid), -row_number(), uid)
  )

# has_prior absorbs first-timers so csuccess_rate is identified off creators with a
# track record (referee Minor: csuccess_rate=0 had conflated first-timers w/ 0%-success).
xvars <- c("log10_goal", "duration_days", "log1p_prior_funded",
           "log1p_prior_failed", "csuccess_rate", "has_prior", "creator_known")

# ---- (1) Logit (fixest) with FE + SE clustered by creator ------------------
fml <- as.formula(paste("funded ~", paste(xvars, collapse = " + "),
                        "| launch_year + launch_month + launch_dow"))
logit <- feglm(fml, data = D, family = binomial(), cluster = ~creator_cluster)
ct <- as.data.frame(coeftable(logit))
logit_tbl <- tibble(term = rownames(ct), coef = ct[, 1], se = ct[, 2],
                    p_value = ct[, 4], odds_ratio = exp(ct[, 1]))
write_csv(logit_tbl, file.path(tabd, "success_logit_coefs.csv"))

cf <- logit_tbl %>%
  mutate(lo = exp(coef - 1.96 * se), hi = exp(coef + 1.96 * se),
         term = fct_reorder(term, odds_ratio))
p_or <- ggplot(cf, aes(odds_ratio, term)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi), color = "#d7191c") +
  scale_x_log10() +
  labs(title = "Odds of funding — Tabletop Kickstarter (ICPSR 2009-2023)",
       subtitle = "odds ratios; 95% CI, SE clustered by creator; year/month/dow FE",
       x = "odds ratio (log scale)", y = NULL)
ggsave(file.path(figd, "success_or_plot.png"), p_or, width = 9, height = 4.5, dpi = 130)

# ---- (2) Honest 5-fold CV: logit vs LASSO vs RF (AUC + Brier) --------------
mm <- model.matrix(as.formula(paste("~", paste(c(xvars, "launch_year",
       "launch_month", "launch_dow"), collapse = " + "))), data = D)[, -1]
y <- D$funded
folds <- sample(rep(1:5, length.out = nrow(D)))
auc_fn <- function(yv, p) {
  n1 <- sum(yv == 1); n0 <- sum(yv == 0)
  (sum(rank(p)[yv == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
preds <- matrix(NA, nrow(D), 3, dimnames = list(NULL, c("Logit", "LASSO", "RandomForest")))
for (k in 1:5) {
  tr <- folds != k; te <- !tr
  df_tr <- as.data.frame(cbind(y = y[tr], mm[tr, ]))
  fo <- suppressWarnings(glm(y ~ ., df_tr, family = binomial()))
  preds[te, "Logit"] <- predict(fo, as.data.frame(mm[te, ]), type = "response")
  cvg <- cv.glmnet(mm[tr, ], y[tr], family = "binomial", alpha = 1)
  preds[te, "LASSO"] <- as.numeric(predict(cvg, mm[te, ], s = "lambda.min", type = "response"))
  rf <- ranger(y = y[tr], x = mm[tr, ], num.trees = 400, min.node.size = 20)
  preds[te, "RandomForest"] <- predict(rf, mm[te, ])$predictions
}
cv <- tibble(model = colnames(preds),
             cv_auc = sapply(colnames(preds), function(m) auc_fn(y, preds[, m])),
             cv_brier = sapply(colnames(preds), function(m) mean((preds[, m] - y)^2)))
write_csv(cv, file.path(tabd, "success_cv_metrics.csv"))

# RF importance (non-FE)
rf_full <- ranger(y = y, x = mm, num.trees = 600, importance = "permutation",
                  min.node.size = 20, probability = FALSE)
imp <- tibble(feature = names(rf_full$variable.importance),
              importance = rf_full$variable.importance) %>%
  filter(!str_detect(feature, "launch_year|launch_month|launch_dow")) %>%
  arrange(desc(importance))
write_csv(imp, file.path(tabd, "success_rf_importance.csv"))

# ROC curve (out-of-fold, all three)
roc_df <- map_dfr(colnames(preds), function(m) {
  o <- order(preds[, m], decreasing = TRUE)
  yy <- y[o]; tpr <- cumsum(yy) / sum(yy); fpr <- cumsum(1 - yy) / sum(1 - yy)
  tibble(model = m, fpr = c(0, fpr), tpr = c(0, tpr))
})
p_roc <- ggplot(roc_df, aes(fpr, tpr, color = model)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
  geom_line(linewidth = .8) + coord_equal() +
  scale_color_manual(values = c(Logit = "#2c7fb8", LASSO = "#33aa66",
                                RandomForest = "#d7191c"), name = NULL) +
  labs(title = "Funding prediction — out-of-fold ROC (Tabletop, ICPSR)",
       x = "false positive rate", y = "true positive rate")
ggsave(file.path(figd, "success_roc.png"), p_roc, width = 6.5, height = 6, dpi = 130)

# ---- console ---------------------------------------------------------------
cat("######## SUCCESS vs FAILURE model (Tabletop, ICPSR 2009-2023) ########\n")
cat(sprintf("n = %d  (successful=%d, failed=%d; base rate %.1f%%)\n",
            nrow(D), sum(y), sum(1 - y), 100 * mean(y)))
cat("\n=== Logit odds ratios (FE: year/month/dow; cluster by creator) ===\n")
print(logit_tbl %>% mutate(across(c(coef, se, odds_ratio), ~round(.x, 3)),
                           p_value = signif(p_value, 2)) %>% as.data.frame())
cat("\n=== Honest 5-fold CV (AUC ↑ better, Brier ↓ better) ===\n")
print(as.data.frame(cv), digits = 4)
cat("\n=== RF permutation importance (non-FE) ===\n")
print(as.data.frame(imp), digits = 3)
cat("\nFigures -> figures/success_*.png ; tables -> tables/success_*.csv\n")
