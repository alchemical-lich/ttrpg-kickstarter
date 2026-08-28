#!/usr/bin/env Rscript
# 21_tier_bundles.R — Does BUNDLE CONTENT (an expensive tier stuffed with accessories)
# track raising more? Companion to 19_reward_tiers.R, which had price and backer counts
# but no measure of what is actually IN a tier.
#
# THE QUESTION 19 COULD NOT ANSWER
#   19's strongest tier coefficient, whale_rev_share (+0.62), is derived FROM the
#   outcome: it is the share of tier revenue from >=$250 tiers, and tier revenue is
#   ~0.76 x pledged. It decomposes the outcome rather than predicting it. The design
#   choice a creator actually makes — offer a big bundled tier or not — needs a
#   content measure, which stages 01_ingest/08 + 03_features/05 now provide.
#
# WHAT THIS SCRIPT ESTIMATES  (two different questions; they do not agree, and that
# disagreement is the finding)
#   (A) PROJECT level: do campaigns offering broader bundles raise more in total?
#   (B) TIER level, within campaign, price held fixed: do broader tiers pull backers
#       away from narrower ones? Project fixed effects + a flexible price control.
#   (C) CREATOR fixed effects: when the SAME creator runs a more heavily bundled
#       campaign, do they raise more? This is the closest thing to a lever test the
#       data supports -- it nets out the obvious confound that creators who bundle
#       are also creators with bigger audiences.
#
# SCOPE & CAVEATS (read before interpreting)
#   * Inherits 19's frame: top decile of FUNDED RPG books with a usable archived page.
#     Funded-only and top-decile-only, so NOTHING here speaks to *getting funded*.
#   * Itemization markup exists ONLY on the page template Kickstarter used for
#     campaigns launched ~2017-2022 (zero coverage before 2017 and after 2022; 81-90%
#     of parsed pages within it). So this is not "41% missing at random" -- it is a
#     hard ERA WINDOW. Read every content result as a statement about the 2017-2022
#     era, not about the decade. Coverage by year is written to tier_bundle_coverage.csv.
#   * Tier itemizations are CUMULATIVE ("everything above, plus..."), so breadth rises
#     with price mechanically. (B) controls price with a natural spline and is re-run
#     dropping each project's cheapest and dearest tier.
#   * ASSOCIATIONAL. Creators choose bundles in anticipation of demand. The within-
#     campaign comparison is tighter than the cross-campaign one but is not random.
#   * SAMPLES ARE FIT SEPARATELY, NOT POOLED. The original frame is the top decile
#     (pledged >= $68,585); the 2026-08 expansion adds the rest of the top quartile
#     ($19,135-68,585), whose campaigns are ~5x smaller. Pooling them under one slope
#     would average away any size-varying effect. Fitting each frame with the SAME
#     specification instead makes the expansion an out-of-sample replication of the
#     top-decile result. This split was specified BEFORE the expansion data existed
#     (see CHANGELOG 2026-08-27); do not retune the spec per sample.
#   * log10(tier revenue) is NOT reported as a separate outcome: revenue = price x
#     backers, so with log price on the RHS its breadth coefficient is algebraically
#     identical to the backers one.
#
# Inputs : data/processed/ttrpg_tier_bundles.csv.gz, ttrpg_project_bundles.csv.gz,
#          ttrpg_reward_tiers.csv.gz, ttrpg_model_features.csv.gz,
#          data/interim/ttrpg_book_targets_audited.csv, ttrpg_reward_coverage.csv,
#          tables/tier_project_structure.csv  (from 19_reward_tiers.R)
# Outputs: figures/tier_bundle_*.png, tables/tier_bundle_*.csv

suppressPackageStartupMessages({ library(tidyverse); library(scales); library(splines); library(fixest)
                                 library(clubSandwich) })
set.seed(42)
theme_set(theme_minimal(base_size = 12)); BLUE <- "#2c7fb8"; ORANGE <- "#de7a22"; GREY <- "grey55"

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))), error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
ggsv <- function(n, p, w = 9, h = 5) ggsave(file.path(figd, n), p, width = w, height = h, dpi = 130)
chr  <- function(x) as.character(x)

# ---- load ------------------------------------------------------------------
TB <- read_csv(file.path(proj, "data/processed/ttrpg_tier_bundles.csv.gz"),   show_col_types = FALSE) %>%
        mutate(id = chr(id), reward_id = chr(reward_id))
PB <- read_csv(file.path(proj, "data/processed/ttrpg_project_bundles.csv.gz"), show_col_types = FALSE) %>%
        mutate(id = chr(id))
# Tier data now spans TWO scraped frames: the original top-decile run and the
# 2026-08 top-quartile 2017-2022 expansion. Load both and apply 19_reward_tiers.R's
# quality filter identically to each (status ok, >=2 tiers, tier backers within
# 0.6-1.2 of the project total at that snapshot).
rd <- function(...) {
  f <- file.path(proj, ...)
  if (file.exists(f)) read_csv(f, show_col_types = FALSE) else NULL
}
TR <- bind_rows(
        rd("data/processed/ttrpg_reward_tiers.csv.gz"),
        rd("data/processed/ttrpg_reward_tiers_expansion.csv.gz")) %>%
      mutate(id = chr(id), reward_id = chr(reward_id)) %>% distinct(id, reward_id, .keep_all = TRUE)
COVR <- bind_rows(
        rd("data/interim/ttrpg_reward_coverage.csv"),
        rd("data/interim/ttrpg_reward_coverage_expansion.csv")) %>%
      mutate(id = chr(id)) %>% distinct(id, .keep_all = TRUE)
AUD <- bind_rows(
        rd("data/interim/ttrpg_book_targets_audited.csv"),
        rd("data/interim/ttrpg_book_targets_expansion_audited.csv")) %>%
      mutate(id = chr(id)) %>% distinct(id, .keep_all = TRUE)

good_ids <- COVR %>%
  mutate(cap = ifelse(our_backers > 0, sum_tier_backers / our_backers, NA),
         ok  = str_starts(status, "ok") & n_tiers >= 2 &
               (is.na(cap) | (cap >= 0.6 & cap <= 1.2))) %>%
  filter(ok) %>% pull(id)
book_ids <- AUD %>% filter(is_book) %>% pull(id)

# project-level tier structure, same definitions as 19_reward_tiers.R
PS <- TR %>%
  filter(id %in% book_ids, id %in% good_ids) %>%
  mutate(price = coalesce(minimum_usd, minimum_native),
         tier_backers = as.numeric(tier_backers), revenue = price * tier_backers) %>%
  filter(!is.na(price), price > 0, !is.na(tier_backers)) %>%
  group_by(id) %>%
  summarise(n_tiers = n(), entry_price = min(price), top_price = max(price),
            tier_rev = sum(revenue),
            whale_rev_share = sum(revenue[price >= 250]) / sum(revenue), .groups = "drop")
fe <- read_csv(file.path(proj, "data/processed/ttrpg_model_features.csv.gz"),  show_col_types = FALSE) %>%
        mutate(id = chr(id)) %>%
        select(id, any_of(c("log10_pledged","pledged_usd","log10_goal","staff_pick",
                            "is_dnd5e","is_osr","is_zine","launch_year")))
fe_creator <- read_csv(file.path(proj, "data/processed/ttrpg_model_features.csv.gz"),
                       show_col_types = FALSE) %>%
        mutate(id = chr(id), creator_id = chr(creator_id)) %>% select(id, creator_id)

CTRL <- c("log10_goal","staff_pick","is_dnd5e","is_osr","is_zine")
# 90th pct of pledged among funded core RPG books; the original tier frame's floor.
DECILE_CUT <- 68585
tidy1 <- function(m, term, lab, note = "") {
  s <- summary(m)$coefficients[term, ]
  tibble(model = lab, term = term, est = s[1], se = s[2], p = s[4], n = nobs(m), note = note)
}

# =====================================================================
# PART 0 — coverage / selection diagnostic
# =====================================================================
COV <- PS %>% left_join(fe, by = "id") %>%
  mutate(has_bundle = id %in% PB$id) %>%
  group_by(has_bundle) %>%
  summarise(n = n(), med_pledged = median(pledged_usd, na.rm = TRUE),
            med_launch_year = median(launch_year, na.rm = TRUE),
            pct_offering_500plus = mean(top_price >= 500, na.rm = TRUE),
            med_n_tiers = median(n_tiers), .groups = "drop")
SEL <- PS %>% left_join(fe, by = "id") %>% mutate(has_bundle = id %in% PB$id)
sel_p_pled <- suppressWarnings(wilcox.test(pledged_usd  ~ has_bundle, data = SEL)$p.value)
sel_p_year <- suppressWarnings(wilcox.test(launch_year ~ has_bundle, data = SEL)$p.value)
COV %>% mutate(wilcox_p_pledged = sel_p_pled, wilcox_p_launch_year = sel_p_year) %>%
  write_csv(file.path(tabd, "tier_bundle_coverage.csv"))

# The coverage story is a TEMPLATE ERA, not a size bias: the "Includes:" itemization
# markup exists only for campaigns launched ~2017-2022. Emit it by year so the scope
# limit is legible instead of buried in a caveat.
COVYR <- PS %>% left_join(fe, by = "id") %>%
  mutate(has_bundle = id %in% PB$id) %>%
  group_by(launch_year) %>%
  summarise(projects = n(), with_itemization = sum(has_bundle),
            coverage = round(mean(has_bundle), 2), .groups = "drop") %>%
  arrange(launch_year)
write_csv(COVYR, file.path(tabd, "tier_bundle_coverage_by_year.csv"))

# =====================================================================
# PART 1 — what bundling looks like (descriptive)
# =====================================================================
tg <- bind_rows(rd("data/interim/ttrpg_book_targets.csv"),
                rd("data/interim/ttrpg_book_targets_expansion.csv")) %>%
  mutate(id = chr(id)) %>% distinct(id, .keep_all = TRUE) %>% select(id, launched_at, deadline)

TT <- TB %>%
  filter(id %in% book_ids, id %in% good_ids) %>%
  inner_join(TR %>% select(id, reward_id, minimum_usd, tier_backers, snapshot_ts),
             by = c("id","reward_id")) %>%
  left_join(tg, by = "id") %>%
  filter(!is.na(minimum_usd), minimum_usd > 0, !is.na(tier_backers), tier_backers > 0) %>%
  # how far into the campaign was the archived page captured? ~half are mid-campaign,
  # so tier backer counts are partial (see the timing placebo in Part 3).
  mutate(snap = as.POSIXct(as.character(snapshot_ts), format = "%Y%m%d%H%M%S", tz = "UTC"),
         .ln  = as.POSIXct(launched_at, origin = "1970-01-01", tz = "UTC"),
         .dl  = as.POSIXct(deadline,    origin = "1970-01-01", tz = "UTC"),
         pct_elapsed = as.numeric(difftime(snap, .ln, units = "secs")) /
                       as.numeric(difftime(.dl,  .ln, units = "secs")),
         late_snap = !is.na(pct_elapsed) & pct_elapsed >= 0.9) %>%
  mutate(l_price = log10(minimum_usd), l_back = log10(tier_backers),
         band = cut(minimum_usd, c(0,25,50,100,250,500,Inf), right = FALSE,
                    labels = c("<$25","$25-50","$50-100","$100-250","$250-500","$500+"))) %>%
  group_by(id) %>% mutate(rank_in_proj = rank(minimum_usd, ties.method = "first"),
                          n_in_proj = n()) %>% ungroup() %>%
  # Assign the frame by pledged relative to the top-decile cut, NOT by which target
  # file the project arrived in: 20 of the expansion targets are top-decile books the
  # original run happened to miss, and they belong with the top decile.
  left_join(fe %>% select(id, pledged_usd), by = "id") %>%
  mutate(sample = case_when(
    is.na(pledged_usd)        ~ NA_character_,
    pledged_usd >= DECILE_CUT ~ "top decile (>=$68.6k)",
    TRUE                      ~ "expansion ($19.1-68.6k)"))

cats <- c("dice","minis","gm_screen","map","cards","art","apparel","other_phys")
CATTAB <- TT %>% select(band, all_of(paste0("has_", cats))) %>%
  pivot_longer(-band, names_to = "category", values_to = "present") %>%
  mutate(category = str_remove(category, "^has_")) %>%
  group_by(band, category) %>% summarise(share = mean(present), .groups = "drop")
write_csv(CATTAB, file.path(tabd, "tier_bundle_category_by_band.csv"))

p1 <- CATTAB %>%
  mutate(category = fct_reorder(category, share, .fun = max)) %>%
  ggplot(aes(band, category, fill = share)) +
  geom_tile(colour = "white", linewidth = .4) +
  # colour mapped per-row (an ifelse() over the un-plotted frame mis-assigns labels)
  geom_text(aes(label = ifelse(share >= .04, percent(share, 1), ""),
                colour = share > .20), size = 3, show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "grey20")) +
  scale_fill_gradient(low = "white", high = BLUE, labels = percent) +
  labs(title = "What gets bundled in, by tier price",
       subtitle = paste0("Share of tiers in each price band that include each accessory type.\n",
                         "Top-decile funded RPG books; itemized tiers only."),
       x = NULL, y = NULL, fill = "share of tiers") +
  theme(panel.grid = element_blank())
ggsv("tier_bundle_category_by_band.png", p1, w = 9.5, h = 4.8)

p2 <- TT %>%
  ggplot(aes(band, bundle_breadth)) +
  geom_boxplot(fill = BLUE, alpha = .25, outlier.size = .6, colour = BLUE) +
  labs(title = "Bundle breadth rises to about $100, then plateaus",
       subtitle = paste0("Distinct accessory categories per tier. Note the $500+ 'whale' tiers are no broader than\n",
                         "the $100-250 ones - expensive tiers are mostly more EXPENSIVE, not more stuffed.\n",
                         "Itemizations are cumulative ('everything above, plus...'), so the models control price\n",
                         "flexibly rather than reading this gradient as an effect."),
       x = "tier price", y = "accessory categories in the tier")
ggsv("tier_bundle_breadth_by_band.png", p2, h = 4.6)

# =====================================================================
# PART 2 — (A) PROJECT level: does breadth track a bigger raise?
# =====================================================================
UB <- TB %>% mutate(b_ub = bundle_breadth + as.integer(n_unclassified > 0)) %>%
  group_by(id) %>% summarise(max_ub = max(b_ub), .groups = "drop")

MP <- PS %>% inner_join(PB, by = "id") %>% inner_join(UB, by = "id") %>%
  left_join(fe, by = "id") %>%
  mutate(l_entry = log10(entry_price), l_top = log10(top_price),
         has_whale = as.integer(top_price >= 500), ly = factor(launch_year),
         sample = case_when(is.na(pledged_usd)        ~ NA_character_,
                            pledged_usd >= DECILE_CUT ~ "top decile (>=$68.6k)",
                            TRUE                      ~ "expansion ($19.1-68.6k)"))

fP <- function(rhs) as.formula(paste("log10_pledged ~", rhs, "+", paste(c(CTRL,"ly"), collapse = " + ")))
fit_project_battery <- function(dat, samp) {
  if (nrow(dat) < 40) return(tibble())
  bind_rows(
    tidy1(lm(fP("max_bundle_breadth + n_tiers + l_entry"), dat), "max_bundle_breadth",
          "project", "breadth, price-free") %>% mutate(sample = samp),
    tidy1(lm(fP("max_bundle_breadth + l_top + n_tiers + l_entry"), dat), "max_bundle_breadth",
          "project", "breadth, + ceiling price") %>% mutate(sample = samp),
    tidy1(lm(fP("max_ub + n_tiers + l_entry"), dat), "max_ub",
          "project", "UPPER BOUND: unclassified counted as accessories") %>% mutate(sample = samp),
    tidy1(lm(fP("has_whale + n_tiers + l_entry"), dat), "has_whale",
          "project", "design proxy: offers a >=$500 tier") %>% mutate(sample = samp))
}

# POOLING THE TWO FRAMES HERE IS A TRAP. The frames differ in BOTH breadth and size
# (top decile: mean breadth 1.71, median pledged ~$149k; expansion: 1.08 and ~$34k),
# so a pooled regression reads that between-frame gradient as a breadth effect:
# pooled gives +0.031 (p=0.005), but the SAME spec fit within each frame gives
# +0.004 (p=0.78) and +0.013 (p=0.09), and adding a frame dummy to the pooled model
# collapses it to +0.014 (p=0.07). The project-level null holds; the pooled number is
# composition. Report the separate fits; keep the pooled row only as a labelled foil.
projA <- bind_rows(
  fit_project_battery(MP, "ALL (pooled - CONFOUNDED, see note)"),
  MP %>% filter(!is.na(sample)) %>% group_split(sample) %>%
    map_dfr(~ fit_project_battery(.x, unique(.x$sample))),
  tidy1(lm(fP("max_bundle_breadth + n_tiers + l_entry + sample"), MP), "max_bundle_breadth",
        "project", "pooled + frame dummy (absorbs the between-frame gradient)") %>%
    mutate(sample = "ALL (pooled + frame dummy)"))
write_csv(projA, file.path(tabd, "tier_bundle_project_models.csv"))

# =====================================================================
# PART 3 — (B) TIER level within campaign, price held fixed
# =====================================================================
TT_in <- TT %>% filter(rank_in_proj > 1, rank_in_proj < n_in_proj)
# Project fixed effects with SEs CLUSTERED BY PROJECT. Tiers within a campaign are
# not independent draws; iid SEs understate uncertainty by ~50% here.
tidyF <- function(m, term, note, samp = NA_character_) {
  s <- summary(m, cluster = ~id)
  tibble(model = "tier", sample = samp, term = term, est = coef(s)[term], se = se(s)[term],
         p = pvalue(s)[term], n = s$nobs, note = note)
}

# THE specification, applied identically to every frame. Defined once so the
# expansion sample cannot be given a differently-tuned model.
fit_tier_battery <- function(TT, samp) {
  if (n_distinct(TT$id) < 20) return(tibble())
  TT_in  <- TT %>% filter(rank_in_proj > 1, rank_in_proj < n_in_proj)
  m_both <- feols(l_back ~ bundle_breadth + n_items + ns(l_price, 4) | id, TT)
  bind_rows(
    tidyF(feols(l_back ~ bundle_breadth + ns(l_price, 4) | id, TT),    "bundle_breadth", "breadth alone, spline price (df=4)", samp),
    tidyF(feols(l_back ~ n_items + ns(l_price, 4)        | id, TT),    "n_items",        "item COUNT alone, spline price", samp),
    tidyF(feols(l_back ~ n_items + ns(l_price, 4)        | id, TT_in), "n_items",        "item COUNT alone, extremes dropped", samp),
    tidyF(m_both, "n_items",        "HORSE RACE: item count, breadth held fixed", samp),
    tidyF(m_both, "bundle_breadth", "HORSE RACE: breadth, item count held fixed", samp))
}

TT_in  <- TT %>% filter(rank_in_proj > 1, rank_in_proj < n_in_proj)
m_both <- feols(l_back ~ bundle_breadth + n_items + ns(l_price, 4) | id, TT)
POOLED <- "ALL (pooled)"
tierA <- bind_rows(
  tidyF(feols(l_back ~ bundle_breadth + l_price          | id, TT),    "bundle_breadth", "breadth alone, linear price",                   POOLED),
  tidyF(feols(l_back ~ bundle_breadth + poly(l_price, 2) | id, TT),    "bundle_breadth", "breadth alone, quadratic price",                POOLED),
  tidyF(feols(l_back ~ bundle_breadth + ns(l_price, 4)   | id, TT),    "bundle_breadth", "breadth alone, spline price (df=4)",            POOLED),
  tidyF(feols(l_back ~ bundle_breadth + ns(l_price, 4)   | id, TT_in), "bundle_breadth", "breadth alone, spline price, extremes dropped", POOLED),
  tidyF(feols(l_back ~ n_items + ns(l_price, 4)          | id, TT),    "n_items",        "item COUNT alone, spline price",                POOLED),
  tidyF(feols(l_back ~ n_items + ns(l_price, 4)          | id, TT_in), "n_items",        "item COUNT alone, extremes dropped",            POOLED),
  # HORSE RACE. Count wins; breadth turns negative once count is held fixed, so
  # breadth's standalone effect is it proxying for count (corr ~ 0.55).
  tidyF(m_both, "n_items",        "HORSE RACE: item count, breadth held fixed", POOLED),
  tidyF(m_both, "bundle_breadth", "HORSE RACE: breadth, item count held fixed", POOLED),
  # SNAPSHOT TIMING placebo: ~half the archived pages were captured mid-campaign, so
  # tier backer counts are partial. A uniform undercount is absorbed by the project FE;
  # what would bias the SLOPE is differential fill-up by tier type. It does not.
  tidyF(feols(l_back ~ n_items + ns(l_price, 4) | id, TT %>% filter(!late_snap)), "n_items",
        "item count, EARLY snapshots (<90% elapsed)", POOLED),
  tidyF(feols(l_back ~ n_items + ns(l_price, 4) | id, TT %>% filter(late_snap)),  "n_items",
        "item count, LATE snapshots (>=90% elapsed)", POOLED))

# --- the pre-specified separate fits (identical spec per frame) ---------------
bySample <- TT %>% filter(!is.na(sample)) %>% group_split(sample) %>%
  map_dfr(~ fit_tier_battery(.x, unique(.x$sample)))
tierA <- bind_rows(tierA, bySample)
write_csv(tierA, file.path(tabd, "tier_bundle_tier_models.csv"))

# =====================================================================
# PART C — CREATOR FIXED EFFECTS: is bundling a lever for a given creator?
# =====================================================================
# The cross-sectional project model conflates two things: creators who bundle more
# vs campaigns that raise more BECAUSE they bundled. Comparing a creator against
# their own other campaigns separates them. Few clusters (~70 creators, ~51 of them
# actually varying breadth), so inference uses CR2 plus a null-imposed wild cluster
# bootstrap, the same treatment 13_zinequest_robust.R gives its few-cluster design.
CT   <- "max_bundle_breadth"
CVARS <- c("log10_pledged", CT, CTRL, "n_tiers", "l_entry", "launch_year", "creator_id")
MC <- MP %>%
  left_join(fe_creator, by = "id") %>%
  filter(!is.na(creator_id)) %>%
  drop_na(any_of(CVARS)) %>%
  group_by(creator_id) %>% filter(n() >= 2) %>%
  arrange(launch_year, .by_group = TRUE) %>% mutate(seq = row_number()) %>% ungroup()

creatorA <- tibble()
if (n_distinct(MC$creator_id) >= 20) {
  rhs <- paste(c(CT, CTRL, "n_tiers", "l_entry"), collapse = " + ")
  grab <- function(m, note, cl = NULL) {
    sm <- if (is.null(cl)) summary(m) else summary(m, cluster = cl)
    tibble(term = CT, est = coef(sm)[CT], se = se(sm)[CT], p = pvalue(sm)[CT],
           n = sm$nobs, note = note)
  }
  creatorA <- bind_rows(
    grab(feols(as.formula(paste("log10_pledged ~", rhs, "| launch_year")), MC),
         "year FE only (cross-sectional, for contrast)"),
    grab(feols(as.formula(paste("log10_pledged ~", rhs, "| creator_id")), MC),
         "CREATOR FE", ~creator_id),
    grab(feols(as.formula(paste("log10_pledged ~", rhs, "| creator_id + launch_year")), MC),
         "CREATOR + YEAR FE", ~creator_id),
    grab(feols(as.formula(paste("log10_pledged ~", rhs, "+ seq | creator_id + launch_year")), MC),
         "CREATOR + YEAR FE, + campaign sequence", ~creator_id))

  # CR2 + wild cluster bootstrap on the headline spec (lm dummies so clubSandwich reads it)
  fD <- as.formula(paste("log10_pledged ~", rhs, "+ factor(creator_id) + factor(launch_year)"))
  mD <- lm(fD, MC)
  V2 <- vcovCR(mD, cluster = MC$creator_id, type = "CR2")
  b  <- coef(mD)[CT]; se2 <- sqrt(diag(V2)[CT]); t_obs <- as.numeric(b / se2)
  ctst <- coef_test(mD, vcov = V2, cluster = MC$creator_id, test = "Satterthwaite")
  p_cr2 <- ctst$p_Satt[rownames(ctst) == CT][1]
  r  <- lm(update(fD, . ~ . - max_bundle_breadth), MC); yh <- fitted(r); uh <- resid(r)
  cl <- unique(MC$creator_id); B <- 1999; ts <- numeric(B)
  for (i in seq_len(B)) {
    w <- setNames(sample(c(-1, 1), length(cl), replace = TRUE), cl)
    Db <- MC; Db$log10_pledged <- yh + w[Db$creator_id] * uh
    mb <- lm(fD, Db)
    ts[i] <- as.numeric(coef(mb)[CT] /
             sqrt(diag(vcovCR(mb, cluster = Db$creator_id, type = "CR2"))[CT]))
  }
  creatorA <- bind_rows(creatorA,
    tibble(term = CT, est = b, se = se2, p = p_cr2, n = nrow(MC),
           note = "CREATOR + YEAR FE, CR2 (Satterthwaite)"),
    tibble(term = CT, est = b, se = se2, p = (1 + sum(abs(ts) >= abs(t_obs))) / (B + 1),
           n = nrow(MC), note = sprintf("CREATOR + YEAR FE, wild cluster bootstrap (B=%d)", B)))
  write_csv(creatorA, file.path(tabd, "tier_bundle_creator_fe.csv"))
}

# ---- headline figure: the two levels side by side --------------------------
PLOT <- bind_rows(
  projA %>% filter(term == "max_bundle_breadth",
                   note == "pooled + frame dummy (absorbs the between-frame gradient)") %>%
    mutate(lab = "PROJECT: total raised\nper accessory category"),
  tierA %>% filter(sample == "ALL (pooled)", note == "item COUNT alone, spline price") %>%
    mutate(lab = "TIER in campaign: backers\nper extra item listed"),
  tierA %>% filter(sample == "ALL (pooled)", note == "HORSE RACE: breadth, item count held fixed") %>%
    mutate(lab = "TIER in campaign: backers\nper category, count held fixed"),
  creatorA %>% filter(note == "year FE only (cross-sectional, for contrast)") %>%
    mutate(lab = "PROJECT: total raised\nper category, ACROSS creators"),
  creatorA %>% filter(note == "CREATOR + YEAR FE") %>%
    mutate(lab = "PROJECT: total raised\nper category, WITHIN creator")) %>%
  mutate(lab = factor(lab, levels = rev(unique(lab)))) %>%
  mutate(lo = est - 1.96*se, hi = est + 1.96*se,
         sig = ifelse(p < .05, "p < .05", "not distinguishable from 0"))

p3 <- ggplot(PLOT, aes(est, lab, colour = sig)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi), linewidth = .8, size = .7) +
  scale_colour_manual(values = c("p < .05" = BLUE, "not distinguishable from 0" = GREY)) +
  scale_x_continuous(sec.axis = sec_axis(~ 10^., name = "multiply by", breaks = c(.95,1,1.1,1.2,1.3))) +
  labs(title = "Bundling moves backers between tiers, not money into the campaign",
       subtitle = paste0(
         "Within a campaign at a fixed price, a tier listing more items draws more backers.\n",
         "The VARIETY of accessory types adds nothing once item count is held fixed, and\n",
         "neither shows up in the campaign total. The last two rows are the same 212 campaigns\n",
         "by 70 repeat creators: across creators the effect looks real; within a creator it is gone.\n",
         "95% CIs. Funded RPG books 2017-2022, itemized tiers, both frames pooled with a frame\n",
         "dummy (tier_bundle_replication.png fits each separately). Project models control goal,\n",
         "staff pick, system tags, tier count, entry price, year; tier models add project FE."),
       x = "coefficient (log10 units)", y = NULL, colour = NULL) +
  theme(legend.position = "bottom")
ggsv("tier_bundle_effects.png", p3, w = 10, h = 6)

# ---- replication figure: the same spec in each frame -----------------------
if (nrow(bySample)) {
  REP <- bind_rows(
      bySample %>% filter(note == "HORSE RACE: item count, breadth held fixed") %>%
        mutate(what = "item COUNT\n(breadth held fixed)"),
      bySample %>% filter(note == "HORSE RACE: breadth, item count held fixed") %>%
        mutate(what = "accessory VARIETY\n(item count held fixed)")) %>%
    mutate(lo = est - 1.96*se, hi = est + 1.96*se,
           what = factor(what, levels = c("item COUNT\n(breadth held fixed)",
                                          "accessory VARIETY\n(item count held fixed)")))
  p4 <- ggplot(REP, aes(est, sample, colour = sample)) +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_pointrange(aes(xmin = lo, xmax = hi), linewidth = .8, size = .6) +
    facet_wrap(~ what) +
    scale_colour_manual(values = c(BLUE, ORANGE), guide = "none") +
    labs(title = "Out-of-sample replication: the same tier spec in two independent frames",
         subtitle = paste0(
           "Effect on log10(tier backers), project fixed effects + natural-spline price control, SEs clustered by project.\n",
           "The specification was fixed BEFORE the expansion frame was scraped. Item count replicates in both; accessory\n",
           "variety flips sign, i.e. noise around zero. 95% CIs."),
         x = "coefficient (log10 units)", y = NULL)
  ggsv("tier_bundle_replication.png", p4, w = 10, h = 4)
}

# ---- console report --------------------------------------------------------
cat("\n=== coverage / selection (tier_bundle_coverage.csv) ===\n")
print(as.data.frame(COV %>% mutate(pct_offering_500plus = percent(pct_offering_500plus, .1))))
cat(sprintf("  Wilcoxon: pledged p=%.3f (size-balanced) | launch_year p=%.3g (ERA-SELECTED)\n",
            sel_p_pled, sel_p_year))
cat(sprintf("  itemized tiers: %d across %d projects\n", nrow(TT), n_distinct(TT$id)))
cat("\n=== coverage by launch year: a TEMPLATE ERA, not a size bias ===\n")
print(as.data.frame(COVYR))
cat("  -> content measures describe the 2017-2022 era only.\n")

cat("\n=== (A) PROJECT level: log10(pledged), EACH FRAME FIT SEPARATELY ===\n")
print(as.data.frame(projA %>% filter(term == "max_bundle_breadth") %>%
        transmute(sample, note, est = round(est,4), se = round(se,4), p = round(p,3), n)))
cat("\n  full battery (all terms) -> tables/tier_bundle_project_models.csv\n")
sep <- projA %>% filter(term == "max_bundle_breadth", note == "breadth, price-free",
                        !str_starts(sample, "ALL"))
cat(sprintf("  -> within-frame estimates: %s\n",
            paste(sprintf("%s %+.4f (p=%.2f)", sep$sample, sep$est, sep$p), collapse = "; ")))
if (all(sep$p > 0.05)) cat("  -> no frame shows a project-level effect; the pooled row is between-frame composition.\n")
mde <- 2.8 * max(sep$se)
cat(sprintf("  -> MDE at 80%% power (weakest frame): %.3f dex/category = x%.2f\n", mde, 10^mde))

cat("\n=== (B) TIER level within campaign: log10(tier backers) ===\n")
print(as.data.frame(tierA %>% filter(sample == "ALL (pooled)") %>%
        transmute(note, est = round(est,4), se = round(se,4), p = signif(p,2), n)))
cat("\n--- SAME SPEC, EACH FRAME FIT SEPARATELY (out-of-sample replication) ---\n")
if (nrow(bySample)) {
  print(as.data.frame(bySample %>% transmute(sample, note, est = round(est,4),
                      se = round(se,4), p = signif(p,2), n)))
} else {
  cat("  expansion frame not present yet -- re-run after stages 05/06/08 + features.\n")
}
cat("\n=== (C) CREATOR FIXED EFFECTS: same creator, more bundling, more money? ===\n")
if (nrow(creatorA)) {
  print(as.data.frame(creatorA %>% transmute(note, est = round(est,4), se = round(se,4),
                                             p = round(p,3), n)))
  hd <- creatorA %>% filter(note == "CREATOR + YEAR FE") %>% slice(1)
  cat(sprintf("  -> identified off %d creators with >=2 campaigns (%d of them varying breadth).\n",
              n_distinct(MC$creator_id),
              MC %>% group_by(creator_id) %>% filter(n_distinct(max_bundle_breadth) > 1) %>%
                     ungroup() %>% pull(creator_id) %>% n_distinct()))
  cat(sprintf("  -> within creator: %+.4f, 95%% CI [x%.2f, x%.2f] per category. The cross-\n",
              hd$est, 10^(hd$est - 1.96*hd$se), 10^(hd$est + 1.96*hd$se)))
  cat("     sectional +0.031 is between-creator composition, not a lever.\n")
} else cat("  too few repeat creators in the bundle sample to identify.\n")

cat("\n  projects per frame:\n")
print(as.data.frame(TT %>% distinct(id, sample) %>% count(sample)))
# NB: subset to the pooled rows -- tierA now also holds the per-sample fits, and an
# unfiltered match would make these sprintf() calls vectorise and print once per row.
POOL <- tierA %>% filter(sample == "ALL (pooled)")
b  <- POOL$est[POOL$note == "breadth alone, spline price (df=4)"]
ci <- POOL$est[POOL$note == "item COUNT alone, spline price"]
hb <- POOL$est[POOL$note == "HORSE RACE: breadth, item count held fixed"]
cat(sprintf("  -> breadth alone: +%.3f dex/category (x%.2f backers), strengthening as the\n", b, 10^b))
cat("     price control gets more flexible.\n")
cat(sprintf("  -> BUT the horse race says that is breadth proxying for sheer item COUNT\n"))
cat(sprintf("     (corr %.2f): count keeps +%.3f dex/item (x%.2f) while breadth flips to\n",
            cor(TT$bundle_breadth, TT$n_items), ci, 10^ci))
cat(sprintf("     %+.3f, p=%.2f, once count is held fixed. It is more THINGS that pulls\n",
            hb, POOL$p[POOL$note == "HORSE RACE: breadth, item count held fixed"]))
cat("     backers to a tier, not more KINDS of thing.\n")
rep <- bySample %>% filter(note == "HORSE RACE: item count, breadth held fixed")
cat(sprintf("  -> REPLICATES out of sample: %s\n",
            paste(sprintf("%s %+.3f (p=%.1g)", rep$sample, rep$est, rep$p), collapse = "; ")))
repb <- bySample %>% filter(note == "HORSE RACE: breadth, item count held fixed")
cat(sprintf("  -> breadth-net-of-count flips sign across frames (%s) -- noise around zero.\n",
            paste(sprintf("%+.3f", repb$est), collapse = " vs ")))
cat("  -> Neither aggregates: no project-level effect on the total raised (Part A).\n")
cat("\nFigures -> figures/tier_bundle_*.png ; tables -> tables/tier_bundle_*.csv\n")
