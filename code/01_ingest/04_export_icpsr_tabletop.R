#!/usr/bin/env Rscript
# 04_export_icpsr_tabletop.R — Crack the ICPSR 38050 .rda (R-native format) and
# export a clean Tabletop Games panel for downstream TTRPG classification + analysis.
#
# ICPSR 38050 "Kickstarter Data, Global, 2009-2023" (Leland, NADAC). DS0001 is the
# public-use project file: 610,015 all-terminal projects (failed/successful/
# canceled/suspended) — so, unlike Web Robots, it carries the failures we need.
# Quirks handled: numerics/dates stored as factors; $-formatted money; padded
# factor levels.
#
# Output: data/interim/icpsr_tabletop_clean.csv.gz  (no TTRPG label yet — that is
# added by code/03_features, reusing the one keyword classifier as single source
# of truth; ICPSR has no blurb, so the flag is NAME-ONLY like the Kaggle panel.)

suppressPackageStartupMessages({ library(tidyverse) })

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
rda  <- file.path(proj, "data", "raw", "ICPSR_38050", "DS0001", "38050-0001-Data.rda")
out  <- file.path(proj, "data", "interim", "icpsr_tabletop_clean.csv.gz")

money <- function(x) as.numeric(gsub("[^0-9.]", "", as.character(x)))

# ICPSR mixes two date formats: "M/D/YYYY" (older rows) and ISO "YYYY-MM-DD"
# (2021-2023 rows). Parse both, else recent projects are silently dropped.
parse_dual <- function(x) {
  x <- trimws(as.character(x))
  out <- suppressWarnings(mdy(x))
  iso <- suppressWarnings(ymd(x))
  out[is.na(out)] <- iso[is.na(out)]
  as.Date(out)
}

e <- new.env(); load(rda, envir = e)
d <- e[["da38050.0001"]]

# Flatten the whole file first (all categories), so creator track record counts a
# creator's PRIOR projects across ALL categories (incl. failures, which ICPSR has).
base <- d %>%
  transmute(
    pid          = PID,
    uid          = UID,                       # creator/user id
    name         = as.character(NAME),
    category     = trimws(as.character(CATEGORY)),
    subcategory  = trimws(as.character(SUBCATEGORY)),
    country      = trimws(as.character(PROJECT_PAGE_LOCATION_COUNTRY)),
    state        = trimws(as.character(STATE)),
    launched     = parse_dual(LAUNCHED_DATE),
    deadline     = parse_dual(DEADLINE_DATE),
    goal_usd     = money(GOAL_IN_USD),
    pledged_usd  = money(PLEDGED_IN_USD),
    backers      = as.numeric(BACKERS_COUNT)
  )

# Creator track record: PRIOR projects (any category) by launch order within UID,
# counting prior successes and failures (a true reputation measure, since ICPSR
# carries failures — unlike the funded-only Web Robots creator history).
ch <- base %>%
  filter(!is.na(uid)) %>%          # ~104k projects have NA uid; do NOT lump them
  arrange(uid, launched) %>%
  group_by(uid) %>%
  mutate(
    creator_prior_n      = row_number() - 1L,
    creator_prior_funded = lag(cumsum(state == "successful"), default = 0L),
    creator_prior_failed = lag(cumsum(state == "failed"),     default = 0L)
  ) %>%
  ungroup() %>%
  mutate(creator_prior_success_rate =
           if_else(creator_prior_n > 0, creator_prior_funded / creator_prior_n, NA_real_)) %>%
  select(pid, creator_prior_n, creator_prior_funded, creator_prior_failed,
         creator_prior_success_rate)

tt <- base %>%
  filter(grepl("Tabletop Games", subcategory, fixed = TRUE)) %>%
  left_join(ch, by = "pid") %>%
  mutate(
    launch_year   = year(launched),
    duration_days = as.numeric(deadline - launched),
    funded        = state == "successful",
    terminal      = state %in% c("successful", "failed", "canceled", "suspended"),
    pct_of_goal   = pledged_usd / na_if(goal_usd, 0)
  )

write_csv(tt, out)
cat(sprintf("ICPSR Tabletop rows: %d  (launched %s..%s)\n",
            nrow(tt), min(tt$launch_year, na.rm = TRUE), max(tt$launch_year, na.rm = TRUE)))
cat("STATE:\n"); print(table(tt$state))
cat(sprintf("\nTrue success (successful vs failed): %.1f%%  (n=%d)\n",
            100 * mean(tt$state[tt$state %in% c("successful","failed")] == "successful"),
            sum(tt$state %in% c("successful","failed"))))
cat("Wrote", out, "\n")
