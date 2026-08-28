#!/usr/bin/env python3
"""05_tier_bundle_features.py — Turn parsed reward-tier item lists (stage 01_ingest/08)
into a "bundle breadth" measure: how many DISTINCT kinds of physical accessory a tier
piles on beyond the core book.

WHY
  The whale-tier question is about tiers "full of random accessories beyond the core
  book," which is a content property, not a price. Price >= $500 is only a proxy for
  it. This scores each tier's itemization into content categories and counts the
  non-core physical ones.

MEASURE
  bundle_breadth = number of distinct ACCESSORY categories present in a tier
                   (dice, minis, map/poster, gm_screen, cards/tokens, art/merch,
                    apparel, other physical). Core book (print or digital), digital
                    extras, VTT files, stretch goals, and social/credit perks do NOT
                    count -- they are not "accessories beyond the book."

CAVEATS
  * Keyword rules on creator-written item text: fuzzy, and undercounts items described
    only in prose rather than the itemization list.
  * Coverage is ~41% of the tier-analysis sample and skews to the older page template,
    so era is confounded -> control for launch year downstream.
  * A tier's itemization lists what is INCLUDED, which for higher tiers is cumulative
    ("everything above, plus..."), so breadth rises mechanically with price. Compare
    tiers at similar price points, or use the residual-of-price version.

Input : data/interim/ttrpg_tier_contents.csv.gz
Output: data/processed/ttrpg_tier_bundles.csv.gz         (tier level)
        data/processed/ttrpg_project_bundles.csv.gz      (project level)
"""
import os, re, gzip, csv, collections

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
IN    = os.path.join(PROJ, "data", "interim", "ttrpg_tier_contents.csv.gz")
OUT_T = os.path.join(PROJ, "data", "processed", "ttrpg_tier_bundles.csv.gz")
OUT_P = os.path.join(PROJ, "data", "processed", "ttrpg_project_bundles.csv.gz")

# Ordered: first match wins, so specific patterns precede general ones
# ("dice bag" -> dice, not other_physical; "art print" -> art, not core print book).
RULES = [
    ("vtt",        r"roll ?20|foundry|fantasy grounds|\bvtt\b|virtual table"),
    ("social",     r"your name|name in the|name in credits|credited|credit in|credits\b|"
                   r"thank you|gratitude|gratefulness|acknowledge?ment|backer[- ]only|"
                   r"discord|shout[- ]?out|cameo|dedicat|livestream|invitation"),
    ("process",    r"pledge manager|add[- ]?ons?\b|beta access|early access|playtest|"
                   r"previews and updates|backer updates|all (backer )?updates|"
                   r"access to updates|feedback round|submit a |shipping calculated|"
                   r"and much more"),
    ("stretch",    r"stretch goal"),
    ("dice",       r"\bdice\b|\bdie\b|d20|dice set|dice bag"),
    ("minis",      r"miniature|\bminis\b|\bmini\b|figurine|\bstandee|statue|\bpawn"),
    ("gm_screen",  r"(gm|dm|game ?master|keeper|referee) ?screen|\bscreen\b"),
    ("map",        r"\bmap\b|\bmaps\b|battlemap|battle ?map|poster|\bchart\b"),
    ("cards",      r"\bcard\b|\bcards\b|\bdeck\b|\btoken|\bcounter|initiative track|"
                   r"character sheet|\bsheets?\b"),
    ("apparel",    r"\bshirt|t-shirt|hoodie|\btote\b|\bbag\b|\bhat\b|\bapron|\bscarf"),
    # NOTE: no bare \bprint\b here -- "print edition"/"print-on-demand" is the BOOK,
    # not merchandise. Scoring those as art inflated bundle_breadth by ~680 items.
    ("art",        r"art ?print|art ?book|\bsticker|\bpin\b|\bpins\b|\bpatch|bookmark|"
                   r"wallpaper|\bdecal|poster art|concept art"),
    ("other_phys", r"\bbox\b|\btray\b|\bcoin\b|journal|notebook|pencil|\bcandle|"
                   r"keychain|mousepad|\bmug\b|\bplaymat|\bruler\b"),
    # core book last: broad, and should not steal items the rules above already claimed
    ("core_book",  r"rulebook|rule book|core book|sourcebook|hardcover|hardback|"
                   r"softcover|paperback|\bpdf\b|e-?book|\bnovel\b|\bmodule\b|"
                   r"adventure|supplement|companion|\bzine\b|campaign setting|"
                   r"\bbook\b|digital|\bprint\b|physical copy|physical edition|"
                   r"printed copy|chapter \d"),
]
COMPILED = [(name, re.compile(pat, re.I)) for name, pat in RULES]
ACCESSORY = {"dice", "minis", "gm_screen", "map", "cards", "apparel", "art", "other_phys"}


def classify(item):
    for name, rx in COMPILED:
        if rx.search(item):
            return name
    return "unclassified"


def main():
    tiers, cat_counts = [], collections.Counter()
    with gzip.open(IN, "rt", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["has_itemization"] != "1":
                continue
            items = [i.strip() for i in r["items"].split("|") if i.strip()]
            cats = [classify(i) for i in items]
            cat_counts.update(cats)
            present = set(cats)
            row = {
                "id": r["id"], "reward_id": r["reward_id"],
                "n_items": len(items),
                "bundle_breadth": len(present & ACCESSORY),
                "n_accessory_items": sum(1 for c in cats if c in ACCESSORY),
                "has_core_book": int("core_book" in present),
                "core_only": int(not (present & ACCESSORY)),
                "n_unclassified": sum(1 for c in cats if c == "unclassified"),
            }
            for c in sorted(ACCESSORY):
                row[f"has_{c}"] = int(c in present)
            tiers.append(row)

    cols = list(tiers[0].keys())
    with gzip.open(OUT_T, "wt", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols); w.writeheader(); w.writerows(tiers)

    # project level: breadth of the richest tier, and the average across tiers
    by = collections.defaultdict(list)
    for t in tiers:
        by[t["id"]].append(t)
    proj = []
    for pid, ts in by.items():
        b = [t["bundle_breadth"] for t in ts]
        proj.append({
            "id": pid, "n_itemized_tiers": len(ts),
            "max_bundle_breadth": max(b),
            "mean_bundle_breadth": round(sum(b) / len(b), 3),
            "n_core_only_tiers": sum(t["core_only"] for t in ts),
            "share_core_only": round(sum(t["core_only"] for t in ts) / len(ts), 3),
        })
    with gzip.open(OUT_P, "wt", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(proj[0].keys())); w.writeheader(); w.writerows(proj)

    tot = sum(cat_counts.values())
    print(f"itemized tiers scored : {len(tiers):,}   projects: {len(proj)}")
    print(f"items classified      : {tot:,}")
    print("\n  category           items    share")
    for c, n in cat_counts.most_common():
        flag = " *" if c in ACCESSORY else ""
        print(f"  {c:16s} {n:7,}   {n/tot:5.1%}{flag}")
    print("\n  (* = counts toward bundle_breadth)")
    print(f"\n-> {OUT_T}\n-> {OUT_P}")


if __name__ == "__main__":
    main()
