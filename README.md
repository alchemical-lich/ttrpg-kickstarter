# What the Data Says About Tabletop RPG Crowdfunding

A reproducible analysis of the tabletop **role-playing game (TTRPG)** corner of
Kickstarter: what gets funded, what raises a lot, and what (if anything) caused the
boom. It triangulates three independent datasets and takes sample selection seriously.

📖 **Read the write-up:** **[alchemical-lich.github.io/ttrpg-kickstarter](https://alchemical-lich.github.io/ttrpg-kickstarter/)**.
This repository is the write-up *and* the reproducible code, data pipeline, and
results behind it. The write-up source lives in [`docs/`](docs/) (a static site
served via GitHub Pages).

---

## The gist

- **The obvious dataset overstates success.** The widely-used Web Robots crawl is
  built from Kickstarter's "discover" pages, which surface survivors: only ~2% of
  finished tabletop projects in it are marked "failed," implying a ~98% success rate.
  Bringing in failure-aware data puts the real rate around two-thirds (2009–18),
  rising to ~86% by 2023.
- **Creator track record predicts funding better than project attributes.** A model
  built only from the creator's history reaches AUC **0.83**, against **0.72** for one
  built from project attributes. Past successes help; past failures hurt. The two
  models run on different datasets, so this is a decomposition across sources rather
  than a head-to-head.
- **Among funded projects, staff picks and repeat creators track the biggest raises.**
  A "Projects We Love" staff pick travels with ~**2.6×** the dollars; a repeat creator
  ~1.4×. The money is very concentrated: the top 1% of funded RPG projects take about
  34% of all pledges, ~38% for accessories.
- **Product type shapes how much you raise but not whether you raise it.** Drivers of
  magnitude differ for rulebooks and accessories (a "5E" label helps books but not
  commodity minis); drivers of funding don't differ.
- **The hobby tilted toward D&D, and naming a system pays.** Books naming D&D 5e went
  from ~7% of funded RPG books (2014–15) to ~40% (2023–26). 5e is mostly content *for*
  the engine (adventures and supplements), while other systems are where new rulebooks
  and zines live. Naming a recognized system (5e, OSR, a known indie line) travels with
  a **~25–45% larger raise** and better funding odds, though the tags add only modestly
  to predictive power.
- **On causal claims.** **ZineQuest** (Kickstarter's February RPG-zine program) roughly
  doubled funded RPG February launches, and it is the one design here close to a natural
  experiment. **D&D 5e produced no identifiable break** — the RPG advantage predates it.
  And the **all-or-nothing funding-threshold RD fails its manipulation test**: projects
  bunch hard just above 100% of goal (McCrary p ≈ 4e-86), so a sharp cutoff isn't
  automatically a usable experiment.

Correlations are labeled as such throughout, and ZineQuest is flagged as the only
result close to a causal claim.

## Repository layout

```
code/                Python ingest + classifier; R analysis & figures
  01_ingest/ 02_clean/ 03_features/ 04_analysis/   (run_all.sh, README.md, r_dependencies.txt)
figures/  tables/    committed results of the pipeline
docs/                the write-up as a static GitHub Pages site (index.md → index.html)
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

## Limits

The TTRPG classifier is ~88% precise on a fresh held-out audit with recall preserved,
and agrees with hand-checking about 97% of the time on the high-dollar tail after
tightening. Label error mostly attenuates category contrasts toward zero, so the
reported differences are conservative. Reward-tier ("whale") data isn't in any bulk
dataset; I recovered a partial, doubly-selected sample of 325 top-decile RPG books and
~3,300 tiers from archived campaign pages on the Internet Archive's Wayback Machine.
A crawl coverage gap still makes the 2023 OGL crisis unanalyzable. All of this is
discussed in the write-up.

## License

- **Code** (`code/`, `run_all.sh`, dependency files): **MIT** — see [`LICENSE`](LICENSE).
- **Figures & result tables** (`figures/`, `tables/`) and the write-up (`docs/`, hosted at
  [alchemical-lich.github.io/ttrpg-kickstarter](https://alchemical-lich.github.io/ttrpg-kickstarter/)):
  **CC BY 4.0** — see [`LICENSE-writeup.md`](LICENSE-writeup.md).
- Underlying Kickstarter data belong to third parties (Web Robots, Kaggle, ICPSR) and
  are **not** redistributed here.

## Citation

> alchemical-lich (2026). *What the Data Says About Tabletop RPG Crowdfunding.*

Inspired by the ["Kickstarter Whales" guest post on Patchwork Paladin](https://patchworkpaladin.com/2026/05/18/kickstarter-whales-guest-post/).
