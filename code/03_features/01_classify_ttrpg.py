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
# Strong RPG-content nouns: a rulebook/module/etc. is core TTRPG even if the
# campaign also bundles miniatures/STL (the book is the product).
CONTENT_CORE = [
    r"rule[\s-]?book", r"source[\s-]?book", r"\bsupplement", r"\bmodule\b",
    r"compendium", r"\bcodex\b", r"bestiary", r"monster manual", r"rpg book",
    r"rpg zine", r"\bruleset\b", r"new classes", r"class expansion",
    r"adventure module", r"adventure anthology", r"\bsplatbook\b", r"campaign setting",
    r"adventure path", r"player'?s guide", r"gm(?:'s)? guide",
]
# STRONG physical accessory PRODUCTS — the campaign IS the object, not a book.
# These win over a mere RPG mention ("dice for D&D" is an accessory, not a rulebook).
ACCESSORY_PRODUCT = [
    r"\bstl\b", r"3d[\s-]?print", r"\bminis?\b", r"miniature", r"\bfigurine",
    r"action figure", r"\bterrain\b", r"\bdiorama\b", r"\d{2}\s?mm",
    r"electronic dice", r"\bdice\b", r"dice (?:set|tower|tray|vault|goblin)",
    r"metal dice", r"gemstone dice", r"enamel pin", r"jewell?ry", r"\bnotebook\b",
    r"battle ?map", r"battle ?mat", r"map tiles?", r"dungeon tiles", r"\bplaymat\b",
    r"gm screen", r"game master screen", r"\btarot\b", r"card deck", r"deck of many",
    r"spell cards?", r"storage (?:box|vault|case)", r"\bcoaster", r"playing card deck",
]
# WEAK accessories: count only when no RPG content/cue (a rulebook bundling tokens stays a book).
ACCESSORY_WEAK = [r"\btokens?\b", r"\bbinder\b", r"card sleeves", r"map pack",
                  r"initiative (?:board|cards?)", r"\bvtt\b", r"companion app", r"soundtrack"]
# Non-RPG GAME forms — board/card/war/video games. NOT books even when wearing RPG
# flavour, UNLESS the TITLE literally says "roleplaying game"/"ttrpg" or there is real
# rulebook CONTENT. (This is the key fix: a mere "RPG"/"D&D" mention no longer rescues
# a board game.) Title-evocative board games with no form word are caught by overrides.
GAME_FORM = [
    r"board ?game", r"\bboardgame\b", r"card game", r"deck[\s-]?build(?:er|ing)?",
    r"trading card", r"\btcg\b", r"\bccg\b", r"miniatures? game", r"\bwargame\b",
    r"war game", r"\bskirmish\b", r"strategy (?:battle|game)", r"\bbattle game\b",
    r"legacy game", r"euro[\s-]?game", r"worker placement", r"push[\s-]?your[\s-]?luck",
    r"tile[\s-]?laying", r"party game", r"co-?op(?:erative)? game",
    r"no (?:game ?master|gm) (?:required|needed)", r"gamemaster-?less",
    r"video ?game", r"roguelike", r"\bsteam\b", r"playstation", r"nintendo", r"pc game",
]
# Curated overrides (hand-verified) — by lowercase TITLE substring.
CURATED_NONTT = [
    "darkest dungeon: the board game","sorcery: contested realm","pixels - the electronic",
    "realm brew","horror on the orient express","trudvang legends","robotech",
    "the deck of many","super dungeon explore","dragonstone dice","tidal blades",
    "obojima tales from yatamon","too many bones","elder dice","ascendice","elixir dice",
    "time of legends","folklore: the affliction","wyrmwood tabletop tiles",
    "wyrmwood magnetic game master screen","return to planet apocalypse","euthia","godice",
    "valor & villainy","apocrypha adventure card game","arcadia quest","rpg inspired jewelry",
    "bisoulovely","infinidungeon","bardsung","npc rivals","d6: dungeons, dudes","damage dice",
    "the adventurer's tarot","elements of inspiration","one last fight","oracle rpg app","ember",
    "animal adventures: tales of dungeons and dog","animal adventures: tales of cats",
    "vampire: the masquerade - heritage","the wyrmwood hero vault","gametee","unspeakable words",
    "cyberpunk red: combat zone","fatum, dark myths","darklands: a world of war",
    "forgotten world: fantasy figures","stonespine architects","realm: the soul searchers",
    "munchkin starfinder","stones dungeon tiles",
]
CURATED_TTRPG = [
    "avatar legends","root: the","lairs & legends","ariadne's book of legends","shadowrun",
    "dc heroes","corvus belli","infinity roleplaying","mythic legions: the roleplaying",
]


def compile_lex(terms):
    return re.compile("|".join(rf"(?:{t})" for t in terms), re.I)


RE = {k: compile_lex(v) for k, v in dict(
    core=CORE, system=SYSTEM, content=CONTENT_CORE,
    acc_prod=ACCESSORY_PRODUCT, acc_weak=ACCESSORY_WEAK, game_form=GAME_FORM).items()}
TITLE_RPG = re.compile(r"role[\s-]?playing game|\bttrpg\b", re.I)
# Clear accessory PRODUCTS identified from the TITLE (the product type lives in the
# title; an adventure that merely *mentions* maps in its blurb must NOT be demoted).
# These override content words (e.g. "Bestiary Cards" is a card deck, not a book),
# unless the title itself says it's a roleplaying game.
TITLE_ACCESSORY = re.compile(
    r"\bcard deck\b|\bdeck of\b"
    r"|\b(?:playing|spell|bestiary|creature|monster|encounter|character|npc|tarot|oracle|rumou?r|loot|item)\s+cards?\b"
    r"|\bmaps\b|\bmap pack\b|\bmap tiles?\b|battle ?maps?\b"          # plural/marked maps = a map product
    r"|\btokens?\b|\bstamps?\b|\bstencils?\b|stat[\s-]?trackers?"
    r"|\btiles\b|\bscenery\b|\bplaymat\b|gm screen|game master screen"
    r"|\brunes?\b|\benamel\b|\bjournals?\b"
    r"|\b(?:t-?shirts?|shirts?|hoodies?|mugs?|enamel pins?)\b", re.I)


def matches(text, rx):
    return sorted(set(m.group(0).lower() for m in rx.finditer(text)))


def classify_row(name, blurb):
    name = name or ""; blurb = blurb or ""
    nl = name.lower()
    for s in CURATED_NONTT:
        if s in nl:
            return "nontt", "override:nontt"
    for s in CURATED_TTRPG:
        if s in nl:
            return "ttrpg", "override:ttrpg"
    text = f"{name}  {blurb}"
    hits = {k: matches(text, rx) for k, rx in RE.items()}
    core, sysm, content, accp, accw, gform = (
        bool(hits[k]) for k in ("core", "system", "content", "acc_prod", "acc_weak", "game_form"))
    rpg = core or sysm                       # RPG cue (rpg/d&d/5e/osr/roleplay/GM/...)
    title_rpg = bool(TITLE_RPG.search(name))  # full phrase in title — protects e.g. "Root: The ... Roleplaying Game"
    title_acc = bool(TITLE_ACCESSORY.search(name)) and not title_rpg
    acc = "ttrpg_accessory" if rpg else "other_accessory"

    if title_acc:
        label = acc                          # clear accessory product by title (card deck / map pack)
    elif content and not gform:
        label = "ttrpg"                      # genuine rulebook/module/etc. (even if it bundles minis)
    elif gform:
        # board/card/video game: keep TTRPG only if the title says so or there's real book content
        label = "ttrpg" if (title_rpg or content) else "nontt"
    elif accp:
        label = acc                          # physical accessory product (minis/dice/tiles/jewelry/...)
    elif rpg:
        label = "ttrpg"                      # RPG content/cue, no game-form, no product
    elif accw:
        label = "other_accessory"
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
