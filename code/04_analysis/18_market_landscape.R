#!/usr/bin/env Rscript
# 18_market_landscape.R - Baseline descriptive landscape figures.
#
# Adds market-size, goal/duration, seasonality/creator, and geography/feature
# baselines that the original 01_descriptive_landscape.R did not cover. All series
# are built from the Web Robots Games panel (games_master), classified into TTRPG
# core / TTRPG accessory / other-tabletop / video / playing-cards / other-games.
#
# SAMPLING-FRAME CAVEATS (read before interpreting):
#   * Discover-listing capture under-represents FAILED campaigns. We therefore
#     report dollar/volume landscapes CONDITIONAL on funded (state==successful).
#   * TOTAL DOLLARS is the most capture-robust aggregate here: failures raise
#     almost nothing, so funded-dollar totals (dominated by well-captured hits)
#     are trustworthy. COUNTS are more biased - read them as lower bounds.
#   * 2022-07 .. 2023-05 is a crawl COVERAGE GAP (the Games category was missed):
#     totals/counts dip there as an ARTIFACT, not a real market contraction. All
#     time plots shade it; the 2022-23 points are not comparable to neighbours.
#   * "Other categories" here means other *Games* subcategories. True non-Games
#     top-level categories (Film, Comics, Tech, ...) were filtered out at ingest
#     and are not available without a new crawl-aggregation pass.
#   * Creator "new vs returning" is measured WITHIN the captured TTRPG panel only;
#     a creator's buried failures or non-Games history are unobserved, so "new"
#     is over-counted (returning share is a lower bound).
#
# Outputs: tables/desc_*.csv and figures/desc_*.png

suppressPackageStartupMessages({
  library(tidyverse)
  library(scales)
})

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
dir.create(tabd, showWarnings = FALSE); dir.create(figd, showWarnings = FALSE)

theme_set(theme_minimal(base_size = 12))
GAP   <- c(2022.5, 2023.4)                 # coverage gap, decimal years
Y0    <- 2014; Y1 <- 2026                  # in-scope launch-year window
gap_rect <- annotate("rect", xmin = GAP[1], xmax = GAP[2], ymin = -Inf, ymax = Inf,
                     fill = "red", alpha = .10)
yr_axis  <- scale_x_continuous(breaks = seq(Y0, Y1, 2))
ggsv <- function(name, p, w = 9, h = 5) ggsave(file.path(figd, name), p, width = w, height = h, dpi = 130)

# ---- load & frame ----------------------------------------------------------
gm  <- read_csv(file.path(proj, "data/processed/games_master.csv.gz"), show_col_types = FALSE)
cls <- read_csv(file.path(proj, "data/processed/tabletop_classified.csv.gz"),
                show_col_types = FALSE) %>% select(id, ttrpg_label)

BUCKETS <- c("TTRPG (core)", "TTRPG accessory", "Other tabletop",
             "Video games", "Playing cards", "Other games")
PAL_BUCKET <- c("TTRPG (core)" = "#2c7fb8", "TTRPG accessory" = "#de7a22",
                "Other tabletop" = "#7fbf7b", "Video games" = "#9e9ac8",
                "Playing cards" = "#fdae6b", "Other games" = "#bdbdbd")
PAL_CLASS <- c("TTRPG (core)" = "#2c7fb8", "TTRPG accessory" = "#de7a22")

g <- gm %>%
  left_join(cls, by = "id") %>%
  mutate(
    launched  = as_datetime(launched_at),
    deadline_d = as_datetime(deadline),
    launch_year  = year(launched),
    launch_month = month(launched),
    funded   = state == "successful",
    duration_days = as.numeric(deadline_d - launched, units = "days"),
    has_video = as.logical(has_video),
    staff_pick = staff_pick == 1,
    bucket = factor(case_when(
      ttrpg_label == "ttrpg"           ~ "TTRPG (core)",
      ttrpg_label == "ttrpg_accessory" ~ "TTRPG accessory",
      cat_name == "Tabletop Games"     ~ "Other tabletop",
      cat_name == "Video Games"        ~ "Video games",
      cat_name == "Playing Cards"      ~ "Playing cards",
      TRUE                             ~ "Other games"), levels = BUCKETS)) %>%
  filter(!is.na(launch_year), launch_year >= Y0, launch_year <= Y1)

# in-scope TTRPG (core + accessory), funded - used for the writeup-relevant panels
rpg  <- g %>% filter(bucket %in% c("TTRPG (core)", "TTRPG accessory"))
fund <- g %>% filter(funded)
rpgf <- rpg %>% filter(funded)

# =====================================================================
# BUNDLE 1 - MARKET SIZE & CATEGORY SHARE
# =====================================================================
by_year_bucket <- fund %>%
  group_by(launch_year, bucket) %>%
  summarise(dollars_musd = sum(pledged_usd, na.rm = TRUE) / 1e6,
            n = n(), .groups = "drop")

market_wide <- by_year_bucket %>%
  group_by(launch_year) %>%
  summarise(
    ttrpg_musd    = sum(dollars_musd[bucket == "TTRPG (core)"]),
    tabletop_musd = sum(dollars_musd[bucket %in% c("TTRPG (core)", "TTRPG accessory", "Other tabletop")]),
    games_musd    = sum(dollars_musd),
    n_ttrpg       = sum(n[bucket == "TTRPG (core)"]),
    .groups = "drop") %>%
  mutate(ttrpg_share_games    = ttrpg_musd / games_musd,
         tabletop_share_games = tabletop_musd / games_musd)
write_csv(by_year_bucket, file.path(tabd, "desc_market_by_year_bucket.csv"))
write_csv(market_wide,    file.path(tabd, "desc_market_share_by_year.csv"))

# Fig: stacked area of funded $ composition across Games
ord <- rev(BUCKETS)
p_area <- by_year_bucket %>% mutate(bucket = factor(bucket, levels = ord)) %>%
  ggplot(aes(launch_year, dollars_musd, fill = bucket)) +
  gap_rect +
  geom_area(alpha = .9, color = "white", linewidth = .2) +
  scale_fill_manual(values = PAL_BUCKET, breaks = BUCKETS, name = NULL) +
  scale_y_continuous(labels = label_dollar(suffix = "M")) + yr_axis +
  labs(title = "Funded crowdfunding dollars on Kickstarter Games, by subcategory",
       subtitle = "red band = 2022-23 crawl coverage gap (artifactual dip)",
       x = "launch year", y = "funded pledged USD")
ggsv("desc_market_dollars_by_year.png", p_area, w = 10, h = 5.5)

# Fig: TTRPG / tabletop share of Games dollars
p_share <- market_wide %>%
  select(launch_year, `TTRPG (core)` = ttrpg_share_games,
         `All tabletop` = tabletop_share_games) %>%
  pivot_longer(-launch_year, names_to = "series", values_to = "share") %>%
  ggplot(aes(launch_year, share, color = series)) +
  gap_rect + geom_line(linewidth = .9) + geom_point() +
  scale_color_manual(values = c("TTRPG (core)" = "#2c7fb8", "All tabletop" = "#238b45"), name = NULL) +
  scale_y_continuous(labels = percent) + yr_axis +
  labs(title = "Share of Kickstarter-Games funded dollars",
       subtitle = "TTRPG roughly tripled its share of gaming-crowdfunding dollars  -  red = coverage gap",
       x = "launch year", y = "share of Games funded $")
ggsv("desc_ttrpg_share_of_games.png", p_share, w = 10, h = 5)

# Fig: share of dollars vs share of projects (concentration), clean window
WIN <- fund %>% filter(launch_year >= 2019, !(launch_year %in% c(2022, 2023)))
shares <- WIN %>% group_by(bucket) %>%
  summarise(dollars = sum(pledged_usd, na.rm = TRUE), n = n(), .groups = "drop") %>%
  mutate(`share of dollars` = dollars / sum(dollars),
         `share of projects` = n / sum(n))
write_csv(shares, file.path(tabd, "desc_share_dollars_vs_projects.csv"))
p_conc <- shares %>%
  select(bucket, `share of dollars`, `share of projects`) %>%
  pivot_longer(-bucket, names_to = "measure", values_to = "share") %>%
  ggplot(aes(reorder(bucket, share), share, fill = measure)) +
  geom_col(position = "dodge") + coord_flip() +
  scale_y_continuous(labels = percent) +
  scale_fill_manual(values = c("share of dollars" = "#2c7fb8", "share of projects" = "#bdbdbd"), name = NULL) +
  labs(title = "Dollars are more concentrated than projects",
       subtitle = "Kickstarter Games, funded, 2019-2025 excl. 2022-23 gap",
       x = NULL, y = "share")
ggsv("desc_share_dollars_vs_projects.png", p_conc, w = 9, h = 4.5)

# =====================================================================
# BUNDLE 2 - GOAL & DURATION BASELINES  (core TTRPG + accessory)
# =====================================================================
p_goal <- rpgf %>% filter(goal_usd > 0) %>%
  ggplot(aes(goal_usd, fill = bucket)) +
  geom_histogram(bins = 60, alpha = .55, position = "identity") +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  scale_fill_manual(values = PAL_CLASS, name = NULL) +
  labs(title = "Funding goals set by funded TTRPG campaigns",
       x = "goal USD (log scale)", y = "funded projects")
ggsv("desc_goal_hist_log.png", p_goal)

goal_dur_year <- rpgf %>%
  filter(duration_days >= 1, duration_days <= 92) %>%
  group_by(launch_year, class = bucket) %>%
  summarise(median_goal = median(goal_usd, na.rm = TRUE),
            median_duration = median(duration_days, na.rm = TRUE),
            .groups = "drop")
write_csv(goal_dur_year, file.path(tabd, "desc_goal_duration_by_year.csv"))

p_medgoal <- ggplot(goal_dur_year, aes(launch_year, median_goal, color = class)) +
  gap_rect + geom_line(linewidth = .8) + geom_point() +
  scale_color_manual(values = PAL_CLASS, name = NULL) +
  scale_y_continuous(labels = label_dollar()) + yr_axis +
  labs(title = "Median funding goal by launch year (funded TTRPG)  -  red = coverage gap",
       x = "launch year", y = "median goal USD")
ggsv("desc_median_goal_by_year.png", p_medgoal, w = 10, h = 4.5)

p_dur <- rpgf %>% filter(duration_days >= 1, duration_days <= 90) %>%
  ggplot(aes(duration_days, fill = bucket)) +
  geom_histogram(binwidth = 1, alpha = .55, position = "identity") +
  scale_fill_manual(values = PAL_CLASS, name = NULL) +
  labs(title = "Campaign length (funded TTRPG)",
       subtitle = "Most cluster at the 30-day default; few exceed 60",
       x = "campaign length (days)", y = "funded projects")
ggsv("desc_duration_hist.png", p_dur)

# =====================================================================
# BUNDLE 3 - SEASONALITY & CREATOR MATURATION  (core TTRPG)
# =====================================================================
core  <- g %>% filter(bucket == "TTRPG (core)")
coref <- core %>% filter(funded)

# Seasonality: within-era share of launches by calendar month (normalises for
# differing #years per era and for the coverage gap)
seas <- core %>%
  mutate(era = if_else(launch_year >= 2019, "2019+ (ZineQuest era)", "2014-2018")) %>%
  count(era, launch_month) %>%
  group_by(era) %>% mutate(share = n / sum(n)) %>% ungroup()
write_csv(seas, file.path(tabd, "desc_seasonality_by_month.csv"))
p_seas <- ggplot(seas, aes(factor(launch_month), share, fill = era)) +
  geom_col(position = "dodge") +
  scale_x_discrete(labels = month.abb) +
  scale_y_continuous(labels = percent) +
  scale_fill_manual(values = c("2014-2018" = "#bdbdbd", "2019+ (ZineQuest era)" = "#2c7fb8"), name = NULL) +
  labs(title = "When core TTRPG projects launch, by calendar month",
       subtitle = "February swells in the ZineQuest era (2019+)",
       x = NULL, y = "share of the era's launches")
ggsv("desc_seasonality_month.png", p_seas, w = 10, h = 4.5)

# Creator maturation: first appearance (by launch time) within the captured core
# TTRPG panel => "new"; any prior captured core launch => "returning".
# LEFT-CENSORING: the panel starts in 2014, so no one can be "returning" in the
# first years (prior history is unobserved). The early climb in returning-share is
# therefore partly mechanical; read the trend only once it stabilises (~2018+).
first_seen <- core %>% group_by(creator_id) %>%
  summarise(first_launch = min(launched, na.rm = TRUE), .groups = "drop")
mat <- core %>% left_join(first_seen, by = "creator_id") %>%
  mutate(status = if_else(launched > first_launch, "returning", "new (first seen)")) %>%
  count(launch_year, status) %>%
  group_by(launch_year) %>% mutate(share = n / sum(n)) %>% ungroup()
write_csv(mat, file.path(tabd, "desc_creator_maturation_by_year.csv"))
p_mat <- ggplot(mat, aes(launch_year, n, fill = status)) +
  gap_rect + geom_col() +
  scale_fill_manual(values = c("new (first seen)" = "#bdbdbd", "returning" = "#2c7fb8"), name = NULL) +
  yr_axis +
  labs(title = "Core TTRPG launches by creator experience (within captured panel)",
       subtitle = "Returning share climbs then settles near half; pre-2018 inflated by left-censoring  -  red = gap",
       x = "launch year", y = "core TTRPG launches")
ggsv("desc_creators_new_vs_returning.png", p_mat, w = 10, h = 4.5)

# =====================================================================
# BUNDLE 4 - GEOGRAPHY & DESIGN-FEATURE PREVALENCE  (core TTRPG)
# =====================================================================
TOPC <- c("US", "GB", "CA", "AU", "DE", "FR")
geo <- coref %>%
  mutate(country2 = if_else(country %in% TOPC, country, "Other")) %>%
  count(country2) %>%
  mutate(country2 = factor(country2, levels = c(TOPC, "Other")),
         share = n / sum(n))
write_csv(geo, file.path(tabd, "desc_country_composition.csv"))
p_geo <- ggplot(geo, aes(country2, share)) +
  geom_col(fill = "#2c7fb8") +
  scale_y_continuous(labels = percent) +
  labs(title = "Where funded core TTRPG projects come from",
       x = NULL, y = "share of funded core TTRPG projects")
ggsv("desc_country_composition.png", p_geo, w = 8, h = 4.5)

# NB: has_video is NOT plotted over time. Its captured TRUE-rate climbs
# monotonically (~6% -> ~58%) with no flagged missingness, which is a crawl-schema
# artifact (early crawls under-recorded video and defaulted it FALSE), not real
# adoption. staff_pick shows no such drift and is safe as a time series. We still
# write both rates to the table so the has_video drift is documented.
feat <- coref %>%
  group_by(launch_year) %>%
  summarise(`staff pick (Projects We Love)` = mean(staff_pick, na.rm = TRUE),
            has_video_unreliable = mean(has_video, na.rm = TRUE),
            .groups = "drop")
write_csv(feat, file.path(tabd, "desc_feature_prevalence_by_year.csv"))
p_feat <- feat %>%
  ggplot(aes(launch_year, `staff pick (Projects We Love)`)) +
  gap_rect + geom_line(linewidth = .8, color = "#de7a22") +
  geom_point(color = "#de7a22") +
  scale_y_continuous(labels = percent, limits = c(0, NA)) + yr_axis +
  labs(title = "Staff-pick rate among funded core TTRPG",
       subtitle = "'Projects We Love' tags ~1-in-10 (has_video omitted - unreliable pre-2022)  -  red = gap",
       x = "launch year", y = "share staff-picked")
ggsv("desc_feature_prevalence_by_year.png", p_feat, w = 10, h = 4.5)

# ---- console report --------------------------------------------------------
cat("\n######## 18_market_landscape.R ########\n")
cat("Capture caveats apply: totals conditional on funded; 2022-23 is a coverage gap.\n\n")
cat("=== Funded $ (M) and TTRPG share of Games, by year ===\n")
print(as.data.frame(market_wide %>%
  transmute(launch_year, ttrpg_musd = round(ttrpg_musd, 1),
            games_musd = round(games_musd, 1),
            ttrpg_share_games = percent(ttrpg_share_games, .1),
            tabletop_share_games = percent(tabletop_share_games, .1))))
cat("\n=== Share of dollars vs projects (2019-2025 excl. gap) ===\n")
print(as.data.frame(shares %>% transmute(bucket,
      dollars_pct = percent(`share of dollars`, .1),
      projects_pct = percent(`share of projects`, .1))))
cat("\n=== Country composition (funded core TTRPG) ===\n")
print(as.data.frame(geo %>% transmute(country2, share = percent(share, .1))))
cat("\nFigures -> figures/desc_market_*, desc_*_by_year, desc_seasonality_*, etc.\n")
