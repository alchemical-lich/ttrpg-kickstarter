#!/usr/bin/env bash
# run_all.sh — reproduce the full pipeline from raw sources to tables/ and figures/.
# Run from the project root:  bash code/run_all.sh
#
# Languages: Python for ingestion + TTRPG classification (data engineering);
# R for all analysis and figures. See code/README.md for details and the data
# sources that must be present under data/raw/ before running.
set -euo pipefail
cd "$(dirname "$0")/.."          # project root

PY=python3
R=Rscript

echo "== [1/?] INGEST =="
# 1a. Web Robots panel: downloads ~134 monthly JSON crawls to /tmp, filters to
#     Games, writes data/interim/games_by_crawl/. SLOW (network, ~40 min) and
#     idempotent (skips crawls already done). Uncomment to (re)build from scratch:
# $PY code/01_ingest/02_build_games_panel.py
if [ ! -d data/interim/games_by_crawl ] || [ -z "$(ls -A data/interim/games_by_crawl 2>/dev/null)" ]; then
  echo "   building Web Robots panel (first run; slow)..."
  $PY code/01_ingest/02_build_games_panel.py
else
  echo "   data/interim/games_by_crawl present -> skipping the slow crawl download"
fi

echo "== [2] CLEAN: master panel =="
$PY code/02_clean/01_build_master_panel.py

echo "== [3] FEATURES: TTRPG classifier (Web Robots) =="
$PY code/03_features/01_classify_ttrpg.py

echo "== [4] INGEST: secondary failure-inclusive sources =="
$PY code/01_ingest/03_build_kaggle_tabletop.py          # needs data/raw/kaggle_ks_2018/
$R  code/01_ingest/04_export_icpsr_tabletop.R           # needs data/raw/ICPSR_38050/
$PY code/03_features/02_classify_icpsr_tabletop.py      # PID label transfer

echo "== [4b] FEATURES: sub-categorize RPG books (system / product type / genre) =="
$PY code/03_features/03_subcategorize_books.py          # needs tabletop_classified + kaggle_tabletop

echo "== [5] CLEAN: coverage diagnostics =="
$R  code/02_clean/02_coverage_map.R

echo "== [6] ANALYSIS =="
$R  code/04_analysis/01_descriptive_landscape.R
$R  code/04_analysis/02_success_rates_kaggle.R
$R  code/04_analysis/03_success_rates_icpsr.R
$R  code/04_analysis/04_build_model_features.R
$R  code/04_analysis/05_drivers_model.R
$R  code/04_analysis/06_success_model.R
$R  code/04_analysis/07_success_model_kaggle.R
$R  code/04_analysis/08_text_drivers.R
$R  code/04_analysis/09_magnitude_by_class.R
$R  code/04_analysis/10_success_by_class_kaggle.R
$R  code/04_analysis/11_did_zinequest.R
$R  code/04_analysis/12_did_5e.R
$R  code/04_analysis/13_zinequest_robust.R
$R  code/04_analysis/14_book_composition.R              # composition shares over time
$R  code/04_analysis/15_funding_threshold_rd.R          # all-or-nothing RD + McCrary test
$R  code/04_analysis/16_composition_5e_split.R          # product mix: 5e vs other systems
$R  code/04_analysis/17_subcat_drivers.R                # sub-tags in magnitude + success models

echo "== DONE. Outputs in tables/ and figures/. =="
