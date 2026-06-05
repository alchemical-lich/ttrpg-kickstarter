#!/usr/bin/env Rscript
# 11_did_zinequest.R — Quasi-experimental study of ZineQuest (Kickstarter's RPG-zine
# promotion, launched Feb 2019, run every February since).
#
# Design: ZineQuest is an RPG-SPECIFIC, platform-driven, sharply-dated shock, so
# non-RPG tabletop (board/card games) is a clean control. Triple-difference on
# monthly FUNDED launch counts:
#     treated = RPG (core ttrpg) ; control = non-RPG tabletop (nontt)
#     feb     = February ; post = year >= 2019
#   ZineQuest effect = rpg : feb : post  (the RPG Feb surge that appears in 2019).
#
# CAVEATS: Web Robots is funded-only, so this is the effect on FUNDED entry (and on
# pledged among funded), NOT on success rate (no post-2018 failures). Launch months
# in the 2022-07..2023-08 coverage gap are excluded (under-captured). Quasi-
# experimental: identification rests on RPG and control sharing trends absent
# ZineQuest (testable via the pre-2019 Februaries).
#
# Out: tables/zq_*.csv, figures/zq_*.png

suppressPackageStartupMessages({ library(tidyverse); library(fixest); library(scales) })
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

gap <- seq(as.Date("2022-07-01"), as.Date("2023-08-01"), by = "month") |> format("%Y-%m")

d <- read_csv(file.path(proj, "data", "processed", "tabletop_classified.csv.gz"),
              show_col_types = FALSE) %>%
  filter(state == "successful") %>%
  mutate(launched = as_datetime(launched_at),
         ym = format(launched, "%Y-%m"), year = year(launched), month = month(launched)) %>%
  filter(year >= 2015, year <= 2026, !(ym %in% gap),
         ttrpg_label %in% c("ttrpg", "nontt")) %>%       # RPG content vs board/card games
  mutate(group = if_else(ttrpg_label == "ttrpg", "RPG", "non-RPG tabletop"),
         is_zine = str_detect(str_to_lower(paste(name, blurb)), "\\bzine\\b|zinequest"))

# monthly funded-launch counts by group
panel <- d %>% count(year, month, group, name = "n") %>%
  complete(year, month, group, fill = list(n = 0)) %>%
  filter(!(sprintf("%04d-%02d", year, month) %in% gap), year <= 2026) %>%
  mutate(rpg = as.integer(group == "RPG"), feb = as.integer(month == 2),
         post = as.integer(year >= 2019), logn = log1p(n))

# ---- triple-difference -----------------------------------------------------
ddd <- feols(logn ~ rpg * feb * post, data = panel, cluster = ~year)
co <- as.data.frame(coeftable(ddd))
ddd_tbl <- tibble(term = rownames(co), coef = co[, 1], se = co[, 2], p = co[, 4]) %>%
  mutate(mult = exp(coef))
write_csv(ddd_tbl, file.path(tabd, "zq_ddd_coefs.csv"))
zq <- ddd_tbl %>% filter(term == "rpg:feb:post")

# placebo / pre-trend: the RPG Feb premium by year (should be flat pre-2019, jump 2019)
febprem <- panel %>%
  group_by(year, group) %>%
  summarise(feb_premium = log1p(n[month == 2][1]) -
              mean(log1p(n[month != 2]), na.rm = TRUE), .groups = "drop")
write_csv(febprem, file.path(tabd, "zq_feb_premium_by_year.csv"))

p1 <- ggplot(febprem, aes(year, feb_premium, color = group)) +
  annotate("rect", xmin = 2018.5, xmax = 2026.5, ymin = -Inf, ymax = Inf, fill = "grey85", alpha = .5) +
  geom_hline(yintercept = 0, linewidth = .3, color = "grey50") +
  geom_line() + geom_point() +
  scale_color_manual(values = c("RPG" = "#2c7fb8", "non-RPG tabletop" = "#d7191c"), name = NULL) +
  scale_x_continuous(breaks = 2015:2026) +
  labs(title = "ZineQuest: February 'launch premium' by year (funded launches)",
       subtitle = "grey = ZineQuest era (2019+). RPG premium jumps in 2019; control flat.",
       x = "year", y = "log(Feb launches) − mean log(other-month launches)") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(figd, "zq_feb_premium.png"), p1, width = 10, height = 4.8, dpi = 130)

# monthly series (raw counts) for context
p2 <- d %>% count(ym, group) %>%
  mutate(date = as.Date(paste0(ym, "-01"))) %>%
  ggplot(aes(date, n, color = group)) +
  geom_line(linewidth = .4) +
  geom_vline(xintercept = as.Date("2019-02-01"), linetype = "dashed") +
  scale_color_manual(values = c("RPG" = "#2c7fb8", "non-RPG tabletop" = "#d7191c"), name = NULL) +
  labs(title = "Funded tabletop launches by month (dashed = first ZineQuest, Feb 2019)",
       subtitle = "gaps = excluded 2022-07..2023-08 coverage hole",
       x = NULL, y = "funded launches / month")
ggsave(file.path(figd, "zq_monthly_series.png"), p2, width = 11, height = 4.5, dpi = 130)

# ---- mechanism: does ZineQuest dilute pledged (many small zines)? ----------
mech <- d %>% filter(group == "RPG") %>%
  mutate(zq_window = if_else(month == 2 & year >= 2019,
                             "ZineQuest (Feb >=2019)", "other RPG")) %>%
  group_by(zq_window) %>%
  summarise(n = n(), median_pledged = median(pledged_usd, na.rm = TRUE),
            median_backers = median(backers_count, na.rm = TRUE),
            zine_share = mean(is_zine), .groups = "drop")
write_csv(mech, file.path(tabd, "zq_pledged_mechanism.csv"))

cat("######## ZineQuest triple-difference (funded entry) ########\n")
cat(sprintf("ZineQuest effect (rpg:feb:post): coef=%.3f (×%.2f funded RPG Feb launches), SE=%.3f, p=%.4f\n",
            zq$coef, zq$mult, zq$se, zq$p))
cat("\n=== Feb launch premium by year (pre-2019 should be flat = parallel pre-trend) ===\n")
print(as.data.frame(febprem %>% pivot_wider(names_from = group, values_from = feb_premium) %>%
        mutate(across(where(is.numeric), ~round(.x, 2)))))
cat("\n=== Mechanism: pledged among funded RPG, ZineQuest-Feb vs other ===\n")
print(as.data.frame(mech %>% mutate(across(where(is.numeric), ~round(.x, 2)))))
cat("\nFigures -> figures/zq_*.png ; tables -> tables/zq_*.csv\n")
