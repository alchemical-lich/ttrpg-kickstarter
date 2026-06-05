#!/usr/bin/env Rscript
# 09_magnitude_by_class.R — Do the DRIVERS of pledged $ differ between TTRPG books
# proper (ttrpg) and TTRPG accessories (ttrpg_accessory)? The pooled magnitude
# model (05) allowed only a class intercept shift (same slopes). Here we test
# whether the slopes themselves differ, via class x feature INTERACTIONS.
#
#   (A) Per-class models (fixest split) — readable book-vs-accessory coefficients.
#   (B) Interaction model — formal joint Wald test that drivers differ, plus the
#       per-driver difference (interaction) with creator-clustered SE.
#   (C) 5-fold CV R^2: pooled (one dummy) vs full interactions — does letting
#       slopes differ improve out-of-sample prediction?
#
# Interacted features = those with support in BOTH classes. Rare genre flags
# (is_osr/is_zine/is_pbta, near-absent among accessories) stay main-effects-only.
# Associational (goal/staff_pick endogenous; funded-only).
#
# Out: tables/magclass_*.csv, figures/magclass_by_class_coefs.png

suppressPackageStartupMessages({ library(tidyverse); library(fixest); library(glmnet); library(scales) })
set.seed(42)
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

D <- read_csv(file.path(proj, "data", "processed", "ttrpg_model_features.csv.gz"),
              show_col_types = FALSE) %>%
  mutate(launch_year = factor(launch_year), launch_month = factor(launch_month),
         launch_dow = factor(launch_dow))

inter <- c("log10_goal", "duration_days", "has_video", "staff_pick", "country_us",
           "creator_prior_funded", "creator_is_repeat", "is_dnd5e")  # support in both
main_only <- c("blurb_words", "title_words", "is_osr", "is_zine", "is_pbta")
FE <- "| launch_year + launch_month + launch_dow"

# ---- (A) per-class models (readable side-by-side) --------------------------
base_fml <- as.formula(paste("log10_pledged ~",
              paste(c(inter, main_only), collapse = " + "), FE))
split_mods <- feols(base_fml, data = D, split = ~ttrpg_label, cluster = ~creator_id)
snames <- names(split_mods)
percls <- map_dfr(seq_along(split_mods), function(i) {
  ct <- as.data.frame(coeftable(split_mods[[i]]))
  cls <- if (str_detect(snames[i], "accessory")) "ttrpg_accessory" else "ttrpg (book)"
  tibble(class = cls, term = rownames(ct), coef = ct[, 1], se = ct[, 2])
})
write_csv(percls, file.path(tabd, "magclass_perclass_coefs.csv"))

# ---- (B) interaction model + joint test ------------------------------------
int_fml <- as.formula(paste("log10_pledged ~ (",
              paste(inter, collapse = " + "), ") * class_accessory +",
              paste(main_only, collapse = " + "), FE))
im <- feols(int_fml, data = D, cluster = ~creator_id)
ct <- as.data.frame(coeftable(im))
int_tbl <- tibble(term = rownames(ct), coef = ct[, 1], se = ct[, 2], p_value = ct[, 4]) %>%
  filter(str_detect(term, ":class_accessory")) %>%
  mutate(driver = str_remove(term, ":class_accessory"),
         diff_mult = 10^coef)                       # accessory-vs-book ratio of effects
write_csv(int_tbl, file.path(tabd, "magclass_interactions.csv"))
joint <- wald(im, ":class_accessory", print = FALSE)

# ---- (C) CV R^2: pooled (one dummy) vs full interactions -------------------
y <- D$log10_pledged
mm_pool <- model.matrix(as.formula(paste("~", paste(c(inter, main_only,
            "class_accessory", "launch_year", "launch_month", "launch_dow"),
            collapse = " + "))), D)[, -1]
mm_int <- model.matrix(as.formula(paste("~ (", paste(inter, collapse = " + "),
            ") * class_accessory +", paste(c(main_only, "launch_year",
            "launch_month", "launch_dow"), collapse = " + "))), D)[, -1]
folds <- sample(rep(1:5, length.out = length(y)))
r2 <- function(o, p) 1 - sum((o - p)^2) / sum((o - mean(o))^2)
cvfit <- function(X) { pr <- numeric(length(y))
  for (k in 1:5) { tr <- folds != k
    g <- cv.glmnet(X[tr, ], y[tr], alpha = 1)
    pr[!tr] <- as.numeric(predict(g, X[!tr, ], s = "lambda.min")) }
  r2(y, pr) }
cmp <- tibble(model = c("pooled (class dummy)", "class x feature interactions"),
              cv_r2 = c(cvfit(mm_pool), cvfit(mm_int)))
write_csv(cmp, file.path(tabd, "magclass_cv_r2.csv"))

# ---- figure: book vs accessory multiplicative effects ----------------------
pf <- percls %>% filter(term %in% inter) %>%
  mutate(mult = 10^coef, lo = 10^(coef - 1.96 * se), hi = 10^(coef + 1.96 * se),
         term = fct_reorder(term, mult))
p <- ggplot(pf, aes(mult, term, color = class)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi), position = position_dodge(width = .5)) +
  scale_x_log10() +
  scale_color_manual(values = c("ttrpg (book)" = "#2c7fb8", "ttrpg_accessory" = "#de7a22"), name = NULL) +
  labs(title = "Do drivers of pledged $ differ: TTRPG books vs accessories?",
       subtitle = "multiplicative effect (×) per unit, by class; 95% CI clustered by creator",
       x = "× pledged per unit increase (log scale)", y = NULL)
ggsave(file.path(figd, "magclass_by_class_coefs.png"), p, width = 9.5, height = 5.5, dpi = 130)

# ---- console ---------------------------------------------------------------
cat("######## Drivers by class: TTRPG books vs accessories ########\n")
cat(sprintf("n: ttrpg book = %d, accessory = %d\n",
            sum(D$class_accessory == 0), sum(D$class_accessory == 1)))
cat(sprintf("\nJoint Wald test (all 8 interactions = 0): stat=%.1f, p=%.2e\n",
            joint$stat, joint$p))
cat("=> small p => drivers DO differ by class.\n")
cat("\n=== Per-driver effect by class (multiplicative ×), + difference test ===\n")
tab <- percls %>% filter(term %in% inter) %>%
  select(class, term, coef) %>% pivot_wider(names_from = class, values_from = coef) %>%
  left_join(int_tbl %>% select(term = driver, diff_coef = coef, diff_p = p_value), by = "term") %>%
  mutate(`book ×` = round(10^`ttrpg (book)`, 3),
         `accessory ×` = round(10^`ttrpg_accessory`, 3),
         diff_p = signif(diff_p, 2)) %>%
  select(driver = term, `book ×`, `accessory ×`, diff_p) %>%
  arrange(diff_p)
print(as.data.frame(tab))
cat("\n=== CV R^2: does allowing different slopes help out-of-sample? ===\n")
print(as.data.frame(cmp), digits = 4)
cat("\nFigures -> figures/magclass_by_class_coefs.png ; tables -> tables/magclass_*.csv\n")
