#!/usr/bin/env Rscript
# 04_build_model_features.R — Engineer the feature matrix for the drivers-of-
# magnitude model (outcome = log10 pledged USD among FUNDED projects).
#
# Sample: funded (state==successful) ttrpg + ttrpg_accessory, launched 2015-2026.
# Predictors are PRE-/AT-LAUNCH only. We deliberately EXCLUDE post-outcome fields
# (backers_count, pct_of_goal, pledged itself) and `spotlight` (a badge granted
# only to funded projects). `staff_pick` is kept but is a quasi-endogenous quality
# signal (KS may award it in anticipation of success) — interpret with care.
# `log10_goal` is also endogenous (creators set goals anticipating demand): read
# associations, not causal effects.
#
# Creator track record = count of the creator's PRIOR funded tabletop campaigns we
# observe (Web Robots misses failures, so this is a prior-success / backer-base
# proxy, not full prior activity).
#
# Out: data/processed/ttrpg_model_features.csv.gz

suppressPackageStartupMessages({ library(tidyverse) })

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
src  <- file.path(proj, "data", "processed", "tabletop_classified.csv.gz")
out  <- file.path(proj, "data", "processed", "ttrpg_model_features.csv.gz")

raw <- read_csv(src, show_col_types = FALSE) %>%
  mutate(launched = as_datetime(launched_at),
         deadline_dt = as_datetime(deadline),
         launch_year = year(launched),
         funded = state == "successful") %>%
  filter(funded, launch_year >= 2015, launch_year <= 2026, pledged_usd > 0)

# creator prior funded campaigns: over ALL funded tabletop (any class), count this
# creator's earlier funded projects by launch order.
creator_hist <- raw %>%
  arrange(creator_id, launched) %>%
  group_by(creator_id) %>%
  mutate(creator_prior_funded = row_number() - 1L) %>%
  ungroup() %>%
  select(id, creator_prior_funded)

txt <- function(x) tolower(paste(x))
has <- function(s, pat) str_detect(s, regex(pat, ignore_case = TRUE))

feat <- raw %>%
  filter(ttrpg_label %in% c("ttrpg", "ttrpg_accessory")) %>%
  left_join(creator_hist, by = "id") %>%
  mutate(
    nm = paste(coalesce(name, ""), coalesce(blurb, "")),
    log10_pledged = log10(pledged_usd),
    log10_goal    = log10(pmax(goal_usd, 1)),
    duration_days = as.numeric(deadline_dt - launched, units = "days"),
    launch_month  = factor(month(launched)),
    launch_dow    = factor(wday(launched, week_start = 1)),
    zinequest_win = as.integer(month(launched) == 2),  # ZineQuest runs in February
    has_video     = as.integer(has_video),
    staff_pick    = as.integer(coalesce(staff_pick, 0)),
    blurb_chars   = nchar(coalesce(blurb, "")),
    blurb_words   = str_count(coalesce(blurb, ""), "\\S+"),
    title_words   = str_count(coalesce(name, ""), "\\S+"),
    country_us    = as.integer(country == "US"),
    class_accessory = as.integer(ttrpg_label == "ttrpg_accessory"),
    creator_is_repeat = as.integer(creator_prior_funded >= 1),
    # system / genre tags (content)
    is_dnd5e   = as.integer(has(nm, "\\b5e\\b|5th edition|d&d|dungeons & dragons|dnd|pathfinder")),
    is_osr     = as.integer(has(nm, "\\bosr\\b|old[ -]?school|mork borg|mörk borg|shadowdark|dcc|osric")),
    is_pbta    = as.integer(has(nm, "powered by the apocalypse|\\bpbta\\b|forged in the dark|blades in the dark")),
    is_zine    = as.integer(has(nm, "\\bzine\\b|zinequest"))
  ) %>%
  filter(duration_days > 0, duration_days < 120) %>%
  select(id, creator_id, ttrpg_label, class_accessory, log10_pledged, pledged_usd,
         log10_goal, duration_days, launch_year, launch_month, launch_dow,
         zinequest_win, has_video, staff_pick, blurb_chars, blurb_words,
         title_words, country_us, creator_prior_funded, creator_is_repeat,
         is_dnd5e, is_osr, is_pbta, is_zine)

write_csv(feat, out)
cat(sprintf("feature rows: %d  (funded ttrpg+accessory, launched 2015+)\n", nrow(feat)))
cat("class:", paste(names(table(feat$ttrpg_label)), table(feat$ttrpg_label), collapse="  "), "\n")
cat("\nfeature means / rates:\n")
feat %>% summarise(
  med_pledged = median(pledged_usd), med_log10_goal = median(log10_goal),
  med_duration = median(duration_days), video = mean(has_video),
  staff = mean(staff_pick), us = mean(country_us), repeat_c = mean(creator_is_repeat),
  dnd5e = mean(is_dnd5e), osr = mean(is_osr), pbta = mean(is_pbta), zine = mean(is_zine)
) %>% as.data.frame() %>% print(digits = 3)
cat("\nWrote", out, "\n")
