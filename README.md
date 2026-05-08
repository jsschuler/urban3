# Urban ABM

This is the first incremental implementation of the urbanization ABM described in `instructions.md`.

The Julia simulation is the authoritative state owner. Browser and Blender clients communicate over websockets and do not compute model transitions.

## Layout

- `src/` Julia model modules
- `gui/index.html` browser control and diagnostics client
- `blender/blender_client.py` Blender websocket visualization client

## Run

Julia is not available on this machine's current `PATH`, so this was not executed locally here. Once Julia is installed:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. src/Main.jl
```

Then open `gui/index.html`.

The GUI websocket defaults to `ws://127.0.0.1:8766`.
The Blender websocket defaults to `ws://127.0.0.1:8765`.

## Headless Use

```julia
using UrbanABM

state = init_state(ModelParams(initial_workers=200, initial_firms=20))
run!(state, 100)
metrics_snapshot(state)
```

## Rent Gradient Diagnostics

Export lot-level data from a model run:

```bash
JULIA_DEPOT_PATH=/tmp/julia_depot julia --project=. scripts/export_rent_gradient_data.jl
```

Generate ggplot diagnostics:

```bash
Rscript diagnostics/rent_gradient_diagnostics.R \
  outputs/diagnostics/lots_latest.csv \
  outputs/diagnostics/rent_gradient
```

Outputs include rent-distance correlations, binned rent profiles, rent maps,
occupancy maps, and high-rent vacant commercial lots.

## Market Clearing Diagnostics

Runs can export the built-in market log with `write_market_log_csv(state, path)`.
Generate plots from a market log CSV:

```bash
Rscript diagnostics/market_clearing_diagnostics.R \
  outputs/diagnostics/market_log_latest.csv \
  outputs/diagnostics/market_clearing
```

Outputs include labor, housing, commercial-space, and goods-market
non-clearing plots over time.

## Firm Revenue Stability Diagnostics

Export a firm-by-tick revenue panel:

```bash
JULIA_DEPOT_PATH=/tmp/julia_depot julia --project=. scripts/export_firm_revenue_data.jl
```

Generate stability plots:

```bash
Rscript diagnostics/firm_revenue_stability.R \
  outputs/diagnostics/firm_revenue_latest.csv \
  outputs/diagnostics/firm_revenue_stability
```

Outputs include total revenue over time, cross-firm revenue CV, zero-revenue
share, sold-out share, revenue concentration, and firm-level revenue CV
distributions.

## Search Coverage Diagnostics

Runs can export search coverage with `write_search_coverage_csv(state, path)`.
Generate coverage plots:

```bash
Rscript diagnostics/search_coverage_diagnostics.R \
  outputs/diagnostics/search_coverage_latest.csv \
  outputs/diagnostics/search_coverage
```

Outputs include search event counts, share of lots ever sampled, and mean
unique lots sampled per search event by domain.
