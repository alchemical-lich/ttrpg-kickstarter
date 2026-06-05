#!/usr/bin/env Rscript
# 16_composition_5e_split.R — Does the MIX of book types differ between D&D-5e
# books and everything else, and how has each evolved? Stacked-area product-type
# shares by year, faceted: "D&D 5e" vs "Other systems".
#
# Motivation: 5e is a rules engine people publish FOR (adventures, supplements,
# bestiaries) more than a line of new core rulebooks; other/indie systems are more
# often whole new games (rulebooks) and zines. This chart tests that intuition.
#
# Sample: funded core `ttrpg` books, 2014-2026 (Web Robots; funded-biased). Tags
# are noisy -> read trends/shares, not levels.
# Out: figures/comp_producttype_5e_split.png, tables/comp_producttype_5e_split.csv
suppressPackageStartupMessages({ library(tidyverse); library(scales) })
here <- tryCatch(dirname(normalizePath(sub("^--file=", "",
          grep("^--file=", commandArgs(FALSE), value = TRUE)))),
          error = function(e) getwd())
proj <- normalizePath(file.path(here, "..", ".."))
tabd <- file.path(proj, "tables"); figd <- file.path(proj, "figures")
theme_set(theme_minimal(base_size = 12))

sub <- read_csv(file.path(proj, "data", "processed", "ttrpg_book_subcats.csv.gz"),
                show_col_types = FALSE)
meta <- read_csv(file.path(proj, "data", "processed", "tabletop_classified.csv.gz"),
                 show_col_types = FALSE) %>%
  filter(ttrpg_label == "ttrpg", state == "successful") %>%
  mutate(launch_year = year(as_datetime(launched_at))) %>%
  filter(launch_year >= 2015, launch_year <= 2026) %>%
  select(id, launch_year)

ptype_ord <- c("rulebook", "setting", "adventure", "supplement", "bestiary",
               "gm_tools", "zine", "other")
ptype_lab <- c(rulebook = "rulebook", setting = "setting", adventure = "adventure",
               supplement = "supplement", bestiary = "bestiary", gm_tools = "GM tools",
               zine = "zine", other = "other")

d <- inner_join(meta, sub, by = "id") %>%
  mutate(grp = if_else(system_family == "dnd5e", "D&D 5e books", "Other-system books"),
         product_type = factor(product_type, levels = ptype_ord))

tab <- d %>%
  count(grp, launch_year, product_type, name = "n") %>%
  group_by(grp, launch_year) %>% mutate(share = n / sum(n)) %>% ungroup()
write_csv(tab, file.path(tabd, "comp_producttype_5e_split.csv"))

# drop very thin early-year cells for 5e (n small pre-2016) from the plot's first years? keep all; note in caption
p <- ggplot(tab, aes(launch_year, share, fill = product_type)) +
  geom_area(color = "white", linewidth = .2) +
  facet_wrap(~grp) +
  annotate("rect", xmin = 2022.5, xmax = 2023.4, ymin = 0, ymax = 1, fill = "grey30", alpha = .12) +
  scale_y_continuous(labels = percent, expand = c(0, 0)) +
  scale_x_continuous(breaks = seq(2015, 2026, 3), expand = c(0, 0)) +
  scale_fill_brewer(palette = "Set2", labels = ptype_lab, name = NULL,
                    guide = guide_legend(reverse = TRUE)) +
  labs(title = "What kind of book is it? D&D 5e vs other systems",
       subtitle = "product-type share of funded RPG books per year (grey band = 2022-23 coverage gap)",
       x = "launch year", y = "share of funded books")
ggsave(file.path(figd, "comp_producttype_5e_split.png"), p, width = 11, height = 5, dpi = 130)

# ---- summary: pooled product mix, 5e vs other ----
pooled <- d %>%
  count(grp, product_type) %>%
  group_by(grp) %>% mutate(share = n / sum(n)) %>% ungroup() %>%
  select(grp, product_type, share) %>%
  pivot_wider(names_from = grp, values_from = share)
cat("=== pooled product-type share: 5e vs other (funded books) ===\n")
print(as.data.frame(pooled %>% mutate(across(where(is.numeric), ~round(.x, 3)))))
cat(sprintf("\nn: 5e books = %d, other-system books = %d\n",
            sum(d$grp == "D&D 5e books"), sum(d$grp == "Other-system books")))
cat("Figure -> figures/comp_producttype_5e_split.png\n")
