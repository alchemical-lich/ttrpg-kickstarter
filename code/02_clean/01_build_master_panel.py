"""
01_build_master_panel.py — Combine per-crawl Games files into analysis datasets.

Inputs:  data/interim/games_by_crawl/games_<date>.csv.gz  (one per crawl)
Outputs (data/processed/):
  - games_observations.csv.gz : every (crawl x project) observation, 2015+.
      Keeps the coarse cross-crawl funding trajectory (a project seen live in
      successive crawls). One row per (id, crawl_date).
  - games_master.csv.gz       : one row per project = its FINAL observation.
      For each id we take the latest TERMINAL observation (state in
      successful/failed/canceled/suspended) if any, else the latest observation.
      This is the cross-sectional analysis table.

Measurement notes:
  - Analysis window starts 2015 (2014 dropped: Games had no subcategories then).
  - pledged_usd: prefer usd_pledged; else converted_pledged_amount; else
    pledged * static_usd_rate. goal_usd: goal * static_usd_rate (fallback fx_rate).
  - is_tabletop: category slug contains "tabletop". (TTRPG sub-classification is a
    later feature step — keyword rules + audit sample.)
"""
import glob
import os

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
IN_DIR = os.path.join(PROJ, "data", "interim", "games_by_crawl")
OUT_DIR = os.path.join(PROJ, "data", "processed")
TERMINAL = {"successful", "failed", "canceled", "cancelled", "suspended"}


def load_observations():
    files = sorted(glob.glob(os.path.join(IN_DIR, "games_*.csv.gz")))
    frames = []
    for f in files:
        cd = os.path.basename(f)[len("games_"):-len(".csv.gz")]
        if cd < "2015":  # drop 2014
            continue
        df = pd.read_csv(f, low_memory=False)
        df["crawl_date"] = cd
        frames.append(df)
    obs = pd.concat(frames, ignore_index=True)
    return obs, files


def add_usd(df):
    pledged_usd = df["usd_pledged"].copy()
    if "converted_pledged_amount" in df:
        pledged_usd = pledged_usd.fillna(df["converted_pledged_amount"])
    rate = df["static_usd_rate"]
    if "fx_rate" in df:
        rate = rate.fillna(df["fx_rate"])
    pledged_usd = pledged_usd.fillna(df["pledged"] * rate)
    df["pledged_usd"] = pledged_usd
    df["goal_usd"] = df["goal"] * rate
    df["pct_of_goal"] = df["pledged"] / df["goal"].replace(0, np.nan)
    return df


def pick_final(obs):
    obs = obs.copy()
    obs["_terminal"] = obs["state"].isin(TERMINAL).astype(int)
    # latest terminal obs if any, else latest obs: sort then take last per id
    obs = obs.sort_values(["id", "_terminal", "crawl_date"])
    final = obs.drop_duplicates("id", keep="last").drop(columns="_terminal")
    return final


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    obs, files = load_observations()
    obs = obs.drop_duplicates(["id", "crawl_date"])
    obs["is_tabletop"] = obs["cat_slug"].fillna("").str.contains("tabletop", case=False)
    obs = add_usd(obs)

    final = pick_final(obs)

    obs.to_csv(os.path.join(OUT_DIR, "games_observations.csv.gz"), index=False, compression="gzip")
    final.to_csv(os.path.join(OUT_DIR, "games_master.csv.gz"), index=False, compression="gzip")

    tt = final[final["is_tabletop"]]
    print(f"crawl files used (2015+): {sum(1 for f in files if os.path.basename(f)[6:-7] >= '2015')}")
    print(f"observations (id x crawl): {len(obs):,}")
    print(f"unique Games projects:     {final['id'].nunique():,}")
    print(f"unique Tabletop projects:  {tt['id'].nunique():,}")
    print("\nTabletop final-state breakdown:")
    print(tt["state"].value_counts().to_string())
    print("\nTabletop by launch year:")
    ly = pd.to_datetime(tt["launched_at"], unit="s", errors="coerce").dt.year
    print(ly.value_counts().sort_index().to_string())


if __name__ == "__main__":
    main()
