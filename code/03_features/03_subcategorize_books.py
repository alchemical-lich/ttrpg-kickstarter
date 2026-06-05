"""
03_subcategorize_books.py — Tag core TTRPG *books* (the `ttrpg` class) on three
axes via priority keyword rules on title+blurb, to chart how the composition of
RPG-book Kickstarters has shifted over time:

  system_family : pbta_fitd | osr | pathfinder | dnd5e | other_named | agnostic_other
  product_type  : zine | bestiary | adventure | setting | gm_tools | supplement | rulebook | other
  genre         : horror | cyberpunk | post_apoc | scifi | superhero | western | historical | fantasy | other

Each axis assigns ONE primary label by first match in a deliberate priority order
(documented below). This is fuzzy — like the top-level classifier, sub-tags are
noisy — so read the *trends/shares*, not any single project's label.

In:  data/processed/tabletop_classified.csv.gz   (uses rows where ttrpg_label=='ttrpg')
Out: data/processed/ttrpg_book_subcats.csv.gz
"""
import os, re
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(PROJ, "data", "processed", "tabletop_classified.csv.gz")
OUT = os.path.join(PROJ, "data", "processed", "ttrpg_book_subcats.csv.gz")

# (label, pattern) lists in PRIORITY order; first match wins.
SYSTEM = [
    ("pbta_fitd",  r"powered by the apocalypse|\bpbta\b|forged in the dark|blades in the dark|belonging outside belonging|carved from brindlewood"),
    ("osr",        r"\bosr\b|old[- ]?school|old-school essentials|\bose\b|m[oö]rk borg|shadowdark|\bdcc\b|dungeon crawl classics|osric|swords? & wizardry|labyrinth lord|basic fantasy|\bknave\b|\bcairn\b|into the odd|\btroika\b|\bb/x\b|becmi|\bad&d\b|\bose\b|white ?box|cepheus"),
    ("pathfinder", r"pathfinder|\bpf2e\b|\bpf1e\b|starfinder"),
    ("dnd5e",      r"\b5e\b|5th edition|fifth edition|d&d|\bdnd\b|dungeons ?& ?dragons|dungeons and dragons|5\.5e|2024 edition"),
    ("other_named", r"call of cthulhu|\bcoc\b|savage worlds|\bgurps\b|fate core|\bfate\b rpg|cypher system|numenera|genesys|mothership|vampire:? the masquerade|world of darkness|cyberpunk red|shadowrun|warhammer|year zero|free league|daggerheart|cortex|delta green|mausritter|dragonbane"),
    ("agnostic_other", r"system[- ]?agnostic|system[- ]?neutral|any system|universal|rules[- ]?(light|lite)"),
]
PRODUCT = [
    ("zine",       r"\bzine\b|zinequest"),
    ("bestiary",   r"bestiary|monster manual|\bmonsters?\b|creatures?|menagerie|\bfoes?\b"),
    ("adventure",  r"adventure|\bmodule\b|one[- ]?shot|scenario|\bdungeon\b|\bquest\b|delve|crawl|mystery|heist"),
    ("setting",    r"\bsetting\b|campaign setting|world ?book|gazetteer|\bworld\b|region|city of|realm|nation"),
    ("gm_tools",   r"gm screen|game ?master|\bgm\b screen|battle ?maps?|\bmaps?\b|random tables|generator|toolkit|\bscreen\b|referee"),
    ("supplement", r"supplement|sub-?classes|\bclasses?\b|\bspells?\b|\bitems?\b|\bfeats?\b|compendium|expansion|options|player'?s guide|sourcebook|splatbook|backgrounds|ancestries|species"),
    ("rulebook",   r"core rule|\brulebook\b|\brules\b|roleplaying game|role-playing game|\brpg\b|\bttrpg\b|core book|game system|complete game"),
]
GENRE = [
    ("horror",     r"horror|lovecraft|cthulhu|cosmic horror|gothic|\bzombie|occult|eldritch|haunted|nightmare"),
    ("cyberpunk",  r"cyberpunk|\bcyber|\bneon\b|dystopia|megacorp|chrome"),
    ("post_apoc",  r"post[- ]?apocal|apocalypse|wasteland|post[- ]?apoc|fallout|mutant"),
    ("scifi",      r"sci-?fi|science fiction|\bspace\b|starship|\bgalaxy|\bmech\b|\brobot|\balien|interstellar|spaceship|planet"),
    ("superhero",  r"superhero|\bsupers\b|\bhero(es)?\b|comic[- ]book|vigilante"),
    ("western",    r"\bwestern\b|wild west|frontier|gunslinger|cowboy"),
    ("historical", r"historical|victorian|\bancient\b|world war|\bww(i|ii|2)\b|samurai|\bviking|napoleonic|medieval history|renaissance"),
    ("fantasy",    r"fantasy|\bdragon|\bsword|\bmagic\b|wizard|\belves?\b|\bdwarf|\bdwarves|\bgoblin|\borc\b|medieval|kingdom|knight|sorcer"),
]


def tagger(rules, default):
    compiled = [(lab, re.compile(pat, re.I)) for lab, pat in rules]
    def tag(text):
        for lab, rx in compiled:
            if rx.search(text):
                return lab
        return default
    return tag


KAGGLE_SRC = os.path.join(PROJ, "data", "processed", "kaggle_tabletop.csv.gz")
KAGGLE_OUT = os.path.join(PROJ, "data", "processed", "kaggle_book_subcats.csv.gz")


def tag_books(bk, text):
    """Add system_family/product_type/genre columns from a lowercased text series."""
    bk = bk.copy()
    bk["system_family"] = text.map(tagger(SYSTEM, "agnostic_other"))
    bk["product_type"] = text.map(tagger(PRODUCT, "other"))
    bk["genre"] = text.map(tagger(GENRE, "other"))
    return bk


def report(bk, label):
    print(f"{label}: {len(bk):,} core RPG books tagged\n")
    for col in ["system_family", "product_type", "genre"]:
        print(f"=== {col} ===")
        print(bk[col].value_counts().to_string()); print()


def main():
    # ---- Web Robots (name + blurb) ----
    df = pd.read_csv(SRC, low_memory=False)
    bk = df[df["ttrpg_label"] == "ttrpg"].copy()
    text = (bk["name"].fillna("") + "  " + bk["blurb"].fillna("")).str.lower()
    bk = tag_books(bk, text)
    bk[["id", "system_family", "product_type", "genre"]].to_csv(
        OUT, index=False, compression="gzip")
    report(bk, "Web Robots")
    print(f"Wrote {OUT}\n")

    # ---- Kaggle (NAME ONLY -- no blurb; noisier, esp. product_type) ----
    if os.path.exists(KAGGLE_SRC):
        kg = pd.read_csv(KAGGLE_SRC, low_memory=False)
        kg = kg[kg["ttrpg_label"] == "ttrpg"].copy()
        ktext = kg["name"].fillna("").str.lower()
        kg = tag_books(kg, ktext)
        kg[["id", "system_family", "product_type", "genre"]].to_csv(
            KAGGLE_OUT, index=False, compression="gzip")
        report(kg, "Kaggle (name-only)")
        print(f"Wrote {KAGGLE_OUT}")


if __name__ == "__main__":
    main()
