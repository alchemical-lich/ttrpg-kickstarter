"""
01_scan_dump.py — Scan a Web Robots Kickstarter monthly dump and characterize it.

Reads all Kickstarter*.csv shards from a single monthly crawl, parses the nested
`category` JSON, deduplicates projects by `id` (a project can be listed under
multiple sub-categories within one crawl, so rows duplicate), and reports:
  - total rows vs. unique projects
  - parent-category distribution
  - Games sub-category distribution
  - a first count of "Tabletop Games" projects (the bucket that contains TTRPGs)

This is a read-only characterization step. No filtered dataset is written yet.
"""
import glob
import json
import os

import pandas as pd

RAW_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "data", "raw", "ks_2026-05-12")
USECOLS = [
    "id", "name", "state", "category", "goal", "pledged", "usd_pledged",
    "converted_pledged_amount", "backers_count", "country", "launched_at",
    "deadline", "created_at", "staff_pick", "spotlight",
]


def load_all(raw_dir):
    files = sorted(glob.glob(os.path.join(raw_dir, "Kickstarter*.csv")))
    print(f"Found {len(files)} CSV shards")
    frames = []
    for f in files:
        frames.append(pd.read_csv(f, usecols=USECOLS, low_memory=False))
    df = pd.concat(frames, ignore_index=True)
    return df


def parse_categories(df):
    cats = df["category"].apply(lambda s: json.loads(s) if isinstance(s, str) else {})
    df["cat_name"] = cats.apply(lambda c: c.get("name"))
    df["cat_slug"] = cats.apply(lambda c: c.get("slug"))
    df["cat_parent"] = cats.apply(lambda c: c.get("parent_name") or c.get("name"))
    return df


def main():
    df = load_all(RAW_DIR)
    print(f"\nTotal rows (with cross-category duplication): {len(df):,}")

    df = parse_categories(df)

    # Deduplicate by project id (keep first occurrence).
    dedup = df.drop_duplicates(subset="id")
    print(f"Unique projects (dedup by id): {len(dedup):,}")

    print("\n=== Parent-category distribution (unique projects) ===")
    print(dedup["cat_parent"].value_counts().head(20).to_string())

    games = dedup[dedup["cat_parent"] == "Games"]
    print(f"\n=== Games sub-category distribution ({len(games):,} Games projects) ===")
    print(games["cat_name"].value_counts().to_string())

    tabletop = dedup[dedup["cat_slug"].fillna("").str.contains("tabletop", case=False)]
    print(f"\n=== Tabletop Games projects: {len(tabletop):,} ===")
    print("State breakdown:")
    print(tabletop["state"].value_counts().to_string())


if __name__ == "__main__":
    main()
