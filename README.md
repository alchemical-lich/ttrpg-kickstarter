# What the Data Says About RPGs on Kickstarter

A reproducible analysis of the tabletop **role-playing game (TTRPG)** corner of
Kickstarter — what gets funded, what raises a lot, and what (if anything) actually
*caused* the boom — built by triangulating three independent datasets and taking
sample-selection seriously.

📖 **Read the write-up:** **[alchemical-lich.github.io/kickstarter-rpgs](https://alchemical-lich.github.io/kickstarter-rpgs/)**.
This repository is the reproducible code, data pipeline, and results behind it.

---

## The gist

- **The obvious dataset lies about success.** The widely-used Web Robots crawl is
  built from Kickstarter's "discover" pages, which surface survivors — only ~2% of
  finished tabletop projects in it are "failed," implying a fake ~98% success rate.
  Bringing in failure-aware data puts the *real* rate around **two-thirds (2009–18),
  rising to ~86% by 2023.**
- **Getting funded is about *who*, not *what*.** A model built only from the
  creator's track record predicts funding much better (AUC **0.83**) than one built
  from project attributes (AUC **0.72**). Past successes help; past failures hurt.
- **Raising *a lot* (once funded) is about quality and social proof.** A "Projects
  We Love" staff pick travels with ~**2.6×** the dollars; a repeat creator ~1.4×.
  Money is brutally concentrated (top 1% of projects ≈ 36–46% of all pledges).
- **Product type shapes *how much*, not *whether*.** Drivers of magnitude differ for
  rulebooks vs. accessories (a "5E" label helps books, not commodity minis); drivers
  of funding do not.
- **Causal honesty:** **ZineQuest** (Kickstarter's Feb RPG-zine program) demonstrably
  ~doubled funded RPG February launches — a clean natural experiment. **D&D 5e did
  *not*** produce an identifiable break — the RPG advantage predates it.

All claims are evidence-based; correlations are labeled as such; the one
quasi-experimental result (ZineQuest) is flagged as the only causal claim.

## Repository layout

```
code/                Python ingest + classifier; R analysis & figures
  01_ingest/ 02_clean/ 03_features/ 04_analysis/   (run_all.sh, README.md, r_dependencies.txt)
figures/  tables/    committed results of the pipeline
data/                git-ignored; data/README.md explains how to obtain the raw sources
```

## Reproduce it

1. Install dependencies: `pip install -r requirements.txt` and the R packages in
   `code/r_dependencies.txt`. (Python 3.9, R 4.2.)
2. Obtain the raw data per [`data/README.md`](data/README.md) (Web Robots downloads
   automatically; Kaggle and ICPSR you place under `data/raw/`).
3. Run the whole pipeline:
   ```bash
   bash code/run_all.sh
   ```
   It goes from raw sources to everything in `figures/` and `tables/`, in order, and
   skips the slow crawl download if the data are already present.

**Languages:** Python for data engineering (ingest, classifier); **R + ggplot2** for
all analysis and figures. See `code/README.md` for the stage-by-stage map.

## Honest limits

The TTRPG classifier is ~77% precise / 71% recall on a fresh held-out audit (label
error attenuates category contrasts toward zero — i.e. the reported differences are
conservative). Reward-tier ("whale") data isn't available in any source, and a
coverage gap makes the 2023 OGL crisis unanalyzable. These points are discussed in
the write-up.

## License

- **Code** (`code/`, `run_all.sh`, dependency files): **MIT** — see [`LICENSE`](LICENSE).
- **Figures & result tables** (`figures/`, `tables/`) and the write-up (hosted at
  [alchemical-lich.github.io/kickstarter-rpgs](https://alchemical-lich.github.io/kickstarter-rpgs/)):
  **CC BY 4.0** — see [`LICENSE-writeup.md`](LICENSE-writeup.md).
- Underlying Kickstarter data belong to third parties (Web Robots, Kaggle, ICPSR) and
  are **not** redistributed here.

## Citation

> alchemical-lich (2026). *What the Data Says About RPGs on Kickstarter.*

Inspired by the ["Kickstarter Whales" guest post on Patchwork Paladin](https://patchworkpaladin.com/2026/05/18/kickstarter-whales-guest-post/).
