#!/usr/bin/env python3
"""07_backfill_tier_usd.py — Backfill missing USD conversion rates in the
reward-tier table.

WHY
  06_scrape_wayback_rewards.py converts each tier's native price to USD with the
  `static_usd_rate` embedded in the archived campaign page:
      minimum_usd = minimum_native * usd_rate
  A few older/partial snapshots don't expose that field, so usd_rate came back
  empty and the scraper silently fell back to the *native* number — i.e. a £20
  tier was recorded as "$20". This understates the USD price of those tiers.

FIX
  The Web Robots panel (data/processed/games_master.csv.gz) stores the same
  campaign-time `static_usd_rate` keyed by project `id`. We join it in and, for
  any tier row with a missing usd_rate, fill the rate (currency-matched; USD->1.0)
  and recompute minimum_usd. This is exactly what the patched scraper now does at
  scrape time; doing it here repairs the already-committed table without a
  non-deterministic Wayback re-scrape.

  Idempotent: rows that already have a usd_rate are untouched, so re-running is a
  no-op. Native prices and backer counts are never modified.

IN/OUT (edits in place; derived file, fully regenerable):
  data/processed/ttrpg_reward_tiers.csv.gz
  reads  data/processed/games_master.csv.gz   (id, currency, static_usd_rate)
"""
import os
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
TIERS = os.path.join(PROJ, "data", "processed", "ttrpg_reward_tiers.csv.gz")
PANEL = os.path.join(PROJ, "data", "processed", "games_master.csv.gz")


def main():
    tiers = pd.read_csv(TIERS)
    panel = pd.read_csv(PANEL, low_memory=False,
                        usecols=["id", "currency", "static_usd_rate"])
    rate_map = (panel.dropna(subset=["static_usd_rate"])
                .set_index("id")[["currency", "static_usd_rate"]])

    need = tiers["usd_rate"].isna()
    print(f"tier rows: {len(tiers)} | missing usd_rate: {need.sum()} "
          f"(non-USD: {(need & tiers['currency'].ne('USD')).sum()})")

    filled = recomputed = unresolved = 0
    for i in tiers.index[need]:
        cur = tiers.at[i, "currency"]
        if cur == "USD":                       # native already == USD
            tiers.at[i, "usd_rate"] = 1.0
            filled += 1
            continue
        pid = tiers.at[i, "id"]
        if pid in rate_map.index:
            prow = rate_map.loc[pid]
            # safety: only trust the panel rate when the currency agrees
            if pd.isna(cur) or prow["currency"] == cur:
                rate = float(prow["static_usd_rate"])
                tiers.at[i, "usd_rate"] = rate
                mn = tiers.at[i, "minimum_native"]
                if pd.notna(mn):
                    tiers.at[i, "minimum_usd"] = round(float(mn) * rate, 2)
                    recomputed += 1
                filled += 1
                continue
        unresolved += 1

    print(f"filled usd_rate: {filled} | non-USD prices recomputed: {recomputed} "
          f"| unresolved (left as-is): {unresolved}")

    tiers.to_csv(TIERS, index=False, compression="gzip")
    print(f"wrote {TIERS}")


if __name__ == "__main__":
    main()
