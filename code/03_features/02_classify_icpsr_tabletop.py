"""
02_classify_icpsr_tabletop.py — Attach a best-effort TTRPG label to the ICPSR
Tabletop panel by LABEL TRANSFER via project id (PID).

ICPSR public-use names are "MASKED BY ICPSR", so we cannot keyword-classify it
directly. But PID is the Kickstarter project id, so we transfer labels we already
have, in priority order:
  1. Web Robots blurb-based label (best quality)  — covers successful/live only
  2. Kaggle name-based label (2009-2018)          — covers failures too, lower recall
  3. else "unlabeled"

CONSEQUENCE: failed TTRPGs in 2019-2023 are unlabelable (no name source with
failures past 2018). So ICPSR is authoritative at the TABLETOP-GAMES level
(2009-2023, incl. failures); TTRPG-specific *success rates* remain a 2009-2018
question (Kaggle). label_source records provenance.

In:  data/interim/icpsr_tabletop_clean.csv.gz
Out: data/processed/icpsr_tabletop.csv.gz
"""
import os
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
IN = os.path.join(PROJ, "data", "interim", "icpsr_tabletop_clean.csv.gz")
OUT = os.path.join(PROJ, "data", "processed", "icpsr_tabletop.csv.gz")
WR = os.path.join(PROJ, "data", "processed", "tabletop_classified.csv.gz")
KG = os.path.join(PROJ, "data", "processed", "kaggle_tabletop.csv.gz")


def main():
    df = pd.read_csv(IN, low_memory=False)
    df["pid"] = df["pid"].astype("Int64")
    wr = (pd.read_csv(WR, usecols=["id", "ttrpg_label"], low_memory=False)
          .rename(columns={"id": "pid", "ttrpg_label": "lab_wr"}))
    kg = (pd.read_csv(KG, usecols=["id", "ttrpg_label"], low_memory=False)
          .rename(columns={"id": "pid", "ttrpg_label": "lab_kg"}))
    wr["pid"] = wr["pid"].astype("Int64"); kg["pid"] = kg["pid"].astype("Int64")

    df = df.merge(wr, on="pid", how="left").merge(kg, on="pid", how="left")
    df["ttrpg_label"] = df["lab_wr"].fillna(df["lab_kg"]).fillna("unlabeled")
    df["label_source"] = (df["lab_wr"].notna().map({True: "wr_blurb"})
                          .fillna(df["lab_kg"].notna().map({True: "kaggle_name"}))
                          .fillna("unlabeled"))
    df["is_ttrpg"] = df["ttrpg_label"] == "ttrpg"
    df = df.drop(columns=["lab_wr", "lab_kg"])
    df.to_csv(OUT, index=False, compression="gzip")

    print(f"rows: {len(df):,}")
    print("\nlabel_source:"); print(df["label_source"].value_counts().to_string())
    print("\nttrpg_label:"); print(df["ttrpg_label"].value_counts().to_string())
    term = df[df["state"].isin(["successful", "failed"])]
    print(f"\nTabletop success (succ vs failed): {term['funded'].mean():.1%} (n={len(term):,})")
    # TTRPG-rate only valid where failures are labelable (2009-2018)
    lab = term[term["label_source"] != "unlabeled"]
    e = lab[(lab["launch_year"] <= 2018)]
    ett = e[e["is_ttrpg"]]
    print(f"TTRPG success 2009-2018 (labeled): {ett['funded'].mean():.1%} (n={len(ett):,})")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
