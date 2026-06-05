"""
01_classify_ttrpg.py — Rule-based TTRPG classification within Tabletop Games.

The "Tabletop Games" Kickstarter subcategory mixes board games, card games,
wargames, 3D-printable miniatures/STL, dice accessories, AND tabletop RPGs. This
script flags which projects are TTRPGs using transparent keyword rules on the
title + blurb, and (crucially) distinguishes three classes:

  ttrpg            core RPG content: rulebooks, systems, settings, adventures, zines
  ttrpg_accessory  RPG-SPECIFIC gear: minis/STL, dice, GM screens, battlemaps,
                   terrain, VTT/apps that carry an EXPLICIT RPG cue
                   (rpg/d&d/pathfinder/5e/osr/roleplay/GM/...)
  other_accessory  physical gear with NO RPG cue: board-game inserts, CCG deck
                   boxes, wargame minis/terrain, generic dice/fantasy minis
  nontt            board/card/war games and everything else

Outputs:
  data/processed/tabletop_classified.csv.gz  — adds ttrpg_label + matched keywords
  tables/ttrpg_label_counts.csv              — label distribution overall & by year
  tables/ttrpg_audit_sample.csv              — stratified random sample to HAND-CHECK

The audit sample is the validation step: the analyst hand-labels it, and we
compare to the rule labels to estimate precision/recall and then tune the lexicons.

Measurement choices are deliberately conservative and explicit; edit the lexicons
below and re-run. Matching is case-insensitive with word boundaries.
"""
import os
import re

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
MASTER = os.path.join(PROJ, "data", "processed", "games_master.csv.gz")
OUT = os.path.join(PROJ, "data", "processed", "tabletop_classified.csv.gz")
TAB = os.path.join(PROJ, "tables")

# --- Lexicons (lowercase regex fragments; \b added automatically per term) -------
# Core RPG content language — strong evidence of an actual RPG product.
CORE = [
    r"role[\s-]?playing game", r"roleplaying game", r"role[\s-]?play",
    r"\brpg\b", r"\bttrpg\b", r"tabletop role", r"\bosr\b", r"old[\s-]?school",
    r"powered by the apocalypse", r"\bpbta\b", r"forged in the dark",
    r"5th edition", r"\b5e\b", r"\bpf2e\b", r"system[\s-]?neutral",
    r"system reference", r"\bsrd\b", r"sourcebook", r"rulebook", r"rules[\s-]?light",
    r"bestiary", r"monster manual", r"adventure module", r"one[\s-]?shot",
    r"campaign setting", r"adventure path", r"game master", r"\bgamemaster\b",
    r"dungeon master", r"\bgm screen\b", r"player'?s guide", r"character sheet",
    r"\bmegadungeon\b", r"hexcrawl", r"dungeon crawl(er)? rpg",
]
# Named systems / properties — strong, but demote if it's clearly an accessory.
SYSTEM = [
    r"\bd&d\b", r"\bdnd\b", r"dungeons? & dragons", r"dungeons and dragons",
    r"pathfinder", r"call of cthulhu", r"shadowdark", r"m[oö]rk borg",
    r"mothership", r"blades in the dark", r"fate core", r"\bgurps\b",
    r"savage worlds", r"vampire: the masquerade", r"world of darkness",
    r"cyberpunk red", r"warhammer fantasy role", r"mausritter", r"\bknave\b",
    r"\bcairn\b", r"dragonbane", r"daggerheart", r"\bswade\b", r"starfinder",
    r"numenera", r"\bfate\b rpg", r"\bose\b", r"old[\s-]?school essentials",
]
# STRONG accessories: physical products (minis/STL/terrain/dice goods). Their
# presence makes the campaign an accessory product even if it is themed around an
# RPG ("minis for D&D") — a distinct, lucrative product class we keep separate.
ACCESSORY_STRONG = [
    r"\bstl\b", r"3d[\s-]?print", r"\bminis?\b", r"miniature", r"\bfigurine",
    r"\bterrain\b", r"dice tower", r"dice set", r"dice tray", r"dice vault",
    r"dice goblin", r"\d{2}\s?mm",  # "28mm", "30 mm" scale = minis
]
# WEAK accessories: count as accessory ONLY when no core/system RPG language is
# present (a rulebook that bundles a GM screen stays a TTRPG).
ACCESSORY_WEAK = [
    r"\bplaymat\b", r"battle ?map", r"\btokens?\b", r"enamel pin",
    r"\bbinder\b", r"card sleeves", r"map pack", r"\bdice\b",
]
# Strong RPG-content nouns: a rulebook/module/etc. is core TTRPG even if the
# campaign also bundles miniatures/STL (book is the product). Protects against
# over-demotion to "accessory".
CONTENT_CORE = [
    r"rule[\s-]?book", r"source[\s-]?book", r"\bsupplement", r"\bmodule\b",
    r"compendium", r"\bcodex\b", r"bestiary", r"monster manual", r"rpg book",
    r"rpg zine", r"\bruleset\b", r"new classes", r"class expansion",
    r"adventure module", r"adventure anthology", r"\bsplatbook\b",
]
# RPG play-aids / props / software / media — reference RPGs but are not a game
# system; demote to "accessory" even when RPG words are present.
PLAY_AID = [
    r"battle ?map", r"map pack", r"maps for", r"\bvtt\b", r"spell scrolls?",
    r"prop scrolls?", r"initiative board", r"initiative cards?",
    r"companion app", r"\bmobile\b", r"digital cartographer", r"soundtrack",
    r"\balbum\b", r"game table", r"storage box", r"storage with", r"drink coaster",
    r"playing card deck",
]
# Board/card/war games — non-RPG game products.
BOARDCARD = [
    r"board game", r"card game", r"deck[\s-]?build", r"trading card",
    r"\btcg\b", r"\bccg\b", r"tile[\s-]?(laying|game)", r"\bwargame\b",
    r"war game", r"miniatures? game", r"skirmish", r"party game",
    r"legacy game", r"push[\s-]?your[\s-]?luck", r"worker placement",
    r"euro[\s-]?game", r"\bboardgame\b",
]


def compile_lex(terms):
    return re.compile("|".join(rf"(?:{t})" for t in terms), re.I)


RE = {k: compile_lex(v) for k, v in dict(
    core=CORE, system=SYSTEM, content=CONTENT_CORE, play_aid=PLAY_AID,
    acc_strong=ACCESSORY_STRONG, acc_weak=ACCESSORY_WEAK, boardcard=BOARDCARD).items()}


def matches(text, rx):
    return sorted(set(m.group(0).lower() for m in rx.finditer(text)))


def classify_row(name, blurb):
    text = f"{name or ''}  {blurb or ''}"
    hits = {k: matches(text, rx) for k, rx in RE.items()}
    core, sysm, content, aid, accs, accw, bc = (
        bool(hits[k]) for k in
        ("core", "system", "content", "play_aid", "acc_strong", "acc_weak", "boardcard"))
    rpg = core or sysm  # explicit RPG cue (rpg/d&d/pathfinder/5e/osr/roleplay/GM/...)
    # An accessory is a TTRPG accessory only with an explicit RPG cue; else "other".
    acc = "ttrpg_accessory" if rpg else "other_accessory"
    if content and not bc:
        # genuine rulebook/module/sourcebook/codex -> core TTRPG even if it bundles minis
        label = "ttrpg"
    elif aid:
        # maps / props / initiative aids / apps / soundtracks
        label = acc
    elif accs:
        # physical accessory product (minis/STL/terrain/dice goods)
        label = acc
    elif core and not bc:
        label = "ttrpg"
    elif sysm and not bc:
        label = "ttrpg"
    elif rpg and accw:          # rulebook bundling a screen/tokens/dice -> still TTRPG
        label = "ttrpg"
    elif accw and not rpg:
        label = "other_accessory"
    elif core and bc:           # RPG language + board/card terms -> ambiguous, keep TTRPG-leaning
        label = "ttrpg"
    else:
        label = "nontt"
    matched = ";".join(f"{k}:{','.join(hits[k])}" for k in hits if hits[k])
    return label, matched


def main():
    df = pd.read_csv(MASTER, low_memory=False)
    tt = df[df["is_tabletop"]].copy()
    res = tt.apply(lambda r: classify_row(r["name"], r["blurb"]), axis=1)
    tt["ttrpg_label"] = [x[0] for x in res]
    tt["ttrpg_matched"] = [x[1] for x in res]
    tt["is_ttrpg"] = tt["ttrpg_label"] == "ttrpg"
    tt["is_ttrpg_accessory"] = tt["ttrpg_label"] == "ttrpg_accessory"
    # convenience flag for "TTRPG ecosystem" = core content + RPG-specific gear
    tt["is_rpg_related"] = tt["ttrpg_label"].isin(["ttrpg", "ttrpg_accessory"])

    os.makedirs(TAB, exist_ok=True)
    tt.to_csv(OUT, index=False, compression="gzip")

    print(f"Tabletop projects classified: {len(tt):,}")
    print(tt["ttrpg_label"].value_counts().to_string())
    print(f"\nis_ttrpg share: {tt['is_ttrpg'].mean():.1%}")

    # label counts by launch year
    yr = pd.to_datetime(tt["launched_at"], unit="s", errors="coerce").dt.year
    by = tt.assign(year=yr).pivot_table(index="year", columns="ttrpg_label",
                                        aggfunc="size", fill_value=0)
    by.to_csv(os.path.join(TAB, "ttrpg_label_counts.csv"))
    print("\nBy launch year (head):")
    print(by.loc[2015:2026].to_string())

    # stratified audit sample for hand-checking (deterministic seed)
    parts = []
    for lab, n in [("ttrpg", 100), ("ttrpg_accessory", 70),
                   ("other_accessory", 45), ("nontt", 45)]:
        sub = tt[tt["ttrpg_label"] == lab]
        parts.append(sub.sample(min(n, len(sub)), random_state=42))
    audit = pd.concat(parts)[["id", "name", "blurb", "cat_name", "ttrpg_label", "ttrpg_matched"]]
    audit = audit.sample(frac=1, random_state=1)  # shuffle so labels aren't grouped
    audit["hand_label"] = ""  # analyst fills: ttrpg / accessory / nontt
    audit.to_csv(os.path.join(TAB, "ttrpg_audit_sample.csv"), index=False)
    print(f"\nWrote audit sample ({len(audit)} rows) -> tables/ttrpg_audit_sample.csv")
    print("  -> hand-fill the 'hand_label' column, then we estimate precision/recall.")


if __name__ == "__main__":
    main()
