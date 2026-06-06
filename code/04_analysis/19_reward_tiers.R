#!/usr/bin/env Rscript
# 19_reward_tiers.R — Reward-tier ("whale tier") analysis for top-decile TTRPG
# BOOK campaigns, using the archive-sourced tier data (stages 05-06) + the book
# audit (03_features/04). Two halves: (1) descriptive — where backers and dollars
# sit across tier price points, how many tiers projects run, how concentrated each
# campaign's money is; (2) tier-structure vs magnitude — associational models of
# whether tier design tracks raising more / higher willingness-to-pay.
#
# SCOPE & CAVEATS (read before interpreting)
#   * SAMPLE = the top decile of *funded* RPG books (pledged >= ~$70k) that also have
#     an archived Kickstarter snapshot. That's a tail of a tail: funded-only, top-
#     decile-only, archive-covered-only. Nothing here generalises to typical books.
#   * "Success vs not" is NOT studyable here — every project is funded. "Success" =
#     MAGNITUDE (pledged, overfunding, avg pledge), not the funding binary.
#   * TIER REVENUE is APPROXIMATE: revenue_tier ~= price(minimum) x backers_tier. It
#     ignores over-pledging, add-ons, and shipping, so per-project tier revenue sums
#     to < pledged. We report sum(tier_rev)/pledged as a coverage diagnostic and use
#     SHARES (robust to the level gap), not absolute tier dollars.
#   * ASSOCIATIONAL only: tier design co-evolves with anticipated demand (a creator
#     expecting whales adds a $500 tier *because* they expect whales). Read the
#     models as descriptions of co-occurrence, not levers.
#
# Inputs : data/processed/ttrpg_reward_tiers.csv.gz, data/interim/ttrpg_reward_coverage.csv,
#          data/interim/ttrpg_book_targets_audited.csv, data/processed/ttrpg_model_features.csv.gz
# Outputs: figures/tier_*.png, tables/tier_*.csv

suppressPackageStartupMessages({ library(tidyverse); library(scales) })
theme_set(theme_minimal(base_size = 12)); BLUE <- "#2c7fb8"; ORANGE <- "#de7a22"

here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))), error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
ggsv <- function(n, p, w = 9, h = 5) ggsave(file.path(figd, n), p, width = w, height = h, dpi = 130)

# ---- load & frame ----------------------------------------------------------
tiers <- read_csv(file.path(proj, "data/processed/ttrpg_reward_tiers.csv.gz"), show_col_types = FALSE)
cov   <- read_csv(file.path(proj, "data/interim/ttrpg_reward_coverage.csv"), show_col_types = FALSE)
aud   <- read_csv(file.path(proj, "data/interim/ttrpg_book_targets_audited.csv"), show_col_types = FALSE)
feat  <- tryCatch(read_csv(file.path(proj, "data/processed/ttrpg_model_features.csv.gz"),
            show_col_types = FALSE) %>%
            select(id, any_of(c("is_dnd5e","is_osr","is_pbta","is_zine","staff_pick",
                                "log10_goal","country_us"))),   # launch_year comes from books
          error = function(e) tibble(id = integer()))

books <- aud %>% filter(is_book) %>%        # name lives on PS (tier table); keep id-keyed cols only
  transmute(id, pledged = pledged_usd, backers = backers_count, goal = goal_usd,
            launch_year = year(as_datetime(launched_at)))

# keep BOOK projects with trustworthy tier capture (status ok + tier backers ~ total)
cov2 <- cov %>%
  mutate(cap_ratio = ifelse(our_backers > 0, sum_tier_backers / our_backers, NA),
         ok = str_starts(status, "ok") & n_tiers >= 2 &
              (is.na(cap_ratio) | (cap_ratio >= 0.6 & cap_ratio <= 1.2)))
good_ids <- cov2 %>% filter(ok) %>% pull(id)

T <- tiers %>%
  filter(id %in% books$id, id %in% good_ids) %>%
  mutate(price = coalesce(minimum_usd, minimum_native),
         tier_backers = as.numeric(tier_backers),
         revenue = price * tier_backers) %>%
  filter(!is.na(price), price > 0, !is.na(tier_backers))

n_books <- n_distinct(T$id)
cat(sprintf("Book projects with usable tier data: %d  (of %d audited books; %d tiers)\n",
            n_books, nrow(books), nrow(T)))
if (n_books < 5) { cat("Too few projects scraped so far — rerun once stage 06 advances.\n"); quit(save = "no") }

# ---- price buckets ---------------------------------------------------------
BRK <- c(0, 10, 25, 50, 100, 250, 500, 1000, Inf)
LAB <- c("<$10","$10-25","$25-50","$50-100","$100-250","$250-500","$500-1k","$1k+")
T <- T %>% mutate(bucket = cut(price, BRK, labels = LAB, right = FALSE))

# =====================================================================
# PART 1 — DESCRIPTIVE
# =====================================================================
# 1a. pooled tier-price distribution
p_price <- ggplot(T, aes(price)) +
  geom_histogram(bins = 50, fill = BLUE, alpha = .8) +
  scale_x_log10(labels = label_dollar()) +
  labs(title = "Reward-tier price points (top-decile RPG books)",
       subtitle = sprintf("%d tiers across %d funded books", nrow(T), n_books),
       x = "tier price (log scale)", y = "number of tiers")
ggsv("tier_price_hist.png", p_price)

# 1b/1c. backers and (approx) dollars by price bucket  — the "whale" question
bsum <- T %>% group_by(bucket) %>%
  summarise(tiers = n(), backers = sum(tier_backers), revenue = sum(revenue), .groups = "drop") %>%
  mutate(backer_share = backers / sum(backers), dollar_share = revenue / sum(revenue))
write_csv(bsum, file.path(tabd, "tier_bucket_summary.csv"))

p_bd <- bsum %>% select(bucket, `backers` = backer_share, `dollars` = dollar_share) %>%
  pivot_longer(-bucket, names_to = "measure", values_to = "share") %>%
  ggplot(aes(bucket, share, fill = measure)) +
  geom_col(position = "dodge") + scale_y_continuous(labels = percent) +
  scale_fill_manual(values = c(backers = "#bdbdbd", dollars = BLUE), name = NULL) +
  labs(title = "Where the backers are vs. where the money is, by tier price",
       subtitle = "share of all backers (grey) and approx. share of all pledged dollars (blue)",
       x = "tier price", y = "share")
ggsv("tier_backers_vs_dollars_by_price.png", p_bd, w = 10)

# 1d. number of tiers per project
PS <- T %>% group_by(id, name) %>%
  summarise(n_tiers = n(), entry_price = min(price), top_price = max(price),
            median_price = median(price), tier_rev = sum(revenue),
            tier_backers = sum(tier_backers),
            top_tier_rev_share = revenue[which.max(price)] / sum(revenue),
            hhi_rev = sum((revenue / sum(revenue))^2),
            whale_rev_share = sum(revenue[price >= 250]) / sum(revenue),
            money_max_price = price[which.max(revenue)],
            .groups = "drop")
write_csv(PS, file.path(tabd, "tier_project_structure.csv"))

p_nt <- ggplot(PS, aes(n_tiers)) + geom_histogram(binwidth = 1, fill = BLUE, alpha = .8) +
  labs(title = "How many reward tiers projects offer", x = "number of tiers", y = "projects")
ggsv("tier_count_hist.png", p_nt, h = 4.5)

# 1e. within-project money concentration: top-tier dollar share
p_conc <- ggplot(PS, aes(top_tier_rev_share)) +
  geom_histogram(bins = 30, fill = BLUE, alpha = .8) + scale_x_continuous(labels = percent) +
  labs(title = "How concentrated each campaign's money is in its single top tier",
       subtitle = "share of a project's (approx.) tier dollars coming from its highest-priced tier",
       x = "top-tier share of project tier-dollars", y = "projects")
ggsv("tier_top_share_hist.png", p_conc, h = 4.5)

# 1f. the "sweet spot": price of each project's money-maximising tier
p_sweet <- ggplot(PS, aes(money_max_price)) +
  geom_histogram(bins = 40, fill = ORANGE, alpha = .85) + scale_x_log10(labels = label_dollar()) +
  geom_vline(xintercept = median(PS$money_max_price), linetype = "dashed") +
  labs(title = "Where the money is made: price of each project's top-grossing tier",
       subtitle = sprintf("dashed = median ($%s)", comma(round(median(PS$money_max_price)))),
       x = "price of the highest-revenue tier (log scale)", y = "projects")
ggsv("tier_sweetspot_hist.png", p_sweet, h = 4.5)

# revenue-approximation diagnostic
diag <- PS %>% inner_join(books, by = "id") %>%
  mutate(rev_cov = tier_rev / pledged)
write_csv(diag %>% select(id, name, pledged, tier_rev, rev_cov),
          file.path(tabd, "tier_revenue_coverage.csv"))

# =====================================================================
# PART 2 — TIER STRUCTURE vs MAGNITUDE (associational)
# =====================================================================
M <- PS %>% inner_join(books, by = "id") %>%
  left_join(feat, by = "id") %>%
  mutate(avg_pledge = pledged / backers,
         pct_of_goal = ifelse(!is.na(goal) & goal > 0, pledged / goal, NA),
         l_pledged = log10(pledged), l_avg = log10(avg_pledge),
         l_entry = log10(entry_price), l_top = log10(top_price),
         price_spread = log10(top_price / entry_price),
         has_whale = as.integer(top_price >= 500),
         ly = factor(launch_year))

run_models <- nrow(M) >= 30
if (run_models) {
  ctrl <- intersect(c("log10_goal","staff_pick","is_dnd5e","is_osr","is_zine"), names(M))
  rhs_struct <- "n_tiers + l_entry + l_top + price_spread + whale_rev_share"
  f1 <- as.formula(paste("l_pledged ~", rhs_struct, "+", paste(c(ctrl,"ly"), collapse = " + ")))
  f2 <- as.formula(paste("l_avg ~ l_top + has_whale + n_tiers +", paste(c(ctrl,"ly"), collapse = " + ")))
  m1 <- lm(f1, M); m2 <- lm(f2, M)
  tidy_lm <- function(m, lab) {
    s <- summary(m)$coefficients
    tibble(model = lab, term = rownames(s), est = s[,1], se = s[,2], p = s[,4]) %>%
      filter(!str_detect(term, "^ly|Intercept"))
  }
  coefs <- bind_rows(tidy_lm(m1, "log10_pledged"), tidy_lm(m2, "log10_avg_pledge"))
  write_csv(coefs, file.path(tabd, "tier_magnitude_models.csv"))

  p_m <- coefs %>% filter(model == "log10_pledged") %>%
    mutate(term = fct_reorder(term, est)) %>%
    ggplot(aes(est, term)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    geom_pointrange(aes(xmin = est - 1.96*se, xmax = est + 1.96*se), color = BLUE) +
    labs(title = "Tier-structure correlates of how much a funded book raises",
         subtitle = "OLS on log10(pledged), top-decile books; bars = 95% CI (associational, not causal)",
         x = "coefficient on log10(pledged)", y = NULL)
  ggsv("tier_magnitude_coefs.png", p_m, h = 5)
} else {
  cat(sprintf("Models skipped: only %d projects (need >=30). Descriptives written.\n", nrow(M)))
}

# ---- console report --------------------------------------------------------
cat("\n=== Backers vs dollars by tier price ===\n")
print(as.data.frame(bsum %>% transmute(bucket, tiers, backers,
      backer_share = percent(backer_share,.1), dollar_share = percent(dollar_share,.1))))
cat(sprintf("\nMedian tiers/project: %d | median top-tier $ share: %s | median money-max tier price: $%s\n",
    median(PS$n_tiers), percent(median(PS$top_tier_rev_share),1), comma(round(median(PS$money_max_price)))))
cat(sprintf("Tier-revenue coverage (sum tier $ / pledged): median %.2f  [approximation, expect <1]\n",
    median(diag$rev_cov, na.rm = TRUE)))
if (run_models) { cat("\n=== log10(pledged) ~ tier structure (+controls) ===\n")
  print(as.data.frame(coefs %>% filter(model=="log10_pledged") %>%
        transmute(term, est = round(est,3), se = round(se,3), p = signif(p,2)))) }
cat("\nFigures -> figures/tier_*.png ; tables -> tables/tier_*.csv\n")
