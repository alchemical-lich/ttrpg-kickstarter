"""
03_build_kaggle_tabletop.py — Build a clean Tabletop panel from the Kaggle
ks-projects-201801 dataset (which, unlike Web Robots, INCLUDES failed projects).

Purpose: recover realistic success rates and a funded-vs-not sample for
2009-2018, which the Web Robots discover-crawl cannot support (survivorship bias).

TTRPG classification here is NAME-ONLY (Kaggle has no blurb), reusing the same
keyword lexicons as code/03_features/01_classify_ttrpg.py. This has LOWER recall
than the Web Robots classifier (many RPG cues live in the blurb), so treat the
TTRPG split as noisier; the tabletop-overall figures are unaffected.

Output: data/processed/kaggle_tabletop.csv.gz
"""
import importlib.util
import os

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
RAW = os.path.join(PROJ, "data", "raw", "kaggle_ks_2018", "ks-projects-201801.csv")
OUT = os.path.join(PROJ, "data", "processed", "kaggle_tabletop.csv.gz")
CLS = os.path.join(PROJ, "code", "03_features", "01_classify_ttrpg.py")

TERMINAL = {"successful", "failed", "canceled", "cancelled", "suspended"}


def load_classifier():
    spec = importlib.util.spec_from_file_location("ttrpg_cls", CLS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    cls = load_classifier()
    df = pd.read_csv(RAW, low_memory=False)
    df = df[df["category"] == "Tabletop Games"].copy()

    df["launched"] = pd.to_datetime(df["launched"], errors="coerce")
    df["deadline"] = pd.to_datetime(df["deadline"], errors="coerce")
    df["launch_year"] = df["launched"].dt.year
    # drop the well-known 1970 placeholder rows + undefined state
    df = df[(df["launch_year"] >= 2009) & (df["state"] != "undefined")]
    df["duration_days"] = (df["deadline"] - df["launched"]).dt.total_seconds() / 86400

    df["funded"] = df["state"].eq("successful")
    df["terminal"] = df["state"].isin(TERMINAL)
    # real (inflation-adjusted) USD already provided by Kaggle
    df["goal_usd_real"] = df["usd_goal_real"]
    df["pledged_usd_real"] = df["usd_pledged_real"]
    df["pct_of_goal"] = df["pledged"] / df["goal"].replace(0, np.nan)
    df["avg_pledge_real"] = df["pledged_usd_real"] / df["backers"].replace(0, np.nan)

    # name-only TTRPG classification (reuse lexicons; blurb empty)
    res = df["name"].apply(lambda n: cls.classify_row(n, ""))
    df["ttrpg_label"] = [x[0] for x in res]
    df["is_ttrpg"] = df["ttrpg_label"] == "ttrpg"
    df["is_ttrpg_accessory"] = df["ttrpg_label"] == "ttrpg_accessory"

    keep = ["ID", "name", "category", "main_category", "country", "currency",
            "launched", "deadline", "launch_year", "duration_days",
            "state", "funded", "terminal", "goal", "pledged", "backers",
            "goal_usd_real", "pledged_usd_real", "pct_of_goal", "avg_pledge_real",
            "ttrpg_label", "is_ttrpg", "is_ttrpg_accessory"]
    out = df[keep].rename(columns={"ID": "id"})
    out.to_csv(OUT, index=False, compression="gzip")

    print(f"Kaggle Tabletop rows: {len(out):,}  (launched {int(out.launch_year.min())}-{int(out.launch_year.max())})")
    print("\nstate:")
    print(out["state"].value_counts().to_string())
    print("\nttrpg_label:")
    print(out["ttrpg_label"].value_counts().to_string())
    term = out[out["terminal"]]
    print(f"\nTrue success rate (terminal): tabletop={term['funded'].mean():.1%}  "
          f"ttrpg={term[term.is_ttrpg]['funded'].mean():.1%}  "
          f"(n_terminal={len(term):,})")
    print(f"\nWrote {OUT}")


if __name__ == "__main__":
    main()
