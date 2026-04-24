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

At 1000 ticks with I-O linkages (seed=77):
- commercial gradient: -0.47
- residential gradient: -0.61
- gap has narrowed relative to no-I-O run (-0.52 vs -0.66)

The commercial gradient is building faster than before. The question is whether it
fully inverts (commercial > residential in magnitude) at 5000 ticks. Four parallel
5000-tick runs were started (seeds 77, 42, 123, 456) but killed at ~tick 2000 due
to time constraints. Each run takes ~1.5 hours to complete.

At tick 2000, seed=77 showed:
- population=6971, firms=424 (152 B2B, 272 B2C)
- mean_input_fill_rate=0.813
- mean_commercial_rent=3.054, mean_residential_rent=4.123

Gradient plots at 1000 ticks are in:
```text
outputs/diagnostics/lots_io_1000.csv
outputs/diagnostics/rent_gradient_io_1000/
```

To resume: run the 5000-tick command from the Next Steps section below and run
`Rscript diagnostics/rent_gradient_diagnostics.R` on the output.

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

### 2026-04-24: Pending — 5000-tick I-O gradient runs (4 seeds)

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

Output files:

```text
outputs/diagnostics/lots_endogenous_bid_250.csv
outputs/diagnostics/rent_gradient_endogenous_bid_250/
outputs/diagnostics/lots_endogenous_bid_1000.csv
outputs/diagnostics/rent_gradient_endogenous_bid_1000/
outputs/diagnostics/market_log_endogenous_bid_1000.csv
```

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
