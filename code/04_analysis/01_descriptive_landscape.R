#!/usr/bin/env Rscript
# 01_descriptive_landscape.R — Descriptive landscape for core TTRPGs and TTRPG
# accessories (the in-scope is_rpg_related classes).
#
# CRITICAL SAMPLING-FRAME CAVEAT
# ------------------------------
# The Web Robots crawl is built from Kickstarter's *discover* listings, which keep
# re-surfacing SUCCESSFUL (and live) projects while FAILED campaigns are quickly
# buried. In our data only ~2% of terminal in-scope projects are `failed` (vs. a
# real tabletop failure rate of ~35-50%). Therefore success RATE is NOT estimable;
# we analyse the landscape CONDITIONAL on being a funded campaign (state==successful)
# and print the state composition up front so the bias is explicit.
#
# No reward-tier (entry vs whale) decomposition exists in Web Robots — only
# campaign-level totals. avg_pledge = pledged_usd / backers is the closest proxy.
#
# Outputs: tables/desc_*.csv and figures/desc_*.png

suppressPackageStartupMessages({
  library(tidyverse)
  library(scales)
})

here  <- tryCatch(dirname(normalizePath(sub("^--file=", "",
            grep("^--file=", commandArgs(FALSE), value = TRUE)))),
            error = function(e) getwd())
proj  <- normalizePath(file.path(here, "..", ".."))
src   <- file.path(proj, "data", "processed", "tabletop_classified.csv.gz")
tabd  <- file.path(proj, "tables")
figd  <- file.path(proj, "figures")
dir.create(tabd, showWarnings = FALSE); dir.create(figd, showWarnings = FALSE)

CLASSES  <- c("ttrpg", "ttrpg_accessory")
PALETTE  <- c(ttrpg = "#2c7fb8", ttrpg_accessory = "#de7a22")
TERMINAL <- c("successful", "failed", "canceled", "cancelled", "suspended")
theme_set(theme_minimal(base_size = 12))
# 2022-23 coverage gap, as decimal years, to shade on time plots
GAP <- c(2022.5, 2023.4)

# ---- load & frame ----------------------------------------------------------
df <- read_csv(src, show_col_types = FALSE) %>%
  filter(ttrpg_label %in% CLASSES) %>%
  mutate(
    launch_year = year(as_datetime(launched_at)),
    funded      = state == "successful",
    terminal    = state %in% TERMINAL,
    avg_pledge  = pledged_usd / na_if(backers_count, 0)
  ) %>%
  filter(launch_year >= 2015, launch_year <= 2026)

funded <- filter(df, funded)

# ---- state composition (shows the survivorship bias) -----------------------
comp <- df %>%
  count(ttrpg_label, state) %>%
  pivot_wider(names_from = state, values_from = n, values_fill = 0)
comp <- comp %>%
  mutate(failure_share_of_terminal =
           coalesce(.data[["failed"]], 0L) /
           (coalesce(.data[["successful"]], 0L) +
            coalesce(.data[["failed"]], 0L) +
            coalesce(.data[["canceled"]], 0L)))
write_csv(comp, file.path(tabd, "desc_state_composition.csv"))

# ---- funded-campaign summary by class --------------------------------------
summ <- funded %>%
  group_by(class = ttrpg_label) %>%
  summarise(
    n_funded             = n(),
    median_goal_usd      = median(goal_usd, na.rm = TRUE),
    median_pledged_usd   = median(pledged_usd, na.rm = TRUE),
    mean_pledged_usd     = mean(pledged_usd, na.rm = TRUE),
    median_backers       = median(backers_count, na.rm = TRUE),
    median_avg_pledge    = median(avg_pledge, na.rm = TRUE),
    median_pct_of_goal   = median(pct_of_goal, na.rm = TRUE),
    share_overfunded_2x  = mean(pct_of_goal >= 2,  na.rm = TRUE),
    share_overfunded_10x = mean(pct_of_goal >= 10, na.rm = TRUE),
    pledged_p10 = quantile(pledged_usd, .10, na.rm = TRUE),
    pledged_p50 = quantile(pledged_usd, .50, na.rm = TRUE),
    pledged_p90 = quantile(pledged_usd, .90, na.rm = TRUE),
    pledged_p99 = quantile(pledged_usd, .99, na.rm = TRUE),
    .groups = "drop"
  )
write_csv(summ, file.path(tabd, "desc_summary_funded.csv"))

# ---- heavy-tail concentration: share of dollars from top X% ----------------
tail_tbl <- funded %>%
  filter(pledged_usd > 0) %>%
  group_by(class = ttrpg_label) %>%
  arrange(desc(pledged_usd), .by_group = TRUE) %>%
  group_modify(function(d, key) {
    tot <- sum(d$pledged_usd); nrows <- nrow(d)
    map_dfr(c(1, 5, 10), function(p) {
      k <- max(1, floor(nrows * p / 100))
      tibble(top_pct = p,
             share_of_dollars = sum(d$pledged_usd[seq_len(k)]) / tot,
             n_in_top = k, total_projects = nrows,
             total_dollars_musd = round(tot / 1e6, 1))
    })
  }) %>% ungroup()
write_csv(tail_tbl, file.path(tabd, "desc_tail_concentration.csv"))

# ---- funded by year --------------------------------------------------------
yb <- funded %>%
  group_by(launch_year, class = ttrpg_label) %>%
  summarise(n_funded = n(),
            median_pledged = median(pledged_usd, na.rm = TRUE),
            median_backers = median(backers_count, na.rm = TRUE),
            .groups = "drop")
write_csv(yb, file.path(tabd, "desc_funded_by_year_class.csv"))

# ---- figures ---------------------------------------------------------------
fill_scale  <- scale_fill_manual(values = PALETTE, name = NULL)
color_scale <- scale_color_manual(values = PALETTE, name = NULL)

p_hist <- ggplot(filter(funded, pledged_usd > 0),
                 aes(pledged_usd, fill = ttrpg_label)) +
  geom_histogram(bins = 60, alpha = .55, position = "identity") +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  fill_scale +
  labs(title = "Pledged USD distribution (funded, launched 2015+)",
       x = "pledged USD (log scale)", y = "funded projects")
ggsave(file.path(figd, "desc_pledged_hist_log.png"), p_hist, width = 9, height = 5, dpi = 130)

p_avg <- ggplot(filter(funded, avg_pledge > 0),
                aes(avg_pledge, fill = ttrpg_label)) +
  geom_histogram(bins = 60, alpha = .55, position = "identity") +
  scale_x_log10(labels = label_dollar()) +
  fill_scale +
  labs(title = "Average pledge (pledged / backers), funded",
       x = "avg pledge USD (log scale)", y = "funded projects")
ggsave(file.path(figd, "desc_avg_pledge_hist_log.png"), p_avg, width = 9, height = 5, dpi = 130)

gap_rect <- annotate("rect", xmin = GAP[1], xmax = GAP[2], ymin = -Inf, ymax = Inf,
                     fill = "red", alpha = .10)

p_med <- ggplot(yb, aes(launch_year, median_pledged, color = class)) +
  gap_rect + geom_line() + geom_point() + color_scale +
  scale_y_continuous(labels = label_dollar()) +
  scale_x_continuous(breaks = seq(2015, 2026, 1)) +
  labs(title = "Median pledged USD by launch year (funded)  •  red = 2022-23 coverage gap",
       x = "launch year", y = "median pledged USD")
ggsave(file.path(figd, "desc_median_pledged_by_year.png"), p_med, width = 10, height = 4.5, dpi = 130)

p_cnt <- ggplot(yb, aes(launch_year, n_funded, color = class)) +
  gap_rect + geom_line() + geom_point() + color_scale +
  scale_x_continuous(breaks = seq(2015, 2026, 1)) +
  labs(title = "Funded project count by launch year (capture-biased)  •  red = 2022-23 gap",
       x = "launch year", y = "funded projects")
ggsave(file.path(figd, "desc_count_by_year.png"), p_cnt, width = 10, height = 4.5, dpi = 130)

# Lorenz curve of dollar concentration
lor <- funded %>%
  filter(pledged_usd > 0) %>%
  group_by(class = ttrpg_label) %>%
  arrange(pledged_usd, .by_group = TRUE) %>%
  mutate(p = row_number() / n(),
         L = cumsum(pledged_usd) / sum(pledged_usd)) %>%
  ungroup()
p_lor <- ggplot(lor, aes(p, L, color = class)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", linewidth = .4) +
  geom_line(linewidth = .9) + color_scale + coord_equal() +
  scale_x_continuous(labels = percent) + scale_y_continuous(labels = percent) +
  labs(title = "Concentration of pledged dollars (Lorenz)",
       x = "cumulative share of funded projects (smallest→largest)",
       y = "cumulative share of dollars")
ggsave(file.path(figd, "desc_lorenz_dollars.png"), p_lor, width = 6, height = 6, dpi = 130)

# ---- console report --------------------------------------------------------
cat("######## SAMPLING-FRAME CAVEAT ########\n")
cat("Failed campaigns are massively under-captured (discover-listing bias).\n")
cat("Success RATE is NOT estimable. Below = landscape CONDITIONAL on funded.\n\n")
cat("=== State composition (in-scope launched 2015+) ===\n")
print(as.data.frame(comp))
cat("\n=== Funded-campaign summary by class ===\n")
print(as.data.frame(summ %>% select(class, n_funded, median_goal_usd, median_pledged_usd,
      mean_pledged_usd, median_backers, median_avg_pledge, median_pct_of_goal,
      share_overfunded_2x, share_overfunded_10x, pledged_p99)), digits = 5)
cat("\n=== Heavy-tail: share of all funded dollars held by top X% ===\n")
print(as.data.frame(tail_tbl), digits = 4)
cat("\nFigures -> figures/desc_*.png ; tables -> tables/desc_*.csv\n")
