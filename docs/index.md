:::notice
**Code & data:** This page is the write-up. The full reproducible pipeline (Python + R), figures, and tables live in [this repository](https://github.com/alchemical-lich/ttrpg-kickstarter).
:::

*Note: Caveat Emptor. The analysis and write-up were generated with the help of Claude Code—since this was done on a whim, I didn’t feel the need to do everything by hand. I checked a lot of the analysis, but there might still be mistakes in there.*

A while back I read [a great guest post on Patchwork Paladin](https://patchworkpaladin.com/2026/05/18/kickstarter-whales-guest-post/) about Kickstarter "whales" — the analysis where Scipio202 went through ENWorld's list of fifty-three tabletop RPG campaigns that raised a million dollars or more and pulled apart their reward tiers.[^whales] The headline finding stuck with me: across those mega-projects, the high-end "whale" tiers brought in roughly 23% of all the money, vastly more than the cheap entry tiers (under 4%), and the sweet-spot whale tier clustered around a sizable but more sensible ~$478, nowhere near the $5,000 dragon-hoard you might picture.

It's a nice piece of detective work. But fifty-three projects is fifty-three projects, and all of them are extreme success stories. I kept wondering about the rest of the ttrpg Kickstarter projects out there. So I went looking for more data to learn about what makes rpg projects work on Kickstarter. 

## Getting the data — and its survivorship problem

There's a wonderful free resource called Web Robots that has been crawling Kickstarter roughly once a month since 2014 and posting the results. With the help of Claude, I stitched together more than a hundred of those monthly snapshots, deduplicated everything, and ended up with about **45,000 tabletop-games projects**. Tabletop is a messy category — it lumps board games, card games, miniatures, dice, and actual roleplaying games together — so I built a keyword classifier to sort RPG rulebooks and adventures (~10,800 of them) and RPG-specific accessories like dice and minis (~4,000) out from the boardgame crowd.[^classifier]

![Tabletop launches by month, with coverage gaps shaded red](images/tabletop_launches_by_month_coverage.png)

*All tabletop launches by month (board games included, not just RPGs), from the stitched-together monthly crawls. The red bands mark months where the **crawl** captured no Games category at all — note these are crawl months, not launch months, so the few projects still showing there were salvaged from much later crawls and badly undercount the real total. One such stretch lands, frustratingly, right on the 2023 OGL crisis.*

Then I did the first thing anyone does: I checked the success rate. The data said tabletop RPGs succeed about **98% of the time**.

That number seems wildly inaccurate, and recognizing *why* it's garbage is a good example of why figuring out where your data come from is so important. Web Robots builds its snapshots from Kickstarter's public "discover" pages — and those pages overwhelmingly surface projects that are live or that succeeded. Campaigns that flopped quietly fall out of view and never make it into the crawl. So what the crawl really captures is the *survivors* — the live and the victorious — with the quiet failures missing almost entirely.[^survivorship] Asking it for a success rate is like surveying lottery winners about the odds of winning the lottery.

This is survivorship bias, and it required a bit of additional thinking. It means there are two separate questions hiding inside "what makes a campaign succeed," and they need different data:

1. **Did it get funded at all?** — You cannot answer this from a dataset with no failures.
2. **Given that it got funded, how much did it raise?** — This you *can* answer, because the survivors are exactly the population you care about.

So I went and found data that *does* include the failures. A widely-used Kaggle export covers 2009–2018 and includes the flops; an academic dataset from ICPSR covers 2009–2023 with all 610,000 Kickstarter projects, successes and failures alike.[^triangulation] Triangulating across three independent sources — using the failure-inclusive ones for "did it fund" and the rich Web Robots crawl for "how much" — is the basis of everything below.

When you bring the failures back, the real tabletop success rate isn't 98%. It's about **two-thirds** over 2009–2018, climbing to roughly **86% by 2023**.[^rate] Tabletop has quietly become one of the most forgiving categories on the platform — but it got there gradually.

![True tabletop success rate by year, two sources](images/icpsr_success_by_year.png)

*The real success rate (successes ÷ finished projects), once you put the failures back in. Two independent datasets agree closely through 2018; the longer one carries the story up to ~86% by 2023.*

## A growing share of gaming crowdfunding

First, a sense of scale — how big is this corner of Kickstarter, and is it growing? The answer is *bigger every year*. Stack up the funded dollars across Kickstarter's whole Games category and tabletop towers over everything else, with the RPG slice climbing steadily underneath it.[^market]

![Funded dollars across Kickstarter Games subcategories by year](images/desc_market_dollars_by_year.png)

*Funded pledged dollars on Kickstarter's Games category, stacked by subcategory. Tabletop dominates — non-RPG tabletop (green, mostly board games) plus the RPG bands (blue core, orange accessories) at the bottom — towering over video games, playing cards, and the rest. The red band is the 2022–23 coverage gap; the dip there is the missing crawls, not a real downturn.*

Pull out just the RPG slice and the rise is real — but worth stating carefully. On *cleaned* labels (after removing the board games, dice, and card games a keyword classifier had mistakenly filed under "RPG"[^cleanlabels]), core RPGs go from about **7% of Kickstarter-Games dollars** in the mid-2010s to the **mid-to-high teens** by the 2020s — **roughly a doubling**, not a tripling. The raw line touches ~24% in 2024, but lean on that peak and it buckles: that single year rides almost entirely on one $15M campaign (the Cosmere RPG), and trimming the top 1% of projects pulls even 2024 down near 14%.[^market] The rising tide the whale post was surfing is genuinely there — just smaller than the headline number suggests.

![Core RPG share of Kickstarter-Games funded dollars over time](images/desc_ttrpg_share_of_games.png)

*Core RPGs' share of all Kickstarter-Games funded dollars (blue, cleaned labels), with tabletop's share overall (green) for context. Both rise; the RPG line roughly doubles — the 2024 spike toward a quarter is one $15M megaproject. (Ignore the 2022–23 plunge — that's the coverage gap.)*

But "tabletop" is mostly *board games* when it comes to dollars. Line up each subcategory's share of the money against its share of the projects and you can see where the big money sits: board games take about **60% of the dollars on 44% of the projects**, while the cheap commodities — playing cards, RPG accessories — are the reverse, lots of projects but little money. Core RPGs land in between, raising roughly in proportion to their numbers.

![Share of dollars vs share of projects, by Games subcategory](images/desc_share_dollars_vs_projects.png)

*Each subcategory's share of funded dollars (blue) vs its share of funded projects (grey). Where blue beats grey — board games, video games — is high-value territory; where grey beats blue — playing cards, accessories — is high-volume but cheap.*

## Where the money actually is

Start with the shape of the money, among funded projects. It is *brutally* top-heavy. The **top 1% of funded RPG projects capture about 35% of all the dollars**; the top 5% capture nearly two-thirds. For accessories it's even more concentrated relative to their size — the top 1% pull in 40%. The whale post wasn't studying a weird fringe; it was studying the part of the distribution where almost all the money actually is.

![Lorenz curve of pledged dollars](images/desc_lorenz_dollars.png)

*How concentrated the money is. The sharp bend near the right edge means a tiny share of projects holds most of the dollars; a straight diagonal would mean perfect equality.*

The typical project is far humbler. A median *funded* RPG book raises around **$5,700** from a bit over 200 backers; a median funded RPG accessory (dice, minis, a GM screen) raises about **$3,000** from roughly 100 backers. Here's a detail I liked: the *per-backer* pledge is nearly identical for the two — about $30 either way. So RPG books pull ahead by attracting roughly twice as many backers at that same price point. The gap comes from demand — how many people show up — while the spend per person barely moves.

![Distribution of pledged dollars, RPG books vs accessories](images/desc_pledged_hist_log.png)

*What funded projects raise (log scale). RPG books sit to the right of accessories — they raise more — but both distributions have a long tail reaching toward the millions.*

Accessories, meanwhile, play a different game. Their median funding goal is **about $400** — basically a formality — and they blow past it: 86% of funded accessories raise at least double their goal, versus 76% for books. "Set a tiny goal and overfund" is a common strategy, especially for accessories.

## What creators ask for

Two numbers a creator picks before anything else are the **goal** and the **clock** — how much to ask for, and how long to run. Both turn out to be remarkably conventional. RPG goals cluster in the low thousands (accessories a notch lower, in the hundreds), with the telltale spikes at round numbers like $1,000 and $5,000.

![Distribution of funding goals, RPG books vs accessories](images/desc_goal_hist_log.png)

*Goals set by funded campaigns (log scale). Core RPG books cluster around $1–5K; accessories sit lower. The vertical spikes are round-number goals.*

What's striking is how goals have *fallen* over the decade. The median funded RPG book asked for about **$4,000 in 2016 but only ~$600 by 2024**; accessories dropped even harder, from ~$2,500 to barely $100. Part of this is the zine wave — small-format projects with tiny goals became common after 2019 — and part is creators gravitating to a modest, beatable goal as the safe default.[^goaltrend]

![Median funding goal by launch year](images/desc_median_goal_by_year.png)

*Median goal by launch year (funded only). Goals more than halved over the decade, with the post-2019 slide tracking the influx of small-goal zines.*

The clock is even more uniform. The overwhelming majority run the platform's **30-day default**, with smaller clusters at two and three weeks and almost nobody past 60 days — campaign length is the one dial creators barely touch.

![Distribution of campaign lengths](images/desc_duration_hist.png)

*Campaign length in days (funded). The spike at 30 is Kickstarter's default; few creators stray far from the common two-to-four-week window.*

## The shift toward D&D 5e

Before asking what *succeeds*, it's worth looking at what people even make — and how that's changed. Over the decade the *mix* of funded RPG books shifted hard. Books that name **D&D's fifth edition** went from about **7%** of funded RPG books in 2014–15 to nearly **40%** by 2023–26. The old-school renaissance (OSR) more than doubled its share, the long tail of titles that don't name any system steadily receded as more creators hitched their book to a recognizable engine, and — a detail I'll come back to in the causal section — Pathfinder *shrank* in relative terms as 5e ate the center of the hobby.[^composition]

![Composition of funded RPG books by system family over time](images/comp_system_family.png)

*The shifting mix of funded RPG books by system. The D&D 5e band (top) swells from a sliver to ~40%; OSR grows; the "agnostic / unnamed" base shrinks as books increasingly name a system. The grey band is the 2022–23 coverage gap.*

But "a 5e book" and "an indie-system book" are usually different *kinds* of object, and splitting the same books by what they physically *are* makes the contrast almost cartoonish:

![Product-type mix, D&D 5e books vs other-system books](images/comp_producttype_5e_split.png)

*What kind of book is it? D&D 5e books (left) versus everything else (right). 5e is mostly adventures and supplements; other systems are where new rulebooks and zines live.*

D&D 5e is something people publish *for*: about **40% of 5e books are adventures**, another quarter are bestiaries and supplements, and only ~6% are new core rulebooks. Other systems are where new *games* live — about a third are rulebooks — and they're also where the zines cluster (**12%** of other-system books, versus ~4% of 5e ones). One ecosystem extends a giant; the other invents. That split will matter when we ask, later, whether 5e's arrival "caused" the boom — because 5e didn't grow the hobby so much as become the substrate everyone else builds on.

## Getting funded depends more on who than what

Now the question the survivor data couldn't speak to. Using the failure-inclusive datasets, I built models to predict funding success and — importantly — checked how well they did out-of-sample, not just how nicely they fit.[^auc] One scope caveat to keep in the back of your mind for this whole section: the failure-inclusive data is either name-identified only through 2018 or not RPG-specific, so the funding-side story leans on tabletop crowdfunding in the 2010s and may not perfectly describe the ZineQuest-era RPG market of the 2020s.[^fundingera]

I started with two models with different kinds of information. One knew only about the **creator**: how many projects they'd run before, how many succeeded, how many failed. The other knew only about the **project**: its genre, its goal, its country, its title.

The creator model came out ahead — AUC about **0.83** against the project model's **0.72**.[^whovwhat] I'd stop short of calling it a clean knockout, though, and the distinction matters: the two models are built on *different* datasets (only one source pairs creator IDs with failures; only the other carries project names), and the creator-history model isn't even RPG-specific — so this is a decomposition *across sources*, not a head-to-head on the same projects. Read with that caveat, the signal is consistent and one-directional: *who is asking* looks at least as predictive as *what they're asking for*. A creator's prior track record is the strongest single predictor I found: each past success multiplies the odds of funding, a strong prior success *rate* multiplies them a lot, and — symmetrically — **past failures predict future failure**. Reputation compounds in both directions.

![Odds-ratio plot of funding predictors from the creator-history model](images/success_or_plot.png)

*What predicts getting funded, from the creator-history model (odds ratios). Bars to the right of 1 improve the odds — a strong prior success rate most of all — while prior failures (left of 1) drag them down.*

This also explains the rising success rate. As the platform ages, a bigger and bigger share of launches come from people who've done it before and succeeded. The market didn't necessarily get easier; apparently the *launchers* got more experienced.

You can watch that happen. Splitting each year's RPG launches into first-timers and creators we've already seen, the returning share climbs from almost nothing in the early years to roughly half by the 2020s — the scene increasingly runs on people who've been through it before.

![Core RPG launches split into new vs returning creators by year](images/desc_creators_new_vs_returning.png)

*Each year's core RPG launches, split into creators making their first appearance (grey) and those seen in an earlier year (blue). The returning share grows as the scene matures. The earliest years are mechanically low, though — with the data starting in 2014, nobody *can* be "returning" at first.*

The project attributes still matter, just less. Holding other things equal: an actual RPG is more likely to fund than a board or card game; a "5E-compatible" or D&D/Pathfinder label helps further; US-based projects do a bit better. And there's the perennial Kickstarter finding — **modest goals fund more reliably.** Each tenfold increase in the goal cuts the odds of funding by roughly two-thirds.

![Success rate by funding-goal bucket](images/icpsr_success_by_goalbucket.png)

*Success falls steadily as the goal climbs. But read this as "who sets what," not as a lever — cautious creators with small audiences are the ones choosing the small goals.*

A warning on that last one, because it's an easily misunderstood statistic: this is a *correlation*, and the goal is not randomly assigned. Creators set goals in anticipation of demand — a cautious creator with a small audience sets $2,000; a publisher with a big mailing list confidently sets $80,000. So "low goals succeed more" absolutely does **not** mean "lower your goal and you'll succeed." The number tells you which kind of creator picks which kind of goal; what would happen if a given creator trimmed their own is a question it simply can't answer. (I'll come back to this trap.)

## Among funded projects, what drives the size of the raise

For the magnitude question — how big does a funded project get — I switched back to the rich Web Robots data, which is exactly the funded population. The standouts, expressed as "multiply the dollars by roughly":

- **A Kickstarter staff pick ("Projects We Love"): ×2.6.** By far the strongest factor in the list.
- **A repeat creator: ×1.4.** The backer-base premium again.
- **Having a video: ×1.13.** Modest but real — though measurable only on recent campaigns.[^video]
- **Being a zine: ×0.73.** Zines are small *by design*.

![Coefficient plot of magnitude drivers](images/drivers_coef_plot.png)

*Correlates of raising more, among funded projects — multiply the dollars by the value on the axis. A "Projects We Love" staff pick travels with ~2.6× the money; a zine, with less.*

I'm deliberately leaving the funding goal off that list even though it has the largest coefficient, because for funded projects its effect is mostly **mechanical**: if you raised enough to succeed, you by definition cleared your goal, so a bigger goal mechanically sets a higher floor.[^goal] 

Two richer wrinkles. First, I fed the campaign *text* — titles and blurbs — into the model to see if the wording tells us anything beyond the obvious numbers. It does, modestly, and the pattern is a clean **premium-versus-commodity axis**: words like "diorama," "scenery," "miniatures," "softcover," and "collectors" predict raising *more*, while "pay what you want," generic "dnd dice," and "quality resin" predict raising *less*.[^text] Presentation as a deluxe object pulls money in; presentation as a cheap commodity doesn't.

![Words that predict raising more vs less](images/text_top_terms.png)

*The words that move money, after controlling for everything else. Premium/deluxe language (blue) predicts bigger raises; commodity and pay-what-you-want language (red) predicts smaller ones.*

Second — and this is the kind of thing only a big dataset lets you ask — the staff-pick and video effects get *stronger* the further up the distribution you go. For a median project a staff pick is worth maybe 1.5×; for the runaway hits near the top it's associated with more like 3.5×. Social proof and polish are amplified in exactly the tail where the whales live. (Correlation again — Kickstarter may hand out staff picks to projects it can already tell will be big — but it's a suggestive pattern.)

### Naming a recognized system raises more

Since I'd tagged every book by its system, I could ask a sharper version of the old "5E helps" folk wisdom: among funded books, does naming a recognized engine correlate with more money? Relative to a system-agnostic book, naming a known system is worth a roughly **25–40% bigger raise** — **D&D 5e ×1.29, OSR ×1.25**, and the named indies (Call of Cthulhu, Mothership, and friends) **×1.39**. Pathfinder and the PbtA family, interestingly, are statistically indistinguishable from agnostic. 

![Dollar premiums by system family and product type](images/subcat_magnitude_premiums.png)

*Multiply-the-dollars premiums for funded RPG books, versus a system-agnostic rulebook. Naming a recognized system (blue) pays; product type (orange) matters less, except that zines raise less.*

And the same "name a system" effect turns up on the *other* question, the one the survivor data can't answer. In the failure-inclusive data, books that name a recognizable system are also meaningfully more likely to **get funded at all** — naming a system seems to reassure backers that an audience already exists for the thing. That said, all of this is second-order: adding the system and product tags barely nudges how well the model predicts dollars, and goal-setting, reputation, and the staff pick still do the heavy lifting.[^sysprem]

## Where books and accessories diverge

Because I'd split RPG books from RPG accessories, I could ask whether they respond to the same things. The answer is a tidy little asymmetry.

For **how much you raise**, the drivers genuinely differ. The starkest example: a "5E-compatible" label *raises* money for a rulebook but is slightly *negative* for an accessory.[^bookacc] That makes intuitive sense — a branded D&D *book* is a selling point, but generic "D&D dice" or "D&D minis" are a commodity in a crowded field. Being US-based flips sign too.

![Magnitude drivers split by product type](images/magclass_by_class_coefs.png)

*Same drivers, different products. The book effect (blue) and accessory effect (orange) pull apart — most strikingly for the 5E label, which lifts books but not commodity minis.*

For **whether you get funded**, though, the drivers *don't* meaningfully differ between books and accessories. The things that get you across the funding line — a modest goal, a reasonable campaign length, an established creator — seem to work about the same regardless of what you're selling.

So: **product type shapes how much you raise, but not whether you raise it.** The recipe for crossing the line is general; the recipe for getting big is product-specific.

## Testing whether 5e caused the boom

Now for the fun part: causation. It's tempting to look at the rising RPG fortunes of the last decade and credit obvious cultural events — 5th edition in 2014, *Stranger Things*, *Critical Role*. Tempting, but mostly unprovable, and in one case likely wrong.

The honest way to test "did event X cause the RPG surge" is a difference-in-differences: compare RPGs (which event X should affect) against board and card games (which it shouldn't) before and after, so the platform-wide trend cancels out. When I do this for **5th edition's mid-2014 release**, the result is a clean *null*. The RPG advantage over other tabletop games was **already there in 2012**, two years before 5e shipped, and it just... continued. There's no break at the release.[^did5e]

![5e event study: RPG-vs-control success gap by year](images/did5e_eventstudy.png)

*The 5e "effect" that wasn't. The RPG-vs-control success gap is already positive in 2012 and flat across the mid-2014 release (dashed line) — no jump, no clean causal story.*

The boom is real, but pinning it on 5e specifically doesn't survive contact with the data — the treatment was too gradual and too anticipated, and 5e probably lifted D&D *board games* too, contaminating the comparison. *Stranger Things* and *Critical Role* are even harder to test cleanly, so I won't.

The 5e test came up empty, but there's one place a real fingerprint *does* show up in the raw data — and you can see it before running any model. Sort core RPG launches by calendar month and one month breaks the pattern, but only recently. Through 2018, February was unremarkable; from 2019 on it swells to more than **a fifth of the whole year's launches**.

![Share of core RPG launches by calendar month, pre- vs post-2019](images/desc_seasonality_month.png)

*Share of core RPG launches by calendar month, split into 2014–18 (grey) and 2019+ (blue). February jumps from an ordinary ~7–8% to ~21% once the later era begins — a seasonal fingerprint hiding in plain sight.*

That February bump is the work of **ZineQuest**, Kickstarter's annual February push for RPG zines, launched in 2019 — and unlike the diffuse 5e rollout, it's sharp enough to actually test. This one is closer to a natural experiment, precisely because it's *RPG-specific* — Kickstarter promotes RPG zines, not board games, so board games make a useful control group. And the effect is unmistakable: funded RPG launches **roughly double every February** in the ZineQuest era, relative to what the season and the trend would predict, with no such jump beforehand.[^zinequest] But the *mechanism* is a nice twist. ZineQuest worked through sheer volume: it summoned a flood of *small* zines that would never otherwise have launched, while leaving the size of the typical project untouched. The February cohort is 41% zines (versus 3% the rest of the year), and its median pledge is less than half the usual. The program lowered the barrier to small-format publishing and a lot of people walked through the door, exactly as intended. One threat I can't fully dismiss, in fairness: my data captures the projects Kickstarter *promotes*, and ZineQuest is itself a promotion push — so some of the February jump could be promoted zines becoming more *visible* to the crawl rather than purely more *numerous*. The board-game control soaks up platform-wide visibility shifts, but not one aimed specifically at RPG zines, so I'd treat the exact size of the effect as suggestive even though its existence is hard to explain away.

![ZineQuest February launch premium by year](images/zq_feb_premium.png)

*ZineQuest's fingerprint. The February "launch premium" for RPGs (blue) is ordinary and flat before 2019, then jumps when the program starts and stays elevated — while the board-game control (red) does not.*

![Placebo test across all twelve months](images/zq_placebo_months.png)

*A placebo check: re-run the test pretending each month is the "treatment." Only February (highlighted) shows the jump — strong evidence the effect is ZineQuest, not noise.*

### The funding threshold isn't a clean experiment

Here's one more causal idea: can we do a regression discontinuity design? Kickstarter is **all-or-nothing**: reach 100% of your goal and you collect the money; finish at 99% and you get nothing. Two campaigns that end at 99% and 101% are, in terms of underlying demand, nearly identical — yet one is "funded" and one is not. That sharp line looks like a natural experiment: line up the just-funded against the just-missed and ask what *getting funded* does to a creator's future — do they come back and launch again?

In the case of Kickstarter projects, this sadly does not work. When I plot where projects actually land relative to their goal, there's a gaping hole just below the line and a pile-up just above it: in the failure-inclusive data only **94 projects** finished in the 90–100% band, against **1,373** in 100–110%.

![Density of projects around the 100%-of-goal line](images/rd_density_mccrary.png)

*The manipulation test. If 100% were a clean dividing line, the density would be smooth across it; instead it jumps — almost nobody ends* just *short, because near-misses get pushed over.*

That’s what is called **manipulation at the threshold**, and it isn't sinister: as a campaign nears its goal in the final days, the creator and their friends nudge it over, and last-day momentum finishes the job, so almost nobody ends *just* short. But it wrecks the experiment — the projects sitting just above the line aren't interchangeable with the ones just below; they're precisely the ones that *managed to cross*. Sure enough, the "effect of funding" I naively estimate is fragile: sizable under one specification, gone under a slightly different one. Moving away from a causal design, we can still explore the relationship between funding goal percentage and future project launches by the same creator. Turns out, the more a campaign raises relative to its goal, the more likely the creator launches again — with no special leap right at the threshold.[^rd]

I'd have loved to study the **2023 OGL crisis** — Wizards of the Coast's botched attempt to revise the Open Game License, which genuinely panicked RPG creators — as a shock to the system. Unfortunately I can't: the Web Robots crawl has a gap in its coverage that sits *exactly* on top of January 2023, and the only failure-inclusive source that reaches that far masks project names so I can't tell the RPGs apart.[^ogl] Bummer.

## What the evidence supports

If you're running an RPG Kickstarter, the evidence-backed takeaways are: your **track record is your biggest asset** (and your past failures follow you); a **modest goal** correlates with funding, though that mostly reflects which creators set small goals in the first place; a **staff pick and a video** travel with much bigger raises; **naming a recognized system** — 5e, OSR, a known indie line — is associated with both clearing the funding bar a little more easily and a somewhat larger raise; and **how you frame the product** — premium object versus cheap commodity — shows up in the dollars.

What I *wouldn't* tell you is that any of these are guaranteed levers. Almost everything here is a correlation drawn from observational data, with all the usual hazards: creators choose their goals strategically, Kickstarter chooses who gets staff-picked, my RPG classifier is right only about three-quarters of the time,[^classifier] and the one result that is in the neighborhood of a causal effect is about a niche February program for zines.

The whale post asked how the giants price their tiers. I can't see reward tiers in my data at all — that detail only exists on individual campaign pages and would take a careful scrape to recover, which is a possible next step.[^tiers] But zooming out from the fifty-three giants to the full forty-five thousand, the RPG corner of Kickstarter turns out to be a place where a handful of projects attract most of the money, most projects are small and increasingly likely to succeed, reputation compounds, and a small February nudge from the platform can elevate the success chances of small zines. 

---

### Footnotes

[^whales]: The original analysis ("Kickstarter Whales," guest post by Scipio202 on Patchwork Paladin) used ENWorld's list of 53 tabletop RPG campaigns that raised ≥ $1,000,000 and tracked four price points per campaign (cheapest digital, cheapest physical, most-common, and the top "whale" tier). It's a tier-level study of mega-successes; this post is a population-level study of the whole category.

[^classifier]: Sorting RPGs out of "tabletop" is genuinely fuzzy, because the clues that mark something as an RPG often live in the blurb, not the title. I validated the classifier on a *fresh* hand-labeled sample it had never seen: about **77% precision and 71% recall** for the core-RPG class. That's good but imperfect, and the imperfection mostly behaves like random noise in the labels — which *understates* differences between categories rather than inventing them. So the contrasts I report are, if anything, conservative.

[^survivorship]: Concretely: in the Web Robots data only about **2% of finished tabletop projects are marked "failed,"** versus a real-world failure rate somewhere around a third to a half. The crawl is essentially "the successful subset." A reassuring cross-check: where the survivor data and the failure-aware data overlap, the funded projects' dollar amounts and backer counts match almost exactly — so the bias is in *which projects appear*, not in the numbers attached to them.

[^triangulation]: The three sources have complementary strengths and weaknesses. Web Robots: rich detail (video, staff pick, full text, creator IDs), 2014–2026, but funded-biased. Kaggle "ks-projects": includes failures and project names, but ends in early 2018. ICPSR 38050: includes failures through 2023 and has a usable creator ID, but masks project names (so I can identify RPGs only by linking to the other two). No single source does everything; the analysis assigns each question to the source that can answer it honestly.

[^rate]: "Success rate" here is successful ÷ (successful + failed), the standard convention. The two independent failure-aware sources agree closely on the 2009–2018 overlap (about 67% vs 69%), which is the kind of cross-source agreement that makes me trust the number.

[^auc]: I report out-of-sample discrimination (AUC, the area under the ROC curve): 0.5 is a coin flip, 1.0 is perfect. I also checked several model types (logistic regression, LASSO, random forest) and they agreed, which is a sign the result isn't an artifact of one method.

[^whovwhat]: The creator-history model reached an AUC of about **0.83**; the project-attribute model about **0.72**. They're built on different datasets (only one source has creator IDs *and* failures; only the other has project names), so this is a decomposition across sources rather than a head-to-head in one regression — but it's robust, and "reputation beats genre" is the clear message.

[^goal]: Among funded projects, pledged dollars are ≥ the goal essentially by definition (I checked: 0.00% of funded projects came in under goal). So the strong goal-pledged relationship for *funded* projects is largely an accounting identity, not behavior. I keep the goal in the model only to hold project scale constant while reading the other coefficients.

[^video]: A wrinkle in the data: Web Robots only started recording whether a campaign has a video in its April 2024 crawls. Every project last seen before then is logged as "no video" regardless of the truth, so the video effect is identified entirely off campaigns captured in 2024 or later — where, reassuringly, it's if anything a touch larger (about ×1.17). Read it as a recent-campaign association rather than a decade-long one, and that's also why I never plot video presence over time.

[^text]: Method, briefly: I turned titles and blurbs into a bag of words and bigrams and let a LASSO pick which ones predict log-dollars, with the vocabulary chosen separately inside each cross-validation fold so the test data couldn't leak in. Adding text lifted out-of-sample R² from about 0.66 to 0.70 — real but modest. One caveat: a bag-of-words model also memorizes specific series and brand names, which don't generalize; the premium-vs-commodity pattern is the part worth keeping.

[^bookacc]: Formally, a joint test that all the book-vs-accessory differences are zero is decisively rejected (p < 0.00001) for the *magnitude* question, but is not significant (p ≈ 0.07) for the *funding* question. Translation: the slopes really do differ for "how much," but not for "whether."

[^did5e]: In an event study, the RPG-vs-control success gap is already positive and sizable in 2012 and flat thereafter; the formal "did the gap jump after mid-2014" interaction is statistically indistinguishable from zero for both funding and dollars. This is a textbook example of why diffuse, anticipated "events" resist clean causal identification.

[^zinequest]: The estimate is about a 2× increase in funded RPG February launches. Because the comparison effectively has only ~12 years of data ("clusters"), a naive significance test overstates confidence; I re-ran it with a wild cluster bootstrap and a placebo test that asks whether any *other* month shows the same jump (none does — February is the unique outlier). The effect holds up. It's also worth noting this measures funded *entry* and dollars, not the success rate, since the rich data still can't see failures.

[^ogl]: Two independent problems collide on the OGL window: a source-side hole in the monthly crawl from mid-2022 to mid-2023 (which I verified is real, not a mistake on my end), and the name-masking in the only failure-aware source that reaches 2023. With neither entry, success, nor dollars observable for RPGs around January 2023, an honest event study isn't possible. A targeted re-scrape of that window is the way to revive it.

[^tiers]: Reward-tier data — the entry-vs-whale breakdown the original post studied — simply isn't in any of these datasets; they only carry campaign-level totals. The closest I can get is average pledge (dollars ÷ backers), which is why the whale-tier question stays open here. Recovering it would mean scraping individual campaign pages, carefully and within Kickstarter's terms.

[^composition]: System and product-type tags come from keyword rules on each book's title and blurb, assigning one label per axis by a priority order. They're fuzzy — PbtA and other indie systems are *undercounted* because those books rarely say "PbtA" on the tin, and a chunk of books name no system at all — so read the trends and the broad shares, not the second decimal. The composition charts are funded books only (the rich crawl can't see failures), and the 2022–23 coverage gap thins those years.

[^sysprem]: Same funded-books regression as the magnitude model above, now with the system-family and product-type tags added (premiums are relative to a system-agnostic rulebook, standard errors clustered by creator). Honesty about effect size: adding the tags lifts cross-validated R² only from about 0.675 to 0.683 — real but small. The success-side claim uses the failure-aware Kaggle data, where adding the tags improves out-of-sample discrimination from AUC ≈ 0.70 to ≈ 0.74; those tags are name-only (no blurb) and pre-2019, so treat them as suggestive. As everywhere here, keyword-tag noise attenuates the contrasts toward zero, so if anything these premiums are understated.

[^rd]: This is a regression-discontinuity design at the 100%-of-goal cutoff, run on the failure-aware data (the only source with the just-missed projects on the left of the line). The formal manipulation test (McCrary/rddensity) rejects a smooth density overwhelmingly (p ≈ 4×10⁻⁸⁶), which invalidates the design. For the record, the naive estimate of "barely funding → relaunching" is about −0.28 under a local-linear fit but a non-significant −0.10 under a local-quadratic one — exactly the instability you expect when the running variable is manipulated. What's robust is the smooth dose-response on both sides: more raised relative to goal predicts a higher chance of launching again.

[^market]: A few caveats. These are *funded*-project dollars (the survivor population the rich crawl captures), but dollar totals are the most capture-robust thing here — failed campaigns raise almost nothing, so the trend is trustworthy even where raw counts aren't. "Games" means Kickstarter's Games category — tabletop, video games, card games, and so on — not the whole platform; I can't line RPGs up against Film or Comics because I only kept the Games category. And a robustness note on the share itself: because the money is so concentrated, a single huge project can swing a year. The 2024 peak (~24%) is the clearest case — strip the top 1% of projects each year and the whole series falls to roughly 7% → 14%, which is why I describe it as a *doubling* rather than reading the raw 2024 number literally.

[^cleanlabels]: An earlier cut of this used a keyword classifier that mislabeled some board games, dice sets, and card games as "RPGs." Because the data is so dollar-skewed, a few of those swung the aggregates hard — *Darkest Dungeon: The Board Game*, a $3.9M card game, a $3.5M dice gadget and the like were about **13% of "RPG" dollars overall and 22% of the top 1%**. I tightened the classifier so board/card/video-game and accessory cues override a stray "RPG" mention (a game stays "RPG" only if its title actually says "roleplaying game" or it has real rulebook content); on the high-dollar tail it now agrees with hand-checking about **97%** of the time. Reassuringly, this barely moved the regression results — coefficients shrug off a handful of mislabels, and label noise mostly *attenuates* contrasts — but it did trim the dollar-share and concentration figures, which one big mislabel can distort. The share-of-gaming numbers above are post-cleanup.

[^goaltrend]: Among funded projects only, so read it as "goals among projects that made it," not the full population. Part of the decline is compositional — the post-2019 flood of small-goal zines drags the median down — and part is creators simply gravitating to modest, beatable goals as the norm.

[^fundingera]: Concretely: the Kaggle export carries project *names* (so I can pick out RPGs) but ends in early 2018, while the academic set reaches 2023 but masks names (so its RPG-level signal is borrowed, and its creator-history model is really an *all-tabletop* model). Either way, the "did it fund / what predicts funding" evidence is anchored in the 2010s and in tabletop broadly. The magnitude ("how much") side, by contrast, uses the 2014–2026 Web Robots crawl and is genuinely RPG-specific and current — so the time-scope caveat bites hardest on the funding-side claims, less on the dollars-side ones.
