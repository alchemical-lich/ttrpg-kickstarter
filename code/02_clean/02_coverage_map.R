#!/usr/bin/env Rscript
# 02_coverage_map.R — Data-coverage diagnostics for the Web Robots crawls.
#
# Produces:
#   tables/crawl_coverage.csv  — per crawl (2015+): did it contain Games data?
#   figures/tabletop_launches_by_month_coverage.png — monthly tabletop launches,
#       with months that have NO Games crawl shaded red (the coverage gaps).
#
# Of the 130 crawls from 2015 on, 31 are partial Web Robots crawls that captured
# no Games category at all (verified — not a parser bug). The severe gap is
# 2022-07 .. 2023-05. See brainstorming/data_sources.md.

suppressPackageStartupMessages({
  library(tidyverse)
  library(scales)
})

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
           grep("^--file=", commandArgs(FALSE), value = TRUE)))),
           error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

# ---- which crawls (2015+) produced Games data? -----------------------------
urls <- read_tsv(file.path(proj, "data", "raw", "_crawl_urls.tsv"),
                 col_names = c("crawl_date", "url"),
                 col_types = cols(.default = col_character()))
have <- list.files(file.path(proj, "data", "interim", "games_by_crawl"),
                   pattern = "^games_.*\\.csv\\.gz$") %>%
  str_remove("^games_") %>% str_remove("\\.csv\\.gz$")

cov <- urls %>%
  filter(crawl_date >= "2015") %>%
  transmute(crawl_date, has_games = crawl_date %in% have)
write_csv(cov, file.path(tabd, "crawl_coverage.csv"))

empty_months <- cov %>%
  filter(!has_games) %>%
  mutate(m = as_date(ym(str_sub(crawl_date, 1, 7)))) %>%
  pull(m)

# ---- monthly tabletop launches (use Date throughout) -----------------------
master <- read_csv(file.path(proj, "data", "processed", "games_master.csv.gz"),
                   show_col_types = FALSE) %>%
  filter(is_tabletop)

monthly <- master %>%
  mutate(m = as_date(floor_date(as_datetime(launched_at), "month"))) %>%
  filter(m >= as.Date("2015-01-01"), m <= as.Date("2026-05-31")) %>%
  count(m, name = "n_projects")
cat(sprintf("monthly rows: %d (max n=%d)\n", nrow(monthly), max(monthly$n_projects)))

# rectangles for the empty-crawl months
gap_df <- tibble(xmin = empty_months, xmax = empty_months %m+% months(1))

p <- ggplot(monthly, aes(m, n_projects)) +
  geom_rect(data = gap_df, inherit.aes = FALSE,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "red", alpha = .18) +
  geom_col(fill = "#33aa66", width = 25) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(title = "Tabletop Kickstarter projects by launch month",
       subtitle = "red = months with NO Web Robots Games crawl (coverage gaps)",
       x = "launch month", y = "unique projects")
ggsave(file.path(figd, "tabletop_launches_by_month_coverage.png"),
       p, width = 13, height = 4.5, dpi = 130)

cat(sprintf("Crawls 2015+: %d total | %d with Games | %d empty\n",
            nrow(cov), sum(cov$has_games), sum(!cov$has_games)))
cat("Wrote tables/crawl_coverage.csv and figures/tabletop_launches_by_month_coverage.png\n")
