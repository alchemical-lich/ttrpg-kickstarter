"""
02_build_games_panel.py — Download every Web Robots monthly JSON dump, filter to
the Games category, and build a per-crawl panel of Games projects.

We use the JSON dumps (.json.gz / .json.zip) rather than CSV because JSON covers
the FULL history (2014-04 .. present, 134 monthly crawls) whereas CSV only exists
for ~2019 onward. Web Robots JSON is newline-delimited: each line is a wrapper
object {id, robot_id, run_id, created_at, table_id, data}; the project lives under
`data`.

Why per-crawl (not just the latest snapshot): a project seen live across several
monthly crawls gives us its pledge trajectory for free. We keep every crawl
observation here; downstream code dedups to the final state when needed.

Disk discipline (avoid bloating the working tree with multi-GB downloads):
  - All transient downloads go to the system TEMP dir (/tmp), outside the project.
  - Each dump is downloaded -> parsed -> DELETED before the next.
  - Only the small Games-only gzipped CSV (one per crawl) lands in the project.

Resumable: a crawl whose output file already exists is skipped.

Usage:
  python3 02_build_games_panel.py            # all crawls in _crawl_urls.tsv
  python3 02_build_games_panel.py --limit 3  # smoke-test first 3
"""
import argparse
import gzip
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import zipfile

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
URL_LIST = os.path.join(PROJ, "data", "raw", "_crawl_urls.tsv")
OUT_DIR = os.path.join(PROJ, "data", "interim", "games_by_crawl")
MANIFEST = os.path.join(PROJ, "data", "interim", "ingest_manifest.csv")
TMP_ROOT = os.path.join(tempfile.gettempdir(), "ks_ingest")

# Scalar project fields worth keeping (drop bulky photo/profile/urls blobs).
SCALARS = [
    "id", "name", "blurb", "state", "goal", "pledged", "usd_pledged",
    "converted_pledged_amount", "backers_count", "percent_funded",
    "country", "currency", "fx_rate", "static_usd_rate", "usd_exchange_rate",
    "staff_pick", "spotlight", "created_at", "launched_at", "deadline",
    "state_changed_at",
]


def out_path(crawl_date):
    return os.path.join(OUT_DIR, f"games_{crawl_date}.csv.gz")


def download(url, dest):
    cmd = ["curl", "-fsSL", "--retry", "3", "--retry-delay", "5",
           "--max-time", "1800", "-o", dest, url]
    subprocess.run(cmd, check=True)


def open_text(path):
    """Return a text stream for a .json.gz or .json.zip dump."""
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    if path.endswith(".zip"):
        z = zipfile.ZipFile(path)
        member = next(m for m in z.namelist() if m.lower().endswith(".json"))
        return io.TextIOWrapper(z.open(member), encoding="utf-8", errors="replace")
    raise ValueError(f"unknown format: {path}")


# Whitespace plus structural chars to skip between concatenated JSON values.
# Tolerating , [ ] lets one parser handle JSONL, concatenated pretty-printed
# objects (2014 dumps), and a single top-level array — all the formats Web
# Robots has used over the years.
_SKIP = set(" \t\r\n,[]")


def iter_projects(path, chunk_size=1 << 20):
    """Stream project dicts from any of Web Robots' JSON layouts, memory-friendly."""
    dec = json.JSONDecoder()
    buf = ""
    with open_text(path) as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            buf += chunk
            i = 0
            n = len(buf)
            while True:
                while i < n and buf[i] in _SKIP:
                    i += 1
                if i >= n:
                    break
                try:
                    obj, end = dec.raw_decode(buf, i)
                except json.JSONDecodeError:
                    break  # incomplete value at tail; wait for more data
                # Web Robots layouts over the years:
                #   recent: wrapper dict with project under "data"
                #   2014:   page dict with a "projects" list of project dicts
                #   bare:   the project dict itself
                if isinstance(obj, dict):
                    if isinstance(obj.get("projects"), list):
                        for p in obj["projects"]:
                            if isinstance(p, dict):
                                yield p
                    else:
                        rec = obj.get("data", obj)
                        if isinstance(rec, dict):
                            yield rec
                i = end
            buf = buf[i:]  # keep unparsed remainder


def parent_of(cat):
    if not isinstance(cat, dict):
        return None
    p = cat.get("parent_name")
    if p:
        return p
    slug = cat.get("slug") or ""
    if "/" in slug:
        return slug.split("/")[0].title()
    return cat.get("name")


def process_dump(path, crawl_date):
    rows = []
    for rec in iter_projects(path):
        cat = rec.get("category") or {}
        if parent_of(cat) != "Games":
            continue
        row = {k: rec.get(k) for k in SCALARS}
        row["cat_id"] = cat.get("id")
        row["cat_name"] = cat.get("name")
        row["cat_slug"] = cat.get("slug")
        row["cat_parent"] = "Games"
        creator = rec.get("creator") or {}
        row["creator_id"] = creator.get("id") if isinstance(creator, dict) else None
        row["has_video"] = rec.get("video") is not None
        rows.append(row)
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows).drop_duplicates(subset="id")  # within-crawl multi-cat dedup
    df["crawl_date"] = crawl_date
    return df


def append_manifest(row):
    pd.DataFrame([row]).to_csv(
        MANIFEST, mode="a", header=not os.path.exists(MANIFEST), index=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(TMP_ROOT, exist_ok=True)

    pairs = []
    with open(URL_LIST) as f:
        for line in f:
            cd, url = line.rstrip("\n").split("\t")
            pairs.append((cd, url))
    pairs.sort()
    if args.limit:
        pairs = pairs[: args.limit]

    # Crawls already SUCCESSFULLY processed in a prior run but which contained no
    # Games projects (partial Web Robots crawls) write no output file. Record them
    # from the manifest so resumes don't re-download known-empty dumps every time.
    processed_empty = set()
    if os.path.exists(MANIFEST):
        try:
            mm = pd.read_csv(MANIFEST)
            processed_empty = set(
                mm[(mm["status"] == "ok") & (mm["n_games"] == 0)]["crawl_date"].astype(str))
        except Exception:  # noqa: BLE001
            pass

    print(f"{len(pairs)} crawls to consider. Temp: {TMP_ROOT}", flush=True)
    for i, (cd, url) in enumerate(pairs, 1):
        outp = out_path(cd)
        if os.path.exists(outp):
            print(f"[{i}/{len(pairs)}] {cd}  SKIP (exists)", flush=True)
            continue
        if cd in processed_empty:
            print(f"[{i}/{len(pairs)}] {cd}  SKIP (prior crawl had no Games)", flush=True)
            continue
        ext = ".json.zip" if url.endswith(".json.zip") else ".json.gz"
        dl = os.path.join(TMP_ROOT, cd + ext)
        print(f"[{i}/{len(pairs)}] {cd}  downloading...", flush=True)
        t0 = time.time()
        try:
            download(url, dl)
            df = process_dump(dl, cd)
            n_games = len(df)
            n_tt = int(df["cat_slug"].fillna("").str.contains("tabletop", case=False).sum()) if n_games else 0
            if n_games:
                df.to_csv(outp, index=False, compression="gzip")
            append_manifest({"crawl_date": cd, "url": url, "status": "ok",
                             "n_games": n_games, "n_tabletop": n_tt,
                             "secs": round(time.time() - t0, 1)})
            print(f"    -> {n_games:,} Games ({n_tt:,} tabletop) in {time.time()-t0:.0f}s", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"    ! FAILED {cd}: {e}", flush=True)
            append_manifest({"crawl_date": cd, "url": url, "status": f"error: {e}",
                             "n_games": 0, "n_tabletop": 0, "secs": round(time.time() - t0, 1)})
        finally:
            if os.path.exists(dl):
                os.remove(dl)

    print("\nDone. Manifest:", MANIFEST, flush=True)


if __name__ == "__main__":
    sys.exit(main())
