#!/usr/bin/env Rscript
# 20_real_terms_trends.R - Have TTRPG-book Kickstarters grown in REAL (inflation-
# adjusted) terms? Deflates nominal pledged USD by CPI-U and tracks, by launch
# year: the total market, the typical project raise, and the typical per-backer
# pledge - nominal vs. real - to ask whether RPG books have outpaced inflation.
#
# WHY THIS SCRIPT EXISTS
#   Everything upstream is NOMINAL USD: pledged_usd/goal_usd convert across
#   CURRENCIES (via static_usd_rate) but are never deflated across YEARS. Comparing
#   a 2015 raise to a 2025 raise therefore mixes real change with ~30% cumulative
#   inflation. Here we put every dollar in constant 2025 USD.
#
# MEASURES (funded core RPG BOOKS only; is_ttrpg == 1, state == successful)
#   * total_real      - sum of real pledged $ in a year  (MARKET SIZE = volume x price)
#   * median/mean proj raise - real pledged per project  (typical PROJECT)
#   * median/mean per-backer pledge = pledged/backers     (typical BACKER's outlay)
#
# READ THE CAVEATS BEFORE INTERPRETING
#   * SURVIVORS / FUNDED ONLY. Web Robots captures funded-heavy listings, so this is
#     conditional on funding. Dollar TOTALS are the most capture-robust aggregate
#     (failures raise ~nothing); per-project and per-backer RATIOS are robust to how
#     many projects a crawl happened to catch. Raw COUNTS are lower bounds.
#   * COVERAGE GAP 2022-07..2023-05 (OGL window): totals/counts dip there as an
#     ARTIFACT. Time plots shade it; those points are not comparable to neighbours.
#   * COMPOSITION. The median project raise is dragged down over time by the influx
#     of cheap zines (ZineQuest from 2019), not necessarily by each segment shrinking
#     - we show a zine-excluded median to separate the two.
#   * 2026 is a PARTIAL launch year (many campaigns still live) -> excluded.
#   * CPI 2025 annual average is itself PARTIAL (Oct-2025 missing, 2025 appropriations
#     lapse); treat the 2025 deflator as provisional.
#
# CPI-U: BLS Consumer Price Index for All Urban Consumers, US city avg, all items,
#        1982-84=100, ANNUAL AVERAGES. Source: BLS (series CUUR0000SA0), as tabulated
#        by usinflationcalculator.com (retrieved 2026-06).
#
# Outputs: tables/real_terms_rpg_books_by_year.csv ; figures/real_*.png

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
BLUE <- "#2c7fb8"; ORANGE <- "#d95f02"; GREY <- "#888888"
Y0 <- 2015; Y1 <- 2025; BASE <- 2025          # window + real-$ base year
GAP <- c(2022.5, 2023.4)
gap_rect <- annotate("rect", xmin = GAP[1], xmax = GAP[2], ymin = -Inf, ymax = Inf,
                     fill = "red", alpha = .10)
yr_axis <- scale_x_continuous(breaks = seq(Y0, Y1, 2))
ggsv <- function(name, p, w = 9, h = 5) ggsave(file.path(figd, name), p, width = w, height = h, dpi = 130)

# ---- CPI-U annual averages (1982-84=100) -----------------------------------
cpi <- tribble(
  ~launch_year, ~cpi,
  2012, 229.594, 2013, 232.957, 2014, 236.736, 2015, 237.017, 2016, 240.007,
  2017, 245.120, 2018, 251.107, 2019, 255.657, 2020, 258.811, 2021, 270.970,
  2022, 292.655, 2023, 304.702, 2024, 313.689, 2025, 321.943)            # 2025 partial
base_cpi <- cpi$cpi[cpi$launch_year == BASE]
cpi <- cpi %>% mutate(deflator = base_cpi / cpi)   # multiply nominal $ -> constant BASE $

# ---- load funded core RPG books --------------------------------------------
cls <- read_csv(file.path(proj, "data/processed/tabletop_classified.csv.gz"),
                show_col_types = FALSE)
# is_zine / is_dnd5e for the WITHIN-SEGMENT composition robustness (does the real
# decline survive holding product type roughly constant?)
seg <- tryCatch(
  read_csv(file.path(proj, "data/processed/ttrpg_model_features.csv.gz"),
           show_col_types = FALSE) %>% select(id, is_zine, is_dnd5e),
  error = function(e) tibble(id = integer(), is_zine = integer(), is_dnd5e = integer()))

books <- cls %>%
  filter(is_ttrpg == 1, state == "successful") %>%
  mutate(launch_year = year(as_datetime(launched_at)),
         avg_pledge  = ifelse(backers_count > 0, pledged_usd / backers_count, NA_real_)) %>%
  filter(!is.na(launch_year), launch_year >= Y0, launch_year <= Y1,
         pledged_usd > 0) %>%
  left_join(cpi, by = "launch_year") %>%
  left_join(seg, by = "id") %>%
  mutate(is_zine     = replace_na(is_zine, 0),
         is_dnd5e    = replace_na(is_dnd5e, 0),
         pledged_real = pledged_usd * deflator,
         avg_pledge_real = avg_pledge * deflator,
         goal_real    = goal_usd * deflator)   # the GOAL is a creator-set choice

# ---- per-year summary (nominal + real) -------------------------------------
by_year <- books %>%
  group_by(launch_year) %>%
  summarise(
    n              = n(),
    cpi            = first(cpi),
    total_nom      = sum(pledged_usd),
    total_real     = sum(pledged_real),
    proj_med_nom   = median(pledged_usd),
    proj_med_real  = median(pledged_real),
    proj_mean_nom  = mean(pledged_usd),
    proj_mean_real = mean(pledged_real),
    proj_med_real_nozine = median(pledged_real[is_zine == 0]),
    proj_med_real_5e     = median(pledged_real[is_dnd5e == 1]),
    pledge_med_nom  = median(avg_pledge, na.rm = TRUE),
    pledge_med_real = median(avg_pledge_real, na.rm = TRUE),
    pledge_med_real_nozine = median(avg_pledge_real[is_zine == 0], na.rm = TRUE),
    pledge_med_real_5e     = median(avg_pledge_real[is_dnd5e == 1], na.rm = TRUE),
    pledge_mean_nom  = mean(avg_pledge, na.rm = TRUE),
    pledge_mean_real = mean(avg_pledge_real, na.rm = TRUE),
    goal_med_nom   = median(goal_usd),
    goal_med_real  = median(goal_real),
    goal_mean_real = mean(goal_real),
    .groups = "drop")
write_csv(by_year, file.path(tabd, "real_terms_rpg_books_by_year.csv"))

# ---- headline numbers to console -------------------------------------------
pc <- function(a, b) sprintf("%+.0f%%", 100 * (b / a - 1))
g  <- function(yr, col) by_year[[col]][by_year$launch_year == yr]
cpi_chg <- 100 * (g(2025, "cpi") / g(2015, "cpi") - 1)
cat(sprintf("\n=== REAL-TERMS SUMMARY (funded core RPG books, constant %d USD) ===\n", BASE))
cat(sprintf("Cumulative CPI inflation %d->%d: +%.0f%%  (a measure must beat this to gain in real terms)\n",
            Y0, Y1, cpi_chg))
cat(sprintf("Total real market    : %s -> %s  (%s real; NOMINAL %s) [coverage-sensitive]\n",
            dollar(round(g(2015,"total_real"))), dollar(round(g(2025,"total_real"))),
            pc(g(2015,"total_real"), g(2025,"total_real")), pc(g(2015,"total_nom"), g(2025,"total_nom"))))
cat(sprintf("Median project raise : %s -> %s  (%s real; NOMINAL %s)\n",
            dollar(round(g(2015,"proj_med_real"))), dollar(round(g(2025,"proj_med_real"))),
            pc(g(2015,"proj_med_real"), g(2025,"proj_med_real")), pc(g(2015,"proj_med_nom"), g(2025,"proj_med_nom"))))
cat(sprintf("  excl. zines        : %s -> %s  (%s real)\n",
            dollar(round(g(2015,"proj_med_real_nozine"))), dollar(round(g(2025,"proj_med_real_nozine"))),
            pc(g(2015,"proj_med_real_nozine"), g(2025,"proj_med_real_nozine"))))
cat(sprintf("Median per-backer $  : %s -> %s  (%s real; NOMINAL %s)\n",
            dollar(round(g(2015,"pledge_med_real"),1)), dollar(round(g(2025,"pledge_med_real"),1)),
            pc(g(2015,"pledge_med_real"), g(2025,"pledge_med_real")), pc(g(2015,"pledge_med_nom"), g(2025,"pledge_med_nom"))))
cat(sprintf("Median goal (set)    : %s -> %s  (%s real; NOMINAL %s)\n",
            dollar(round(g(2015,"goal_med_real"))), dollar(round(g(2025,"goal_med_real"))),
            pc(g(2015,"goal_med_real"), g(2025,"goal_med_real")), pc(g(2015,"goal_med_nom"), g(2025,"goal_med_nom"))))
cat("--- WITHIN-SEGMENT robustness (is the decline composition, or broad?) ---\n")
cat(sprintf("Per-backer, non-zine : %s -> %s  (%s real)\n",
            dollar(round(g(2015,"pledge_med_real_nozine"),1)), dollar(round(g(2025,"pledge_med_real_nozine"),1)),
            pc(g(2015,"pledge_med_real_nozine"), g(2025,"pledge_med_real_nozine"))))
cat(sprintf("Per-backer, 5e-named : %s -> %s  (%s real)\n",
            dollar(round(g(2015,"pledge_med_real_5e"),1)), dollar(round(g(2025,"pledge_med_real_5e"),1)),
            pc(g(2015,"pledge_med_real_5e"), g(2025,"pledge_med_real_5e"))))
cat(sprintf("Raise,      5e-named : %s -> %s  (%s real)\n",
            dollar(round(g(2015,"proj_med_real_5e"))), dollar(round(g(2025,"proj_med_real_5e"))),
            pc(g(2015,"proj_med_real_5e"), g(2025,"proj_med_real_5e"))))

# ---- FIG A: nominal indices vs the inflation line (the headline) -----------
idx <- by_year %>%
  transmute(launch_year,
            `Median project raise` = 100 * proj_med_nom  / proj_med_nom[launch_year == Y0],
            `Median per-backer pledge` = 100 * pledge_med_nom / pledge_med_nom[launch_year == Y0],
            `CPI (inflation)` = 100 * cpi / cpi[launch_year == Y0]) %>%
  pivot_longer(-launch_year, names_to = "series", values_to = "index")
pA <- ggplot(idx, aes(launch_year, index, color = series, linetype = series)) +
  gap_rect +
  geom_hline(yintercept = 100, color = GREY, linewidth = .3) +
  geom_line(linewidth = 1.1) + geom_point(size = 1.6) +
  scale_color_manual(values = c("Median project raise" = BLUE,
                                "Median per-backer pledge" = ORANGE,
                                "CPI (inflation)" = "black"), name = NULL) +
  scale_linetype_manual(values = c("Median project raise" = "solid",
                                   "Median per-backer pledge" = "solid",
                                   "CPI (inflation)" = "dashed"), name = NULL) +
  yr_axis +
  labs(title = "Have RPG-book Kickstarters kept pace with inflation?",
       subtitle = sprintf("Nominal index, %d = 100. A line below the dashed CPI curve has LOST ground to inflation.", Y0),
       x = "launch year", y = sprintf("index (%d = 100)", Y0)) +
  theme(legend.position = "top")
ggsv("real_index_vs_inflation.png", pA)

# ---- FIG B: real per-backer pledge, WITHIN segments (composition check) -----
# If the decline were just cheap zines entering, it would vanish once we drop them
# or hold genre constant. It doesn't -> the fall is broad, not compositional.
pledge_long <- by_year %>%
  transmute(launch_year, `All core books` = pledge_med_real,
            `Non-zine only` = pledge_med_real_nozine,
            `D&D 5e-named` = pledge_med_real_5e) %>%
  pivot_longer(-launch_year, names_to = "seg", values_to = "usd")
pB <- ggplot(pledge_long, aes(launch_year, usd, color = seg)) +
  gap_rect + geom_line(linewidth = 1.1) + geom_point(size = 1.6) +
  scale_color_manual(values = c("All core books" = BLUE, "Non-zine only" = "#1b9e77",
                                "D&D 5e-named" = ORANGE), name = NULL) +
  scale_y_continuous(labels = dollar, limits = c(0, NA)) + yr_axis +
  labs(title = "Real per-backer pledge falls within segments, not just overall",
       subtitle = sprintf("Median pledged / backers, constant %d USD. Dropping zines or fixing the genre barely changes it.", BASE),
       x = "launch year", y = sprintf("real $ per backer (%d USD)", BASE)) +
  theme(legend.position = "top")
ggsv("real_per_backer_pledge.png", pB)

# ---- FIG C: real project raise (levels), with zine-excluded median ---------
raise_long <- by_year %>%
  select(launch_year, `Median (all)` = proj_med_real,
         `Median (excl. zines)` = proj_med_real_nozine, Mean = proj_mean_real) %>%
  pivot_longer(-launch_year, names_to = "stat", values_to = "usd")
pC <- ggplot(raise_long, aes(launch_year, usd, color = stat)) +
  gap_rect + geom_line(linewidth = 1.1) + geom_point(size = 1.6) +
  scale_color_manual(values = c("Median (all)" = BLUE,
                                "Median (excl. zines)" = "#1b9e77", Mean = ORANGE), name = NULL) +
  scale_y_continuous(labels = dollar) + yr_axis +
  labs(title = "Real raise per funded RPG book",
       subtitle = sprintf("In constant %d USD. The all-books median is dragged down by the post-2019 zine influx.", BASE),
       x = "launch year", y = sprintf("real pledged $ (%d USD)", BASE)) +
  theme(legend.position = "top")
ggsv("real_per_project_raise.png", pC)

# ---- FIG D: total real market $ (market size) ------------------------------
pD <- ggplot(by_year, aes(launch_year, total_real / 1e6)) +
  gap_rect +
  geom_col(fill = BLUE, alpha = .85) +
  yr_axis +
  scale_y_continuous(labels = label_number(suffix = "M", prefix = "$")) +
  labs(title = "Total real $ raised by funded RPG books",
       subtitle = sprintf("Constant %d USD. Market SIZE = volume x price; sensitive to crawl coverage (gap shaded).", BASE),
       x = "launch year", y = sprintf("real pledged $ (millions, %d USD)", BASE))
ggsv("real_total_dollars_by_year.png", pD)

# ---- FIG E: real funding GOAL set by creators (levels) ---------------------
goal_long <- by_year %>%
  transmute(launch_year, `Median (real)` = goal_med_real, `Mean (real)` = goal_mean_real,
            `Median (nominal)` = goal_med_nom) %>%
  pivot_longer(-launch_year, names_to = "stat", values_to = "usd")
pE <- ggplot(goal_long, aes(launch_year, usd, color = stat, linetype = stat)) +
  gap_rect + geom_line(linewidth = 1.1) + geom_point(size = 1.5) +
  scale_color_manual(values = c("Median (real)" = BLUE, "Mean (real)" = ORANGE,
                                "Median (nominal)" = GREY), name = NULL) +
  scale_linetype_manual(values = c("Median (real)" = "solid", "Mean (real)" = "solid",
                                   "Median (nominal)" = "dashed"), name = NULL) +
  scale_y_continuous(labels = dollar) + yr_axis +
  labs(title = "Funding goals set by RPG-book creators, in real dollars",
       subtitle = sprintf("Constant %d USD (nominal median dashed for reference). The goal is a pre-launch creator choice.", BASE),
       x = "launch year", y = sprintf("goal $ (%d USD)", BASE)) +
  theme(legend.position = "top")
ggsv("real_goal_by_year.png", pE)

cat(sprintf("\nWrote tables/real_terms_rpg_books_by_year.csv and 5 figures (real_*.png) for %d-%d.\n", Y0, Y1))
