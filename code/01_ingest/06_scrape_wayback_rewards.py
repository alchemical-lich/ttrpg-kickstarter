#!/usr/bin/env python3
"""06_scrape_wayback_rewards.py — Recover per-reward-tier data (price, backers,
limit, title) for the top-decile TTRPG book projects from the INTERNET ARCHIVE
(Wayback Machine), never touching kickstarter.com.

DATA ETHICS / ToS
  Kickstarter's ToS forbids automated access to its Services. We therefore read
  ARCHIVED copies from archive.org (whose CDX + snapshot APIs are public and built
  for research). Requests are sequential, rate-limited, retried with backoff, and
  CACHED on disk so reruns don't re-hit the archive. This is for non-commercial
  research; only AGGREGATES should be published, never raw archived pages.

METHOD (per target project)
  1. CDX -> list archived snapshots of the project page.
  2. Pick the snapshot nearest the campaign DEADLINE (earliest capture at/after the
     deadline = final per-tier tallies; else latest pre-deadline capture, flagged).
  3. Fetch that snapshot's raw capture (the `id_` replay mode = original bytes).
  4. Extract the reward tiers: primarily from the embedded project JSON
     (`"rewards":[...]`), with an HTML reward-card fallback for older layouts.
  5. Validate: sum(tier backers) vs the project's backers_count in the same page.

INPUT : data/interim/ttrpg_book_targets.csv   (from 05_recover_project_urls.py)
OUTPUT: data/processed/ttrpg_reward_tiers.csv.gz   (one row per project x tier)
        data/interim/ttrpg_reward_coverage.csv     (one row per project: status)
        data/interim/wayback_cache/                 (cached CDX json + snapshots)

USAGE
  python3 06_scrape_wayback_rewards.py --limit 10   # test on first 10 targets
  python3 06_scrape_wayback_rewards.py              # full run (resumable)
"""
import os, sys, re, json, csv, gzip, time, html, argparse, subprocess, urllib.parse
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
TARGETS = os.path.join(PROJ, "data", "interim", "ttrpg_book_targets.csv")
CACHE   = os.path.join(PROJ, "data", "interim", "wayback_cache")
TIERS   = os.path.join(PROJ, "data", "processed", "ttrpg_reward_tiers.csv.gz")
COVER   = os.path.join(PROJ, "data", "interim", "ttrpg_reward_coverage.csv")
PAUSE   = 1.5   # seconds between archive.org requests (politeness)

TIER_COLS = ["id", "name", "our_pledged_usd", "our_backers", "snapshot_ts",
             "post_deadline", "currency", "usd_rate", "reward_id",
             "minimum_native", "minimum_usd", "tier_backers", "tier_limit", "tier_title"]
COVER_COLS = ["id", "name", "our_pledged_usd", "our_backers", "status",
              "snapshot_ts", "post_deadline", "n_snapshots", "n_tiers",
              "sum_tier_backers", "snap_total_backers"]


def curl_bytes(url, retries=4):
    for a in range(retries):
        p = subprocess.run(["curl", "-sSL", "--compressed", "--max-time", "120", url],
                           capture_output=True)
        if p.returncode == 0 and p.stdout:
            return p.stdout
        time.sleep(2 * (a + 1))  # backoff
    return None


def curl_text(url, retries=4):
    b = curl_bytes(url, retries)
    return b.decode("utf-8", "ignore") if b is not None else None


def cdx_snapshots(project_url, pid):
    """Return list of (timestamp, original) for 200/text-html captures, cached."""
    cf = os.path.join(CACHE, f"cdx_{pid}.json")
    if os.path.exists(cf):
        return json.load(open(cf))
    base = project_url.split("?")[0]
    q = ("http://web.archive.org/cdx/search/cdx?url=" +
         urllib.parse.quote(base, safe="") +
         "&output=json&filter=statuscode:200&filter=mimetype:text/html&collapse=digest")
    snaps = []
    for attempt in range(3):              # retry empties (archive.org throttling)
        out = curl_text(q); time.sleep(PAUSE)
        if out and out.strip().startswith("["):
            try:
                data = json.loads(out)
                snaps = [[r[1], r[2]] for r in data[1:]]  # timestamp, original
            except Exception:
                snaps = []
            if snaps:
                break
        time.sleep(3 * (attempt + 1))     # back off before retrying an empty
    if snaps:                             # cache only non-empty (never poison with a throttled zero)
        json.dump(snaps, open(cf, "w"))
    return snaps


def pick_snapshot(snaps, deadline_dt):
    parsed = []
    for ts, orig in snaps:
        try:
            parsed.append((datetime.strptime(ts, "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc), ts, orig))
        except ValueError:
            continue
    if not parsed:
        return None, None, None
    if deadline_dt is not None:
        # latest capture AT/BEFORE the deadline: all tiers still listed + near-final
        # backers. (Kickstarter hides ended reward tiers after a campaign closes, so
        # post-deadline captures lose per-tier data.)
        before = [x for x in parsed if x[0] <= deadline_dt]
        if before:
            x = max(before, key=lambda t: t[0]); return x[1], x[2], False
        after = [x for x in parsed if x[0] > deadline_dt]
        x = min(after, key=lambda t: t[0]); return x[1], x[2], True   # fallback (may be incomplete)
    x = max(parsed, key=lambda t: t[0]); return x[1], x[2], None


def fetch_snapshot(ts, original, pid):
    cf = os.path.join(CACHE, f"snap_{pid}_{ts}.html.gz")
    if os.path.exists(cf):
        with gzip.open(cf, "rt", encoding="utf-8", errors="ignore") as f:
            return f.read()
    url = f"http://web.archive.org/web/{ts}id_/{original}"
    b = curl_bytes(url); time.sleep(PAUSE)
    if not b:
        return None
    if b[:2] == b"\x1f\x8b":           # archived original was gzip-encoded
        try:
            b = gzip.decompress(b)
        except OSError:
            pass
    h = b.decode("utf-8", "ignore")
    with gzip.open(cf, "wt", encoding="utf-8", errors="ignore") as f:
        f.write(h)
    return h


def extract_rewards(raw):
    """Return (rewards_list, project_backers, currency, usd_rate, method)."""
    u = html.unescape(raw)
    # project-level fields (best-effort)
    cur = re.search(r'"currency":"([A-Z]{3})"', u)
    rate = re.search(r'"static_usd_rate":([\d.]+)', u)
    currency = cur.group(1) if cur else None
    usd_rate = float(rate.group(1)) if rate else None
    proj_backers = max([int(x) for x in re.findall(r'"backers_count":(\d+)', u)] or [0])

    # strategy A: embedded "rewards":[...] JSON array (raw_decode respects strings)
    idx = u.find('"rewards":[')
    if idx != -1:
        j = u.find("[", idx)
        try:
            arr, _ = json.JSONDecoder().raw_decode(u, j)
            if isinstance(arr, list) and arr and isinstance(arr[0], dict) and "minimum" in arr[0]:
                rewards = [{"reward_id": r.get("id"), "minimum": r.get("minimum"),
                            "backers_count": r.get("backers_count"),
                            "limit": r.get("limit"), "title": (r.get("title") or "")}
                           for r in arr]
                return rewards, proj_backers, currency, usd_rate, "embedded_json"
        except Exception:
            pass

    # strategy B: HTML reward-card fallback (older layouts)
    rewards = []
    for b in re.split(r'(?=<li[^>]*data-reward-id=")', raw):
        m = re.search(r'data-reward-id="(\d+)"', b)
        if not m or m.group(1) == "0":
            continue
        money = re.search(r'class="money"[^>]*>\s*([^<]*?\d[\d.,]*)', b)
        bk = re.search(r'pledge__backer-count"[^>]*>\s*([\d,]+)', b)
        ti = re.search(r'pledge__title"[^>]*>\s*([^<]+)', b)
        mn = re.sub(r"[^\d.]", "", money.group(1).replace(",", "")) if money else None
        rewards.append({"reward_id": int(m.group(1)),
                        "minimum": float(mn) if mn else None,
                        "backers_count": int(bk.group(1).replace(",", "")) if bk else None,
                        "limit": None, "title": ti.group(1).strip() if ti else ""})
    if rewards:
        return rewards, proj_backers, currency, usd_rate, "html_cards"
    return [], proj_backers, currency, usd_rate, "none"


def to_deadline_dt(val):
    try:
        return datetime.fromtimestamp(float(val), tz=timezone.utc)
    except (TypeError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None, help="process only first N targets")
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    os.makedirs(os.path.dirname(TIERS), exist_ok=True)

    targets = [r for r in csv.DictReader(open(TARGETS))
               if r.get("project_url") and r["project_url"] != "MISSING"]
    if args.limit:
        targets = targets[:args.limit]

    done = set()
    if os.path.exists(COVER):
        done = {r["id"] for r in csv.DictReader(open(COVER))}

    cov_f = open(COVER, "a", newline="")
    cov_w = csv.DictWriter(cov_f, fieldnames=COVER_COLS)
    if os.path.getsize(COVER) == 0 if os.path.exists(COVER) else True:
        cov_w.writeheader(); cov_f.flush()
    tier_new = open(TIERS.replace(".gz", "") + ".part", "a", newline="")
    tier_w = csv.DictWriter(tier_new, fieldnames=TIER_COLS)
    if os.path.getsize(tier_new.name) == 0:
        tier_w.writeheader()

    n_ok = n_nosnap = n_norew = 0
    for i, t in enumerate(targets, 1):
        pid = t["id"]
        if pid in done:
            continue
        snaps = cdx_snapshots(t["project_url"], pid)
        ddl = to_deadline_dt(t.get("deadline"))
        ts, orig, post = pick_snapshot(snaps, ddl)
        status = "ok"; n_tiers = 0; sumb = 0; snap_tot = 0
        if not snaps or ts is None:
            status = "no_snapshot"; n_nosnap += 1
        else:
            raw = fetch_snapshot(ts, orig, pid)
            if not raw:
                status = "fetch_fail"
            else:
                rewards, snap_tot, currency, usd_rate, method = extract_rewards(raw)
                if not rewards:
                    status = "no_rewards"; n_norew += 1
                else:
                    n_tiers = len(rewards)
                    for r in rewards:
                        mn = r["minimum"]
                        tier_w.writerow({
                            "id": pid, "name": t["name"],
                            "our_pledged_usd": t["pledged_usd"], "our_backers": t["backers_count"],
                            "snapshot_ts": ts, "post_deadline": post,
                            "currency": currency, "usd_rate": usd_rate,
                            "reward_id": r["reward_id"], "minimum_native": mn,
                            "minimum_usd": (round(mn * usd_rate, 2) if (mn is not None and usd_rate) else mn),
                            "tier_backers": r["backers_count"], "tier_limit": r["limit"],
                            "tier_title": (r["title"] or "")[:80]})
                        sumb += r["backers_count"] or 0
                    status = f"ok:{method}"; n_ok += 1
                    tier_new.flush()
        cov_w.writerow({"id": pid, "name": t["name"], "our_pledged_usd": t["pledged_usd"],
                        "our_backers": t["backers_count"], "status": status,
                        "snapshot_ts": ts or "", "post_deadline": post if ts else "",
                        "n_snapshots": len(snaps), "n_tiers": n_tiers,
                        "sum_tier_backers": sumb, "snap_total_backers": snap_tot})
        cov_f.flush()
        if i % 10 == 0 or args.limit:
            print(f"[{i}/{len(targets)}] {pid} {status} | tiers={n_tiers} "
                  f"sumB={sumb} snapTot={snap_tot} | ok={n_ok} nosnap={n_nosnap} norew={n_norew}",
                  flush=True)

    cov_f.close(); tier_new.close()
    # merge tier .part -> gzip
    part = tier_new.name
    rows = list(csv.DictReader(open(part)))
    with gzip.open(TIERS, "wt", newline="") as gz:
        w = csv.DictWriter(gz, fieldnames=TIER_COLS); w.writeheader(); w.writerows(rows)
    os.remove(part)
    print(f"\nDONE. ok={n_ok} no_snapshot={n_nosnap} no_rewards={n_norew} "
          f"| tiers -> {TIERS} | coverage -> {COVER}")


if __name__ == "__main__":
    main()
