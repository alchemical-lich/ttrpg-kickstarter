# Data

**Raw, intermediate, and processed data are intentionally NOT included in this
repository** (they are git-ignored). The underlying sources belong to third
parties under their own terms, and some restrict redistribution. The pipeline
regenerates everything from these sources; this README explains how to obtain them.

Place raw inputs under `data/raw/` as described below, then run `bash code/run_all.sh`.

## Sources

### 1. Web Robots Kickstarter crawls (primary)
- Monthly JSON snapshots of Kickstarter, 2014–present.
- Homepage: https://webrobots.io/kickstarter-datasets/
- **You do not download these manually.** `code/01_ingest/02_build_games_panel.py`
  reads the crawl URLs in `data/raw/_crawl_urls.tsv` (included), downloads each
  monthly dump to a temp folder, filters to the Games category, and writes
  `data/interim/games_by_crawl/`. ~40 minutes, network-bound, idempotent.

### 2. Kaggle "Kickstarter Projects" (failures, 2009–2018)
- Dataset: https://www.kaggle.com/datasets/kemical/kickstarter-projects
  (file `ks-projects-201801.csv`).
- Place at: `data/raw/kaggle_ks_2018/ks-projects-201801.csv`.

### 3. ICPSR 38050 — Kickstarter Data, Global, 2009–2023 (failures through 2023)
- Leland, Jonathan. *Kickstarter Data, Global, 2009-2023*. ICPSR 38050.
  https://doi.org/10.3886/ICPSR38050.v3
- Requires a free ICPSR account. Download the package and extract so that
  `data/raw/ICPSR_38050/DS0001/38050-0001-Data.rda` exists.
- ICPSR has its own Terms of Use; we do not redistribute the file.

## What the pipeline produces (all git-ignored)
- `data/interim/games_by_crawl/` — per-crawl Games subsets (Web Robots).
- `data/processed/` — analysis-ready panels:
  `tabletop_classified.csv.gz`, `kaggle_tabletop.csv.gz`, `icpsr_tabletop.csv.gz`,
  `ttrpg_model_features.csv.gz`, `games_master.csv.gz`, `games_observations.csv.gz`.

The committed `figures/` and `tables/` are the *outputs* of running the pipeline on
these inputs, so the write-up renders without re-running anything.
