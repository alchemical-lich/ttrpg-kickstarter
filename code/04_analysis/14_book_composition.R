#!/usr/bin/env Rscript
# 14_book_composition.R — How has the composition of funded RPG-BOOK Kickstarters
# shifted over time? Stacked-area shares by launch year for three axes
# (system family, product type, genre), tagged in 03_subcategorize_books.py.
#
# Sample: core `ttrpg` books, FUNDED (state==successful), launched 2014-2026
# (Web Robots). Caveats on the charts: funded-only (capture-biased); the 2022-2023
# coverage gap thins those years; sub-tags are noisy (esp. genre ~half "other",
# and PbtA undercounted because indie games rarely name the label). Read trends,
# not precise levels.
#
# Out: tables/book_composition_*.csv, figures/comp_*.png

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
  filter(launch_year >= 2014, launch_year <= 2026) %>%
  select(id, launch_year)

d <- inner_join(meta, sub, by = "id")
cat(sprintf("funded RPG books, 2014-2026: %d\n", nrow(d)))

# factor orders (for sensible stacking/legends)
ord <- list(
  system_family = c("dnd5e", "pathfinder", "osr", "pbta_fitd", "other_named", "agnostic_other"),
  product_type  = c("rulebook", "setting", "adventure", "supplement", "bestiary", "gm_tools", "zine", "other"),
  genre         = c("fantasy", "scifi", "horror", "cyberpunk", "post_apoc", "superhero", "western", "historical", "other")
)
labels <- list(
  system_family = c(dnd5e = "D&D 5e", pathfinder = "Pathfinder", osr = "OSR",
                    pbta_fitd = "PbtA / FitD", other_named = "other named system",
                    agnostic_other = "agnostic / unnamed"),
  product_type  = c(rulebook = "rulebook", setting = "setting", adventure = "adventure",
                    supplement = "supplement", bestiary = "bestiary", gm_tools = "GM tools",
                    zine = "zine", other = "other"),
  genre         = c(fantasy = "fantasy", scifi = "sci-fi", horror = "horror",
                    cyberpunk = "cyberpunk", post_apoc = "post-apoc", superhero = "superhero",
                    western = "western", historical = "historical", other = "other")
)
titles <- c(system_family = "System family", product_type = "Product type", genre = "Genre")

make_chart <- function(axis) {
  tab <- d %>% count(launch_year, !!sym(axis), name = "n") %>%
    rename(cat = !!sym(axis)) %>%
    group_by(launch_year) %>% mutate(share = n / sum(n)) %>% ungroup() %>%
    mutate(cat = factor(cat, levels = ord[[axis]]))
  write_csv(tab, file.path(tabd, paste0("book_composition_", axis, ".csv")))
  p <- ggplot(tab, aes(launch_year, share, fill = cat)) +
    geom_area(color = "white", linewidth = .2) +
    annotate("rect", xmin = 2022.5, xmax = 2023.4, ymin = 0, ymax = 1, fill = "grey30", alpha = .12) +
    scale_y_continuous(labels = percent, expand = c(0, 0)) +
    scale_x_continuous(breaks = seq(2014, 2026, 2), expand = c(0, 0)) +
    scale_fill_brewer(palette = if (length(ord[[axis]]) > 8) "Set3" else "Set2",
                      labels = labels[[axis]], name = NULL,
                      guide = guide_legend(reverse = TRUE)) +
    labs(title = paste0("Composition of funded RPG books: ", titles[axis]),
         subtitle = "share of funded core-RPG-book launches per year (grey band = 2022-23 coverage gap)",
         x = "launch year", y = "share of funded RPG books")
  ggsave(file.path(figd, paste0("comp_", axis, ".png")), p, width = 10, height = 5, dpi = 130)
  tab
}

for (a in names(ord)) make_chart(a)

# ---- highlight numbers ----
hl <- d %>%
  mutate(era = case_when(launch_year <= 2015 ~ "2014-15", launch_year >= 2023 ~ "2023-26", TRUE ~ "mid")) %>%
  filter(era != "mid") %>%
  group_by(era) %>%
  summarise(n = n(),
            dnd5e = mean(system_family == "dnd5e"),
            osr = mean(system_family == "osr"),
            zine = mean(product_type == "zine"),
            adventure = mean(product_type == "adventure"), .groups = "drop")
cat("\n=== composition shift (share), early vs recent ===\n")
print(as.data.frame(hl %>% mutate(across(c(dnd5e, osr, zine, adventure), ~round(.x, 3)))))
cat("\nFigures -> figures/comp_*.png ; tables -> tables/book_composition_*.csv\n")
