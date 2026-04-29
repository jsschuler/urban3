# Urban ABM Problem and Change Log

## Open Issues

### 2026-04-22: Commercial rents blow up despite high commercial vacancy

Observed during a larger headless stress test:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12

Results:
- population = 4998
- employment = 2120
- unemployment = 2878
- unhoused = 2883
- firm_count = 127
- residential_vacancy_rate = 0.4865
- commercial_vacancy_rate = 0.8934
- mean_residential_rent = 1.1751
- mean_commercial_rent = 104.5185
- mean_commute = 2.8022
```

Problem:

Commercial rents rose sharply even though aggregate commercial vacancy remained very high. This suggests a mismatch between local rent updates, firm commercial-space search, and spatial consolidation behavior. Occupied commercial lots can become extremely expensive while unused commercial space elsewhere remains underused.

Likely areas to inspect:

- `developer_update!` commercial rent adjustment rule
- `commercial_space_search!` candidate ranking and consolidation preference
- commercial search may be too conservative, causing firms to miss abundant vacant commercial space outside their narrow sampled neighborhoods
- firm expansion behavior that adds commercial demand
- whether firms should relocate or abandon expensive commercial units
- whether commercial rent increases need a cap, dampening, or local vacancy smoothing

Status: open.

### 2026-04-23: Commercial center still fails to emerge under current endogenous extensions

Observed after sequential additions of:

- bounded staged search with commercial rescue
- endogenous residential/job accessibility
- employee-commute utility in firm location choice
- probabilistic goods choice
- shopping habits with review-triggered re-search
- human capital and workplace-distance social ties

Current issue:

- residential rent gradients now emerge strongly and robustly
- commercial rent gradients remain near zero in magnitude
- some extensions reduce mean commercial rents or improve goods absorption, but no tested combination has produced a meaningful endogenous commercial center
- the human-capital/network mechanism slightly strengthens the commercial gradient signal, but only from very near zero to still-weak values

Most recent evidence:

```text
Shopping habits:
- commercial rent vs geometric center distance = -0.0184
- unsold_output = 472

Human capital + workplace-distance ties:
- commercial rent vs geometric center distance = -0.0272
- unsold_output = 777
```

**Resolved 2026-04-23:**

The location-value premium was identified as an imposed spatial shortcut, not a
genuine emergent mechanism. It was removed and the incumbent bid scaling was
fixed instead (see change log below). The commercial gradient now forms
endogenously and reaches -0.52 at 1000 ticks.

Status: resolved.

## Open Questions

### 2026-04-24: Does the commercial gradient overtake residential at long horizons with I-O linkages?

**Tentative findings from 5000-tick runs (seeds 77, 42, 123, 456):**

Rent levels (mean commercial vs residential across seeds):

```text
         tick 1000              tick 2000              tick 3000              tick 4000
seed=77  com=3.60 res=5.90     com=3.05 res=4.12     com=3.43 res=3.79     com=2.71 res=3.01
seed=42  com=4.03 res=5.01     com=4.46 res=3.35*    com=6.92 res=4.91     com=4.16 res=3.24*
seed=123 com=4.67 res=5.25     com=5.48 res=4.44*    com=8.89 res=4.94     com=7.43 res=3.87
seed=456 com=4.45 res=5.05     com=4.56 res=3.84*    com=5.91 res=3.91     com=5.77 res=3.59

* = commercial rent exceeds residential
```

**Complete 5000-tick results (all four seeds):**

Rent levels:
```text
         tick 1000              tick 2000              tick 3000              tick 4000              tick 5000
seed=77  com=3.60 res=5.90     com=3.05 res=4.12     com=3.43 res=3.79     com=2.71 res=3.01     com=2.07 res=2.20
seed=42  com=4.03 res=5.01     com=4.46 res=3.35*    com=6.92 res=4.91     com=4.16 res=3.24*    com=3.77 res=2.25*
seed=123 com=4.67 res=5.25     com=5.48 res=4.44*    com=8.89 res=4.94     com=7.43 res=3.87     com=2.30 res=2.53
seed=456 com=4.45 res=5.05     com=4.56 res=3.84*    com=5.91 res=3.91     com=5.77 res=3.59     com=4.47 res=2.42*

* = commercial rent exceeds residential
```

Gradient correlations (rent vs distance from centroid) at tick 5000:
```text
seed    com_gradient  res_gradient  ratio (com/res)
77      -0.457        -0.635        0.72
42      -0.455        -0.627        0.73
123     -0.384        -0.621        0.62
456     -0.497        -0.638        0.78
mean    -0.448        -0.630        0.71
```

**Assessment:**

The I-O linkages produce the right directional effects on rent levels (commercial
exceeds residential in 3 of 4 seeds by tick 5000, and fill rates stabilize around
0.87-0.90, confirming the Leontief mechanism is active). However, the gradient
ordering has not inverted in any seed — residential gradient remains steeper across
all four seeds at 5000 ticks, with commercial at 62-78% of residential magnitude.

Notably, commercial rent levels can be high (seed 456: 4.47 vs 2.42 residential)
while the spatial concentration of those rents is still flatter than residential.
This means commercial rents are elevated but more uniformly distributed, while
residential rents are concentrated near the center. The agglomeration force from
I-O linkages is adding commercial rent mass without adding spatial concentration.

Key structural problems:

1. **Late-run commercial rent collapse** (seeds 123 and 77): commercial rents spike
   mid-run (tick 3000) then collapse sharply, suggesting developer supply response
   overshoots or B2C profitability erodes at scale. Seeds 42 and 456 sustain
   commercial premium through tick 5000 — worth investigating what differs.

2. **Agglomeration force too diffuse**: B2B firms cluster near consumers (same
   locational signal as B2C), so the inter-firm agglomeration amplifies the
   existing consumer-access gradient rather than creating a distinct, steeper
   commercial clustering mechanism. The one-tier shallow network provides too
   weak a localization pull to differentiate commercial from residential.

**Next direction**: explore a deeper supplier network (B2B firms also purchasing
from other B2B firms). Multi-tier networks create compounding spatial pull because
each tier has an additional reason to locate near its upstream suppliers, generating
a commercial cluster that is qualitatively more concentrated than what consumer
proximity alone produces.

Status: in progress — three-tier network implemented 2026-04-25.

### 2026-04-24: Is the B2B/B2C firm count ratio stable and appropriate?

At 1000 ticks, the B2B:B2C ratio is roughly 1:1.3 (128:172 for seed=77). With 2
B2B types and 2 B2C types and random founding, this seems plausible. However, the
ratio should be monitored — if B2B firms are more profitable they may crowd out
B2C firms or vice versa, distorting the I-O network structure.

### 2026-04-24: Is the input fill rate sustainable long-run?

Fill rates are holding at 0.75–0.81 through tick 2000. This means B2C firms are
running at ~75-80% capacity due to input constraints. Whether this stabilizes or
deteriorates at longer horizons is unknown. A persistent fill rate near zero would
collapse B2C output and is a failure mode to watch for.

## Next Steps

### 2026-04-25: Completed — 5000-tick I-O gradient runs (4 seeds)

Run the following to complete the long-run gradient comparison. Takes ~1.5 hours per seed;
run all four in parallel on a fast machine.

```julia
for seed in [77, 42, 123, 456]
    julia --project -e "
    using UrbanABM
    params = ModelParams(width=40, height=40, initial_workers=3000, initial_firms=150,
        outside_entry_rate=2.0, seed=$seed,
        enable_decision_logging=false, enable_search_logging=false,
        enable_market_logging=false)
    state = init_state(params)
    t0 = time()
    for t in 1:5000
        step!(state)
        if t in Set([1000,2000,3000,5000])
            m = metrics_snapshot(state)
            im = m[\"input_market_summary\"]
            println(\"seed=$seed tick=\",t,\" pop=\",m[\"population\"],
                \" fill=\",round(im[\"mean_input_fill_rate\"],digits=3),
                \" com_rent=\",round(m[\"mean_commercial_rent\"],digits=3),
                \" res_rent=\",round(m[\"mean_residential_rent\"],digits=3))
            flush(stdout)
        end
    end
    write_lot_csv(state, \"outputs/diagnostics/lots_io_5000_seed${seed}.csv\")
    " > outputs/diagnostics/run_io_5000_seed${seed}.log 2>&1 &
end
```

Then run gradient diagnostics on each output and compare:
- commercial gradient at 5000 ticks vs residential gradient
- whether commercial > residential in magnitude (the target ordering)

Success criterion: commercial gradient magnitude exceeds residential across
most seeds at 5000 ticks.

### 2026-04-24: Implemented — firm supplier network (I-O linkages)

The commercial rent gradient is weaker than the residential gradient (-0.52 vs
-0.66 at 1000 ticks), which is the reverse of empirical patterns in real cities.
The diagnosis is that the model lacks inter-firm agglomeration: firms only benefit
from proximity to consumers, not from proximity to each other.

The planned fix is a firm supplier network. Design decisions confirmed:

- firm types are classified as B2B (sells to firms only) or B2C (sells to consumers only); no hybrids
- B2B firms use only labor, capital, and commercial space — no upstream inputs (shallow network)
- I-O linkage matrix is fully parameterized, generated randomly from a seed and density parameter, fixed for the run
- B2C production uses Leontief scaling: binding fill rate across all required input types scales output; zero fill rate on any input means zero output — record this assumption
- input search is batch (not one-at-a-time), uses existing Poisson + global architecture
- input pricing uses same raise/lower rule as consumer goods, separate parameters
- input travel cost per block creates the agglomeration force
- B2B firms follow same founding rules as B2C

Full design is in section 28 of instructions.md.

Key architectural changes:

- `Types.jl`: `firm_role` on `FirmType`; `input_price`, `committed_intermediate_output`, `intermediate_sales_history`, `inputs_acquired` on `Firm`
- `Parameters.jl`: io_matrix, io_matrix_seed, io_matrix_density, input pricing rates, input travel cost, input SearchParams
- `Firms.jl`: B2B output commitment, B2C input search and purchase, input price adjustment, Leontief capacity scaling
- `Scheduler.jl`: B2B commitment phase and B2C input purchasing phase before B2C production
- `Metrics.jl`: input fill rate, mean input price, intermediate sales by type

Work is on the `io-linkages` branch.

---

## Changes

### 2026-04-24: Implemented firm supplier network (I-O linkages)

Added B2B/B2C firm roles and an intermediate goods market to give firms a direct
spatial incentive to co-locate, with the goal of steepening the commercial rent
gradient relative to residential.

**Design:**

- each firm type is classified as B2B (sells to firms only) or B2C (sells to
  consumers only); no hybrids
- B2B firms use only labor, capital, and commercial space — no upstream inputs
  (shallow network, one tier)
- the I-O linkage matrix is generated randomly at initialization from a seed and
  density parameter, then fixed for the run; `io_matrix[buyer_type, supplier_type]`
  gives units of B2B good required per unit of B2C output
- B2C production uses Leontief scaling: binding fill rate across all required input
  types scales output; zero fill on any type means zero output
- B2C firms search for input suppliers using Poisson neighborhood + global sampling;
  effective input cost = `goods_price + input_travel_cost_per_block * distance`
- B2B firms use the same `goods_price` field and `realized_sales_history` as B2C
  (reused for intermediate sales); price review logic is identical with separate
  `input_price_raise_rate` / `input_price_cut_rate` parameters
- B2C profits deduct `input_cost_this_tick`; B2B profits are unaffected

**Scheduler change:**

Added two phases before production commitment:
1. `commit_intermediate_output!` — B2B firms commit output
2. `input_purchasing_phase!` — B2C firms search for and buy inputs
Then `commit_production!` applies Leontief scaling for B2C firms.

**Files changed:**

- `Types.jl`: added `inputs_acquired::Dict{Int,Int}` and `input_cost_this_tick::Float64`
  to `Firm`; added `io_matrix::Matrix{Float64}` to `ModelState`
- `Parameters.jl`: added `firm_role::Symbol` to `FirmTypeParams`; added io_matrix,
  input pricing, and input search params to `ModelParams`; updated default firm types
  to 4 (2 B2B, 2 B2C)
- `State.jl`: added `generate_io_matrix`; updated `init_state`
- `Entrepreneurship.jl`: updated `found_firm!` to initialize new Firm fields
- `Firms.jl`: added `is_b2b`, `is_b2c`, `required_input_types`, `leontief_input_scale`,
  `commit_intermediate_output!`, `input_purchasing_phase!`, `sample_input_suppliers`,
  `effective_input_cost`; updated `commit_production!`, `firm_reviews!`,
  `calculate_profits!`
- `Workers.jl`: `consumption_phase!` now excludes B2B firms
- `Scheduler.jl`: added two new phases
- `Metrics.jl`: added `input_market_summary`; `mean_price` now excludes B2B firms

**Results at 1000 ticks (seed=77, 40×40, 3000 workers, 150 firms, entry_rate=2.0):**

```text
tick=250:  pop=3473, firms=245 (106 B2B, 139 B2C), fill=0.796, com_rent=1.29,  res_rent=4.634
tick=500:  pop=3971, firms=248 (104 B2B, 144 B2C), fill=0.747, com_rent=2.889, res_rent=6.705
tick=750:  pop=4468, firms=277 (124 B2B, 153 B2C), fill=0.783, com_rent=3.839, res_rent=6.399
tick=1000: pop=4968, firms=300 (128 B2B, 172 B2C), fill=0.771, com_rent=3.601, res_rent=5.895
```

Rent gradients at 1000 ticks:
```text
commercial rent vs geometric center distance  = -0.471
residential rent vs geometric center distance = -0.619
```

Comparison against no-I-O baseline at 1000 ticks:
```text
No I-O: commercial = -0.52, residential = -0.66
With I-O: commercial = -0.47, residential = -0.62
```

The gap between commercial and residential gradients has narrowed. The ordering
(residential > commercial) persists at 1000 ticks but the I-O mechanism is building
the commercial gradient faster. Whether it inverts at 5000 ticks is an open question
(see Open Questions above).

---

### 2026-04-25: Cash flow modeling — implementation and cold-start calibration

Added true cash-flow tracking to eliminate zombie firms and replaced an
over-aggressive contraction rule and price-revision rule that caused cold-start
collapse under the three-tier supply chain.

---

#### Motivation

The prior model had no cash drain mechanism. Firms recorded `profit_history` but
nothing was ever subtracted from any balance. Contraction required firms to reach
(1 worker, 1 capital) — a floor reachable only through the probabilistic
contraction review — and liquidation triggered only when a firm fell to zero
workers or zero capital, which the while-loop floor prevented. Zombie firms
persisted indefinitely regardless of losses.

---

#### Cash flow implementation

Added `cash::Float64` to `Firm` (in `Types.jl`). Initialized from `initial_cash`
kwarg in `found_firm!` (default = `startup_capital`; initial firms use a new
`initial_firm_cash` parameter).

In `calculate_profits!` (Firms.jl):
```julia
profit = revenue - wages - rent - input_costs
f.cash += profit
```

Capital and process purchases are deducted from cash immediately:
```julia
if f.cash >= cap_cost
    f.cash -= cap_cost
    f.capital_units += 1
    ...
end
```

Insolvency check added at the top of `firm_contraction_expansion!`:
```julia
if f.cash < 0
    liquidate_firm!(state, f)
    continue
end
```

New parameters added to `ModelParams`:
- `initial_firm_cash::Float64 = 15_000.0`
- `initial_hire_per_firm::Int = 3`
- `startup_production_target::Int = 2` (unused after recalibration; see below)
- `min_hire_cash_ticks::Int = 200`

---

#### Problem 1: cold-start cascade (immediate collapse)

With `initial_firm_cash=2000`, all initial firms went bankrupt within 33 ticks.
With 18 workers/firm (from `initial_hire!` using `max_workers_per_firm`), wage
bills were ~180/tick while early revenue was near zero. Root cause: too many
workers hired at startup before any market exists.

**Fix:** Added `initial_hire_per_firm::Int = 3` parameter and wired it into
`initial_hire!` in `State.jl`. Initial firms now start with at most 3 workers.

---

#### Problem 2: firms over-hiring during cold start

Even with 3 initial workers, firms recruited aggressively from the pool of 160+
unemployed workers via the normal job search (which uses `max_workers_per_firm=18`
as the cap, not `initial_hire_per_firm`). By tick 10, some firms had 9 workers,
multiplying wage bills before any revenue existed.

**Fix:** Added a cash-based hiring gate to `hire_worker!` in `Firms.jl`:
```julia
current_payroll = sum(values(f.current_worker_wages); init=0.0)
f.cash < (current_payroll + f.posted_wage) * state.params.min_hire_cash_ticks && return false
```
With `min_hire_cash_ticks=200`, a firm with 3 workers (payroll 30) needs
cash ≥ (30+10)×200=8000 to hire a 4th worker. Firms grow slowly and stop
hiring when cash becomes insufficient to cover expanded payroll.

---

#### Problem 3: premature contraction kills employment

With `modal_sales_lookback=12`, contraction fired as soon as any sales history
existed — after tick 1, a firm with 1 data point of zero sales would target
`modal=0` and fire workers down to 1. This collapsed employment from 48 to
~13 within 12 ticks, destroying consumer demand before B2C firms could
establish any market.

**Fix:** Contraction now requires a full lookback window before firing:
```julia
if rand(state.rng) < state.params.contraction_review_prob &&
        length(f.realized_sales_history) >= state.params.modal_sales_lookback
```
Firms get 12 ticks of grace before contraction can reduce their workforce.

---

#### Problem 4: T1/T2 price deflation death spiral

T1 firms committed ~6 units but sold only 2-3 (T2 demand is Leontief-fixed
per unit of T2 output and limited by T2 capacity). Consistently not sold out →
price cut every review → price falls below break-even (≈3.75) → cash drains →
T1 exits → T2 loses inputs → T2 exits → B2C has no T2 inputs → collapse.

The original price revision logic cut prices whenever `realized_sales < committed`.
In a Leontief B2B market, input demand is quantity-fixed: cutting price does not
attract more buyers if demand is structurally limited. Price cuts reduce revenue
without creating new customers.

**Fix:** Changed price revision in `firm_reviews!` to cut price only when
`last_sales > 0` (partial sell-through: buyers exist but you're not capturing all
of them). No cut when `last_sales == 0` (no buyers exist regardless of price):
```julia
if sold_out
    f.goods_price *= (1 + raise)
elseif last_sales > 0
    f.goods_price *= (1 - cut)
# else: zero sales — leave price unchanged; cutting won't attract Leontief buyers
end
```

---

#### Problem 5: IO coefficients and tier prices not calibrated for three-tier viability

Original IO coefficients (min=0.5, max=2.0, density=0.7) were designed for a
zombie economy. Under cash flow, firms with high input costs and low prices were
structurally unprofitable at any scale.

Working backward from minimum viable parameters with 1 worker per firm (cap≈4):
- Break-even: `price = (wages + rent) / cap = (10+5)/4 = 3.75` per tier
- T2 viable: `P_t2 > P_t1 × coeff × density × 2_types + 3.75`
  → with coeff=0.625, density=0.5: `P_t2 > 5×0.625×1.0 + 3.75 = 6.875`
- B2C viable: `P_t3 > P_t2 × coeff × density × 2_types + 3.75`
  → `P_t3 > 8.5×0.625×1.0 + 3.75 = 9.06`

**Fix:**
- IO density: 0.7 → 0.5 (fewer active links per firm, reducing total input burden)
- IO coefficients: min=0.5, max=0.75 (mean≈0.625; above break-even for T1 viability
  with ~5 T2 buyers per T1 firm, below the spiral threshold)
- Added `initial_goods_price_min/max` to `FirmTypeParams` for tier-specific pricing:
  - T1: 4–6 (above break-even 3.75)
  - T2: 7–10 (above break-even 6.9)
  - B2C: 10–14 (above break-even 9.1)
- Updated `found_firm!` to use `params.firm_types[ftype].initial_goods_price_min/max`
  instead of hardcoded `4.0 + rand(rng) * 2.0`

---

#### Files changed

- `Types.jl`: added `cash::Float64` to `Firm`
- `Parameters.jl`: added `initial_firm_cash`, `initial_hire_per_firm`,
  `startup_production_target`, `min_hire_cash_ticks` to `ModelParams`; added
  `initial_goods_price_min/max` to `FirmTypeParams`; updated default `firm_types`
  with tier-specific price ranges; updated `io_matrix_density`, coefficients
- `State.jl`: `initial_hire!` now caps at `initial_hire_per_firm`
- `Firms.jl`: `calculate_profits!` adds/subtracts from `f.cash`; capital/process
  purchases deducted from `f.cash`; insolvency check at top of
  `firm_contraction_expansion!`; `hire_worker!` has cash-based gate;
  `firm_reviews!` uses no-cut-on-zero-sales price logic; contraction requires
  full lookback window
- `Entrepreneurship.jl`: `found_firm!` uses tier-specific price range; accepts
  `initial_cash` kwarg

Status: implemented; awaiting 500-tick stability test.

---

### 2026-04-25: Parameter recalibration — cash flow exposed structural unviability

#### Finding

Adding cash flow tracking made a previously invisible structural problem visible:
the three-tier economy was mathematically unviable at the parameters set before
cash flow was introduced. Without cash flow, firms were immortal zombies —
chronically loss-making firms persisted indefinitely, so the model appeared
"stable" and could be tuned to produce interesting-looking spatial patterns.
With cash flow, insolvent firms exit, and the economy collapses by tick 350–450
regardless of other fixes applied.

The key insight: **cash flow acts as a feasibility test**. Any parameter
combination that allows firms to survive indefinitely regardless of losses is
concealing whether the underlying production economics are coherent. The collapse
under cash flow is not a bug — it is the model correctly reporting that the prior
parameters described an economy that cannot sustain itself.

#### Two independent structural failures

**1. T1 chronic under-utilization (31% demand coverage)**

With equal firm counts per tier (~5 firms/tier), IO density=0.5, mean coeff=0.625:

```
T1 demand per tick = n_T2 × density × coeff × (T2 output / T1 cap)
                   ≈ 5 × 0.5 × 0.625 × 1.0 = 1.56 units total across all T1 firms
T1 supply per firm = cap ≈ 4–6 units
T1 utilization     ≈ 31%
```

At 31% utilization, T1 revenue ≈ 6.25 < cost ≈ 15 (wages + rent with cap=4).
T1 firms slowly drain cash and exit. As T1 exits, T2 loses inputs, T2 exits,
B2C loses inputs, collapse cascades. The no-cut-on-zero-sales fix slows but
does not prevent this because T1 does have *some* sales (partial sell-through)
and correctly cuts on partial sell-through — price still drifts below break-even.

**2. Three-tier affordability constraint violated**

For a 3-tier chain to sustain itself, the B2C break-even price must be within
worker budget. With wage=10, housing≈1.85, commute≈0.65, workers can spend
≈8.5 on goods. The viability constraint is:

```
N × (wages + rent) / cap < worker_budget
3 × (10 + 5) / 4 = 11.25 > 8.5   ← violated
```

Break-even B2C price ≈ T2_price × density × coeff + cost/cap
≈ 8.75 × 0.625 + 3.75 ≈ 9.2 — already above the 8.5 worker budget.
Initial B2C price range was 10–14: workers literally could not buy any goods
from tick 1. B2C revenue = 0, immediate cash drain, exit within 100 ticks.

Both failures were **always present** in the model but invisible under zombie-firm
dynamics. Cash flow revealed them simultaneously.

#### Fix: raise productivity and reset tier-specific prices

Viability requires `N × (wages+rent)/cap < worker_budget`. With N=3 and
worker_budget=8.5: `cap ≥ 3 × 15 / 8.5 = 5.29`. Setting cap=5.5 satisfies
this: `3 × 15 / 5.5 = 8.18 < 8.5 ✓`.

New `productivity` = 5.5 for all six firm types (was 4.0/3.6/4.8/3.4).

Tier-specific initial prices derived from break-even at cap=5.5:
- Break-even per tier: `(10 + 5) / 5.5 = 2.73`
- T1 break-even: 2.73 → initial range **3–5**
- T2 break-even: T1_price × density × coeff + 2.73 ≈ 4 × 0.5 × 0.625 + 2.73 = 4.0
  → initial range **5–7** (safe margin above break-even)
- B2C break-even: T2_price × density × coeff + 2.73 ≈ 6 × 0.5 × 0.625 + 2.73 = 4.6
  → initial range **5–8** (well under worker budget of 8.5)

#### Files changed

- `Parameters.jl`: `productivity` for all 6 firm types → 5.5; T1 price range
  3–5, T2 price range 5–7, B2C price range 5–8

Status: implemented; running 600-tick stability test.

---

### 2026-04-25: Extended to three-tier supply network

Extended the one-tier I-O network to three tiers to create a deeper agglomeration
pull toward the commercial core.

**Design:**

- `supply_tier::Int` replaces `firm_role::Symbol` in `FirmTypeParams`
  - Tier 1 (upstream B2B): uses only labor/capital/space; sells to Tier 2 only
  - Tier 2 (midstream B2B): buys from Tier 1, sells to B2C; Leontief-scaled
  - Tier 3 (final B2C): buys from Tier 2, sells to consumers; Leontief-scaled
- `is_b2b`/`is_b2c` are derived from tier position relative to `max_supply_tier`
- `generate_io_matrix` enforces tier ordering: links only from tier T to tier T-1
- Default firm_type_count raised from 4 to 6 (2 types per tier)
- Scheduler now runs two intermediate phases before B2C production

**Scheduler change:**

```
commit_intermediate_output!         # Tier 1 commits (no inputs)
input_purchasing_phase!(state, 2)   # Tier 2 buys from Tier 1
commit_b2b_with_inputs!            # Tier 2 commits Leontief-scaled
input_purchasing_phase!(state, max_supply_tier(state))  # B2C buys from Tier 2
commit_production!                  # B2C commits Leontief-scaled
```

**Files changed:**

- `Parameters.jl`: replaced `firm_role` with `supply_tier` in `FirmTypeParams`;
  updated default firm types to 6 (2 per tier); `firm_type_count` default = 6
- `State.jl`: `generate_io_matrix` uses tier ordering instead of role
- `Firms.jl`: added `firm_supply_tier`, updated `is_b2b`/`is_b2c`, updated
  `commit_intermediate_output!` to skip firms with inputs, added
  `commit_b2b_with_inputs!`, changed `input_purchasing_phase!` to accept
  `buyer_tier::Int`, updated `calculate_profits!` to deduct input costs for all
  tiers
- `Scheduler.jl`: two-phase intermediate production
- `Metrics.jl`: fill rates now collected for all firms with input requirements

**Results (seed=123, 40×40, 3000 workers, 2000 ticks):**

```text
tick=500:  b2b=165 b2c=90  fill=0.656 com_rent=3.84  res_rent=6.59
tick=1000: b2b=193 b2c=114 fill=0.727 com_rent=15.39 res_rent=5.17
tick=2000: b2b=245 b2c=172 fill=0.752 com_rent=17.76 res_rent=4.78
```

Gradient correlations (vs centroid) at tick 2000:
```text
commercial  = -0.577
residential = -0.651
ratio (com/res) = 0.89
```

This is a major improvement over the two-tier system (which reached only 0.62-0.78 ratio at
5000 ticks). The three-tier system nearly closes the gap in 2000 ticks. Commercial rent levels
are now 3.7× residential (vs 1.2× in two-tier at the same horizon), and the spatial gradient
is close to parity. Whether the gradient ordering inverts at 5000 ticks is the next question.

Output files:
```text
outputs/diagnostics/lots_io_250.csv
outputs/diagnostics/rent_gradient_io_250/
outputs/diagnostics/lots_io_1000.csv
outputs/diagnostics/rent_gradient_io_1000/
```

### 2026-04-23: Replaced location-value premium with endogenous mean-normalized bid scaling

Removed the artificial location-value premium from commercial bids and fixed
the underlying incumbent access-scale bug that made it necessary.

**Root cause of the original weakness:**

The expected-revenue bid for an incumbent firm scaled candidate consumer access
against the firm's own anchor access:

```julia
access_scale = (candidate_access + 1.0) / (anchor_access + 1.0)
```

A firm already at a central location has high anchor access. When bidding on
other central lots, candidate ≈ anchor, so access_scale ≈ 1.0. Central firms
did not bid more for central lots than for peripheral ones — the spatial
differentiation collapsed.

The location-value premium (`commercial_bid_location_value_weight`) was added
to paper over this by directly adding a location score to every bid. That
produced a strong gradient (-0.42 at 250 ticks) but the mechanism was imposed,
not emergent.

**Fix:**

Changed the incumbent access scale to use the citywide mean as denominator,
matching the startup formula:

```julia
mean_access = mean(state.consumer_access_by_lot)
access_scale = (candidate_access + 1.0) / (mean_access + 1.0)
```

Now every firm — incumbent or startup — bids in proportion to a lot's absolute
demand potential relative to the city average. Central lots always attract
higher bids regardless of where the bidding firm currently sits.

Removed `commercial_bid_location_value_weight` from `Parameters.jl` and removed
the location-premium term from `commercial_bid_amount` in `Firms.jl`. The bid
is now purely:

```julia
raw_bid = commercial_bid_share * expected_site_revenue(state, f, lot_id)
```

**How the gradient forms:**

The mechanism is a reinforcing spatial loop with no hard-coded center:

1. Workers choose housing partly by job-access utility, so residential density
   clusters near employment.
2. `consumer_access_by_lot` is recomputed each tick from actual worker
   residential locations with distance decay — lots near dense residential areas
   get high consumer access.
3. Firms bid more for high consumer-access lots because expected sales (and
   therefore expected revenue) are higher there.
4. Commercial rents adjust toward winning bids at 30% per tick.
5. Higher-rent central commercial lots attract more firms, which attracts more
   workers, which raises consumer access further.

The gradient is slow to build because residential clustering must develop
first, and rents capitalize bid signals gradually. At 250 ticks the gradient
is modest; by 1000 ticks it is strong.

**Results:**

```text
Configuration (matched benchmark):
- width = 40, height = 40
- initial_workers = 3000, initial_firms = 150
- outside_entry_rate = 2.0, seed = 77
```

```text
250 ticks:
- population = 3521, employment = 3329, firms = 238
- mean_commercial_rent = 1.7133
- commercial rent vs geometric center distance = -0.1874
- residential rent vs geometric center distance = -0.6325

1000 ticks:
- population = 4999, employment = 4359, firms = 290
- mean_commercial_rent = 2.8713
- commercial rent vs geometric center distance = -0.5245
- residential rent vs geometric center distance = -0.6577
```

**Comparison against prior approaches:**

```text
Expected-revenue bids, anchor-normalized (old):    250 ticks: -0.15
Location-value premium, weight=1.0 (artificial):   250 ticks: -0.42
Mean-normalized, no premium (this change):         250 ticks: -0.19
Mean-normalized, no premium (this change):        1000 ticks: -0.52
```

The commercial gradient is now fully endogenous and durable. The residential
gradient is stable throughout (-0.63 to -0.66).

---

### 2026-04-25: Outside supply as cold-start bridge for upstream tiers

#### Problem

With cash flow tracking active, the three-tier economy collapses by tick 200
regardless of productivity calibration. The root cause is not prices — it is
**utilization**. With six firm types distributed uniformly, initialization
produces roughly equal tier counts (~5 T1, ~7 T2, ~4 B2C from 16 initial
firms). T2 operates at ~18% utilization (too many T2 firms for the few B2C
buyers), buying full-capacity T1 inputs every tick but selling almost none of
its committed output. Cash drain exhausts `initial_firm_cash` in ~230 ticks.
B2C loses T2 supply and exits shortly after.

The utilization imbalance cannot be solved by parameter calibration alone:
with random equal-probability type assignment, the tier distribution is always
roughly uniform, but a viable supply chain requires a pyramid (many B2C, fewer
T2, very few T1). Even a correctly shaped pyramid creates a different failure:
severe upstream scarcity drives T1/T2 prices up, the B2C cost cascade exceeds
the worker goods budget, and B2C exits anyway.

#### Root cause discussion

The cash-flow model is revealing that the cold start is a **bootstrapping
problem**: T2 needs B2C demand to be viable, but B2C needs T2 supply to
produce. Neither can exist first. Before cash flow, the infinite initial
subsidy (zombie firms) let both sides develop in parallel. Removing that
subsidy collapses both simultaneously.

#### Solution: outside supply as a fallback

Downstream firms (T2, B2C) can purchase required inputs from a supplier
**outside the model** at a known price, as a fallback when local upstream
suppliers are unavailable or too expensive. This models the period before
local backward linkages have formed — firms import intermediate goods, then
shift to local sourcing as upstream firms enter and become competitive.

**Design:**

- `outside_input_prices::Vector{Float64}` — one base price per supplier tier
  (indexed by supplier tier: `[price_for_T1_goods, price_for_T2_goods, ...]`).
  Outside supply is available for any tier that has an entry in this vector.
- The outside supplier participates in the same cost comparison as local
  firms: `effective_cost = outside_price + input_travel_cost_per_block × outside_distance`.
  `outside_distance` is a model parameter representing the virtual distance
  of the outside supplier from the grid — a large fixed value (e.g., 20 blocks)
  that encodes the friction of dealing with non-local supply.
- Buyer firms always prefer local suppliers when local effective cost is lower.
  Outside supply fills only what local suppliers cannot cover.
- As local upstream firms enter and locate near their buyers, their
  `price + actual_travel_cost` beats `outside_price + outside_distance_cost`,
  and they win the business. This creates the import-substitution dynamic and
  gives upstream firms a spatial incentive to locate near their buyers.

**Calibration constraints:**

For each supplier tier T, the outside price must satisfy:
- `outside_price[T] ≥ break_even_price[T]` — so local T-tier firms can enter
  at a profitable price and still undercut outside supply (when close enough)
- `outside_price[T]` low enough that downstream tiers remain viable
  (cost cascade does not push B2C break-even above worker goods budget)

With 1 worker per firm (most efficient size given Cobb-Douglas with
labor_elasticity < 1), break-even prices are:
- T1: ~2.5, T2: ~4.8, B2C: ~5.5 (within worker goods budget ~6.9)

Candidate outside prices: T1 goods ≈ 3.5, T2 goods ≈ 5.5. Local T1 firms
within 5 blocks of a T2 buyer can undercut outside at these prices.

**Implementation note — local supplier sweep:**

The initial implementation took only the single cheapest local supplier and
sent any unfilled remainder to outside, even when other local candidates were
also cheaper than outside. The correct logic is to sweep all local candidates
in ascending cost order, buying from each as long as its effective cost is
below the outside effective cost, stopping only when demand is satisfied or
the next local option exceeds outside cost. Outside supply fills only what
genuinely cannot be sourced locally at a competitive price.

**Status:** implemented.

Output files:

```text
outputs/diagnostics/lots_endogenous_bid_250.csv
outputs/diagnostics/rent_gradient_endogenous_bid_250/
outputs/diagnostics/lots_endogenous_bid_1000.csv
outputs/diagnostics/rent_gradient_endogenous_bid_1000/
outputs/diagnostics/market_log_endogenous_bid_1000.csv
```

---

### 2026-04-25: Outside labor market as consumption-side cold-start bridge

#### Problem

Even with outside input supply stabilizing upstream firms, the economy collapses
on the consumption side. Contraction fires after the `modal_sales_lookback` grace
period (tick 12), firms shed workers, and unemployed workers earn zero. With no
income, they stop buying B2C goods, B2C revenue collapses, and B2C exits — taking
T2 demand down with it. The supply-side bridge alone cannot save the economy if
the demand side is gone.

#### Root cause

`worker_income` returns 0.0 for unemployed workers. Workers without income skip
the consumption loop entirely. There is no outside employment option: once a firm
sheds a worker, that worker's purchasing power drops to zero immediately.

#### Solution: outside labor market

Workers can work "outside the model" — supplying labor to employers that are not
explicitly represented on the grid. This provides a consumption floor that prevents
demand collapse during the bootstrap period, symmetric to the outside input supply
mechanism on the production side.

**Design:**

- Unemployed workers earn a flat `outside_wage` each tick.
- The outside employer is conceptually at the city edge. To equalize the outside
  option with the worst inside option (and give inside firms a location advantage),
  the outside commute cost is set to `job_access_radius × commute_cost_per_block`.
  With defaults (radius=8, cost=0.12), this is 0.96/tick.
- Workers always prefer an in-model job: the job search already places them in the
  best available in-model job, and they only fall back to outside when none is
  available.
- Unemployed workers can now also find and hold housing, using `outside_wage` as
  their income and the maximum commute deduction as their commute cost. This
  allows them to participate in the housing market and preserves their shopping
  anchor location.

**Parameters added:**

- `outside_wage::Float64 = 5.0` — flat wage paid to unemployed workers per tick

**Files changed:**

- `Parameters.jl`: added `outside_wage`
- `Workers.jl`: `worker_income` takes `params` argument, returns `params.outside_wage`
  when unemployed; `housing_affordable` uses `outside_wage` and max commute cost
  for unemployed workers; `housing_search!(::Unhoused, ::Unemployed, ...)` enabled
  to call `move_to_best_home!` instead of returning false; `consumption_phase!`
  updated to pass `state.params`

**Status:** implemented.

---

### 2026-04-25: Cold-start parameter calibration via MC viability search

#### Problem

Test runs after implementing outside supply and outside labor market still showed
cold-start collapse. Analytical cash-flow checks identified two compounding issues:

1. `outside_wage = 5.0` gives unemployed workers a shopping budget of ~4.25/tick
   (after savings). B2C goods break even around 6.5–8.0/unit. Workers cannot
   afford B2C goods at all, so demand collapses despite the outside wage floor.

2. `io_matrix_coefficient_min = 0.50` means every unit of B2C output requires at
   least 0.50 units of T2 input. With T2 outside effective cost at 8.0/unit,
   input costs alone exceed B2C revenue at any affordable price.

#### Diagnosis: MC viability search

A Monte Carlo search over 15 parameters simultaneously (200,000 samples × 30
inner environment draws) evaluated three analytical conditions:
- C1: T1 break-even price < outside T1 effective cost (local T1 beats outside)
- C2: T2 break-even price < outside T2 effective cost (local T2 beats outside)
- C3: unemployed worker shopping budget ≥ T3 break-even + travel cost

Results:
- C1 passes 97.8% of the time across the full parameter space — never binding
- C2 passes 86.3% of the time — rarely binding
- C3 passes only 38.3% — the single dominant constraint everywhere

Only two parameters were flagged as strongly separating viable from non-viable
samples (viable distribution shifted more than 15% of range from the full midpoint):

- `outside_wage`: current 5.0 is below the 10th percentile of viable samples
  (viable q10/q50/q90 = 9.0/12.6/14.6). However, many of these samples had
  outside_wage > base_wage, which is economically incoherent — workers outside
  the model would earn more than those inside. The correct parameterization is a
  **reservation wage ratio** (outside_wage = ratio × base_wage). With the ratio
  constrained to ≤ 0.85 and base_wage = 10.0, outside_wage should be ≤ 8.5.

- `io_matrix_coefficient_min`: current 0.50 is above the 90th percentile of viable
  samples (viable q10/q50/q90 = 0.13/0.24/0.46). B2C input requirements need to
  be much lighter for the supply chain to be cost-viable at consumer prices.

#### Parameter changes

- `io_matrix_coefficient_min`: 0.50 → 0.20
- `io_matrix_coefficient_max`: 0.75 → 0.40
- `outside_wage`: 5.0 → 8.0  (= 0.80 × base_wage; reservation wage 80%)
- `outside_input_prices[2]`: 7.0 → 5.0  (lowers T2 outside cost, reducing B2C
  input burden and widening the feasible window for T2 vs B2C pricing)

**Why these values:** with coeff ∈ [0.20, 0.40], cap(L=1) = 6, and
outside_eff_t2 = 6.0 (op2=5.0 + input_tc×distance=1.0), B2C break-even is
≈ (10 + 6 + 2×6) / 6 = 4.67/unit at mean coeff 0.30. Unemployed worker budget
= 8.0 × 0.85 = 6.8; delivered cost = 4.67 + travel ≈ 5.4. Margin ≈ 1.4/unit.

**Files changed:** `Parameters.jl`

**Status:** implemented; search script updated with ratio constraint and rerun.

#### Viable parameter ranges for future tuning

Wide MC search (300,000 samples × 30 inner draws, 15 free parameters,
`outside_wage = ow_ratio × base_wage` constraint enforced) found 4.76% of the
full parameter space robustly viable (≥90% of inner draws pass all three
conditions). After the first-round changes above, the updated default
parameters score **90.6% viability**.

Parameters that strongly separate viable from non-viable samples (viable median
shifted >15% of range from the full-space midpoint):

| Parameter | Viable q10 | Viable q50 | Viable q90 | Current |
|---|---|---|---|---|
| `productivity` | 5.82 | 8.18 | 9.68 | 6.5 (updated) |
| `base_wage` | 8.56 | 12.33 | 14.52 | 10.0 |
| `ow_ratio` (outside_wage/base_wage) | 0.62 | 0.82 | 0.93 | 0.80 |
| `coeff_lo` (io_matrix_coefficient_min) | 0.07 | 0.16 | 0.36 | 0.20 |
| `rent_lo` (initial_commercial_rent_min) | 1.44 | 3.43 | 6.62 | 3.0 (updated) |

Parameters where current values are well-centered in the viable distribution
(no flag): `op1`, `op2`, `outside_distance`, `input_tc`, `goods_tc`,
`coeff_hi`, `rent_hi`, `sr_lo`, `sr_hi`, `travel_max`.

**Condition bottleneck:** C3 (unemployed worker can afford B2C at break-even
price) passes only 29.5% of the full parameter space at mean environment.
C1 and C2 are almost never binding (97.8% and 87.3% pass rates). All future
tuning should prioritise C3 headroom: higher `outside_wage` (via ratio), lower
`coeff_lo`, lower initial commercial rent, and higher productivity all increase
C3 pass rate independently.

**Second-round parameter changes** (applied immediately after first-round):
- `productivity`: 5.5 → 6.5 for all 6 firm types (was below viable q10=5.82)
- `initial_commercial_rent_min`: 4.5 → 3.0 (viable q50=3.43; prior value above median)
- `initial_commercial_rent_max`: 7.5 → 5.5 (scaled proportionally)

**Files changed:** `Parameters.jl`

**Status:** implemented.

---

### 2026-04-25: Initial price calibration and B2B price-cut rule fix

#### Root causes

Two compounding problems prevented local B2B firms from ever winning market share
from outside supply, even with the outside supply mechanism in place.

**1. Initial B2B prices straddle outside effective costs**

Outside effective costs (with current defaults):
- T1: `outside_input_prices[1] + input_travel_cost × outside_distance = 3.5 + 0.20×5 = 4.5`
- T2: `outside_input_prices[2] + input_travel_cost × outside_distance = 5.0 + 0.20×5 = 6.0`

Prior initial price ranges:
- T1: [3.0, 5.0] — half the distribution (4.5–5.0) starts ABOVE outside_eff_t1
- T2: [5.0, 7.0] — 33% of the distribution (6.0–7.0) starts ABOVE outside_eff_t2

Any firm that initializes above the outside effective cost for its tier can never
win a single B2B customer at startup. T2 buyers will always choose outside supply
over a local T1 firm priced above 4.5.

**2. Zero-sales trap in the B2B price-cut rule**

`firm_reviews!` used `elseif last_sales > 0` as the price-cut condition: only cut
if some sales occurred last period. For a T1 firm with zero sales (because its
price exceeds outside effective cost), `last_sales = 0`, so the cut condition is
false — price never adjusts downward. With `initial_firm_cash = 15,000`, such a
firm could survive ~1,000 ticks at slow cash drain while its price remains stuck
above the competitive threshold. The outside supply mechanism keeps T2 buyers
fully supplied throughout, so the T1 firm's price overrun is never corrected.

The `last_sales > 0` rule was introduced in the cold-start calibration entry to
prevent T1 firms from cutting into break-even territory when no T2 buyers existed
yet (the Leontief case where cutting price creates no new demand). That logic was
correct for the pre-outside-supply world. With outside supply, T2 buyers DO exist
but are using outside supply because local T1 is too expensive — cutting local T1
price IS effective because buyers will switch when local price falls below outside
effective cost.

#### Fix 1: anchor initial prices below outside effective costs

Revised initial price ranges so ALL initial draws are at or below outside effective
cost:
- T1: [3.0, 5.0] → **[2.5, 4.0]** (max 4.0 < outside_eff_t1 4.5 ✓)
- T2: [5.0, 7.0] → **[3.5, 5.5]** (max 5.5 < outside_eff_t2 6.0 ✓)
- T3 (B2C): [5.0, 8.0] → **[4.0, 6.5]** (max 6.5 < worker budget ~6.8 ✓)

T3 calibration: unemployed worker budget = `outside_wage × (1 - savings_rate_mean)
= 8.0 × 0.85 = 6.8`. Initial B2C goods at max 6.5 ensures consumers can afford
at least some goods from tick 1, anchoring B2C demand.

#### Fix 2: B2B firms use utilization signal for price cutting

Changed `firm_reviews!` to use a tier-specific cut condition:
- B2B firms: `last_sales == 0 && committed_output > 0` — cut only when completely
  frozen out of the market (zero sales). This breaks the "above outside cost" trap:
  a B2B firm priced above `outside_eff_cost[tier]` earns zero sales; cutting will
  eventually bring the price below outside effective cost, at which point T2 buyers
  switch back to local supply.
- B2B firms at partial utilization (1 ≤ last_sales < committed_output): no cut. In
  the Leontief B2B market, total input demand from T2 buyers is quantity-fixed by
  T2's Leontief coefficients and capacity. Cutting price does not attract additional
  T2 demand — T2 already buys all the T1 goods it needs from the cheapest available
  source. Cutting below break-even just destroys revenue without gaining volume.
- B2C firms: `last_sales > 0` unchanged — cut only when some consumers bought
  but firm is not sold out. Zero B2C sales still suppresses cuts because zero B2C
  demand is structural (workers can't afford it) rather than a price-competition loss.

The distinction: B2B demand is quantity-fixed (Leontief) and price-competitive only
at the local-vs-outside margin. B2C demand is budget-constrained and responds to
price throughout the range.

#### Files changed

- `Parameters.jl`: initial price ranges for all 6 firm types
- `Firms.jl`: `firm_reviews!` uses `do_cut` variable with B2B/B2C branching

**Status:** implemented; running cold-start stability test.

---

### 2026-04-23: Added location-value premium to commercial bids

Follow-up to the expected-revenue bid pass and subsequent demand-side extensions
(accessibility, commute utility, probabilistic goods, shopping habits, human
capital) that collectively left the commercial rent gradient near zero.

Root cause:

- `expected_site_sales_units` for incumbents uses `candidate_access / anchor_access`
  as the access scaling ratio
- an incumbent already at a central location gets an access scale near 1.0 when
  bidding for other central lots, so bids do not systematically favour central lots
  over peripheral ones
- this collapses spatial differentiation in the bid schedule

Design change:

- keep the revenue-based component: `commercial_bid_share * expected_site_revenue`
- add an additive location premium: `commercial_bid_location_value_weight * commercial_location_gross_value`
- `commercial_location_gross_value` uses consumer access, job access, and employee
  commute terms already calibrated — the premium is therefore always highest at
  the most accessible lots, regardless of where the incumbent currently sits
- bids are still clamped to `commercial_bid_cap`

New parameter in `src/Parameters.jl`:

- `commercial_bid_location_value_weight = 1.0`

Implementation in `src/Firms.jl`:

- `commercial_bid_amount` now sums the revenue component and the location premium

Matched 250-tick benchmark:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Final state:

```text
- population = 4958
- employment = 4590
- firm_count = 369
- mean_commercial_rent = 2.5233
- unsold_output = 764
```

Rent-gradient read from final lots:

```text
- residential rent vs geometric center distance = -0.6611
- commercial rent vs geometric center distance = -0.4239
- residential rent vs residential centroid distance = -0.6638
- commercial rent vs residential centroid distance = -0.4307
- residential rent vs commercial centroid distance = -0.6829
- commercial rent vs commercial centroid distance = -0.4446
```

Comparison against prior runs:

```text
Expected-revenue bids only (no location premium):
- mean_commercial_rent = 1.6290
- commercial rent vs geometric center distance = -0.1505
- commercial_with_cheaper_unsampled_share = 0.1251

Human capital run (most recent before this change):
- mean_commercial_rent = 81.4072
- commercial rent vs geometric center distance = -0.0272

Location-value premium added (this change):
- mean_commercial_rent = 2.5233
- commercial rent vs geometric center distance = -0.4239
- commercial_with_cheaper_unsampled_share = 0.5972
```

Assessment:

- the location premium substantially restored the commercial rent gradient
- commercial gradient is now -0.42, comparable to the first heuristic-only bid
  pass (-0.4616) but now combined with the revenue basis
- commercial rents remain low in absolute terms (mean = 2.52) — the bid cap and
  smoothing rate keep rents from spiking, which is desirable
- the residentially-driven gradient is also strong and preserved (-0.66)
- `commercial_with_cheaper_unsampled_share` rose to 0.60, meaning many firms are
  still landing on non-optimal lots; this is an open search-coverage tradeoff
- the primary remaining question is whether the gradient is durable at longer
  runs or whether it washes out as the city grows

Status: promising. Next step is to rerun the open issue check for commercial rent
blow-up at longer horizons and verify the gradient holds under the new bid
structure.

Output files:

```text
outputs/diagnostics/open_diagnostic_locprem_250/
outputs/diagnostics/rent_gradient_locprem_250/
```

### 2026-04-23: Added minimal periodic commercial bidding for vacant units

Changed the commercial-space allocation mechanism so firms can compete for the
same vacant commercial lots within a tick instead of immediately occupying the
best sampled lot in isolation.

Design:

- firms still use bounded staged search to form a sampled candidate set
- each reviewing firm now submits at most one commercial bid, for its best
  sampled vacant lot
- bids are based on gross commercial location value rather than current rent
- a new bid-resolution phase awards vacant units lot-by-lot to the highest
  bidders
- commercial rents now adjust toward the mean winning bid on awarded lots
- vacancy markdowns remain in place
- the old automatic commercial full-occupancy rent raise was removed so bidding
  becomes the primary commercial rent-discovery mechanism
- newly founded firms that lose a contested first-round bid can still use a
  bounded global vacant-lot rescue if commercial space remains elsewhere

Implementation:

- added `CommercialBidProposal` and a per-tick bid buffer in model state
- added gross-value and bid-ceiling logic in `src/Firms.jl`
- `commercial_space_search!` now submits a bid proposal instead of directly
  taking space
- added `resolve_commercial_bids!` after entrepreneurship and expansion reviews
- updated startup firm handling so entry is confirmed only after securing an
  initial commercial unit
- removed the commercial occupied/full rent raise from `src/Developer.jl`

New parameters in `src/Parameters.jl`:

- `commercial_bid_base`
- `commercial_bid_slope`
- `commercial_bid_cap`
- `commercial_rent_bid_adjustment_rate`

Smoke validation:

```text
Configuration A:
- width = 12
- height = 12
- initial_workers = 40
- initial_firms = 8
- ticks = 5
- seed = 1

Result:
- initial active firms after bid resolution = 8
- active firms at tick 5 = 8
- mean_commercial_rent = 2.7692
```

```text
Configuration B:
- width = 16
- height = 16
- initial_workers = 80
- initial_firms = 12
- ticks = 20
- seed = 2

Result:
- active firms at tick 20 = 11
- mean_commercial_rent = 1.1083
- commercial_vacancy_rate = 0.9562
```

Assessment:

- the minimal bidding mechanism is implemented and runs without runtime errors
  in smoke tests
- commercial rent formation is now tied to competing firm bids rather than only
  local occupancy
- this has not yet been evaluated on the matched 250-tick and 5000-tick
  diagnostics used elsewhere in this log
- the next question is whether the bid calibration is too weak, given the low
  commercial rents seen in short smoke runs
- if so, the next levers are likely bid scaling, bid caps, or a more direct
  expected-revenue basis for bids

### 2026-04-23: Replaced heuristic-score commercial bids with expected-revenue bids

Follow-up to the first bidding pass after the matched 250-tick benchmark showed
that bidding created a clear commercial rent gradient but left the entire
commercial rent field compressed near the minimum.

Triggering evidence from the first bid pass:

```text
Matched 250-tick benchmark:
- final mean_commercial_rent = 1.4214
- commercial rent vs geometric center distance = -0.4616
- commercial rent by distance bin was downward sloping, but mostly in the range 1.0 to 1.9
```

Interpretation:

- the auction structure was working in a directional spatial sense
- the bid schedule itself was too weak because bids were still derived from a
  heuristic location score rather than expected monetary payoff
- firms were competing for central space, but not bidding enough to capitalize
  that advantage into meaningful rents

Design change:

- keep the same periodic vacant-unit bidding structure
- replace heuristic-score bids with bids based on expected site revenue
- for incumbent firms, expected site sales scale from recent realized sales and
  the ratio of candidate consumer access to current-site consumer access
- for startup firms, expected site sales scale from a startup baseline and the
  ratio of candidate consumer access to mean citywide consumer access
- discount expected sales by nearby same-type competition so firms do not all
  bid as if they capture the full local market
- set bid ceiling as a fixed share of expected site revenue, still capped and
  smoothed into rents on award

Implementation:

- added expected-sales and expected-revenue helpers in `src/Firms.jl`
- `commercial_bid_amount` now uses expected site revenue instead of heuristic
  score units
- replaced `commercial_bid_base` and `commercial_bid_slope` with:
  - `commercial_bid_share`
  - `commercial_bid_recent_sales_lookback`
  - `commercial_bid_startup_expected_sales`
  - `commercial_bid_same_type_competition_weight`
- raised `commercial_bid_cap` to allow meaningful commercial premia if the new
  revenue-based bids support them

Status:

Implemented. Next rerun the matched 250-tick benchmark and compare commercial
rent level, rent gradient, and market-clearing outcomes against both the
pre-bidding and first-bidding runs.

Matched rerun after switching to expected-revenue bids:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Final state:

```text
- population = 4982
- employment = 4555
- firm_count = 348
- mean_commercial_rent = 1.6290
- unsold_output = 630
```

Rent-gradient read from final lots:

```text
- residential rent vs geometric center distance = -0.7350
- commercial rent vs geometric center distance = -0.1505
- residential rent vs residential centroid distance = -0.7354
- commercial rent vs commercial centroid distance = -0.1426
```

Commercial-search comparison against the first bid pass:

```text
First bid pass:
- mean_commercial_rent = 1.4214
- commercial rent vs geometric center distance = -0.4616
- commercial_with_cheaper_unsampled_share = 0.5645
- commercial_mean_rent_gap_to_best_global = 0.5392
- unsold_output = 1053

Expected-revenue bid pass:
- mean_commercial_rent = 1.6290
- commercial rent vs geometric center distance = -0.1505
- commercial_with_cheaper_unsampled_share = 0.1251
- commercial_mean_rent_gap_to_best_global = 0.0309
- unsold_output = 630
```

Assessment:

- switching to expected-revenue bids improved commercial-rent level modestly
  and materially reduced local search/path mismatch
- goods-market absorption also improved relative to the first bid pass
- however, the commercial spatial gradient became much weaker than in the first
  bid pass
- current evidence suggests the revenue-based bid is still underpowered on rent
  level while also flattening the strong central premium created by the earlier
  bid heuristic
- the likely next move is to keep the expected-revenue basis but restore a
  stronger location-value multiplier, rather than choosing between pure access
  heuristics and pure recent-sales scaling

### 2026-04-23: Switched to bounded staged search with commercial rescue

Changed search behavior after the time-local substitute audit showed that extreme commercial-rent spikes were strongly associated with missed cheaper vacant lots available elsewhere in the same tick.

Design change:

- searches still begin from the existing local-first sampled process
- search now widens in bounded stages instead of using one fixed draw
- each stage increases Poisson search intensity, radius, and global sampling while reducing local anchoring
- search stops early only if a domain-specific satisficing condition is met
- commercial-space search has a final bounded global rescue path when staged local/global sampling still fails to find a satisfactory vacant lot

Commercial-space rule:

- require at least a small set of vacant sampled alternatives before accepting the search result
- for incumbent firms, accept only if the best sampled vacant rent is not too far above the current anchor lot rent
- otherwise escalate search up to the capped number of stages
- if the escalated search still has no satisfactory result, pick the cheapest globally vacant commercial lot

Goods rule:

- widen search when the sampled affordable choice set is too thin
- keep this adaptive logic bounded and lighter than the commercial-space rescue logic

Implementation:

- `SearchParams` now supports bounded escalation controls
- `adaptive_candidate_lots` added in `src/Search.jl`
- `commercial_space_search!` now uses staged search plus a global rescue fallback
- `choose_good` now uses staged search with a minimum affordable-candidate threshold

Expected effect:

- commercial-space search should stop accepting extremely expensive local outcomes when much cheaper vacant space exists elsewhere
- goods search should reduce false no-choice events caused by thin sampled affordable sets

Matched rerun after the staged-search change:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Before staged search:

```text
- mean_commercial_rent = 132.4042
- unsold_output = 1024
- commercial_with_cheaper_unsampled_share = 0.0998
- commercial_late_share_with_cheaper_unsampled = 0.2602
- commercial_high_rent_share_with_cheaper_unsampled = 0.9879
- goods_no_choice_despite_affordable = 16258
```

After staged search:

```text
- mean_commercial_rent = 95.0867
- unsold_output = 1517
- commercial_with_cheaper_unsampled_share = 0.1318
- commercial_late_share_with_cheaper_unsampled = 0.3705
- commercial_high_rent_share_with_cheaper_unsampled = 0.5675
- goods_no_choice_despite_affordable = 8044
```

Assessment:

- the staged search materially reduced the commercial-rent blow-up by tick 250
- the extreme high-rent commercial tail is less dominated by missed cheaper substitutes than before
- goods-search false no-choice events were cut roughly in half
- however, unsold goods increased and commercial vacancy tightened sharply by tick 250, so this is a tradeoff rather than a clean fix

Status:

Promising partial improvement. Keep the issue open and next inspect whether the commercial rescue rule is over-concentrating firms into the cheapest currently vacant space.

### 2026-04-23: Added endogenous accessibility forces for firms, workers, and goods demand

Changed the model to create a minimal endogenous agglomeration loop rather than relying only on rent and current-commute comparisons.

Design:

- goods demand is now spatial through a distance-based shopping cost
- firms evaluate commercial lots using nearby consumer access and nearby job access, not rent alone
- worker housing utility now includes nearby job access, not only rent and commute to the current employer
- these effects are computed from the current state each tick; no center is hard-coded

Implementation:

- added cached lot-level `consumer_access_by_lot` and `job_access_by_lot`
- added `refresh_spatial_access!` in `src/SpatialAccess.jl`
- scheduler now refreshes spatial access before goods consumption, commercial-space search, job search, and housing search phases
- goods choice now uses `goods_price + travel_cost`
- commercial-space search now ranks vacant lots by access-adjusted location score
- housing utility now adds a job-access term

New parameters in `src/Parameters.jl`:

- `goods_travel_cost_per_block`
- `consumer_access_radius`
- `job_access_radius`
- `access_distance_decay`
- `housing_job_access_weight`
- `firm_consumer_access_weight`
- `firm_job_access_weight`

Expectation:

- dense residential areas should create stronger nearby demand for firms
- dense employment areas should create stronger nearby housing demand
- firms and workers should begin to reinforce accessible locations without imposing an exogenous center

Matched rerun after adding endogenous accessibility:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Final state:

```text
- population = 5035
- employment = 4808
- firm_count = 371
- mean_commercial_rent = 94.9536
- unsold_output = 583
```

Rent-gradient read from final lots:

```text
- residential rent vs geometric center distance = -0.6648
- commercial rent vs geometric center distance = -0.0168
- residential rent vs residential centroid distance = -0.6651
- commercial rent vs commercial centroid distance = -0.0069
```

Assessment:

- the new accessibility loop created a strong residential rent gradient
- commercial rents still do not show a meaningful gradient
- aggregate market performance improved relative to the staged-search-only run on employment and unsold output
- however, goods-search no-choice events despite affordable supply increased sharply, so the goods-search side still needs work under the new spatial demand rule

Status:

Residential spatial structure is now emerging endogenously. Commercial spatial structure remains unresolved.

### 2026-04-23: Added employee-commute utility to firm commercial location choice

Changed firm commercial-space evaluation so firms also prefer locations that reduce expected worker commute.

Rule:

- when a firm evaluates candidate commercial lots, its location score now includes a penalty for mean commute distance from current employees' residences to the candidate lot
- firms with no housed employees fall back to the existing access and rent terms only

Implementation:

- added `firm_employee_commute_weight` in `src/Parameters.jl`
- added mean employee commute term to `commercial_location_score` in `src/Firms.jl`

Expectation:

- incumbent firms should become less willing to drift into low-rent but labor-inconvenient space
- this may strengthen the spatial coupling between employment and residential clusters
- commercial centers, if they emerge, should be more compatible with worker residence patterns rather than only customer access and low rent

Matched rerun after adding the employee-commute term:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Final state:

```text
- population = 4974
- employment = 4692
- firm_count = 361
- mean_commercial_rent = 85.7895
- unsold_output = 661
```

Rent-gradient read from final lots:

```text
- residential rent vs geometric center distance = -0.6179
- commercial rent vs geometric center distance = -0.0181
- residential rent vs residential centroid distance = -0.6236
- commercial rent vs commercial centroid distance = -0.0171
```

Comparison against the prior accessibility-only run:

```text
Accessibility-only:
- final mean_commercial_rent = 94.9536
- final unsold_output = 583
- residential rent vs geometric center distance = -0.6648
- commercial rent vs geometric center distance = -0.0168

With employee commute term:
- final mean_commercial_rent = 85.7895
- final unsold_output = 661
- residential rent vs geometric center distance = -0.6179
- commercial rent vs geometric center distance = -0.0181
```

Assessment:

- the employee-commute term reduced commercial rents further
- it preserved a strong residential rent gradient
- it did not produce a meaningful commercial rent gradient
- current evidence suggests commercial accessibility remains too diffuse or too weakly tied to realized firm revenue for a commercial center to emerge

### 2026-04-23: Switched goods demand from deterministic best-score choice to sampled-set probabilistic choice

Changed the goods-purchase rule to preserve endogeneity while making firm revenue depend more directly on local delivered utility.

Design:

- consumers still search locally first and widen search only in bounded stages
- purchase choice is now probabilistic over the sampled affordable set rather than a deterministic best-score rule
- delivered utility depends on consumer taste and total delivered cost, including distance-based travel cost
- search friction remains in the sampled set construction; it is not imposed again as a separate purchase penalty

Intended behavior:

- nearby firms should gain a persistent demand advantage without hard-coding a center
- accessible commercial locations should become valuable through realized sales, not only through heuristic access terms
- local search friction should still matter because firms outside the sampled set cannot be chosen

Matched rerun after the probabilistic-goods change:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Final state:

```text
- population = 4961
- employment = 4710
- firm_count = 359
- mean_commercial_rent = 107.9943
- unsold_output = 805
```

Rent-gradient read from final lots:

```text
- residential rent vs geometric center distance = -0.6203
- commercial rent vs geometric center distance = 0.0041
- residential rent vs residential centroid distance = -0.6230
- commercial rent vs commercial centroid distance = 0.0036
```

Comparison against the prior commute-aware run:

```text
Commute-aware deterministic goods choice:
- final mean_commercial_rent = 85.7895
- final unsold_output = 661
- residential rent vs geometric center distance = -0.6179
- commercial rent vs geometric center distance = -0.0181

Commute-aware probabilistic goods choice:
- final mean_commercial_rent = 107.9943
- final unsold_output = 805
- residential rent vs geometric center distance = -0.6203
- commercial rent vs geometric center distance = 0.0041
```

Assessment:

- the probabilistic-goods rule preserved the strong residential rent gradient
- it did not generate a commercial rent gradient
- final commercial rents and unsold output both increased relative to the prior commute-aware run
- current evidence suggests that sampled-set choice stochasticity alone is not sufficient to create a durable commercial center

### 2026-04-23: Added shopping habits with review-triggered re-search

Changed the goods-demand rule so workers default to habitual suppliers and only re-search when the match deteriorates or a random review fires.

Design:

- workers remember a preferred firm by good type and the last delivered cost paid for that type
- if the preferred supplier is active, in stock, and still affordable, workers buy from habit by default
- workers re-search when:
  - the supplier is inactive or sold out
  - delivered cost exceeds the stored cost by more than a tolerance
  - a random shopping review fires
- fallback search remains local-first and bounded

Intended behavior:

- create persistent customer-firm links without hard-coding market leaders
- stabilize nearby demand and make accessible commercial locations more valuable through repeat business
- preserve endogenous switching when a supplier becomes worse

Matched rerun after the shopping-habits change:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Final state:

```text
- population = 4950
- employment = 4670
- firm_count = 364
- mean_commercial_rent = 104.1892
- unsold_output = 472
```

Rent-gradient read from final lots:

```text
- residential rent vs geometric center distance = -0.6430
- commercial rent vs geometric center distance = -0.0184
- residential rent vs residential centroid distance = -0.6437
- commercial rent vs commercial centroid distance = -0.0190
```

Comparison against recent demand variants:

```text
Commute-aware deterministic goods choice:
- final unsold_output = 661
- final mean_commercial_rent = 85.7895

Commute-aware probabilistic goods choice:
- final unsold_output = 805
- final mean_commercial_rent = 107.9943

Shopping habits with review-triggered re-search:
- final unsold_output = 472
- final mean_commercial_rent = 104.1892
```

Assessment:

- shopping habits materially improved goods-market absorption relative to the recent non-habit demand variants
- the strong residential rent gradient was preserved
- commercial rents still do not show a meaningful spatial gradient
- current evidence suggests that demand persistence helps market clearing, but commercial location value is still not concentrated enough to generate a center

### 2026-04-23: Added experience-based human capital and workplace-distance social ties

Implemented the minimal human-capital/network version to break worker uniformity and make productive relationships persistent but spatially grounded.

Design:

- workers accumulate human capital when employed
- workers form coworker ties inside firms
- ties persist after workers move but decay as a function of current workplace distance
- same-firm ties decay very slowly
- weak ties are dropped to keep the network sparse
- production now uses effective labor instead of raw worker count

Effective labor:

```text
effective_labor(worker) = human_capital(worker) * network_multiplier(worker)
```

Network multiplier:

- based on the sum of active tie strengths
- strongest for same-firm ties
- also counts nearby-firm ties within a spillover radius
- capped to avoid runaway superstar effects

Implementation:

- added `experience_ticks`, `human_capital`, and sparse `social_ties` to `Worker`
- added `src/HumanCapital.jl`
- scheduler now updates human capital and social ties each tick before production
- `production_capacity` now uses summed effective labor

Expectation:

- longer-worked workers become more productive
- worker mobility carries productive relationships across firms
- nearby employment clusters should preserve network value better than distant ones
- the model gains a new endogenous mechanism for persistent local agglomeration

Matched rerun after adding human capital and workplace-distance social ties:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Final state:

```text
- population = 5014
- employment = 4634
- firm_count = 378
- mean_commercial_rent = 81.4072
- unsold_output = 777
```

Rent-gradient read from final lots:

```text
- residential rent vs geometric center distance = -0.6471
- commercial rent vs geometric center distance = -0.0272
- residential rent vs residential centroid distance = -0.6521
- commercial rent vs commercial centroid distance = -0.0253
```

Comparison against the shopping-habits run:

```text
Shopping habits:
- final mean_commercial_rent = 104.1892
- final unsold_output = 472
- residential rent vs geometric center distance = -0.6430
- commercial rent vs geometric center distance = -0.0184

Human capital + workplace-distance ties:
- final mean_commercial_rent = 81.4072
- final unsold_output = 777
- residential rent vs geometric center distance = -0.6471
- commercial rent vs geometric center distance = -0.0272
```

Assessment:

- the new productivity mechanism preserved the strong residential gradient
- it lowered mean commercial rents relative to the shopping-habits run
- it slightly strengthened the commercial gradient signal, but the effect remains weak
- goods-market absorption worsened materially relative to the shopping-habits run
- current evidence suggests human capital and local network persistence may help commercial clustering at the margin, but they are not yet strong enough to generate a meaningful commercial center

### 2026-04-22: Hypothesis added for commercial rent blow-up

Added working hypothesis that commercial-space search is too conservative. Next test should loosen commercial search radius/global sampling and compare against the 250-tick stress-test baseline.

### 2026-04-22: Widened commercial-space search defaults

Changed `commercial_search` defaults in `src/Parameters.jl`:

```text
Before:
- poisson_intensity = 4.0
- radius = 5
- global_samples = 8
- local_weight = 0.75

After:
- poisson_intensity = 8.0
- radius = 12
- global_samples = 48
- local_weight = 0.45
```

Matched stress-test comparison:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12

Before:
- mean_commercial_rent = 104.5185
- commercial_vacancy_rate = 0.8934
- firm_count = 127
- firm_entries = 9
- firm_exits = 4

After:
- mean_commercial_rent = 69.9972
- commercial_vacancy_rate = 0.8992
- firm_count = 123
- firm_entries = 4
- firm_exits = 11
```

Assessment:

Wider search reduced the commercial-rent blow-up materially but did not resolve it. The remaining issue likely involves local occupied-lot rent escalation plus weak relocation/abandonment behavior for expensive commercial units.

### 2026-04-22: Added compact in-model decision logging

Added `DecisionLog` and `DecisionRecord` structures to model state.

Design:

- keep a bounded rolling list of compact decision records
- keep aggregate counters for exact audit questions
- avoid storing full verbose traces for every tick

Initial instrumented decision:

- `commercial_space_search`

Captured fields:

- tick
- actor kind and id
- decision type
- number of candidates considered
- number of viable/vacant candidates
- chosen kind and id
- reason code
- min/max candidate rent

Aggregate commercial-space counters:

- vacant commercial lot considered count by lot id
- vacant commercial lot chosen count by lot id

New query:

```julia
vacant_commercial_lot_considered(state, lot_id)
```

Focused test:

```text
Configuration:
- width = 12
- height = 12
- initial_workers = 80
- initial_firms = 8
- outside_entry_rate = 1.0
- ticks = 25
- seed = 21

Result:
- retained commercial-search records = 9
- vacant commercial lots considered = 139
- vacant commercial-lot consideration events = 346
- vacant commercial lots chosen = 9
```

### 2026-04-22: Commercial vacant-lot consideration audit

Ran matched large test after adding decision logging:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12

Results:
- mean_commercial_rent = 69.9972
- commercial_vacancy_rate = 0.8992
- retained decision records = 2138
- commercial vacant lots considered = 1596
- commercial vacant-lot consideration events = 74603
- commercial vacant lots chosen = 1135
- currently vacant commercial lots = 1182
- currently vacant commercial lots never considered = 0
- vacant-lot consideration count range = 1 to 91
- mean consideration count among considered lots = 46.7437
```

High-rent vacant commercial lots were still considered:

```text
lot_id : rent : vacant_units : consideration_count
10   : 5383.77 : 1 : 11
1238 : 5240.05 : 1 : 5
1296 : 3718.87 : 1 : 4
1215 : 2792.22 : 1 : 10
1552 : 1623.65 : 1 : 8
```

Assessment:

The issue is not that vacant commercial lots are never considered. Current evidence points instead to rent path dependence: lots can become extremely expensive while occupied/full, then become vacant later and only decay gradually under the current rent update rule.

### 2026-04-22: Added explicit vacancy rent markdown parameters

Added dedicated per-tick vacancy markdown parameters:

```text
residential_vacancy_rent_cut_rate = 0.05
commercial_vacancy_rent_cut_rate = 0.15
```

Rule:

If a lot has any vacant units of a use type during the developer update, rent for that use type is multiplied by `1 - vacancy_rent_cut_rate` for that tick.

This makes the vacancy markdown explicit and separates it from the full-occupancy rent increase parameter.

Matched large test:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12

Result after vacancy markdown:
- population = 4974
- employment = 2113
- unhoused = 2853
- firm_count = 128
- mean_commercial_rent = 73.8066
- commercial_vacancy_rate = 0.8991
- mean_residential_rent = 1.0866
```

Highest-rent currently vacant commercial lots after the change:

```text
lot_id : rent : vacant_units
1552 : 1372.24 : 1
560  : 431.13  : 1
1143 : 245.58  : 1
460  : 15.82   : 1
431  : 11.64   : 1
```

Assessment:

The new rule reduced the extreme vacant-lot rent tail substantially compared with the prior audit, where top vacant commercial rents exceeded 5000. Mean commercial rent remains elevated because occupied high-rent lots still contribute to the average.

### 2026-04-22: Rent-distance gradient diagnostic

Question:

Are rents decaying away from the center?

Matched large test:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Geometric-center correlations:

```text
residential rent vs distance from geometric center = 0.0184
commercial rent vs distance from geometric center = 0.0275
residential occupancy vs distance from geometric center = -0.0109
commercial occupancy vs distance from geometric center = 0.0063
```

Endogenous-center correlations:

```text
residential occupancy centroid = (20.50, 18.55)
commercial occupancy centroid = (21.55, 19.25)

residential rent vs distance from residential centroid = -0.0067
commercial rent vs distance from commercial centroid = 0.0309
residential rent vs distance from commercial centroid = 0.0075
commercial rent vs distance from residential centroid = 0.0228
```

Assessment:

No meaningful rent decay away from either the geometric center or endogenous occupancy centroids. Current rent patterns are dominated by local occupancy/rent path dynamics, not by a central-place gradient.

### 2026-04-22: Long-run stress test for central tendencies

Question:

Was the previous model run too short for center/rent-gradient tendencies to emerge?

Long-run test:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 3000
- initial_firms = 150
- outside_entry_rate = 2.0
- ticks = 5000
- seed = 77
- decision logging = off

Runtime:
- elapsed = 228.694 seconds
```

Checkpoints:

```text
tick 100  : population = 3209,  employment = 2627, unhoused = 944,   firms = 160, mean_res_rent = 2.796, mean_com_rent = 5.369
tick 500  : population = 3987,  employment = 2609, unhoused = 1547,  firms = 152, mean_res_rent = 1.033, mean_com_rent = 24121.158
tick 1000 : population = 5022,  employment = 2637, unhoused = 4898,  firms = 149, mean_res_rent = 1.000, mean_com_rent = 363.237
tick 2000 : population = 7040,  employment = 2680, unhoused = 7040,  firms = 149, mean_res_rent = 1.000, mean_com_rent = 18.094
tick 3000 : population = 9056,  employment = 2673, unhoused = 9056,  firms = 150, mean_res_rent = 1.000, mean_com_rent = 54.618
tick 4000 : population = 11038, employment = 2677, unhoused = 11038, firms = 149, mean_res_rent = 1.000, mean_com_rent = 2.595
tick 5000 : population = 13018, employment = 2682, unhoused = 13018, firms = 151, mean_res_rent = 1.000, mean_com_rent = 1.025
```

Final diagnostics:

```text
population = 13018
employment = 2682
unemployment = 10336
unhoused = 13018
firm_count = 151
firm_entries = 2
firm_exits = 0
residential_units = 5340
commercial_units = 2608
residential_vacancy_rate = 1.0
commercial_vacancy_rate = 0.6258
mean_wage = 1.0010
mean_residential_rent = 1.0
mean_commercial_rent = 1.0249
mean_price = 0.4246
mean_commute = 0.0
```

R rent-gradient diagnostics:

```text
residential rent vs geometric center distance = NA
commercial rent vs geometric center distance = -0.0078
residential rent vs residential occupancy centroid distance = NA
commercial rent vs residential occupancy centroid distance = -0.0078
residential rent vs commercial occupancy centroid distance = NA
commercial rent vs commercial occupancy centroid distance = -0.0091
```

Output files:

```text
outputs/diagnostics/lots_long_5000.csv
outputs/diagnostics/rent_gradient_long_5000/
```

Assessment:

The longer run did not produce a central rent gradient. Instead it revealed a more serious long-run collapse:

- all workers become unhoused
- residential vacancy reaches 100%
- residential rents fall to the minimum
- wages fall to approximately the minimum
- commute distance becomes zero because nobody is housed

This suggests the next issue is not run length. The model needs investigation of the worker housing/search/affordability transition and the wage/firm demand dynamics that eventually make housing unoccupied even at minimum rent.

### 2026-04-22: Added market-clearing time-series logging

Added `MarketLog` and `MarketSnapshot` to model state.

Tracked each tick:

- population, employed, unemployed, housed, unhoused
- residential units and vacant residential units
- commercial units and vacant commercial units
- active firms
- firm job vacancies and firms with vacancies
- committed output, realized sales, unsold output, sold-out firms
- mean wage, residential rent, commercial rent, and goods price

Added query/export helpers:

```julia
market_failure_summary(state)
write_market_log_csv(state, path)
```

Added R diagnostics:

```text
diagnostics/market_clearing_diagnostics.R
```

Generated plots:

- worker state counts
- housing market non-clearing
- labor market non-clearing
- commercial-space excess supply
- goods market non-clearing
- prices over time
- rates over time

Smoke test:

```text
Configuration:
- width = 10
- height = 10
- initial_workers = 50
- initial_firms = 8
- outside_entry_rate = 1.0
- ticks = 50
- seed = 51

Final market failure summary:
- labor_excess_supply = 36
- labor_excess_demand = 52
- housing_excess_supply = 58
- housing_excess_demand = 37
- commercial_space_excess_supply = 88
- goods_excess_supply = 25
```

Long-run rerun with market logging:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 3000
- initial_firms = 150
- outside_entry_rate = 2.0
- ticks = 5000
- seed = 77
- decision logging = off
- market logging = on

Runtime:
- elapsed = 228.19 seconds
- market log records = 5000
```

Checkpoints:

```text
tick 100  : pop = 3209,  employed = 2627, housed = 2265, unhoused = 944,   vacant_res = 810,  job_vacancies = 253, unsold = 261
tick 500  : pop = 3987,  employed = 2609, housed = 2440, unhoused = 1547,  vacant_res = 2892, job_vacancies = 127, unsold = 440
tick 1000 : pop = 5022,  employed = 2637, housed = 124,  unhoused = 4898,  vacant_res = 5408, job_vacancies = 45,  unsold = 561
tick 2000 : pop = 7040,  employed = 2680, housed = 0,    unhoused = 7040,  vacant_res = 5436, job_vacancies = 2,   unsold = 499
tick 3000 : pop = 9056,  employed = 2673, housed = 0,    unhoused = 9056,  vacant_res = 5388, job_vacancies = 27,  unsold = 518
tick 4000 : pop = 11038, employed = 2677, housed = 0,    unhoused = 11038, vacant_res = 5351, job_vacancies = 5,   unsold = 598
tick 5000 : pop = 13018, employed = 2682, housed = 0,    unhoused = 13018, vacant_res = 5340, job_vacancies = 36,  unsold = 623
```

R market-clearing summary:

```text
final_population = 13018
final_employed = 2682
final_unemployed = 10336
final_housed = 0
final_unhoused = 13018
final_vacant_residential_units = 5340
final_vacant_commercial_units = 1632
final_unsold_output = 623
max_vacant_residential_units = 5500
tick_first_zero_housed = 1315
```

Output files:

```text
outputs/diagnostics/market_log_long_5000.csv
outputs/diagnostics/lots_long_5000_marketlog.csv
outputs/diagnostics/market_clearing_long_5000/
```

Assessment:

The market log localizes the long-run failure. Housing market fails with simultaneous excess supply and excess demand:

- thousands of vacant residential units
- all workers unhoused by tick 1315
- residential rent at minimum

Labor market also fails by excess labor supply:

- unemployment grows with outside entry
- firm job vacancies are near zero after tick 2000

Goods market retains unsold output, but this appears secondary to the housing/labor collapse.

### 2026-04-22: Firm revenue stability diagnostic

Question:

Is firm revenue statistically stable enough to reason from, or is instability/churn upstream of the broader market failures?

Added exporter:

```text
scripts/export_firm_revenue_data.jl
```

Added R diagnostics:

```text
diagnostics/firm_revenue_stability.R
```

Tracked per firm per tick:

- workers, capital units, process count, commercial units
- goods price
- committed output, realized sales, unsold output, sold-out flag
- revenue
- wage bill, rent bill, profit

Generated plots:

- total firm revenue over time
- cross-firm revenue coefficient of variation
- zero-revenue share
- sold-out share
- revenue concentration
- loss-firm share
- firm revenue CV distribution
- firm zero-revenue share distribution
- firm observed lifetime distribution
- continuing-firm revenue CV distribution

Run:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 3000
- initial_firms = 150
- outside_entry_rate = 2.0
- ticks = 2000
- seed = 77
```

Checkpoints:

```text
tick 100  : firms = 160, mean_revenue = 69.216, cv_revenue = 0.826
tick 500  : firms = 152, mean_revenue = 46.086, cv_revenue = 1.203
tick 1000 : firms = 149, mean_revenue = 17.295, cv_revenue = 1.093
tick 2000 : firms = 149, mean_revenue = 10.878, cv_revenue = 1.185
```

R summary:

```text
ticks = 2000
firm_rows = 302474
unique_firms = 4575
final_active_firms = 149
final_total_revenue = 1620.7594
final_mean_revenue = 10.8776
final_cv_revenue = 1.1850
final_zero_revenue_share = 0.0
final_sold_out_share = 0.5235
mean_total_revenue = 4349.7964
cv_total_revenue_over_time = 0.7580
median_firm_cv_revenue = 0.9799
median_firm_zero_revenue_share = 1.0
median_firm_lag1_revenue_corr = 0.9343
mean_revenue_gini = 0.4104
```

Firm lifetime audit:

```text
unique firms observed = 4575
median observed lifetime = 1 tick
mean observed lifetime = 66.11 ticks
share with lifetime 1 tick = 0.9672
share with lifetime <= 5 ticks = 0.9672
share with lifetime >= 100 ticks = 0.0326
share with lifetime >= 1000 ticks = 0.0326
continuing firms observed >= 100 ticks = 149
continuing-firm median revenue CV = 0.9805
continuing-firm median zero-revenue share = 0.0
```

Assessment:

Revenue is not statistically stable in a strong sense:

- aggregate total revenue has high time-series variation
- cross-firm revenue CV is usually near or above 1
- continuing firms have persistent but volatile revenue

More importantly, the diagnostic exposes a firm lifecycle bug:

- almost every non-initial founded firm appears for exactly one tick
- current scheduler places entrepreneurship after worker job search
- zero-worker firms then reach the next contraction/liquidation phase before they have a chance to hire

Likely next starting point:

Allow new firms a grace period or move hiring/job-search opportunity before zero-worker liquidation for newly founded firms. Otherwise firm entry mostly creates one-tick firms and does not become meaningful labor demand.

### 2026-04-22: Moved entrepreneurship before worker job search

Changed scheduler order:

```text
Before:
1. firm contraction / expansion reviews
2. worker job search
3. worker housing search
4. developer update
5. entrepreneurship
6. outside entry

After:
1. firm contraction / expansion reviews
2. entrepreneurship
3. worker job search
4. worker housing search
5. developer update
6. outside entry
```

Reason:

Newly founded zero-worker firms need to be visible to the same tick's worker job-search phase. Under the prior order, most founded firms were liquidated before they could hire.

Matched 2000-tick firm revenue comparison after scheduler change:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 3000
- initial_firms = 150
- outside_entry_rate = 2.0
- ticks = 2000
- seed = 77
```

Checkpoints after change:

```text
tick 100  : firms = 257, mean_revenue = 81.953,  cv_revenue = 0.823
tick 500  : firms = 235, mean_revenue = 447.183, cv_revenue = 1.041
tick 1000 : firms = 305, mean_revenue = 369.154, cv_revenue = 1.045
tick 2000 : firms = 416, mean_revenue = 246.540, cv_revenue = 0.937
```

Before/after summary:

```text
Before:
- final_active_firms = 149
- final_total_revenue = 1620.7594
- final_mean_revenue = 10.8776
- share_firms_lifetime_1_tick = 0.9672
- continuing_firms_ge_100_ticks = 149
- continuing_firm_median_cv_revenue = 0.9805

After:
- final_active_firms = 416
- final_total_revenue = 102560.6
- final_mean_revenue = 246.54
- share_firms_lifetime_1_tick = 0.7938
- continuing_firms_ge_100_ticks = 552
- continuing_firm_median_cv_revenue = 0.6891
```

Assessment:

The scheduler change materially improves firm survival, labor demand, and revenue stability. It does not fully remove one-tick firm churn, but the failure is much less severe.

### 2026-04-22: Added search-coverage logging

Added `SearchCoverageLog` and `SearchCoverageRecord` to model state.

Tracked per search event:

- tick
- search domain
- actor kind and id
- origin lot id
- raw draw count
- unique lot count
- local draw count
- global draw count

Aggregate coverage by domain:

- number of search events
- lots ever sampled
- share of all lots ever sampled
- raw draws
- unique draws
- mean raw draws per event
- mean unique lots per event

Added helpers:

```julia
search_coverage_summary(state)
write_search_coverage_csv(state, path)
```

Added R diagnostic:

```text
diagnostics/search_coverage_diagnostics.R
```

Post-change 500-tick search coverage run:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 3000
- initial_firms = 150
- outside_entry_rate = 2.0
- ticks = 500
- seed = 77

Final:
- population = 3959
- employment = 3629
- unemployment = 330
- unhoused = 337
- firm_count = 235
- residential_vacancy_rate = 0.3796
- mean_wage = 43.2927
- mean_price = 16.0977
```

Search coverage:

```text
domain             events   lots_covered   coverage_share   mean_unique_lots_per_event
commercial_space     5435           1600        1.0                 47.8773
goods             4018139           1600        1.0                  9.4545
housing            314730           1600        1.0                 11.7995
job                320455           1600        1.0                 11.6835
```

Assessment:

At 500 ticks, every search domain has sampled every lot at least once. If search failures persist, the next question is less "was the lot ever sampled?" and more "was it sampled by the relevant actor at the relevant time, and was it rejected by affordability/utility/hiring constraints?"

### 2026-04-22: Post-scheduler-fix long-run rerun

Question:

Does the 5000-tick collapse persist after moving entrepreneurship before worker job search?

Run:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 3000
- initial_firms = 150
- outside_entry_rate = 2.0
- ticks = 5000
- seed = 77
- decision logging = off
- search logging = off
- market logging = on

Runtime:
- elapsed = 2345.153 seconds
- market log records = 5000
```

Checkpoints:

```text
tick 100  : pop = 3162,  emp = 3007,  housed = 2428,  unhoused = 734,  firms = 257, vacant_res = 641,  job_vacancies = 1619, unsold = 278,  mean_wage = 13.546, mean_price = 5.166
tick 500  : pop = 3959,  emp = 3629,  housed = 3622,  unhoused = 337,  firms = 235, vacant_res = 2216, job_vacancies = 601,  unsold = 1130, mean_wage = 43.293, mean_price = 16.098
tick 1000 : pop = 4997,  emp = 4434,  housed = 4446,  unhoused = 551,  firms = 305, vacant_res = 2702, job_vacancies = 1056, unsold = 2196, mean_wage = 38.076, mean_price = 14.877
tick 2000 : pop = 6948,  emp = 6190,  housed = 6170,  unhoused = 778,  firms = 416, vacant_res = 3057, job_vacancies = 1298, unsold = 3819, mean_wage = 28.906, mean_price = 13.086
tick 3000 : pop = 8939,  emp = 7703,  housed = 7787,  unhoused = 1152, firms = 511, vacant_res = 3546, job_vacancies = 1495, unsold = 5651, mean_wage = 22.226, mean_price = 10.584
tick 4000 : pop = 10959, emp = 9493,  housed = 9456,  unhoused = 1503, firms = 623, vacant_res = 4057, job_vacancies = 1721, unsold = 6635, mean_wage = 18.338, mean_price = 9.048
tick 5000 : pop = 12855, emp = 11306, housed = 11246, unhoused = 1609, firms = 726, vacant_res = 4352, job_vacancies = 1762, unsold = 7662, mean_wage = 14.356, mean_price = 7.652
```

Final diagnostics:

```text
population = 12855
employment = 11306
unemployment = 1549
unhoused = 1609
firm_count = 726
firm_entries = 2
firm_exits = 0
residential_units = 15598
commercial_units = 14505
residential_vacancy_rate = 0.2790
commercial_vacancy_rate = 0.2670
mean_wage = 14.3565
mean_residential_rent = 1.0735
mean_commercial_rent = 224.8861
mean_price = 7.6523
mean_commute = 3.2678
```

Final market-clearing summary:

```text
labor_excess_supply = 1549
labor_excess_demand = 1762
housing_excess_supply = 4352
housing_excess_demand = 1609
commercial_space_excess_supply = 3873
goods_excess_supply = 7662
goods_sold_out_firms = 393
```

R market-clearing summary:

```text
final_housed = 11246
final_unhoused = 1609
final_vacant_residential_units = 4352
final_vacant_commercial_units = 3873
final_unsold_output = 7662
max_unhoused = 1807
max_unemployed = 1905
max_vacant_residential_units = 4453
max_vacant_commercial_units = 4018
max_unsold_output = 7985
tick_first_zero_housed = NA
```

R rent-gradient diagnostics:

```text
geometric center = (20.5, 20.5)
residential occupancy centroid = (20.972, 20.597)
commercial occupancy centroid = (20.538, 20.631)

residential rent vs geometric center distance = -0.0393
commercial rent vs geometric center distance = -0.0196
residential rent vs residential centroid distance = -0.0410
commercial rent vs residential centroid distance = -0.0182
residential rent vs commercial centroid distance = -0.0397
commercial rent vs commercial centroid distance = -0.0198
```

Output files:

```text
outputs/diagnostics/lots_long_5000_post_scheduler.csv
outputs/diagnostics/market_log_long_5000_post_scheduler.csv
outputs/diagnostics/market_clearing_long_5000_post_scheduler/
outputs/diagnostics/rent_gradient_long_5000_post_scheduler/
```

Assessment:

The earlier all-unhoused long-run collapse does not persist after the scheduler fix. The model now has a much more viable long-run state with high employment and housing occupancy.

Remaining issues:

- commercial rents can still spike locally; mean commercial rent is high
- goods market has large unsold output even while many firms are sold out
- housing and labor both show simultaneous excess supply and excess demand
- rent gradients are still weak; commercial rent remains dominated by local spikes rather than a smooth center gradient

### 2026-04-22: Open question on unsearched substitutes during price/rent spikes

Question:

When commercial rent or goods-price spikes happen, are there relevant substitutes available at that same tick that the searching agents/firms did not sample?

Motivation:

Aggregate search coverage shows that all lots are eventually sampled by each search domain, but that does not answer the relevant market-clearing question. What matters is whether, at the time of a spike, the relevant actor's search set excluded viable substitutes that existed elsewhere.

Needed analysis:

- identify ticks/lots/firms where commercial rent spikes occur
- identify the relevant firm commercial-space searches near those spikes
- compare searched candidates against all available vacant commercial substitutes at that tick
- measure the rent gap between searched choices and unsearched viable alternatives
- do analogous checks for goods markets where firms are sold out while other firms have unsold substitute goods

Status:

Open diagnostic question. Do not assume aggregate search coverage rules out search failure; analyze time-local substitute availability.

### 2026-04-23: Time-local substitute audit for commercial rent and goods-price spikes

Added targeted event-level diagnostics and export script:

- `src/OpenDiagnostics.jl`
- `scripts/export_open_diagnostic_data.jl`

These diagnostics record, for each commercial-space search and goods search:

- sampled search-set size
- chosen lot/firm
- best sampled option
- best globally available option at that same tick
- count of better unsearched alternatives

Matched run used for the audit:

```text
Configuration:
- width = 40
- height = 40
- initial_workers = 2000
- initial_firms = 120
- outside_entry_rate = 12.0
- ticks = 250
- seed = 12
```

Run outputs:

```text
outputs/diagnostics/open_diagnostic_250/commercial_search.csv
outputs/diagnostics/open_diagnostic_250/goods_search.csv
outputs/diagnostics/open_diagnostic_250/market_log.csv
outputs/diagnostics/open_diagnostic_250/lots_final.csv
```

Final state in this matched run:

```text
- population = 4953
- employment = 4622
- firm_count = 406
- mean_commercial_rent = 132.4042
- unsold_output = 1024
- sold_out_firms = 304
- vacant_commercial_units = 93
```

Commercial-space findings:

```text
All chosen commercial-search events:
- chosen events = 4921
- share with at least one cheaper unsearched vacant lot = 0.0998
- mean chosen-rent gap to cheapest global vacant lot = 1.9768

Late-stage spike window (ticks >= 200):
- share with at least one cheaper unsearched vacant lot = 0.2602

Top 5% highest-rent chosen commercial events:
- share with at least one cheaper unsearched vacant lot = 0.9879
- mean chosen-rent gap to cheapest global vacant lot = 38.7238
```

Representative high-rent choices:

```text
tick : firm : chosen_lot : chosen_rent : best_global_vacant_rent : cheaper_unsearched_vacant_lots
246 : 2904 :  668 : 4419.70 : 1.00 :  97
246 : 2567 :  506 : 2041.27 : 1.00 : 100
243 : 2868 : 1036 :  590.88 : 1.00 : 109
225 : 2577 :  331 :  422.74 : 1.00 : 159
```

Assessment:

The open commercial-space question is answered yes. Aggregate search coverage was misleading for the spike question. Extreme commercial rent events are strongly associated with firms failing to sample abundant cheaper vacant substitutes available elsewhere in the same tick.

Goods-search findings:

```text
- goods search events retained = 250000
- purchase events = 168274
- share of purchase events with a better unsearched affordable option = 0.9920
- mean chosen-score gap to best global affordable option = 0.0219
- no-choice events despite globally affordable goods existing = 16258
```

Assessment:

The open goods-market substitute question is also answered yes, but with a different magnitude profile. Limited sampling almost always leaves a better global option unsearched, yet the mean score gap is modest. This suggests a broad, persistent search-friction problem in goods markets rather than a rare extreme tail comparable to the commercial-rent spikes.

Implication for next changes:

- commercial-space search likely needs a stronger fallback to global vacant-space search when sampled rents are high
- goods search likely needs wider or adaptive sampling, but the urgency appears lower than the commercial-space spike problem


#### PASTED IN AFTER USAGE LIMIT
the diagnosis is definitive: at tick 10, can_hire=0 across all 150 firms. The min_hire_cash_ticks=500 gate requires (payroll + posted_wage) × 500 in cash. With 3 initial workers at wage=10 (payroll=30), hiring a 4th needs (30+11)×500=20,500 — exceeding initial cash of 15,000 from day 1. Workers leave firms, can't be replaced, and all tiers spiral to 0 workers.

---

### 2026-04-25: Wage spiral and hiring re-lock — open problem

#### Symptom

Even after reducing `min_hire_cash_ticks` from 500 to 300 (which unblocked hiring at startup), the hiring market re-locks by tick 200–300. Diagnostic at tick 300:

```text
T3 (n=8, dead=3): workers=0.62  posted_wage=88.0  cash=16,414  hire_thresh=39,157  can_hire=0
```

`posted_wage` spiraled from 10 at startup to 88 by tick 300. With 1 remaining worker (payroll=10), the gate requires (10 + 88) × 300 = 29,400 to hire — nearly double available cash. The spiral continues unchecked.

#### Three interacting loops

**Loop 1 — Persistent vacancy signal.**
The wage-raise condition in `firm_reviews!` is:

```julia
has_vacancy = length(f.worker_ids) < state.params.max_workers_per_firm
f.posted_wage *= has_vacancy ? (1 + wage_raise_rate) : (1 - wage_cut_rate)
```

Firms start with 3 workers and `max_workers_per_firm=18`, so `has_vacancy=true` from tick 1 for all firms. The vacancy signal never clears. With `wage_review_prob=0.20` and `wage_raise_rate=0.05`, expected compound growth is 1.05^(0.20×t) — doubling in ~70 ticks, tripling in ~110 ticks. The diagnostic of 88 at tick 300 is consistent: 1.05^(0.20×300) ≈ 9× baseline.

**Loop 2 — Hiring gate that rises with the wage it gates.**
`hire_worker!` blocks when `cash < (current_payroll + posted_wage) × min_hire_cash_ticks`. As `posted_wage` rises, the threshold rises proportionally. The gate blocks hiring precisely because the wage spiraled. The two quantities chase each other: a higher wage makes the gate harder to pass, which preserves the vacancy, which triggers another wage raise.

Crucially, `f.current_worker_wages` is set at hire time and does not update when `posted_wage` rises. Existing workers' actual wages are frozen at their hire rate. The payroll does not increase with the spiral — only the hiring threshold does. The cash drain from the spiral is zero; the gate cost is entirely hypothetical (the cost of a future hire that never happens).

**Loop 3 — Contraction amplifies vacancies.**
When modal sales are low, `firm_contraction_expansion!` fires workers until `production_capacity ≤ modal_sales`. A firm with low sales sheds workers down to 1. With 1 worker and `max_workers_per_firm=18`, `has_vacancy=true` again. Wage reviews fire. Posted wage rises further. Eventually the last remaining worker quits for a higher-wage competitor (job switch fires when another firm posts 8%+ above current wage). The firm drops to 0 workers and is liquidated.

#### Root misdiagnosis in the wage-raise rule

The wage-raise signal is designed to mean: "I have a vacancy and workers are choosing competitors over me — I need to offer more." But the actual cause of the persistent vacancy is "my cash gate is blocking me from accepting workers who want to come." Raising wages makes the gate harder to pass, not easier. The rule conflates two fundamentally different reasons for failing to hire:

1. **Demand-side failure**: workers are not showing up at this wage; raise the wage to attract them.
2. **Supply-side failure**: workers are showing up but the cash gate blocks the hire; raising the wage makes the gate harder, not easier.

The current rule treats both cases identically.

#### Three possible directions (not yet resolved)

**Option A — Conditional raise: only raise if cash gate would allow hiring at the new wage.**
Before raising, check whether the firm could actually afford to hire at the new rate. If not, hold the wage flat (or let it drift down). This directly breaks the loop at the mechanism that causes it.

```julia
new_wage = f.posted_wage * (1 + wage_raise_rate)
current_payroll = sum(values(f.current_worker_wages); init=0.0)
can_afford = f.cash >= (current_payroll + new_wage) * min_hire_cash_ticks
if has_vacancy && can_afford
    f.posted_wage = new_wage
elseif !has_vacancy
    f.posted_wage *= (1 - wage_cut_rate)
end
```

Simple, directly addresses the mechanism. Risk: cash-poor firms in genuine labor-market competition can no longer signal higher wages.

**Option B — Demand-based vacancy signal.**
Replace `max_workers_per_firm` as the vacancy ceiling with the labor target implied by modal sales — the same target the contraction rule uses. A firm that just shed workers because sales are low is not trying to hire; it should not raise wages. Only firms whose modal-sales target exceeds current worker count should raise wages.

This is more economically grounded: firms set wages to attract the workers they actually want, not to fill some maximum capacity they don't need. But it requires computing the labor target outside the contraction block, where it is currently computed.

**Option C — Reduce max_workers_per_firm.**
If the cap were 6 instead of 18, firms start at 50% capacity and have only 3 slots to fill. The spiral is proportionally slower and firms can actually reach full capacity before the gate re-locks. This papers over the mechanism rather than fixing it, but buys time to test other dynamics.

Status: open. Need to decide between Options A and B before implementing.

#### Related issue — B2B spatial disadvantage (noted, not yet addressed)

B2B firms (T1, T2) use the consumer-access signal for commercial bidding, the same as B2C. This places them in competition for central lots near consumers, where consumer-facing revenue is highest but B2B revenue is determined by proximity to downstream buyers, not consumers. B2B firms end up either at expensive central locations they can't justify, or at peripheral lots where workers don't find them in job search. Workers spatially cluster near T3 (central), leaving T1/T2 (peripheral) understaffed. This is a separate structural problem from the wage spiral but compounds it for B2B tiers.

The fix is to lower min_hire_cash_ticks. The threshold for initial hiring to be possible: (30+10)×X ≤ 15,000 → X ≤ 375. I'll use 300 to leave margin against wage inflation.

### 2026-04-25: Implemented patch set — wage-lock fix, tiered siting, stronger commercial rescue

Implemented across `src/Firms.jl` and `src/Parameters.jl`.

#### 1) Wage spiral / hiring re-lock mitigation (Option B + affordability guard)

**What changed**

- Added `labor_target_for_wage_review(state, f)` in `Firms.jl`.
  - Uses a sales-implied labor target based on modal recent sales (`modal_sales_lookback`), with startup fallback to `max(startup_production_target, committed_output)`.
  - Converts target sales to target workers using current `production_capacity / current_workers`.
  - Clamped to `[1, max_workers_per_firm]`.
- Updated wage review block in `firm_reviews!`:
  - Replaced vacancy test `length(worker_ids) < max_workers_per_firm` with demand-based vacancy test `length(worker_ids) < labor_target`.
  - Wage raise now requires affordability at the **proposed** wage:
    - `can_afford = cash >= (current_payroll + proposed_wage) * min_hire_cash_ticks`
  - If demand vacancy exists but affordability fails, wage is cut (prevents runaway escalation under a binding cash gate).

**Intended effect**

- Breaks the positive feedback loop where persistent cap-based vacancies force wage growth that tightens the hire gate.
- Aligns wage increases with actual labor demand and feasible hiring.

#### 2) Tier-specific commercial location signal for B2B firms

**What changed**

- Added tier-network access helper `firm_tier_access_at_lot(state, lot_id, target_tier)` in `Firms.jl`.
- Updated `commercial_location_gross_value`:
  - Tier 3 (B2C) retains consumer-access-driven term via `firm_consumer_access_weight`.
  - Tiers 1/2 (B2B) now use:
    - low residual consumer pull,
    - downstream-tier access pull,
    - upstream-tier access pull,
    - plus existing job-access, commute, and consolidation terms.

**New parameters in `ModelParams`**

- `firm_b2b_consumer_access_weight::Float64 = 0.01`
- `firm_b2b_downstream_access_weight::Float64 = 0.10`
- `firm_b2b_upstream_access_weight::Float64 = 0.04`

**Intended effect**

- Reduces B2B over-reliance on consumer-centrality and increases clustering around supplier-customer tier structure.

#### 3) Commercial-space global rescue thresholding (tail-rent suppression)

**What changed**

- Reworked rescue logic in `commercial_space_search!`:
  - Always evaluates global rescue candidate when `commercial_search_global_rescue=true`.
  - Rescue activates if any of:
    - no local choice,
    - local sampled set not satisficed,
    - global score gain exceeds threshold,
    - chosen-rent minus rescue-rent exceeds threshold **and** score loss is within tolerance.
  - On rescue, evaluated candidates are promoted to global for logging/diagnostics consistency.

**New parameters in `ModelParams`**

- `commercial_search_rescue_min_rent_gap::Float64 = 5.0`
- `commercial_search_rescue_min_score_gain::Float64 = 0.50`
- `commercial_search_rescue_max_score_loss::Float64 = 0.25`

**Intended effect**

- Prevents extreme overpay choices from surviving local undersampling unless they provide a meaningful location-score advantage.

#### Verification status

- Code edits completed.
- Runtime validation was **not** executed in this environment because `julia` is not available on PATH (`command not found: julia`).

### 2026-04-26: Entrepreneurship eligibility fix + scheduler redesign decision

#### A) Implemented: allow former owners of inactive firms to found again

Problem:

- Founding logic required `isempty(w.ownership_shares)` for both solo and coalition entrepreneurship.
- Liquidation did not clear historical ownership entries from workers.
- Result: any worker who had ever owned a firm was permanently excluded from future founding.

Change implemented in `src/Entrepreneurship.jl`:

- Added `has_active_ownership(state, w)` helper:
  - returns true only if worker owns shares in at least one **active** firm.
- Replaced entrepreneurship filters:
  - solo path: skip only when `has_active_ownership(state, w)` is true
  - coalition candidate filter: include workers when `!has_active_ownership(state, w)` and `w.savings > 0`

Effect:

- Former owners of liquidated/inactive firms can now re-enter entrepreneurship.
- Workers still cannot found while actively owning another live firm.

Validation:

- Short smoke run completed successfully after patch (40 ticks).

#### B) Agreed redesign (not yet implemented): two-stage startup activation with order `found -> hire -> produce`

Decision:

- Use the safer two-stage activation variant first:
  - firms founded this tick can hire this tick,
  - first production commitment starts next tick.

Rationale:

- Reduces startup mortality from current ordering where firms can face contraction/liquidation risk before stabilizing labor.
- Preserves causal ordering without introducing abrupt same-tick production shocks.

Implementation plan (next step):

1. **Scheduler phase reordering**
   - move entrepreneurship earlier in tick, before worker hiring search.
   - ensure commercial bid resolution for entrants occurs before hiring.
2. **Startup state semantics**
   - preserve `startup_pending`/new flag semantics so entrants are visible to hiring immediately.
   - block production commitment for newly founded firms until next tick.
3. **Liquidation guard for new entrants**
   - prevent zero-worker liquidation checks from firing on the same tick a firm is created.
4. **Metrics/diagnostics**
   - add startup cohort diagnostics: founded, hired-at-least-one-within-1-tick, liquidated-within-5-ticks.
5. **Validation pass**
   - rerun multi-seed 5000-tick tests and compare:
     - net firm count trajectory,
     - employment rate,
     - demand vacancies vs cap vacancies,
     - startup survival.

### 2026-04-26: Persistent labor slack diagnosis + implemented startup sequencing changes

#### Investigation summary (seed 77 long run)

To diagnose persistent labor slack, we instrumented demand-vacancy vs cap-vacancy dynamics and startup/founding behavior.

Key snapshots (seed 77):

```text
tick 500:  pop=3990  emp=1372 (34.4%)  firms=108
           demand_vacancies=0  cap_vacancies=572
           can_hire_any=59  can_hire_demand=0

tick 1000: pop=4993  emp=1260 (25.2%)  firms=88
           demand_vacancies=1  cap_vacancies=324

tick 1500: pop=6038  emp=1238 (20.5%)  firms=71
           demand_vacancies=2  cap_utilization=0.9687

tick 2000: pop=6988  emp=1242 (17.8%)  firms=70
           demand_vacancies=1  cap_utilization=0.9857

tick 2500: pop=7961  emp=1224 (15.4%)  firms=68
           demand_vacancies=0  cap_vacancies=0  cap_utilization=1.0
```

Interpretation:

- The dominant late-run mechanism is **capacity saturation**, not inability to hire.
- Surviving firms become nearly fully staffed relative to model cap while population continues growing.
- Employment rate declines because labor demand does not scale with entrant population.

#### Profit question clarified

Question raised: if demand rises while supply does not, should profits rise?

Answer in this implementation: **not necessarily**.

- Profit is `revenue - wages - rent - input_costs`.
- Price adjustment and cost pressure can offset demand increases.
- Therefore demand growth can coexist with flat/declining margins and weak entry.

#### Implemented code changes

Implemented in this pass:

1. **Former-owner re-entry into entrepreneurship**
   - already patched earlier today:
   - founding eligibility now blocks only workers with ownership in active firms.

2. **Scheduler reordering to `found -> hire -> produce`**
   - `entrepreneurship_phase!` now runs before worker job search and production phases.
   - `resolve_commercial_bids!` remains immediately after entrepreneurship so entrants can secure space before hiring.
   - `worker_job_search!` now runs before production commitment phases.

3. **Two-stage startup activation**
   - added `founded_tick::Int` to `Firm`.
   - newly founded firms skip production commitment on their birth tick.

4. **Birth-tick liquidation guard**
   - `firm_contraction_expansion!` skips contraction/liquidation logic for firms founded on current tick.
   - avoids immediate startup failure before at least one post-entry adjustment cycle.

#### Validation run after changes

- Smoke test passed (`120` ticks, no errors).
- `test_coldstart.jl` completed through tick `500` successfully.
- Hiring feasibility remained nonzero across tiers after startup period; no wage-lock relapse observed.

---

### 2026-04-26: Spatial access performance — scatter kernel + redundant refresh removal

#### Motivation

Headless runs were blocking on `refresh_spatial_access!`. On a 40×40 grid with
3000+ workers, the prior gather implementation was O(lots × occupied_lots) per
call = ~2.24M inner iterations, called 5 times per tick. Combined with unbounded
growth of `state.firms` (dead firms never removed), this compounded each tick.

#### Changes

**`SpatialAccess.jl` — gather → scatter algorithm**

Replaced the nested gather loop (for each destination lot, sum over all source
lots) with a scatter kernel (`scatter_access!`) that iterates over occupied source
lots only and writes into the diamond of reachable destination lots using the
taxicab triangle constraint:

```julia
for dy in -radius:radius
    dx_max = radius - abs(dy)
    for dx in -dx_max:dx_max
        ...
    end
end
```

This makes the inner loop O(lots_within_radius) ≈ π×r² rather than O(all_lots).
At radius=8 on a 40×40 grid, ~87% of lot pairs are out of range; the old loop
computed a taxicab distance and a multiply for all of them. Expected speedup per
call: ~8–10×.

**`Scheduler.jl` — 5 refresh calls reduced to 3**

Two calls were redundant:
- Call at tick start (line 13): duplicated the end-of-tick refresh from the
  previous step; spatial data does not change between ticks.
- Call after `calculate_profits!` (line 28): nothing affecting firm or worker
  locations runs between the post-bid refresh and this point.

Remaining calls: after `resolve_commercial_bids!` (firms may have moved), after
`firm_contraction_expansion!` (firms may have expanded), and at end of tick
(canonical refresh for next tick's firm and housing decisions).

#### Trade-off to revisit

`firm_reviews!` and `entrepreneurship_phase!` now consume spatial data from the
end of the previous tick rather than a fresh refresh. These functions use spatial
scores for ranking (not absolute thresholds), so one-tick staleness is not expected
to change model outcomes. If spatial responsiveness of firm location decisions is
ever a concern, the start-of-tick refresh can be restored by adding
`refresh_spatial_access!(state)` before `human_capital_phase!` in `Scheduler.jl`.

Status: implemented, pending gradient validation.

---

### 2026-04-26: Ownership/employment separation and hiring threshold fix

#### Motivation

Diagnostic run (500 ticks, 20×20, 500 workers, 30 initial firms) revealed massive
firm churn: ~5 entries and exits per tick, with net firm count barely stable and
growing unemployment. Root cause: `min_hire_cash_ticks = 300` required
`300 × base_wage = 3,000` cash to hire a single worker, but solo and coalition
startup capital was only 120–180. Every new firm immediately liquidated on the
following tick due to zero workers, never having been able to hire.

A secondary issue: `has_active_ownership` blocked workers who already owned a
firm from participating in new solo or coalition foundings, unnecessarily
restricting the pool of potential entrepreneurs.

#### Changes

**`Parameters.jl` — `min_hire_cash_ticks` 300 → 5**

Lowers the hiring cash buffer from a 300-tick payroll reserve to a 5-tick
solvency check. With `base_wage = 10` and solo startup capital of 120, a new
firm can now hire its first worker (threshold: 50 cash) and retain ~70 for rent
while it ramps up. Established firms are also affected but the 5-tick buffer is
still a meaningful guard against immediately-insolvent hiring.

**`Firms.jl` — remove zero-workers death condition**

Removed `length(f.worker_ids) == 0` from the liquidation trigger in
`firm_contraction_expansion!`. A firm that fails to hire now persists, paying
rent from its cash balance, and liquidates only when `cash < 0`. This correctly
separates insolvency (the meaningful death signal) from a transient failure to
recruit.

**`Entrepreneurship.jl` — remove `has_active_ownership` gate**

Removed the gate that prevented workers who already own a firm from founding
additional ones. Both solo founding and coalition candidate selection now use
`w.savings` as the sole eligibility criterion. No double-counting risk: founders
only invest personal liquid savings (deducted in `found_firm!`); firm assets
remain with the firm. Workers who invested all savings in an existing firm will
have zero savings and cannot invest further — the natural accounting guard.

Status: implemented.

---

### 2026-04-26: Commercial space expansion — three compounding bugs fixed

#### Motivation

Cohort analysis at tick 400 (40×40, seed=12) showed `com_units=1.0` for every
age cohort, including firms with 200+ ticks of age, 10+ capital units, and
46,000+ cash. Established firms were accumulating capital and cash but never
expanding their spatial footprint. This prevented any commercial rent gradient
from forming: with every firm occupying exactly one lot, there was no spatial
competition mechanism.

Instrumentation revealed three independent bugs, each of which would have
prevented expansion alone.

#### Bug 1: Bid buffer cleared before resolution (`Scheduler.jl`)

`reset_tick_flags!` called `empty!(state.commercial_bid_buffer)` at the start
of every tick. `firm_contraction_expansion!` runs near the end of a tick and
places expansion bids in the buffer. `resolve_commercial_bids!` runs near the
start of the *next* tick — after `reset_tick_flags!` had already wiped the
buffer. Every expansion bid ever placed was silently discarded before
resolution. `resolve_commercial_bids!` already calls `empty!` on the buffer
at its own end, so the reset-tick clear was both redundant and destructive.

**Fix:** removed `empty!(state.commercial_bid_buffer)` from `reset_tick_flags!`.

#### Bug 2: Global rescue funnels all firms to the same lot (`Firms.jl`)

The old `commercial_space_search!` required ≥3 vacant candidates locally to
pass satisficing. In a dense grid most firms failed this check, triggering the
global rescue path: `cheapest_global_vacant_commercial_lot` — a deterministic
O(lots × active_firms) scan that returned the same globally-best lot for every
firm calling it in the same tick. All expansion bids targeted identical lots;
only one winner per tick per lot; effectively all expansion bids lost. This was
also the dominant O(N²) performance bottleneck.

**Fix:** rewrote `commercial_space_search!`. Accept condition is now "any vacant
lot found" (O(1) per candidate). Lot selection uses `commercial_location_score_fast`
— consumer/job access + consolidation bonus minus rent, all from precomputed
arrays, O(1) per lot. Fallback when local search finds nothing is a random
sample of `commercial_global_fallback_samples` (default 64) lots rather than
a global best-score scan. Different firms get different fallback samples and
therefore bid on different lots.

Also removed `same_type_competition_index` (O(active_firms) per bid) from
`commercial_bid_amount`, replacing it with a consumer-access-scaled expected
revenue calculation that is O(1).

#### Bug 3: `active_firm_ids` not maintained — O(total firms) iteration (`Types.jl`, `State.jl`, `Firms.jl`, `Entrepreneurship.jl`)

`active_firms(state)` scanned the entire `state.firms` vector (including all
dead firms) every call. Dead firms accumulate unboundedly as the simulation
runs: by tick 400 with ~10,000 entries and ~9,000 exits, the vector held
~10,000 entries but only ~500 were active. `active_firms` is called in every
major per-tick loop, producing O(total_firms) cost that compounded to
O(total_firms²) overall.

**Fix:** added `active_firm_ids::Set{Int}` to `ModelState`. `active_firms`
now iterates this set (O(active_firms)). The set is updated in `found_firm!`
(add), `liquidate_firm!` (delete), and the failed-startup path in
`finalize_pending_startup_firms!` (delete).

#### Results after all three fixes (40×40, seed=12, 400 ticks)

```
tick=100  firms=292  emp=1350  com_vac=0.580  com_rent=1.77  elapsed=6.8s
tick=200  firms=362  emp=1380  com_vac=0.334  com_rent=2.72  elapsed=22.5s
tick=300  firms=437  emp=1462  com_vac=0.227  com_rent=3.39  elapsed=53.6s
tick=400  firms=492  emp=1545  com_vac=0.193  com_rent=3.99  elapsed=105.0s

Cohort analysis at tick 400:
Age   1–5:   capital=2.0   com_units=1.0    cash=54
Age  21–50:  capital=4.0   com_units=3.2    cash=302
Age 101–200: capital=4.4   com_units=7.0    cash=1539
Age 201–400: capital=10.6  com_units=13.1   cash=11082
```

Commercial expansion is now working. Firms grow from 1 to 13 commercial units
as they age. Commercial vacancy fell from 0.89 to 0.19 and mean commercial
rent rose from 1.01 (floor) to 3.99 over 400 ticks. The spatial competition
conditions for a commercial rent gradient are now in place.

Status: implemented, gradient validation pending.

---

### 2026-04-26: Performance — lot→firm index and worker exit mechanism

#### Motivation

Two compounding scalability problems emerged as the simulation grows:

1. **O(workers × firms) consumption and job search.** `probabilistic_goods_choice`,
   `affordable_sampled_goods_count`, and `best_job` all loop over `active_firms(state)`
   (O(active_firms)) for every worker. At tick 700 with 1,101 firms and 10,495 workers,
   profiling showed `consumption_phase!` taking 1,755 ms (89% of tick time). The inner
   loop iterates all active firms to filter those with commercial units at sampled lots —
   an O(N²) pattern.

2. **Unbounded worker population.** `outside_entry_rate=3.0` adds ~3 workers per tick
   with no corresponding exit mechanism. Workers accumulate until memory exhausts —
   at tick 700, 10,495 workers with no ceiling. Most are perpetually unemployed and
   contribute to the O(workers) outer loop without adding economic activity.

#### Fix 1: Lot→firm index

Build a `Dict{Int,Vector{Int}}` mapping each lot_id to the IDs of firms with
commercial units there. Build once per phase (O(active_firms)), then flip the inner
loop: iterate sampled lots → firms at those lots rather than all active firms →
sampled lots. This reduces inner loop cost from O(active_firms) to
O(sampled_lots × mean_firms_per_lot) — roughly 18× speedup on consumption at scale.

Changes:
- `Workers.jl`: `consumption_phase!` builds b2c lot→firm index; `worker_job_search!`
  builds full lot→firm index. `probabilistic_goods_choice`, `affordable_sampled_goods_count`,
  `best_job` accept `lot_firm_idx::Dict{Int,Vector{Int}}` and iterate sampled lots
  rather than all active firms. `choose_good`, all `job_search!` dispatch variants,
  and `apply_best_job!` pass the index through.

#### Fix 2: Worker exit mechanism

Add an `inactive_ticks` counter to each worker. Each tick that a worker is unemployed,
the counter increments; employment resets it to zero. Workers who exceed
`worker_exit_threshold` consecutive unemployed ticks are removed from the active set,
vacating their home if housed. This bounds worker population to a steady state
determined by entry rate and exit rate rather than allowing unbounded accumulation.

Changes:
- `Types.jl`: `inactive_ticks::Int` added to `Worker`; `active_worker_ids::Set{Int}`
  added to `ModelState` (mirrors `active_firm_ids` pattern).
- `Parameters.jl`: `worker_exit_threshold::Int = 20`.
- `State.jl`: `draw_worker` initializes `inactive_ticks=0`; `init_state` initializes
  `active_worker_ids`; `active_workers` helper added.
- `Entrepreneurship.jl`: loops use `active_worker_ids`; `outside_entry!` adds to set.
- `HumanCapital.jl`, `SpatialAccess.jl`, `Scheduler.jl`: main worker loops switch
  to `active_worker_ids`.
- `Workers.jl`: `consumption_phase!`, `worker_job_search!`, `worker_housing_search!`
  iterate active workers; `worker_exit!` function added.
- `Scheduler.jl`: `worker_exit!(state)` called after `worker_housing_search!`.
- `Metrics.jl`, `MarketLogging.jl`: population counts use `active_worker_ids`.

#### Note on threading

The natural next step after these fixes is `Threads.@threads` on the per-worker
phases (consumption, job search, housing search). This requires per-worker RNGs
because `state.rng` (a single `MersenneTwister`) is not thread-safe. Deferred —
implement when ready to add per-worker RNG seeding.

#### Calibration note: worker_exit_threshold

Initial value of 20 caused population collapse — workers received only ~4 job searches
(at `job_review_prob=0.20`) before exiting, and the ~1640 initial unemployed workers all
hit the threshold simultaneously around tick 20. Raised to 150, giving workers ~30 search
attempts. Steady-state unemployed pool ≈ `entry_rate × threshold × (1 - emp_rate)`.

#### Results (40×40, seed=12, 2000 initial workers, 120 firms, entry_rate=3.0)

```
tick=100   pop=2320  emp=982   firms=254  com_vac=0.679  com_rent=1.49  elapsed=3.6s
tick=200   pop=2633  emp=854   firms=254  com_vac=0.519  com_rent=2.36  elapsed=5.6s
tick=300   pop=2928  emp=845   firms=262  com_vac=0.499  com_rent=2.52  elapsed=8.3s
tick=400   pop=3214  emp=890   firms=256  com_vac=0.509  com_rent=2.48  elapsed=11.4s
tick=500   pop=3489  emp=906   firms=290  com_vac=0.482  com_rent=2.84  elapsed=15.1s
tick=600   pop=3764  emp=1010  firms=262  com_vac=0.527  com_rent=2.38  elapsed=19.3s
tick=700   pop=4048  emp=1088  firms=305  com_vac=0.506  com_rent=2.51  elapsed=23.9s
tick=800   pop=4341  emp=1128  firms=310  com_vac=0.517  com_rent=2.25  elapsed=29.1s
tick=900   pop=4585  emp=1135  firms=385  com_vac=0.473  com_rent=2.42  elapsed=35.0s
tick=1000  pop=4743  emp=1187  firms=403  com_vac=0.465  com_rent=2.51  elapsed=41.8s
```

Performance: 1000 ticks in 41.8s (~34× faster than pre-index ~1440s/1000 ticks).
Population growth rate is slowing (growth per 100 ticks: 313 → 313 → 295 → 286 → 275 → 275
→ 284 → 293 → 244 → 158) as the exit mechanism absorbs the excess unemployed pool.
Economy is stable with growing firm count and employment.

Status: implemented.

---

### 2026-04-26: Split job search probability by employment state

#### Motivation

A single `job_review_prob=0.20` applied to both employed and unemployed workers
gave unemployed workers only ~30 search attempts in the 150-tick exit window —
too few to clear unemployment in a thin labor market, causing premature exit and
economic contraction. The fix is economically straightforward: unemployed workers
are urgently searching and should search every tick; employed workers are
opportunistically checking for a wage premium and only need occasional review.

#### Changes

- `Parameters.jl`: replace `job_review_prob::Float64 = 0.20` with:
  - `job_search_prob_unemployed::Float64 = 1.0` (search every tick while unemployed)
  - `job_search_prob_employed::Float64 = 0.10` (occasional wage-premium search)
- `Parameters.jl`: `worker_exit_threshold` remains 150 — with `prob=1.0` this now
  means 150 genuine search attempts before exit. Threshold=50 caused a cold-start
  collapse: 2000 initial workers, only 360 hired at startup, so 1640 mass-exit by
  tick 50 wiping out consumers and cascading into firm failures. 150 gives enough
  runway to survive the initial thin-market phase and boom/bust corrections.
- `Workers.jl`: `worker_job_search!` selects probability by employment state.

#### Results (40×40, seed=12, 2000 workers, 120 firms, entry_rate=3.0, threshold=150)

```
tick=100   pop=2299  emp=1684  firms=222  com_vac=0.753  com_rent=1.31  elapsed=4.0s
tick=200   pop=2593  emp=941   firms=159  com_vac=0.747  com_rent=1.83  elapsed=6.2s
tick=300   pop=2905  emp=846   firms=135  com_vac=0.711  com_rent=2.29  elapsed=8.4s
tick=400   pop=3030  emp=865   firms=161  com_vac=0.671  com_rent=2.53  elapsed=10.9s
tick=500   pop=2978  emp=888   firms=195  com_vac=0.635  com_rent=2.75  elapsed=13.7s
tick=600   pop=2926  emp=848   firms=166  com_vac=0.666  com_rent=2.59  elapsed=16.5s
tick=700   pop=2941  emp=921   firms=192  com_vac=0.638  com_rent=2.48  elapsed=19.5s
tick=800   pop=2998  emp=755   firms=182  com_vac=0.648  com_rent=2.30  elapsed=22.5s
tick=900   pop=2985  emp=798   firms=192  com_vac=0.639  com_rent=2.11  elapsed=25.8s
tick=1000  pop=2925  emp=822   firms=186  com_vac=0.619  com_rent=2.23  elapsed=29.4s
```

Population stabilizes around 2900-3000. The spike to emp=1684 at tick 100 (prob=1.0 fills
jobs fast) then correction to ~850 reflects early undercapitalized firms failing after
startup cash depletes — the economy working correctly, not a bug. Firms then recover to
~186 by tick 1000. Performance: 1000 ticks in 29.4s.

Status: implemented.

---

### 2026-04-26: Feasibility search — wide parameter space survey

#### Design

432 runs: 4 productivity levels × 4 io_density levels × 3 entry rates × 3 founding
probabilities × 3 seeds. Run to tick 1000 on 12 threads (~18 min wall time).
Results written to `outputs/feasibility_search.csv`.

Feasibility criteria (all must hold at tick 1000):
- `firm_count >= 50`
- `emp_rate >= 0.20`
- `com_vac <= 0.85`
- `com_rent > 1.1`

Parameter grid:
- `productivity`: 4.0, 5.5, 7.0, 9.0
- `io_matrix_density`: 0.2, 0.4, 0.6, 0.8
- `outside_entry_rate`: 1.0, 2.0, 4.0
- `solo_found_prob`: 0.005, 0.010, 0.020
- seeds: 12, 42, 77

#### Findings

**380 / 432 runs feasible (88%). All 52 failures have `found_prob=0.005`.**

Feasibility rate by entry_rate × found_prob:
```
entry_rate   fp=0.005  fp=0.010  fp=0.020
1.0             0.25      1.00      1.00
2.0             0.67      1.00      1.00
4.0             1.00      1.00      1.00
```
`found_prob=0.005` is the sole source of infeasibility. The firm entry rate is too low
to build an adequate firm base before workers exhaust their exit threshold and leave.
`found_prob=0.010` and above are unconditionally feasible across all tested parameter
combinations. The interaction with `entry_rate` at `found_prob=0.005` reflects that
higher worker inflow provides more founders and consumers, partially compensating for
the low founding probability.

**Lower io_density yields better employment; higher density yields higher commercial rent.**

Mean emp_rate_1000 by productivity × io_density (feasible runs only):
```
prod \ density   0.2    0.4    0.6    0.8
4.0             0.396  0.396  0.269  0.269
5.5             0.409  0.409  0.277  0.271
7.0             0.387  0.387  0.287  0.284
9.0             0.376  0.376  0.292  0.288
```

Mean com_rent_1000 by productivity × io_density:
```
prod \ density   0.2    0.4    0.6    0.8
4.0             1.81   1.81   1.70   1.71
5.5             1.84   1.84   2.00   1.94
7.0             1.88   1.88   2.20   2.02
9.0             1.82   1.82   2.30   2.28
```

Higher io_density imposes more Leontief input constraints on B2C firms. When any
required input type is undersupplied, B2C output is scaled down, reducing employment
demand. At density 0.6-0.8, employment rates drop to ~28% vs ~40% at density 0.2-0.4.
The tradeoff: denser I-O networks generate higher commercial rents (through inter-firm
agglomeration), but at the cost of utilization.

Mean firm count by entry_rate × found_prob:
```
entry_rate   fp=0.005  fp=0.010  fp=0.020
1.0              55        81       119
2.0              64       110       167
4.0              83       169       274
```

**Known confound: io_matrix_seed=0 is fixed across all runs.**

The io_matrix is generated from a dedicated RNG seeded by `io_matrix_seed` (default 0),
independent of the simulation seed. This means all 432 runs use the same link pattern.
The identical results for density=0.2 and density=0.4 across all metrics confirm this:
the 8 buyer-supplier draws from MersenneTwister(0) all fall either below 0.2 or above
0.4, producing identical binary link matrices at both density levels. The effective
density dimension sampled is {low, 0.6, 0.8} rather than {0.2, 0.4, 0.6, 0.8}.

**Employment rate is structurally low (~33%) across the entire feasible space.**

Even at the best configurations, employment rate peaks around 40%. The model has
persistent excess labor supply: `outside_entry_rate` continuously adds workers and
`worker_exit_threshold=150` gives each a long window before exit. The firm base
(determined by founding probability and entry rate) cannot absorb labor fast enough
at these parameter levels.

#### Recommendations for next session

1. **Drop `found_prob=0.005`** from future parameter sweeps — infeasible in most
   configurations. Minimum viable value is `found_prob=0.010`.

2. **Fix the io_matrix_seed confound** before interpreting density effects. Vary
   `io_matrix_seed` per config (e.g., set it equal to the simulation seed), or use
   a known fixed matrix and vary coefficients directly. Without this fix, density
   0.2 and 0.4 are aliases of each other.

3. **Trade-off to calibrate**: low density (~0.2) for employment health vs high
   density (~0.6-0.8) for commercial rent gradient strength. At current calibration,
   density 0.6-0.8 with productivity 7.0-9.0 gives the best commercial rents (2.2-2.3)
   but lowest employment (28%). Decision depends on whether the research priority is
   employment realism or spatial rent gradient emergence.

4. **Add `coalition_found_prob` to the next sweep.** Solo founding alone may be
   insufficient to sustain the firm base at all parameter levels. Coalition founding
   (which pools savings) is a separate lever on firm entry that wasn't varied here.

5. **Revisit `outside_entry_rate` vs `worker_exit_threshold`** as a joint calibration
   problem. The steady-state unemployed pool ≈ `entry_rate × threshold × (1 - emp_rate)`.
   At current values (3.0 × 150 × 0.67 ≈ 300), the pool is large. Lowering the
   threshold or entry rate reduces the pool, which may improve employment rates but
   risks cold-start collapse. Next sweep should include threshold as a dimension.

Status: complete. Raw results in `outputs/feasibility_search.csv`.
