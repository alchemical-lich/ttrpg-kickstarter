#!/usr/bin/env python3
"""05_recover_project_urls.py — Recover Kickstarter project URLs (+ deadlines) for
the TOP-DECILE funded core-TTRPG *book* projects, so the Wayback reward-tier stage
(06) can locate archived campaign pages.

WHY THIS EXISTS
  The main ingest (02_build_games_panel.py) deliberately dropped the bulky `urls`
  blob, so `data/processed/*` has no project URL. Wayback lookups need it. We
  re-open the raw Web Robots crawls and pull `urls.web.project` + `slug` for the
  target ids only.

TARGET = top decile (>= 90th percentile of pledged_usd) among FUNDED projects with
  ttrpg_label == "ttrpg" (i.e. RPG *books/adventures/zines*, NOT accessories).

STRATEGY (bandwidth-aware)
  Each target id is guaranteed to appear in the crawl that produced its master row
  (`crawl_date`). We greedily download those crawls — biggest-yield first — parse,
  extract URLs for every target present (not just that crawl's master ids, since
  big books recur across crawls), delete the download, and stop once all are found.
  Resumable: found URLs are flushed to a partial CSV each crawl.

USAGE
  python3 05_recover_project_urls.py --plan     # print scale, download nothing
  python3 05_recover_project_urls.py            # do the recovery

Output: data/interim/ttrpg_book_targets.csv
"""
import os, sys, gzip, json, csv, subprocess, argparse
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
CLASSIFIED = os.path.join(PROJ, "data", "processed", "tabletop_classified.csv.gz")
URL_LIST   = os.path.join(PROJ, "data", "raw", "_crawl_urls.tsv")
OUT        = os.path.join(PROJ, "data", "interim", "ttrpg_book_targets.csv")
TMP        = "/tmp"
DECILE     = 0.90   # top 10% by pledged among funded core-ttrpg books

_SKIP = "\r\n\t ,[]"
def iter_projects(path):
    dec = json.JSONDecoder()
    with gzip.open(path, "rb") as f:
        buf = b""
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            buf += chunk
            s = buf.decode("utf-8", "ignore"); i = 0; n = len(s); last = 0
            while True:
                while i < n and s[i] in _SKIP:
                    i += 1
                if i >= n:
                    break
                try:
                    obj, end = dec.raw_decode(s, i)
                except json.JSONDecodeError:
                    break
                if isinstance(obj, dict):
                    if isinstance(obj.get("projects"), list):
                        for p in obj["projects"]:
                            if isinstance(p, dict):
                                yield p
                    else:
                        rec = obj.get("data", obj)
                        if isinstance(rec, dict):
                            yield rec
                i = end; last = i
            buf = s[last:].encode("utf-8")


def select_targets():
    df = pd.read_csv(CLASSIFIED, low_memory=False)
    df = df[(df["ttrpg_label"] == "ttrpg") & (df["state"] == "successful")].copy()
    df = df[df["pledged_usd"].notna() & (df["pledged_usd"] > 0)]
    cut = df["pledged_usd"].quantile(DECILE)
    tg = df[df["pledged_usd"] >= cut].copy()
    keep = ["id", "name", "pledged_usd", "backers_count", "goal_usd",
            "launched_at", "deadline", "crawl_date"]
    return tg[keep].sort_values("pledged_usd", ascending=False).reset_index(drop=True), cut


def load_crawl_urls():
    m = {}
    with open(URL_LIST) as f:
        for line in f:
            cd, url = line.rstrip("\n").split("\t")
            m[cd] = url
    return m


def download(url, dest):
    subprocess.run(["curl", "-fsSL", "--retry", "3", "--retry-delay", "5",
                    "--max-time", "1800", "-o", dest, url], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", action="store_true", help="print scale and exit")
    args = ap.parse_args()

    targets, cut = select_targets()
    want = {int(r.id): {"id": int(r.id), "name": r.name,
                        "pledged_usd": r.pledged_usd, "backers_count": r.backers_count,
                        "goal_usd": r.goal_usd, "launched_at": r.launched_at,
                        "deadline": r.deadline}
            for r in targets.itertuples()}
    crawl_urls = load_crawl_urls()
    # candidate crawls = distinct master crawl_dates, highest target-yield first
    by_crawl = targets.groupby("crawl_date").size().sort_values(ascending=False)
    cand = [cd for cd in by_crawl.index if cd in crawl_urls]
    missing_url = [cd for cd in by_crawl.index if cd not in crawl_urls]

    print(f"TARGET: top {round((1-DECILE)*100)}% of funded core-TTRPG books")
    print(f"  pledged cutoff (90th pct): ${cut:,.0f}")
    print(f"  n targets: {len(want)}  | pledged range ${targets.pledged_usd.min():,.0f}–${targets.pledged_usd.max():,.0f}")
    print(f"  distinct master crawls to cover them: {len(cand)}"
          + (f"  (+{len(missing_url)} crawl-dates not in URL list)" if missing_url else ""))
    if args.plan:
        print("\n--plan: stopping before any download. Re-run without --plan to recover URLs.")
        return

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    found = {}
    # resume from any existing partial output
    if os.path.exists(OUT):
        for r in csv.DictReader(open(OUT)):
            if r.get("project_url") and r["project_url"] != "MISSING":
                found[int(r["id"])] = r

    def flush():
        with open(OUT, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["id", "name", "pledged_usd", "backers_count",
                "goal_usd", "launched_at", "deadline", "slug", "project_url",
                "rewards_url", "found_in_crawl"])
            w.writeheader()
            for pid, info in want.items():
                row = found.get(pid)
                if row:
                    w.writerow({k: row.get(k, "") for k in w.fieldnames})
                else:
                    w.writerow({**info, "slug": "", "project_url": "MISSING",
                                "rewards_url": "", "found_in_crawl": ""})

    for ci, cd in enumerate(cand, 1):
        if len(found) >= len(want):
            break
        dl = os.path.join(TMP, f"crawl_{cd}.json.gz")
        try:
            if not os.path.exists(dl):
                download(crawl_urls[cd], dl)
            size_mb = os.path.getsize(dl) // (1 << 20)
            hits = 0
            for rec in iter_projects(dl):
                pid = rec.get("id")
                if pid in want and pid not in found:
                    web = (rec.get("urls") or {}).get("web") or {}
                    found[pid] = {**want[pid], "slug": rec.get("slug"),
                                  "project_url": web.get("project") or "MISSING",
                                  "rewards_url": web.get("rewards") or "",
                                  "found_in_crawl": cd}
                    hits += 1
            print(f"[{ci}/{len(cand)}] {cd} ({size_mb}MB): +{hits}  total {len(found)}/{len(want)}",
                  flush=True)
            flush()
        except Exception as e:
            # a transient download/parse failure on one crawl must not abort the run
            print(f"[{ci}/{len(cand)}] {cd}: SKIPPED ({type(e).__name__})", flush=True)
        finally:
            if os.path.exists(dl):
                os.remove(dl)

    flush()
    miss = [want[p]["name"] for p in want if p not in found]
    print(f"\nDONE. recovered {len(found)}/{len(want)} URLs -> {OUT}")
    if miss:
        print(f"  {len(miss)} not found (likely only in crawl-dates absent from URL list).")


if __name__ == "__main__":
    main()
