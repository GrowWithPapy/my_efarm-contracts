# MECHANICS.md — My e-farm, full mechanics reconstruction

**Status: frozen at v1.0 on 2026-09-14**, together with ECONOMY.md v1.0. From here it
changes only by a versioned amendment. Under the v1.0 two-layer economy (ECONOMY §3.0b),
every in-game price in this document — Co-op produce and supplies, capital goods, the
loan, level thresholds, upkeep and the vet — is denominated in **coins**; land, bonds,
contests and champion auctions are ECU.

Sources read in full:
- Fan guide *Aide Myefarm* (2005): presentation, rules, levels 1–3, help L1/L2, the three
  market pages, farm-sitting, SOS, and the ten official level-3 design sheets ("fiches").
- 2024 revival (api.myefarm.net): general rules, coop rules, FAQ level 1 and level 2.
  The revival is a faithful-ish reconstruction with its own tuning; where it differs from
  the original I say so. Its Stripe monetisation is noted only as something we replace.
- Not recoverable: the original `myefarm.com/regles.php` (dead), exact Co-op price list,
  exact sickness probabilities, level 4–5 (never built). Those are marked **GAP** and
  followed by a proposed design value.

Tags: `[orig]` original 2004 game · `[rev]` 2024 revival · `[design]` our proposal.

Where the original and the revival gave conflicting rules, phase 0 picked one; those calls
are recorded inline (tick window §1, vet §2, rabbit reproduction §3.1, Co-op hours §7,
level-2 condition §6) and the reasoning is in `PLAN.md` §6. Conflicts not yet resolved are
still shown as both variants.

---

## 1. Daily cycle

- One server "day change" per night. The revival ran it 02:00–06:00 `[rev]` (original guides
  say "le passage", same idea); **ours is 03:00–05:00 server time** `[design]`, which the
  original Co-op opening hours (§7) already leave closed on both weekdays and weekends.
  Farm is locked during the tick. `[orig][rev]`
- At the tick: animals age, babies mature, eggs and milk not sold/incubated are **lost**,
  states reset (fed/watered/clean/healthy), random events roll (sickness, dirt), fields grow,
  constructions advance, rankings recompute (every 30 min for ranking `[orig]`). `[orig][rev]`
- Feed changes at level-up, so don't feed the day you move up. `[orig]`
- Actions cost either a stock item from the barn (feed bag, bucket, syringe, soap) or a
  per-animal cash price via the action buttons. `[orig][rev]`

Per-animal button prices `[rev]` (ECU): feed 0.3–0.6, water 0.3, treat 0.3–1.0, clean 0.3.
One stock item covers a whole unit: 1 feed bag = one mini-coop or mini-hutch. `[orig][rev]`

## 2. Animal states, sickness, hygiene

Every animal has four daily states: **fed, watered, clean, healthy**. `[orig][rev]`

- Only an animal that is fed, watered, clean and healthy produces (eggs, milk, litters). `[rev]`
- Dirty animals can fall sick and stop producing. `[rev]` Cow must be washed before 18:00 or
  there's no evening milk. `[orig]`
- Sick animals are treated with a syringe (button or stock) or by a **vet subscription**
  that auto-treats the whole farm at the tick. The subscription is **0.5 ECU per sick head
  per day**, ordered the day before during Co-op hours, and the fee goes to the Co-op
  reserve `[rev][design]`. The 30 ECU/day flat variant `[orig L2]` is dropped. Bees are not
  covered. `[rev]`
- Intensive tools bought on the Black Market (milking machine, electric shearer, duck lamps)
  raise disease risk and break down. `[orig L3]`
- Neglect kills: no room in an adult pen when babies mature → deaths `[rev]`; horses left to
  die give a daily negative-point malus until replaced and donated. `[orig L3]`

**GAP** — sickness and dirt probabilities were never published. `[design]`:

```
P(dirty_next_day)  = 0.15 + 0.10·density_ratio            # density_ratio = heads / pen_capacity
P(sick_next_day)   = 0.02 + 0.10·dirty + 0.08·unfed + 0.08·unwatered + 0.05·overcrowded
sick 3 consecutive days untreated → dies; sick animals produce 0
vet subscription = auto-treat at tick, 0.5 ECU per sick head per day (sink), never free
```

**Care capacity, and telling the player about it** `[design]`

One player can only look after so many animals. Care is 1.0 up to
`animals.care.full_care_head_count` head and `full_care_head_count / heads` above it,
floored at `animals.care.min_care`. Below care 0.5 a farm's sick animals are no longer
treated, so they run the three days to death.

**UI requirement.** The daily tick report must tell the player where they stand:

> "You can care for about **N** animals. You have **M**."

with `N` the head count at which care would fall below the expansion threshold
(`sim.agents.min_care_when_expanding`), and `M` the current head count. When `M > N`, say
so plainly and name the consequence — that sick animals will stop being treated.

This is not decoration. Simulation run 3 lost **eight ninths of all Co-op payouts** to
exactly this: farms reaching level 2 found their pen capacity quadrupled, bred towards it,
crossed the care cliff, and then lost a fifth of the herd a day while selling nothing.
The pens said yes and nothing said no. A player who can see both numbers stops expanding;
a player who cannot, does not — and neither did the simulated one until it was told the
same rule (`sim/world.py: care_head_ceiling`).

## 3. Species reference

### 3.1 Rabbits `[orig][rev]`
- Start: 8 babies, sex random at adulthood `[orig]` / 3 couples `[rev]`.
- Feed: basic feed bag (L1), wheat (L2); boosters carrots and salad. Water optional booster (L1).
- Reproduction `[orig][design]`: each fertile couple produces **one kit per day with
  probability `repro_rate`**, where `repro_rate = 0.40 base (wheat) + 0.10 water
  + 0.25 carrots + 0.25 salad`, capped at 1.0. The `[rev]` 0–2 litter is dropped — it
  double-counts the percentage. A couple is one adult male + one adult female in the same
  pen; a male can serve up to 3 females. This reproduces the veteran rule of thumb
  `[orig]`: 18 couples on wheat + water + carrots → `repro_rate` 0.75 → 13.5 ≈ 14 kits/day.
- Maturity: 5 days (D0–D4), adult on day 6. `[rev]`
- Pens: L1 one hutch, 50 max `[orig]`; L2 separate baby and adult hutches, 30 each `[rev]`
  or 50 with no hard cap on count `[orig]`. Optimal L2 layout `[orig]`: 3 baby hutches :
  2 adult hutches : 1 empty buffer for the daily sale.
- Sale: Co-op bought adults at a fixed 25 ECU `[orig]`.

### 3.2 Poultry `[orig][rev]`
- Start: 3 hens + 1 rooster (player memory, `[rev]`) — default for the rebuild. The 2005 guide
  describes 4 chicks that grew into 1 rooster + 3 hens `[orig, early]`; the starter evidently
  changed over the game's life.
- Early sale: chicks can be sold as chicks or raised and sold as adults `[orig L2]`; same for
  rabbit kits vs adults. Only layers can be sold, never brooding hens. `[rev]`
- Ratio: 1 rooster fertilises 5 hens `[orig]` / 3 hens `[rev]`; brooding hens don't need a rooster.
- Laying: 1 egg/hen/day `[orig]`, 0–2 `[rev]`, only if fed, watered, clean, healthy.
  Layers don't need water; brooders and chicks do. `[orig]`
- Eggs: sell same day or incubate, else lost. Incubation 3 days, chicks on day 4; hen switching
  brooder→layer skips a day. Chicks mature in 5 days; sex fixed at adulthood. `[rev]`
  Only incubate coops with ≥4–5 eggs. `[orig]`
- Caps: L1 50 hens + 10 roosters `[orig]` / 250 + 50 `[rev]`. L2 unlimited mini-coops,
  auto-created as birds arrive `[orig]`; 75 hens + 25 roosters per adult coop, 50 per chick coop `[rev]`.
- Feed: basic feed bag (L1), corn (L2).

### 3.3 Cow `[orig][rev]`
- Adult at 10 days / 80 kg. Adult cow needs no feed or water `[orig L2]`; `[rev]` still needs care.
- Milk daily, 5–10 L `[rev]`; unsold milk lost at tick. 12 L → 1 butter `[orig]` / 5 L `[rev]`.
- L3: herd with heat cycle — heat 3 days (choose to breed), gestation 6 days, rest 10 days
  (milking period), calf adult in 4 days, 1 bull per 4 cows, one calf per cow; whole herd
  synchronised. Manure = natural fertiliser. Rested cows and bulls sellable to Co-op (seeds new
  L1 players) or livestock market. `[orig L3]`

### 3.4 Sheep `[orig][rev]`
- L2 gift. Adult at 8 days / 30 kg; needs feed (straw) and water until adult, then only cleaning.
- Wool 2 cm/day, 3 with salad, stops at 20 cm; Co-op 8 ECU/cm. L2 objective: sell 2 m. `[orig]`
- L3: ewe/ram cycle — heat 2 days, gestation 4 days, rest 3 days, 1–3 lambs, adult in 4 days,
  1 ram per 2 ewes; ewe milk daily → sheep cheese. `[orig L3]`

### 3.5 Level-3 species `[orig L3, design sheets]`
- **Horses**: stallion/mare, 3 coat colours, pen capped at 3 head; foals must be donated to a
  riding centre (tracked list); manure only; bonus points while healthy, daily malus if dead.
- **Ducks**: like poultry with own incubation and ratio; free-range or battery; battery + special
  feed mix + age/weight constraints → foie gras (females only), magret; free-range → terrines.
- **Bees** `[rev]`: apiary of 3 hives, one queen each; fed syrup (mixer), treated with syringes,
  cleaned with soap; +4 % field yield per hive.

## 4. Buildings, capacity, storage

| Item | Level | Cost / time | Effect | Tag |
|---|---|---|---|---|
| Hutch or mini-hutch | 2 | 600 ECU / 2 d (craftsman) or 400 / 3 d (DIY) | +1 pen | orig, rev |
| Mini-coop | 2 | free, auto-created | +1 pen | orig |
| Well | 2 | 500 ECU / 3 d | 6 buckets/day | orig, rev |
| Barn (remise) expansion | 2 | 2,000 / 5 d or 1,500 / 7 d; only 25 slots during works | +15 slots | orig |
| Barn slots `[rev]` | 1→2 | 10 (L1) → 15 → 30 → 65 | storage | rev |
| Van | 2 | 2,000 ECU | 18 → 36 purchase trips/day | orig |
| Harvester | 2 | 2,500 ECU (+upgrades) | harvest 2 d → 1 d, more sacks; one field at a time | orig, rev |
| Feed mixer | 2 | Co-op | 1 wheat + 1 corn + 1 water + 1 butter + 1 carrots → 8 feed bags | orig |
| Cheese machine | 3 | Co-op | cow/sheep milk → cheese | orig L3 |
| Silos, fuel tanks, cold room | 3 | Co-op | typed bulk storage; cold room needs fuel, breaks down | orig L3 |
| Common barns | 3 | on level-up, fee | animals grouped per species, not per pen | orig L3 |

Storage matters: harvests, deliveries and lottery wins go to the barn; overflow is lost. `[rev]`
Speculation needs slots — the +15 expansion was called "not negligible when you speculate". `[orig]`

## 5. Crops `[orig][rev]`

| Crop | Seed cost | Growth | Harvest | Yield |
|---|---|---|---|---|
| Wheat field | 200 | 4 d fertilised / 6 d | 1 d harvester / 2 d hand | 20 wheat + 10 straw (18 + 7 by hand) |
| Corn field | 100 (+50 fertiliser `[orig]`) | 3 d / 4 d | 1 d / 2 d | 15 corn (12 by hand) |
| Carrot patch | 15 | 4 d | — | 4 crates |
| Salad patch | 20 | 3 d | — | 3 crates |

- Ripe crops must be harvested within 2 days or are lost. `[rev]`
- Soil boosters `[rev]`: enriched compost ×1.5, premium manure ×2, super humus ×3, fallow 2 days.
- L3 `[orig]`: unlimited fields, consolidated into one large field per crop, machine sowing,
  industrial vs natural fertiliser, partial sowing, sunlight needed to trigger harvest, rain or
  fuel-driven pump irrigation, continuous harvest bars.
- Who eats what: wheat → rabbits; corn → poultry; straw → sheep, cow; carrots → rabbit booster
  and feed recipe; salad → rabbit and sheep booster; butter → feed recipe only. `[rev]`

## 6. Levels and objectives

| Level | Start kit | Objective | Tag |
|---|---|---|---|
| 1 | 3 hens + 1 rooster (4 chicks in the 2005 guide), 8 kits, 1 cow, 300 ECU, 1,500 loan, 12 trips/day | Reach 2,000 ECU, then repay the 1,500 loan — repayment is gated on balance ≥ 2,000, and level 2 is granted at repayment (ECONOMY §7) | orig |
| 1 `[rev]` | 3 hens, 1 rooster, 3 rabbit couples, 1 cow, 300 ECU | 10,000 ECU to the Co-op, 3 public orders, 50 L milk sold | rev |
| 2 | + sheep, 1 field, 2 patches, machine, transport, well, vet; barn/coop/hutch expansion; butter, wool | Sell 2 m wool and hold > 20,000 ECU | orig |
| 3 | + horse, 2 fields, 1 patch, flower field, crop rotation, common barns | Obtain the organic label; meet production quotas over ~6 months | orig (design sheets) |
| 3 `[rev]` | — | 130 days played, 200,000 ECU repaid, 600,000 capital, 10 public orders, voted 3× | rev |
| 4–5 | never built | — | orig |

Veteran advice: don't leave level 1 before ~10,000 ECU. `[orig][rev]`

## 7. Markets (summary — pricing maths live in ECONOMY.md)

- **Co-op** `[orig]`: site-fed, fixed prices both ways, buy-only for supplies and animals,
  36 purchases/day cap (level-dependent). **Opening hours — the original ones are canonical
  for the rebuild** (§12.8): weekdays 05–14, 17–20, 22–03; weekends 09–14, 19–03, server
  time. The `[rev]` schedule (06–09, 12–15, 19–22, 10 purchases per opening at L1, 100 at
  L2, animal buy-back prices varying day to day) is recorded for reference only and is
  **not** what we build; pricing comes from ECONOMY §3 instead of a fixed list.
- **Farmers' Market** `[orig]`: player supply only, list at any price under a shown ceiling,
  24/7, buys count against the trip cap, +commerce points on both sides. Rabbit price dipped
  to ~8 ECU around 22:30 vs 25 at the Co-op → the classic arbitrage.
- **Black Market** `[orig]`: sell high, buy higher, price re-rolled every minute with brutal
  swings, cheapest ~05:00, negative points, gifts sellable up to 300 ECU. L3 adds shady
  vendors of fragile yield tools.
- **Auction room** `[rev]`: post a buy request; other farmers may accept.
- **Livestock market** `[orig L3]`: Wednesdays and Sundays only, register the day before,
  rested cows/ewes/horses only, animals presented stop producing; a showcase for big producers.
- **Level-3 market segregation** `[orig L3]`: L3 farmers trade on their own market; sacks let
  them trade with L1/L2; anti-monopoly quotas on sacks and on share of listed goods.
- **Deliveries** `[orig L3]`: order feed, water, fuel the day before → truck at 05:00;
  express same-day at a mark-up; exposure to strikes and incidents.

## 8. Ranking `[orig]`

Points from: commerce (Farmers' Market buy and sell), production (harvest, patches, eggs sold,
poultry sold, rabbits sold, milking, shearing), and balance. Black Market trades give negative
points. Recomputed every 30 min. `[rev]` adds weekly rankings, "competitors of the week",
a cumulative weekly palmarès, and sales statistics per farmer.

## 9. Community systems

- **Farm-sitting** `[orig]`: volunteer sitters of various levels run your farm while you're away
  so you don't have to hibernate; recruited on character; external site farm-sitting.com.
- **Hibernation** `[orig]`: freeze the account instead of letting animals die.
- **SOS farm in distress** `[orig]`: approved volunteers take over a struggling farm for a few
  days, stabilise it, then teach the owner.
- **Public orders** `[rev]`: institutional bulk orders (restaurants, neighbouring countries)
  that need several farmers; max 2 per week; gated by capitalisation; required for level-up.
- **Town Hall** `[rev]`: mayor elected for 10 days every 15; four pillars (hospital, police,
  leisure, school) to balance; residents' mood falls if a pillar collapses or dominates.
- **Bank** `[rev]`: loans 100–10,000 ECU with interest; savings account.
- **Lottery** `[rev]`: one free daily spin (water, animals, ECU); extra spins for cash.
- Gifts on birthdays and holidays (Easter, Halloween, Christmas): keep in the office collection,
  sell on the Black Market ≤ 300, or discard. `[orig]`

## 10. Level-3 "industrial" design principles `[orig, design sheets]`

Worth keeping verbatim in spirit — this is where the original's designers were going:

- Story: market glut, "it's the crisis" → mass production is the only way through.
- Animals managed per species as one unit; states shown as percentage bars (satiety, hydration,
  cleanliness, health) indexed on head count and items supplied.
- **Uncertainty band**: with 700 hens fed to 60 %, individual care would guarantee 420 fed;
  bulk care yields 380–420. At 90 % the band narrows to 610–630. Higher care % → fewer surprises.
- Machines need **fuel** (ordered from the Co-op); intensive use causes **breakdowns** needing a
  technician. Cold-room compressor is the most fragile.
- Incidents and breakdowns model the farmer's lost attention.
- Diversify to survive: horses, ducks, cattle, sheep, each with its own cycle and feed.

## 11. What the revival monetises with cash `[rev]` — and what we do instead `[design]`

| Revival (Stripe) | Ours |
|---|---|
| Extra Co-op purchases | Vehicles bought in ECU raise the trip cap (van, truck) |
| Unlimited barn storage | Barn expansions in ECU, burned |
| Bigger hutches (100/150) | Pen upgrades in ECU, burned |
| Extra cows | Bought at Co-op or Farmers' Market in ECU |
| Extra lottery spins | Daily spin only; contest entries paid in ECU to Town Hall |

No cash shortcuts: every convenience is an ECU sink, which is what keeps the token economy honest.

## 12. Deltas to apply to ECONOMY.md

Items 1, 2 and 4 are **applied** in ECONOMY v0.2; the rest are still pending.

1. ✅ Add **sickness and vet** as a daily sink: vet subscription priced per sick head
   (0.5 ECU), ordered the day before during Co-op hours, fee to the Co-op reserve; syringes
   at the Co-op; sick animals produce nothing (§2 formula).
2. ✅ Add **capacity as sinks**: pens (400/600), barn expansions (1,500/2,000), well (500),
   van (2,000), harvester (2,500) — all burned, not paid to the Co-op reserve. Generalised
   in ECONOMY §3.5 as the consumables-and-services vs capital-goods split: recurring spend
   recycles into the reserve, one-off capacity purchases are burned.
3. Production rates for `P_ref` tuning: hens 0–2 eggs/day, rabbits 0–2 kits per couple/day,
   cow 5–10 L/day, sheep 2–3 cm/day; eggs and milk perish at the tick (so Co-op inventory of
   eggs and milk must also decay).
4. ✅ **Public orders** become the Co-op's demand shock mechanism: a bulk order temporarily
   raises `c_g` (NPC demand) for that good, pulling `P_buy` up for 48 h, then it normalises.
   Scheduling: game-side public orders land in **phase 1b**, after the first gate results.
   For phase 1 they exist **only in the simulator** — every 2–4 days, one good, `c_g` × 2–3
   for 48 h, schedule and multiplier in `economy.yaml` (ECONOMY §9).
5. Add the **livestock market** (Wed/Sun, register the day before, rested animals only) as a
   third P2P venue for large animals — this is the natural home for animal NFTs.
6. Add a **Level-3 fuel and breakdown** sink: fuel ordered from the Co-op, technician fees, all
   ECU, all burned.
7. Track **cleanliness density**: overcrowded pens raise dirt and sickness (§2), which makes
   bot farms that stack animals pay for it.
8. ✅ Keep the original **trip caps** and **opening hours** exactly; they are the anti-spam
   layer the original relied on and players remember them. Hours are now stated once, in
   §7 and ECONOMY §3.4, as weekdays 05–14 / 17–20 / 22–03 and weekends 09–14 / 19–03.
9. ✅ Add **risk scoring** (ECONOMY §11) as the sybil layer the trip caps assume: trips make
   bot scaling linear in *farms*, so something has to make farms expensive. 0–100 score,
   shadow at 40, challenge at 70, frozen at 90.
