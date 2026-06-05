#!/usr/bin/env Rscript
# 17_subcat_drivers.R — Do the new book sub-tags (system family, product type)
# add anything to the predictive models? Two outcomes:
#
#  A) MAGNITUDE | funded  (Web Robots): log10(pledged) on the existing drivers,
#     then + system_family, then + product_type. We report (i) multiplicative
#     dollar premiums per system/type (ref = agnostic system / rulebook), with SE
#     clustered by creator; (ii) the INCREMENTAL R^2 the tags buy over the base
#     drivers — both in-sample and honest 5-fold cross-validated.
#
#  B) SUCCESS  (Kaggle, has failures): logit funded on goal/duration/year, then
#     + system_family + product_type. Odds ratios + incremental AUC/pseudo-R^2.
#     CAVEAT: Kaggle tags are NAME-ONLY (no blurb) -> noisier, esp. product_type;
#     Kaggle ends 2018 so this is the pre-ZineQuest, pre-5e-boom-peak era.
#
# Everything here is ASSOCIATIONAL. Measurement error in the tags (fuzzy keyword
# rules) attenuates the contrasts toward zero -> estimates are conservative.
#
# Out: tables/subcat_*.csv, figures/subcat_*.png
suppressPackageStartupMessages({
  library(tidyverse); library(fixest); library(scales); library(pROC)
})
set.seed(42)
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))
sys_lvls  <- c("agnostic_other", "dnd5e", "pathfinder", "osr", "pbta_fitd", "other_named")
type_lvls <- c("rulebook", "adventure", "setting", "supplement", "bestiary",
               "gm_tools", "zine", "other")
r2 <- function(obs, pred) 1 - sum((obs - pred)^2) / sum((obs - mean(obs))^2)

############################  A) MAGNITUDE (Web Robots)  ######################
feat <- read_csv(file.path(proj, "data", "processed", "ttrpg_model_features.csv.gz"),
                 show_col_types = FALSE) %>%
  filter(ttrpg_label == "ttrpg")                       # core books only (subcats defined here)
sub <- read_csv(file.path(proj, "data", "processed", "ttrpg_book_subcats.csv.gz"),
                show_col_types = FALSE)
D <- feat %>% inner_join(sub, by = "id") %>%
  mutate(system_family = factor(system_family, levels = sys_lvls),
         product_type  = factor(product_type,  levels = type_lvls),
         launch_year = factor(launch_year), launch_month = factor(launch_month),
         launch_dow = factor(launch_dow))
cat(sprintf("MAGNITUDE sample: %d funded core RPG books\n", nrow(D)))

base_x <- c("log10_goal", "duration_days", "has_video", "staff_pick",
            "blurb_words", "title_words", "country_us",
            "creator_prior_funded", "creator_is_repeat")
fe <- "| launch_year + launch_month + launch_dow"
f_base <- as.formula(paste("log10_pledged ~", paste(base_x, collapse = "+"), fe))
f_sys  <- as.formula(paste("log10_pledged ~", paste(c(base_x, "system_family"), collapse = "+"), fe))
f_typ  <- as.formula(paste("log10_pledged ~", paste(c(base_x, "system_family", "product_type"), collapse = "+"), fe))

m_base <- feols(f_base, D, cluster = ~creator_id)
m_sys  <- feols(f_sys,  D, cluster = ~creator_id)
m_full <- feols(f_typ,  D, cluster = ~creator_id)

inc <- tibble(
  model = c("base drivers", "+ system_family", "+ product_type"),
  r2     = c(r2(D$log10_pledged, predict(m_base)),
             r2(D$log10_pledged, predict(m_sys)),
             r2(D$log10_pledged, predict(m_full))),
  adj_r2 = c(fitstat(m_base,"war2")$war2, fitstat(m_sys,"war2")$war2,
             fitstat(m_full,"war2")$war2))
write_csv(inc, file.path(tabd, "subcat_magnitude_incremental_r2.csv"))

# coefficients (multiplicative $ premium vs reference) from the full model
ct <- as.data.frame(coeftable(m_full))
prem <- tibble(term = rownames(ct), coef = ct[,1], se = ct[,2], p = ct[,4]) %>%
  filter(str_detect(term, "system_family|product_type")) %>%
  mutate(axis = if_else(str_detect(term, "system_family"), "system", "product type"),
         level = str_remove(term, "system_family|product_type"),
         mult = 10^coef, lo = 10^(coef-1.96*se), hi = 10^(coef+1.96*se))
write_csv(prem, file.path(tabd, "subcat_magnitude_premiums.csv"))

p_prem <- ggplot(prem, aes(mult, fct_reorder(level, mult), color = axis)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi)) +
  facet_grid(axis ~ ., scales = "free_y", space = "free_y") +
  scale_x_log10() + scale_color_manual(values = c("system"="#2c7fb8","product type"="#d95f0e"), guide="none") +
  labs(title = "Dollar premiums by system & product type (funded RPG books)",
       subtitle = "x pledged vs reference (system: agnostic; type: rulebook); 95% CI, SE clustered by creator",
       x = "x pledged (log scale)", y = NULL)
ggsave(file.path(figd, "subcat_magnitude_premiums.png"), p_prem, width = 8.5, height = 6, dpi = 130)

# honest 5-fold CV: does adding tags improve OUT-OF-SAMPLE prediction?
mm_of <- function(form) model.matrix(form, D)[, -1]
X_base <- mm_of(as.formula(paste("~", paste(c(base_x,"launch_year","launch_month","launch_dow"), collapse="+"))))
X_full <- mm_of(as.formula(paste("~", paste(c(base_x,"system_family","product_type","launch_year","launch_month","launch_dow"), collapse="+"))))
y <- D$log10_pledged; folds <- sample(rep(1:5, length.out = nrow(D)))
cvp <- matrix(NA, nrow(D), 2, dimnames = list(NULL, c("base","+subcats")))
for (k in 1:5) {
  tr <- folds != k; te <- !tr
  cvp[te,"base"]     <- predict(lm(y[tr]~., data.frame(X_base[tr,,drop=FALSE])), data.frame(X_base[te,,drop=FALSE]))
  cvp[te,"+subcats"] <- predict(lm(y[tr]~., data.frame(X_full[tr,,drop=FALSE])), data.frame(X_full[te,,drop=FALSE]))
}
cv_mag <- tibble(model = colnames(cvp), cv_r2 = c(r2(y,cvp[,1]), r2(y,cvp[,2])))
write_csv(cv_mag, file.path(tabd, "subcat_magnitude_cv_r2.csv"))

cat("\n=== A) MAGNITUDE: incremental fit ===\n"); print(as.data.frame(inc), digits=4)
cat("\n--- 5-fold CV R^2 (base vs +subcats) ---\n"); print(as.data.frame(cv_mag), digits=4)
cat("\n--- biggest system/type premiums (x pledged) ---\n")
print(prem %>% arrange(desc(mult)) %>%
      mutate(across(c(mult,lo,hi),~round(.x,2)), p=signif(p,2)) %>%
      select(axis, level, mult, lo, hi, p) %>% as.data.frame())

############################  B) SUCCESS (Kaggle)  ###########################
kg <- read_csv(file.path(proj, "data", "processed", "kaggle_tabletop.csv.gz"),
               show_col_types = FALSE) %>% filter(ttrpg_label == "ttrpg", terminal)
ksub <- read_csv(file.path(proj, "data", "processed", "kaggle_book_subcats.csv.gz"),
                 show_col_types = FALSE)
K <- kg %>% inner_join(ksub, by = "id") %>%
  mutate(log10_goal = log10(pmax(goal_usd_real, 1)),
         system_family = factor(system_family, levels = sys_lvls),
         product_type  = factor(product_type,  levels = type_lvls),
         launch_year = factor(launch_year)) %>%
  filter(duration_days > 0, duration_days < 120, is.finite(log10_goal)) %>%
  # lump rare levels (e.g. only 2 PbtA books -> quasi-separation) to stabilize logit
  mutate(system_family = fct_drop(fct_lump_min(system_family, 10, other_level = "other_named")),
         product_type  = fct_drop(fct_lump_min(product_type,  10, other_level = "other")),
         system_family = relevel(system_family, "agnostic_other"),
         product_type  = relevel(product_type,  "rulebook"))
cat(sprintf("\n\nSUCCESS sample (Kaggle ttrpg books, terminal): %d  funded rate %.3f\n",
            nrow(K), mean(K$funded)))

g_base <- glm(funded ~ log10_goal + duration_days + launch_year, K, family = binomial)
g_full <- glm(funded ~ log10_goal + duration_days + launch_year + system_family + product_type,
              K, family = binomial)
mcf <- function(m) 1 - (m$deviance/2) / (m$null.deviance/2)
auc_of <- function(m) as.numeric(pROC::auc(K$funded, predict(m, type="response"), quiet=TRUE))
succ_fit <- tibble(model = c("base","+subcats"),
                   mcfadden = c(mcf(g_base), mcf(g_full)),
                   auc = c(auc_of(g_base), auc_of(g_full)))
write_csv(succ_fit, file.path(tabd, "subcat_success_fit.csv"))

co <- summary(g_full)$coefficients
or <- tibble(term = rownames(co), beta = co[,1], se = co[,2], p = co[,4]) %>%
  filter(str_detect(term, "system_family|product_type")) %>%
  mutate(axis = if_else(str_detect(term,"system_family"),"system","product type"),
         level = str_remove(term, "system_family|product_type"),
         OR = exp(beta), lo = exp(beta-1.96*se), hi = exp(beta+1.96*se))
write_csv(or, file.path(tabd, "subcat_success_or.csv"))

cat("\n=== B) SUCCESS: fit (Kaggle, name-only tags) ===\n"); print(as.data.frame(succ_fit), digits=4)
cat("\n--- odds ratios for funding (vs ref: agnostic system / rulebook) ---\n")
print(or %>% mutate(across(c(OR,lo,hi),~round(.x,2)), p=signif(p,2)) %>%
      select(axis, level, OR, lo, hi, p) %>% as.data.frame())

cat("\nFigures -> figures/subcat_magnitude_premiums.png\n")
cat("Tables  -> tables/subcat_*.csv\n")
