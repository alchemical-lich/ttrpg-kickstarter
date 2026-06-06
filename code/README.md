# Code — TTRPG Kickstarter analysis

Reproducible pipeline from raw sources to the tables and figures used in the paper.

## How to run
```bash
bash code/run_all.sh        # from the project root
```
The script runs the whole pipeline in dependency order and is idempotent (the slow
Web Robots crawl download is skipped if `data/interim/games_by_crawl/` is already
populated). Dependencies: `requirements.txt` (Python) and `code/r_dependencies.txt` (R).

## Language split (convention)
- **Python** — data engineering only: ingesting/parsing the Web Robots JSON dumps
  (`01_ingest/`) and the keyword TTRPG classifier (`03_features/`).
- **R (tidyverse + ggplot2)** — all analysis, modeling, tables, and figures
  (`02_clean/`, `04_analysis/`). One exception: `01_ingest/04_export_icpsr_tabletop.R`
  is R because ICPSR ships as an R `.rda`.

## Raw inputs required under `data/raw/`
- Web Robots crawls: downloaded automatically to `/tmp` by `01_ingest/02_...py`
  (URLs in `data/raw/_crawl_urls.tsv`). Nothing to place manually.
- `data/raw/kaggle_ks_2018/ks-projects-201801.csv` (Kaggle export; see its `SOURCE.md`).
- `data/raw/ICPSR_38050/` (ICPSR 38050 public-use, extracted; see its `SOURCE.md`).

## Pipeline order (what each stage produces)
| Stage | Script | Output |
|---|---|---|
| Ingest | `01_ingest/02_build_games_panel.py` | `data/interim/games_by_crawl/` |
| Clean | `02_clean/01_build_master_panel.py` | `data/processed/games_{master,observations}.csv.gz` |
| Features | `03_features/01_classify_ttrpg.py` | `data/processed/tabletop_classified.csv.gz` (4-class label) |
| Ingest | `01_ingest/03_build_kaggle_tabletop.py` | `data/processed/kaggle_tabletop.csv.gz` |
| Ingest | `01_ingest/04_export_icpsr_tabletop.R` | `data/interim/icpsr_tabletop_clean.csv.gz` |
| Features | `03_features/02_classify_icpsr_tabletop.py` | `data/processed/icpsr_tabletop.csv.gz` (PID label transfer) |
| Features | `03_features/03_subcategorize_books.py` | `data/processed/{ttrpg,kaggle}_book_subcats.csv.gz` (system / product-type / genre tags) |
| Clean | `02_clean/02_coverage_map.R` | `tables/crawl_coverage.csv`, coverage figure |
| Analysis | `04_analysis/01_descriptive_landscape.R` | descriptive tables/figures |
| Analysis | `04_analysis/02,03_success_rates_*.R` | true success rates (Kaggle, ICPSR) |
| Analysis | `04_analysis/04_build_model_features.R` | `data/processed/ttrpg_model_features.csv.gz` |
| Analysis | `04_analysis/05_drivers_model.R` | magnitude model (OLS/LASSO/RF, quantile) |
| Analysis | `04_analysis/06,07_success_model*.R` | success/failure models (ICPSR, Kaggle) |
| Analysis | `04_analysis/08_text_drivers.R` | text-as-data (leakage-free CV) |
| Analysis | `04_analysis/09,10_*_by_class*.R` | books-vs-accessories interactions |
| Analysis | `04_analysis/11,13_zinequest*.R` | ZineQuest DiD + robust inference |
| Analysis | `04_analysis/12_did_5e.R` | 5e event study |
| Analysis | `04_analysis/14_book_composition.R` | composition shares by year (system / product type / genre) |
| Analysis | `04_analysis/15_funding_threshold_rd.R` | all-or-nothing RD at 100%-of-goal + McCrary manipulation test |
| Analysis | `04_analysis/16_composition_5e_split.R` | product-type mix, D&D 5e vs other systems |
| Analysis | `04_analysis/17_subcat_drivers.R` | system/product-type tags in the magnitude & success models |
| Analysis | `04_analysis/18_market_landscape.R` | baseline landscape: category dollar-share over time, goal/duration distributions, seasonality, creator maturation (`figures/desc_*`, `tables/desc_*`) |

## Reward tiers (manual, network — not in `run_all.sh`)
A separate, network-dependent path recovers per-reward-tier data (price, backers, limit)
for the top-decile RPG **books**, reading *archived* campaign pages from the Internet
Archive (never Kickstarter directly):
- `01_ingest/05_recover_project_urls.py` — recover project URLs + deadlines from the raw
  crawls for the top decile of funded core-TTRPG books.
- `03_features/04_audit_book_targets.py` — hand-audited filter of those targets to genuine
  RPG *books* (`is_book`).
- `01_ingest/06_scrape_wayback_rewards.py` — fetch the Wayback snapshot nearest each
  deadline, parse the embedded reward tiers (cached, rate-limited, resumable).
- `04_analysis/19_reward_tiers.R` — entry-vs-whale dollar shares, sweet-spot tier price,
  tier-structure-vs-magnitude models (`figures/tier_*`, `tables/tier_*`).

These hit archive.org, so they're run manually; outputs are committed.

## Notes & conventions
- Seeds (`set.seed(42)`) are set in every script with a stochastic step.
- Money: Web Robots magnitude models use **nominal** USD with year fixed effects;
  Kaggle uses **real** (CPI-adjusted) USD; ICPSR uses **nominal**. Cross-source
  dollar comparisons are labeled accordingly.
- The TTRPG class label is measured with error. After the 2026-06 classifier overhaul
  (plus a title-anchored pass that moves named RPG *accessories* — map packs, card decks,
  token/dice goods, merch — out of the core class), fresh hand-labeled held-out audits
  (`tables/ttrpg_heldout_audit_v2.csv`, `ttrpg_heldout_audit_v3.csv`) put core-RPG
  **precision ≈ 88%** (was ~77%) with **recall preserved** (0 false negatives on sampled
  non-RPG items and on spot-checks of demoted items; was ~71% recall). Residual precision
  errors are small RPG accessories whose product type appears only in the blurb (floor-plan
  packs, scenery) — diminishing returns to chase, and no effect on the dollar aggregates.
  Treat class contrasts as attenuated toward null.
- `code/replication/` holds the independent (Referee 2) Python re-estimation used to
  cross-validate the R results; it is verification, not part of the main pipeline.
