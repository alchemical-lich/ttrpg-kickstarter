#!/usr/bin/env python3
"""08_parse_tier_contents.py — Re-parse the cached Wayback campaign pages for reward
tier *contents* (what is actually in each tier), which stage 06 did not extract.

WHY THIS EXISTS
  Stage 06 pulled per-tier price and backer counts only. The "whale tier" question
  ("do expensive tiers stuffed with accessories drive bigger raises?") is about tier
  CONTENT, not price. Kickstarter's older page template renders an explicit
  itemization ("Includes:" -> <ul><li class="list-disc">) that names each item in the
  tier. That markup is already sitting in data/interim/wayback_cache/ — no new
  network calls are needed.

WHAT IT EMITS
  One row per (project, reward tier) with the tier title, free-text description, the
  itemized item list (pipe-joined), and the item count.

COVERAGE CAVEAT
  Only the pre-React page template carries the itemization markup. Newer snapshots
  render rewards client-side, so this recovers roughly 60% of the tier sample. The
  missing 40% are NOT missing at random (they skew recent), so treat era as a
  confound and control for launch year in anything downstream.

Input : data/interim/wayback_cache/snap_<id>_<ts>.html.gz
Output: data/interim/ttrpg_tier_contents.csv.gz
"""
import os, re, csv, gzip, glob, html, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(PROJ, "data", "interim", "wayback_cache")
OUT   = os.path.join(PROJ, "data", "interim", "ttrpg_tier_contents.csv.gz")

# Each reward is an <li ... data-reward-id="N"> block; split on the marker and parse
# within each segment. Segments are capped so a malformed page can't bleed forward.
SEG_CAP = 30000
RE_AMOUNT = re.compile(r'class="pledge__amount">(.*?)</h2>', re.S)
RE_TITLE  = re.compile(r'class="pledge__title">(.*?)</h3>', re.S)
RE_DESC   = re.compile(r'class="pledge__reward-description[^"]*">(.*?)'
                       r'(?:<span class="itemization|</div>)', re.S)
RE_ITEMUL = re.compile(r'itemization-includes.*?<ul[^>]*>(.*?)</ul>', re.S)
RE_ITEMLI = re.compile(r'<li class="list-disc">(.*?)</li>', re.S)
RE_BACKER = re.compile(r'class="pledge__backer-count">(.*?)</span>', re.S)
RE_MONEY  = re.compile(r'class="money">([^<]+)</span>')


def clean(s):
    """strip tags, unescape entities, collapse whitespace"""
    if s is None:
        return ""
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s))).strip()


def parse_page(text):
    """-> list of dicts, one per reward tier; deduped by reward_id"""
    out, seen = {}, set()
    for seg in text.split('data-reward-id="')[1:]:
        rid = seg.split('"', 1)[0]
        if not rid.isdigit():
            continue
        seg = seg[:SEG_CAP]
        m_ul = RE_ITEMUL.search(seg)
        items = [clean(i) for i in RE_ITEMLI.findall(m_ul.group(1))] if m_ul else []
        items = [i for i in items if i]
        row = {
            "reward_id": rid,
            "tier_title": clean(RE_TITLE.search(seg).group(1)) if RE_TITLE.search(seg) else "",
            "tier_desc": clean(RE_DESC.search(seg).group(1)) if RE_DESC.search(seg) else "",
            "amount_raw": clean(RE_MONEY.search(seg).group(1)) if RE_MONEY.search(seg) else "",
            "backers_raw": clean(RE_BACKER.search(seg).group(1)) if RE_BACKER.search(seg) else "",
            "n_items": len(items),
            "items": " | ".join(items),
            "has_itemization": int(bool(m_ul)),
        }
        # keep the richest rendering when a reward appears twice (sidebar + main list)
        prev = out.get(rid)
        if prev is None or (row["n_items"], len(row["tier_desc"])) > (prev["n_items"], len(prev["tier_desc"])):
            out[rid] = row
        seen.add(rid)
    return list(out.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="parse only N files (smoke test)")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(CACHE, "snap_*.html.gz")))
    if args.limit:
        files = files[: args.limit]
    print(f"cached snapshots: {len(files)}")

    n_pages_ok = n_pages_empty = n_unreadable = 0
    rows = []
    for f in files:
        base = os.path.basename(f)
        pid, ts = base.split("_")[1], base.split("_")[2].split(".")[0]
        try:
            text = gzip.open(f, "rt", errors="ignore").read()
        except Exception:
            n_unreadable += 1
            continue
        tiers = parse_page(text)
        itemized = [t for t in tiers if t["has_itemization"]]
        if itemized:
            n_pages_ok += 1
        else:
            n_pages_empty += 1
        for t in tiers:
            t.update(id=pid, snapshot_ts=ts)
            rows.append(t)

    cols = ["id", "snapshot_ts", "reward_id", "amount_raw", "backers_raw",
            "tier_title", "tier_desc", "has_itemization", "n_items", "items"]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with gzip.open(OUT, "wt", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    n_item_rows = sum(1 for r in rows if r["has_itemization"])
    print(f"  pages with itemized tiers : {n_pages_ok}  ({n_pages_ok/max(1,len(files)):.0%})")
    print(f"  pages without             : {n_pages_empty}")
    print(f"  unreadable                : {n_unreadable}")
    print(f"  tier rows written         : {len(rows):,}  (itemized: {n_item_rows:,})")
    print(f"  total items parsed        : {sum(r['n_items'] for r in rows):,}")
    print(f"-> {OUT}")


if __name__ == "__main__":
    main()
