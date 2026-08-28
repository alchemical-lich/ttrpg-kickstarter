#!/usr/bin/env python3
"""04_audit_book_targets.py — Audit the top-decile TTRPG target list down to genuine
RPG *books* (rulebooks / adventures / settings / supplements / sourcebooks /
bestiaries / zines), excluding non-book products the keyword classifier let through:
dice, miniatures/terrain, board games, card/deck/TCG games, video/digital games,
jewelry, maps/mats/screens and other accessories.

WHY: ttrpg_label=="ttrpg" is noisy at the top — e.g. "Pixels - The Electronic Dice"
(dice), "Darkest Dungeon: The Board Game" (board game), "Sorcery ... TCG" (card
game) all slipped in. Pure keyword rules are imprecise BOTH ways (they miss board
games like "Bardsung", and falsely flag real RPG books like "Avatar Legends" that
merely mention a board-game origin), so this combines high-precision title rules
with hand-verified override lists and flags the rest for review.

Input : data/interim/ttrpg_book_targets.csv  (+ blurbs from tabletop_classified)
Output: data/interim/ttrpg_book_targets_audited.csv  (adds is_book, label, reason)
"""
import os, re, sys, argparse
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
TG   = os.path.join(PROJ, "data", "interim", "ttrpg_book_targets.csv")
CL   = os.path.join(PROJ, "data", "processed", "tabletop_classified.csv.gz")
OUT  = os.path.join(PROJ, "data", "interim", "ttrpg_book_targets_audited.csv")

# --- hand-verified overrides (by distinctive lowercase title substring) ---------
# Real RPG BOOKS that the rules below would wrongly exclude (incidental words):
# --- HAND-VERIFIED OVERRIDES, PINNED TO PROJECT IDS -------------------------
# These encode human calls about SPECIFIC projects, so they are keyed by id. They
# were originally written as title substrings, which silently leaked onto any new
# project sharing a name fragment: on the 2026-08 top-quartile expansion, the
# FORCE_KEEP entry "root: the" whitelisted "Root: The Marauder Expansion" ($2.0M)
# and "Root: The Underworld Expansion" ($1.7M), and "shadowrun" whitelisted
# "Shadowrun: Sprawl Ops Boardgame" ($293k) -- all board games, and because
# FORCE_KEEP is checked BEFORE HARD_EXCLUDE, the literal word "Boardgame" in the
# title could not save it. Pinning to ids makes an override apply to the project a
# human actually looked at and nothing else. The id sets below reproduce the
# original top-decile audit exactly (12 keeps / 64 excludes).
# Provenance -- the substrings these were resolved from:
#   KEEP:    avatar legends / root: the / lairs & legends / ariadne's book of legends /
#            shadowrun / dc heroes / corvus belli / infinity roleplaying /
#            mythic legions: the roleplaying / kingdoms, warfare & more minis
#   EXCLUDE: see git history for the 59 substrings (dice, board games, minis, VTT, etc.)
# To override a NEW project, add its id here after checking it by hand.
FORCE_KEEP_IDS = {
    88939782, 279502168, 781308113, 966643752, 1017655225, 1237480310, 1267388269,
    1320623133, 1398121404, 1491991867, 1805778307, 2092989754
}

# 2026-08-27: +19 ids from hand-reviewing the expansion frame's review:default_keep
# bucket (board-game expansions incl. Root Marauder/Underworld, wargames, card decks,
# terrain, a VTT, a convention, an actual-play series, metal coins, a deck box), plus
# 3 that the generic rules waved through: a rules-teaching APP whose blurb says
# "skip the rulebook", a dice-carrying case, and a box of condition rings (the last
# passed because BOOK_SIGNAL matches a bare "RPG" anywhere in the title).
FORCE_EXCLUDE_IDS = {
    20643541, 28618311, 34826433, 39662244, 45013082, 91488235, 99446425, 147133584,
    155384546, 222010673, 224234069, 236666395, 270751638, 278155818, 299287174,
    336396222, 337792901, 361189273, 383786970, 404100990, 416743843, 454198961,
    603512871, 619342545, 637799472, 649215067, 675227295, 717195057, 734267646,
    767721919, 781752217, 789714926, 797712747, 798311583, 872237421, 927490714,
    927796413, 937294187, 954382197, 993119939, 995168509, 1019039281, 1043743498,
    1100304724, 1120021125, 1126754232, 1174760394, 1205282050, 1233850363, 1295579858,
    1304260125, 1330403707, 1335064839, 1352145973, 1357271204, 1368412031, 1373371332,
    1380310762, 1419050255, 1475643313, 1478074330, 1487828540, 1487875152, 1501883284,
    1624367842, 1650606848, 1687074130, 1690704587, 1691374856, 1718020169, 1826699694,
    1827553534, 1837926388, 1840588764, 1848456681, 1859509147, 1875566704, 1913513490,
    1953460883, 1953926196, 1978834938, 2004729639, 2021895418, 2073980318, 2113586431,
    2123520847
}

HARD_EXCLUDE = re.compile(
    r"\b(board ?game|deck-?build(?:er|ing)?|trading card game|\btcg\b|\bccg\b|"
    r"miniatures?|\bminis\b|\bstl\b|\bterrain\b|jewell?ry|map tiles?|battle ?mat|"
    r"tabletop tiles|game master screen|gm screen|\btarot\b|action figure|enamel pin|"
    r"\bplaymat\b|\bpuzzle\b|war ?game|strategy battle|battle game|video ?game|roguelike)\b", re.I)
DICE_TITLE   = re.compile(r"\bdice\b", re.I)
BOOK_SIGNAL  = re.compile(
    r"\b(roleplaying game|role-playing game|\brpg\b|ttrpg|5e\b|5th edition|adventure|"
    r"campaign|setting|sourcebook|supplement|bestiary|\bzine\b|module|\btome\b|"
    r"grimoire|player'?s guide|guide to|monster|rulebook|sourcebook|one-?shot|"
    r"\bbook\b|hardcover|softcover)\b", re.I)


def classify(pid, name, blurb):
    nl = (name or "").lower(); tl = (nl + " || " + (blurb or "")).lower()
    if pid in FORCE_KEEP_IDS:
        return True, "book", "override:keep"
    if pid in FORCE_EXCLUDE_IDS:
        return False, "non_book", "override:exclude"
    if HARD_EXCLUDE.search(name or ""):
        return False, "non_book", "rule:title_nonbook"
    if DICE_TITLE.search(name or "") and not re.search(r"roleplaying|\brpg\b|adventure|setting", nl):
        return False, "non_book", "rule:dice_title"
    if BOOK_SIGNAL.search(name or ""):
        return True, "book", "rule:book_title"
    if HARD_EXCLUDE.search(tl):                     # blurb backup for clear games
        return False, "non_book", "rule:blurb_nonbook"
    if BOOK_SIGNAL.search(tl):
        return True, "book", "rule:book_blurb"
    return True, "book", "review:default_keep"      # unknown -> keep but flag


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--targets", default=None,
                    help="target CSV to audit (default: the canonical top-decile list)")
    ap.add_argument("--out", default=None, help="output path")
    args = ap.parse_args()
    tg_path, out_path = args.targets or TG, args.out or OUT
    if os.path.abspath(tg_path) == os.path.abspath(out_path):
        sys.exit("refusing to run: --targets and --out are the same file")
    # NOTE for expansion runs: the override lists below were hand-built against the
    # TOP-DECILE names. On a new frame they will not fire, so more rows fall through
    # to the generic rules and to review:default_keep -- treat the audit as noisier
    # there and spot-check the survivors.
    tg = pd.read_csv(tg_path)
    cl = pd.read_csv(CL, low_memory=False)[["id", "blurb"]]
    df = tg.merge(cl, on="id", how="left").sort_values("pledged_usd", ascending=False)
    res = df.apply(lambda r: classify(int(r["id"]), r["name"], r["blurb"]), axis=1)
    df["is_book"] = [x[0] for x in res]
    df["label"]   = [x[1] for x in res]
    df["reason"]  = [x[2] for x in res]
    df["needs_review"] = df["reason"].str.startswith("review")
    df.to_csv(out_path, index=False)

    n = len(df); nb = int(df["is_book"].sum())
    print(f"audited {n} targets -> {nb} books, {n-nb} non-books "
          f"({df['needs_review'].sum()} flagged needs_review)")
    print("\n=== EXCLUDED as non-books (top 40 by pledged) ===")
    for r in df[~df["is_book"]].head(40).itertuples():
        print(f"  ${r.pledged_usd:>10,.0f}  [{r.reason:18}] {str(r.name)[:48]}")
    print("\n=== needs_review (unclassifiable by rules; kept by default) ===")
    for r in df[df["needs_review"]].head(25).itertuples():
        print(f"  ${r.pledged_usd:>10,.0f}  {str(r.name)[:46]}  ||  {str(r.blurb)[:60]}")
    print(f"\nWrote {out_path}")


if __name__ == "__main__":
    main()
