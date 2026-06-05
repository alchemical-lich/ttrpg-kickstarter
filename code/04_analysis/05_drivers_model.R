#!/usr/bin/env Rscript
# 05_drivers_model.R — Drivers of MAGNITUDE: what predicts how much a FUNDED
# TTRPG / TTRPG-accessory campaign raises. Outcome = log10(pledged USD).
#
# Three complementary views:
#   (1) OLS (fixest) with launch year/month/dow fixed effects and SEs clustered by
#       creator — interpretable associations (coef b => pledged multiplies by 10^b).
#   (2) Honest 5-fold CROSS-VALIDATED R^2 for OLS vs LASSO vs random forest — out-
#       of-sample predictive power, not in-sample fit. Plus RF variable importance.
#   (3) Quantile regression (tau = .1/.5/.9) — do drivers differ for small vs
#       runaway projects (the heavy tail)?
#
# ASSOCIATIONAL, not causal: log10_goal and staff_pick are endogenous (goals are
# chosen anticipating demand; staff picks may anticipate success). Sample is
# funded-only (Web Robots survivorship) — this is "given funded, how much".
#
# Out: tables/drivers_*.csv, figures/drivers_*.png

suppressPackageStartupMessages({
  library(tidyverse); library(fixest); library(glmnet); library(ranger)
  library(quantreg); library(scales)
})
set.seed(42)
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

D <- read_csv(file.path(proj, "data", "processed", "ttrpg_model_features.csv.gz"),
              show_col_types = FALSE) %>%
  mutate(launch_year = factor(launch_year),
         launch_month = factor(launch_month),
         launch_dow = factor(launch_dow))

# predictors (zinequest_win dropped: collinear with launch_month FE)
xvars <- c("log10_goal", "duration_days", "has_video", "staff_pick",
           "blurb_words", "title_words", "country_us", "class_accessory",
           "creator_prior_funded", "creator_is_repeat",
           "is_dnd5e", "is_osr", "is_pbta", "is_zine")
fml <- as.formula(paste("log10_pledged ~", paste(xvars, collapse = " + "),
                        "| launch_year + launch_month + launch_dow"))

# ---- (1) OLS with clustered SE --------------------------------------------
ols <- feols(fml, data = D, cluster = ~creator_id)
ct <- as.data.frame(coeftable(ols))
ols_tbl <- tibble(term = rownames(ct), coef = ct[, 1], se = ct[, 2],
                  p_value = ct[, 4]) %>%
  mutate(mult_effect = 10^coef,                # pledged multiplies by this per +1 unit
         pct_effect = 100 * (mult_effect - 1))
write_csv(ols_tbl, file.path(tabd, "drivers_ols_coefs.csv"))

# coefficient plot (multiplicative effect, 95% CI) for binary/scaled drivers
plotv <- c("log10_goal", "has_video", "staff_pick", "country_us", "class_accessory",
           "creator_is_repeat", "is_dnd5e", "is_osr", "is_zine")
cf <- ols_tbl %>% filter(term %in% plotv) %>%
  mutate(lo = 10^(coef - 1.96 * se), hi = 10^(coef + 1.96 * se),
         term = fct_reorder(term, mult_effect))
p_coef <- ggplot(cf, aes(mult_effect, term)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi), color = "#2c7fb8") +
  scale_x_log10() +
  labs(title = "Drivers of pledged $ (funded TTRPG + accessories)",
       subtitle = "multiplicative effect on pledged USD (×); 95% CI, SE clustered by creator",
       x = "× pledged per unit increase (log scale)", y = NULL)
ggsave(file.path(figd, "drivers_coef_plot.png"), p_coef, width = 9, height = 5, dpi = 130)

# ---- (2) 5-fold CV: OLS vs LASSO vs RF -------------------------------------
mm <- model.matrix(as.formula(paste("~", paste(c(xvars, "launch_year",
       "launch_month", "launch_dow"), collapse = " + "))), data = D)[, -1]
y <- D$log10_pledged
folds <- sample(rep(1:5, length.out = nrow(D)))
r2 <- function(obs, pred) 1 - sum((obs - pred)^2) / sum((obs - mean(obs))^2)

oos <- tibble(model = c("OLS", "LASSO", "RandomForest"), cv_r2 = NA_real_)
preds <- matrix(NA, nrow(D), 3, dimnames = list(NULL, oos$model))
for (k in 1:5) {
  tr <- folds != k; te <- !tr
  df_tr <- as.data.frame(cbind(y = y[tr], mm[tr, ])); df_te <- as.data.frame(mm[te, ])
  # OLS
  fo <- lm(y ~ ., df_tr); preds[te, "OLS"] <- predict(fo, df_te)
  # LASSO (lambda.min via inner CV)
  cvg <- cv.glmnet(mm[tr, ], y[tr], alpha = 1)
  preds[te, "LASSO"] <- as.numeric(predict(cvg, mm[te, ], s = "lambda.min"))
  # Random forest
  rf <- ranger(y = y[tr], x = mm[tr, ], num.trees = 400, min.node.size = 5)
  preds[te, "RandomForest"] <- predict(rf, mm[te, ])$predictions
}
oos$cv_r2 <- sapply(oos$model, function(m) r2(y, preds[, m]))
write_csv(oos, file.path(tabd, "drivers_cv_r2.csv"))

# RF importance on full data
rf_full <- ranger(y = y, x = mm, num.trees = 600, importance = "permutation",
                  min.node.size = 5)
imp <- tibble(feature = names(rf_full$variable.importance),
              importance = rf_full$variable.importance) %>%
  filter(!str_detect(feature, "launch_year|launch_month|launch_dow")) %>%
  arrange(desc(importance)) %>% slice_head(n = 14)
write_csv(imp, file.path(tabd, "drivers_rf_importance.csv"))
p_imp <- ggplot(imp, aes(importance, fct_reorder(feature, importance))) +
  geom_col(fill = "#2c7fb8") +
  labs(title = "Random-forest permutation importance (non-FE features)",
       x = "importance (increase in MSE)", y = NULL)
ggsave(file.path(figd, "drivers_rf_importance.png"), p_imp, width = 9, height = 5, dpi = 130)

# observed vs predicted (RF, out-of-fold)
ovp <- tibble(obs = y, pred = preds[, "RandomForest"])
p_ovp <- ggplot(ovp, aes(10^pred, 10^obs)) +
  geom_point(alpha = .12, size = .6, color = "#2c7fb8") +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  scale_y_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  labs(title = "Out-of-fold predictions (random forest)",
       x = "predicted pledged USD", y = "observed pledged USD")
ggsave(file.path(figd, "drivers_obs_pred.png"), p_ovp, width = 6.5, height = 6, dpi = 130)

# ---- (3) Quantile regression (do drivers differ across the distribution?) --
qfml <- as.formula(paste("log10_pledged ~", paste(xvars, collapse = " + "), "+ launch_year"))
qr <- rq(qfml, tau = c(.1, .5, .9), data = D)
qs <- summary(qr, se = "nid")
qtab <- map_dfr(seq_along(c(.1, .5, .9)), function(i) {
  co <- qs[[i]]$coefficients
  tibble(tau = c(.1, .5, .9)[i], term = rownames(co),
         coef = co[, 1], p_value = co[, 4])
}) %>% filter(term %in% xvars) %>%
  mutate(mult_effect = 10^coef)
write_csv(qtab, file.path(tabd, "drivers_quantile.csv"))

# ---- console ---------------------------------------------------------------
cat("######## DRIVERS OF MAGNITUDE (funded TTRPG + accessories, 2015+) ########\n")
cat(sprintf("n = %d ; outcome = log10(pledged USD)\n", nrow(D)))
cat(sprintf("OLS within-R2 = %.3f (adj %.3f)\n", r2(y, predict(ols)),
            fitstat(ols, "war2")$war2))
cat("\n=== OLS coefficients (multiplicative effect on pledged $) ===\n")
print(ols_tbl %>% mutate(across(c(coef, se, mult_effect, pct_effect), ~round(.x, 3)),
                         p_value = signif(p_value, 2)) %>% as.data.frame())
cat("\n=== Honest 5-fold cross-validated R^2 ===\n"); print(as.data.frame(oos), digits = 3)
cat("\n=== RF importance (top non-FE) ===\n"); print(as.data.frame(imp), digits = 3)
cat("\n=== Quantile regression: mult. effect at tau=.1/.5/.9 (key vars) ===\n")
print(qtab %>% filter(term %in% c("log10_goal","has_video","staff_pick",
      "creator_prior_funded","class_accessory","is_zine")) %>%
      mutate(mult_effect = round(mult_effect, 3)) %>%
      select(term, tau, mult_effect) %>% pivot_wider(names_from = tau, values_from = mult_effect) %>%
      as.data.frame())
cat("\nFigures -> figures/drivers_*.png ; tables -> tables/drivers_*.csv\n")
