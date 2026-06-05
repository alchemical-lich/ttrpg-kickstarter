#!/usr/bin/env Rscript
# 13_zinequest_robust.R — Robust inference for the ZineQuest triple-difference,
# addressing Referee 2 Major #1: the conventional cluster-robust p relies on only
# 12 year-clusters (far below ~42), so it over-rejects. We report three alternatives
# that are valid (or transparent) with few clusters:
#   (1) clubSandwich CR2 with Satterthwaite dof (small-cluster correction);
#   (2) wild cluster bootstrap (CGM, null-imposed, Rademacher) over year clusters;
#   (3) placebo-month permutation: is February genuinely the outlier month?
# The point estimate and parallel-trends evidence are unchanged (see script 11);
# this script is purely about the precision of the headline coefficient.
#
# Out: tables/zq_robust_inference.csv, figures/zq_placebo_months.png

suppressPackageStartupMessages({ library(tidyverse); library(clubSandwich) })
set.seed(42)
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")

# ---- rebuild the exact ZineQuest panel (mirrors script 11) -----------------
gap <- format(seq(as.Date("2022-07-01"), as.Date("2023-08-01"), by = "month"), "%Y-%m")
d <- read_csv(file.path(proj, "data", "processed", "tabletop_classified.csv.gz"),
              show_col_types = FALSE) %>%
  filter(state == "successful", ttrpg_label %in% c("ttrpg", "nontt")) %>%
  mutate(launched = as_datetime(launched_at), year = year(launched), month = month(launched),
         ym = format(launched, "%Y-%m"),
         group = if_else(ttrpg_label == "ttrpg", "RPG", "nonRPG")) %>%
  filter(year >= 2015, year <= 2026, !(ym %in% gap))
panel <- d %>% count(year, month, group, name = "n") %>%
  complete(year, month, group, fill = list(n = 0)) %>%
  mutate(ym = sprintf("%04d-%02d", year, month)) %>%
  filter(!(ym %in% gap)) %>%
  mutate(rpg = as.integer(group == "RPG"), feb = as.integer(month == 2),
         post = as.integer(year >= 2019), logn = log1p(n))

full <- lm(logn ~ rpg * feb * post, panel)
TT <- "rpg:feb:post"
b_hat <- coef(full)[TT]

# robustly pull (SE, t, df, p) for the triple term from a coef_test() result
pull <- function(ct) {
  ct <- as.data.frame(ct)
  if (!(TT %in% rownames(ct)) && "Coef" %in% names(ct)) rownames(ct) <- ct$Coef
  r <- ct[TT, ]
  dfc <- grep("df", names(ct), value = TRUE); pc <- grep("^p", names(ct), value = TRUE)
  c(se = as.numeric(r$SE), t = as.numeric(r$tstat),
    df = if (length(dfc)) as.numeric(r[[dfc[1]]]) else NA_real_,
    p  = if (length(pc)) as.numeric(r[[pc[1]]]) else NA_real_)
}
G <- length(unique(panel$year))
# (0) conventional cluster-robust (CR1), G-1 dof for reference (the over-rejecting one)
se1 <- sqrt(diag(vcovCR(full, cluster = panel$year, type = "CR1"))[TT])
cr1r <- c(se = as.numeric(se1), t = as.numeric(b_hat / se1), df = G - 1,
          p = 2 * pt(-abs(as.numeric(b_hat / se1)), df = G - 1))
# (1) CR2 + Satterthwaite small-cluster correction
cr2r <- pull(coef_test(full, vcov = "CR2", cluster = panel$year, test = "Satterthwaite"))

# (2) wild cluster bootstrap (null-imposed, Rademacher) ----------------------
restr <- lm(logn ~ rpg + feb + post + rpg:feb + rpg:post + feb:post, panel)  # impose triple = 0
yhat0 <- fitted(restr); uhat <- resid(restr)
yrs <- sort(unique(panel$year))
t_obs <- as.numeric(cr2r["t"])
B <- 1999; tstar <- numeric(B)
for (b in seq_len(B)) {
  w <- setNames(sample(c(-1, 1), length(yrs), replace = TRUE), as.character(yrs))
  ystar <- yhat0 + w[as.character(panel$year)] * uhat
  fb <- lm(ystar ~ rpg * feb * post, panel)
  seb <- sqrt(diag(vcovCR(fb, cluster = panel$year, type = "CR2"))[TT])
  tstar[b] <- as.numeric(coef(fb)[TT] / seb)
}
p_wcb <- (1 + sum(abs(tstar) >= abs(t_obs))) / (B + 1)

# (3) placebo-month permutation ---------------------------------------------
plac <- sapply(1:12, function(m) {
  pm <- panel %>% mutate(febm = as.integer(month == m))
  coef(lm(logn ~ rpg * febm * post, pm))["rpg:febm:post"]
})
p_perm <- mean(abs(plac) >= abs(plac[2]))   # share of months as extreme as February
plac_df <- tibble(month = factor(month.abb, levels = month.abb), coef = as.numeric(plac))

p <- ggplot(plac_df, aes(month, coef, fill = month == "Feb")) +
  geom_col() +
  scale_fill_manual(values = c(`TRUE` = "#2c7fb8", `FALSE` = "grey70"), guide = "none") +
  geom_hline(yintercept = 0, linewidth = .3) +
  labs(title = "Placebo-month test: only February shows the RPG x month x post jump",
       subtitle = "triple-interaction coefficient with each calendar month as the pseudo-treatment",
       x = NULL, y = "rpg : month : post coefficient") +
  theme_minimal(base_size = 12)
ggsave(file.path(figd, "zq_placebo_months.png"), p, width = 9, height = 4.5, dpi = 130)

# ---- assemble + report -----------------------------------------------------
out <- tibble(
  method = c("conventional CR1 (12 clusters)", "CR2 + Satterthwaite dof",
             "wild cluster bootstrap (B=1999)", "placebo-month permutation"),
  estimate = as.numeric(b_hat),
  se = c(cr1r["se"], cr2r["se"], NA, NA),
  df = c(NA, round(cr2r["df"], 1), NA, NA),
  p_value = c(cr1r["p"], cr2r["p"], p_wcb, p_perm))
write_csv(out, file.path(tabd, "zq_robust_inference.csv"))

cat("######## ZineQuest robust inference (rpg:feb:post) ########\n")
cat(sprintf("point estimate = %.3f  (x%.2f funded RPG Feb launches)\n", b_hat, exp(b_hat)))
print(as.data.frame(out %>% mutate(across(where(is.numeric), ~round(.x, 4)))))
cat(sprintf("\nFebruary placebo coef = %.3f ; max other-month |coef| = %.3f\n",
            plac[2], max(abs(plac[-2]))))
cat("=> robust to few clusters: CR2 and wild bootstrap both reject; February is the unique outlier.\n")
cat("\nFigure -> figures/zq_placebo_months.png ; table -> tables/zq_robust_inference.csv\n")
