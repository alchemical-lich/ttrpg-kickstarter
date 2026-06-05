#!/usr/bin/env Rscript
# 10_success_by_class_kaggle.R — Do FUNDING drivers differ by product type, Kaggle
# tabletop 2009-2018? Parallels 09 (magnitude) on the success side.
#
# CAVEAT — partition differs from 09 by necessity: Kaggle's name-only classifier
# yields only 63 terminal `ttrpg_accessory` projects (the minis/STL boom is
# post-2018), too few for a books-vs-TTRPG-accessory split. The closest feasible
# contrast is CONTENT/BOOKS (ttrpg, n=1,238) vs PHYSICAL ACCESSORIES
# (ttrpg_accessory + other_accessory, n=1,517). The accessory group is mostly
# non-RPG-cued gear, so this is a product-TYPE comparison, not the exact RPG
# book-vs-accessory split (that one is well-powered only on the Web Robots
# magnitude side, script 09). board/card games (nontt) are excluded.
#
# Test: class x feature interactions on funded (logit, HC1 SE — Kaggle has no
# creator id to cluster on). Joint Wald + per-class + CV. Associational.
#
# Out: tables/sclass_kaggle_*.csv, figures/sclass_kaggle_by_class.png

suppressPackageStartupMessages({ library(tidyverse); library(fixest); library(glmnet); library(scales) })
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
         ttrpg_label %in% c("ttrpg", "ttrpg_accessory", "other_accessory"),
         launch_year >= 2009, launch_year <= 2018,
         goal_usd_real > 0, duration_days > 0, duration_days < 120) %>%
  mutate(
    funded = as.integer(state == "successful"),
    product = if_else(ttrpg_label == "ttrpg", "content (book)", "physical accessory"),
    class_acc = as.integer(product == "physical accessory"),
    log10_goal = log10(goal_usd_real),
    launch_month = factor(month(launched)), launch_dow = factor(wday(launched, week_start = 1)),
    launch_year = factor(launch_year),
    country_us = as.integer(country == "US"),
    title_words = str_count(coalesce(name, ""), "\\S+"),
    is_dnd5e = has(name, "\\b5e\\b|5th edition|d&d|dungeons & dragons|dnd|pathfinder")
  )

inter <- c("log10_goal", "duration_days", "country_us", "title_words")  # vary in both groups
FE <- "| launch_year + launch_month + launch_dow"

# per-class logits (split)
base_fml <- as.formula(paste("funded ~", paste(c(inter, "is_dnd5e"), collapse = " + "), FE))
sm <- feglm(base_fml, data = D, family = binomial(), split = ~product, vcov = "hetero")
sn <- names(sm)
percls <- map_dfr(seq_along(sm), function(i) {
  ct <- as.data.frame(coeftable(sm[[i]]))
  cls <- if (str_detect(sn[i], "accessor")) "physical accessory" else "content (book)"
  tibble(class = cls, term = rownames(ct), coef = ct[, 1], se = ct[, 2])
})
write_csv(percls, file.path(tabd, "sclass_kaggle_perclass.csv"))

# interaction model + joint test
int_fml <- as.formula(paste("funded ~ (", paste(inter, collapse = " + "),
              ") * class_acc + is_dnd5e", FE))
im <- feglm(int_fml, data = D, family = binomial(), vcov = "hetero")
ct <- as.data.frame(coeftable(im))
int_tbl <- tibble(term = rownames(ct), coef = ct[, 1], se = ct[, 2], p_value = ct[, 4]) %>%
  filter(str_detect(term, ":class_acc")) %>% mutate(driver = str_remove(term, ":class_acc"))
write_csv(int_tbl, file.path(tabd, "sclass_kaggle_interactions.csv"))
joint <- wald(im, ":class_acc", print = FALSE)

# CV AUC: pooled (class dummy) vs interactions
y <- D$funded
mm_pool <- model.matrix(as.formula(paste("~", paste(c(inter, "is_dnd5e", "class_acc",
            "launch_year", "launch_month", "launch_dow"), collapse = " + "))), D)[, -1]
mm_int <- model.matrix(as.formula(paste("~ (", paste(inter, collapse = " + "),
            ") * class_acc + is_dnd5e +", paste(c("launch_year", "launch_month",
            "launch_dow"), collapse = " + "))), D)[, -1]
folds <- sample(rep(1:5, length.out = length(y)))
auc_fn <- function(yv, p) { n1 <- sum(yv == 1); n0 <- sum(yv == 0)
  (sum(rank(p)[yv == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
cvauc <- function(X) { pr <- numeric(length(y))
  for (k in 1:5) { tr <- folds != k
    g <- cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 1)
    pr[!tr] <- as.numeric(predict(g, X[!tr, ], s = "lambda.min", type = "response")) }
  auc_fn(y, pr) }
cmp <- tibble(model = c("pooled (class dummy)", "class x feature interactions"),
              cv_auc = c(cvauc(mm_pool), cvauc(mm_int)))
write_csv(cmp, file.path(tabd, "sclass_kaggle_cv.csv"))

# figure: odds ratios by class
pf <- percls %>% filter(term %in% inter) %>%
  mutate(or = exp(coef), lo = exp(coef - 1.96 * se), hi = exp(coef + 1.96 * se),
         term = fct_reorder(term, or))
p <- ggplot(pf, aes(or, term, color = class)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi), position = position_dodge(width = .5)) +
  scale_x_log10() +
  scale_color_manual(values = c("content (book)" = "#2c7fb8", "physical accessory" = "#de7a22"), name = NULL) +
  labs(title = "Funding drivers: RPG content/books vs physical accessories (Kaggle 2009-2018)",
       subtitle = "odds ratios by class; 95% CI (HC1). NOTE: accessory group is mostly non-RPG gear.",
       x = "odds ratio (log scale)", y = NULL)
ggsave(file.path(figd, "sclass_kaggle_by_class.png"), p, width = 9.5, height = 4.8, dpi = 130)

cat("######## Funding drivers by product type (Kaggle 2009-2018) ########\n")
cat(sprintf("content/books n=%d (%.0f%% funded) ; physical accessories n=%d (%.0f%% funded)\n",
            sum(D$class_acc == 0), 100 * mean(D$funded[D$class_acc == 0]),
            sum(D$class_acc == 1), 100 * mean(D$funded[D$class_acc == 1])))
cat(sprintf("\nJoint Wald test (interactions = 0): stat=%.2f, p=%.3f\n", joint$stat, joint$p))
cat("\n=== Odds ratios by class + difference test ===\n")
tab <- percls %>% filter(term %in% inter) %>% select(class, term, coef) %>%
  pivot_wider(names_from = class, values_from = coef) %>%
  left_join(int_tbl %>% select(term = driver, diff_p = p_value), by = "term") %>%
  mutate(`book OR` = round(exp(`content (book)`), 3),
         `accessory OR` = round(exp(`physical accessory`), 3),
         diff_p = signif(diff_p, 2)) %>%
  select(driver = term, `book OR`, `accessory OR`, diff_p) %>% arrange(diff_p)
print(as.data.frame(tab))
cat("\n=== CV AUC: pooled vs interactions ===\n"); print(as.data.frame(cmp), digits = 4)
cat("\nFigures -> figures/sclass_kaggle_by_class.png ; tables -> tables/sclass_kaggle_*.csv\n")
