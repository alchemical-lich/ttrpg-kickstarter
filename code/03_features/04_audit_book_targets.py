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
import os, re
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, "..", ".."))
TG   = os.path.join(PROJ, "data", "interim", "ttrpg_book_targets.csv")
CL   = os.path.join(PROJ, "data", "processed", "tabletop_classified.csv.gz")
OUT  = os.path.join(PROJ, "data", "interim", "ttrpg_book_targets_audited.csv")

# --- hand-verified overrides (by distinctive lowercase title substring) ---------
# Real RPG BOOKS that the rules below would wrongly exclude (incidental words):
FORCE_KEEP = [
    "avatar legends", "root: the", "lairs & legends", "ariadne's book of legends",
    "shadowrun", "dc heroes", "corvus belli", "infinity roleplaying",
    "mythic legions: the roleplaying", "kingdoms, warfare & more minis",
]
# Non-books the rules might miss or that need a human call (verified via blurb):
FORCE_EXCLUDE = [
    "darkest dungeon: the board game", "sorcery: contested realm", "pixels - the electronic",
    "realm brew", "horror on the orient express", "trudvang legends", "robotech",
    "the deck of many", "super dungeon explore", "dragonstone dice", "tidal blades",
    "obojima tales from yatamon", "too many bones", "elder dice", "ascendice",
    "elixir dice", "time of legends", "folklore: the affliction", "wyrmwood tabletop tiles",
    "wyrmwood magnetic game master screen", "return to planet apocalypse", "euthia",
    "godice", "valor & villainy", "apocrypha adventure card game", "arcadia quest",
    "rpg inspired jewelry", "bisoulovely", "infinidungeon", "bardsung", "npc rivals",
    "d6: dungeons, dudes", "damage dice", "the adventurer's tarot",
    "elements of inspiration", "one last fight", "oracle rpg app", "ember",
    # additional non-books verified from the needs_review pass:
    "animal adventures: tales of dungeons and dog", "animal adventures: tales of cats",
    "vampire: the masquerade - heritage", "the wyrmwood hero vault", "gametee",
    "unspeakable words", "cyberpunk red: combat zone", "fatum, dark myths",
    "darklands: a world of war", "forgotten world: fantasy figures", "stonespine architects",
    "realm: the soul searchers", "munchkin starfinder", "stones dungeon tiles",
    # borderline RPG-adjacent products excluded under the STRICT books/PDFs-only rule
    # (card/accessory packs, GM tool-kits, digital/VTT, hybrid games):
    "daggerheart class packs", "serpent's tongue", "the far traveler's collection",
    "roleplaying without limits", "gamemaster's chest", "wind wraith",
    "grim & deliberate beast",
]

# --- high-precision rules (title primarily; blurb only as backup) ---------------
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


def classify(name, blurb):
    nl = (name or "").lower(); tl = (nl + " || " + (blurb or "")).lower()
    for s in FORCE_KEEP:
        if s in nl:
            return True, "book", "override:keep"
    for s in FORCE_EXCLUDE:
        if s in nl:
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
    tg = pd.read_csv(TG)
    cl = pd.read_csv(CL, low_memory=False)[["id", "blurb"]]
    df = tg.merge(cl, on="id", how="left").sort_values("pledged_usd", ascending=False)
    res = df.apply(lambda r: classify(r["name"], r["blurb"]), axis=1)
    df["is_book"] = [x[0] for x in res]
    df["label"]   = [x[1] for x in res]
    df["reason"]  = [x[2] for x in res]
    df["needs_review"] = df["reason"].str.startswith("review")
    df.to_csv(OUT, index=False)

    n = len(df); nb = int(df["is_book"].sum())
    print(f"audited {n} targets -> {nb} books, {n-nb} non-books "
          f"({df['needs_review'].sum()} flagged needs_review)")
    print("\n=== EXCLUDED as non-books (top 40 by pledged) ===")
    for r in df[~df["is_book"]].head(40).itertuples():
        print(f"  ${r.pledged_usd:>10,.0f}  [{r.reason:18}] {str(r.name)[:48]}")
    print("\n=== needs_review (unclassifiable by rules; kept by default) ===")
    for r in df[df["needs_review"]].head(25).itertuples():
        print(f"  ${r.pledged_usd:>10,.0f}  {str(r.name)[:46]}  ||  {str(r.blurb)[:60]}")
    print(f"\nWrote {OUT}")


if __name__ == "__main__":
    main()
