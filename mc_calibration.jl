using UrbanABM
using Base.Threads
using Printf
using Statistics
using Random

# ── Configuration ─────────────────────────────────────────────────────────────
# Run with:  julia --threads=auto --project=. mc_calibration.jl

const N_SAMPLES = 2000
const N_TICKS   = 750           # long enough to see expansion and firm growth
const SEEDS     = [42, 77]      # average over 2 seeds to reduce stochastic noise
const OUT       = "outputs/mc_calibration.csv"

# ── Parameter space ───────────────────────────────────────────────────────────
# Core bootstrap parameters (why the economy can't grow from founding headcount):
#   productivity:       output_per_worker ≈ 1.23 × productivity.
#                       Growth requires output_per_worker < sales_per_firm,
#                       which at founding ≈ 1.5 × initial_hire.
#                       So growth iff productivity < 1.22 × initial_hire.
#                       With current defaults (prod=6.5, hire=3): 6.5 > 3.66 → stuck.
#   initial_hire_per_firm: direct seed of initial consumer base.
#
# Secondary calibration parameters:
#   solo_found_prob:    rate of entrepreneurial firm founding
#   goods_tc:           travel cost for goods (affects spatial access vs demand)
#   bid_share:          fraction of marginal revenue bid as commercial rent
#   grid_min_res_occ:   residential occupancy threshold for grid expansion
#   sold_out_premium:   expansion incentive multiplier when sold out

function make_firm_types(prod::Float64)
    [
        UrbanABM.FirmTypeParams(supply_tier=1, productivity=prod,
            initial_goods_price_min=2.5, initial_goods_price_max=4.0),
        UrbanABM.FirmTypeParams(supply_tier=1, productivity=prod,
            initial_goods_price_min=2.5, initial_goods_price_max=4.0),
        UrbanABM.FirmTypeParams(supply_tier=2, productivity=prod,
            initial_goods_price_min=3.5, initial_goods_price_max=5.5),
        UrbanABM.FirmTypeParams(supply_tier=2, productivity=prod,
            initial_goods_price_min=3.5, initial_goods_price_max=5.5),
        UrbanABM.FirmTypeParams(supply_tier=3, productivity=prod,
            initial_goods_price_min=4.0, initial_goods_price_max=6.5),
        UrbanABM.FirmTypeParams(supply_tier=3, productivity=prod,
            initial_goods_price_min=4.0, initial_goods_price_max=6.5),
    ]
end

# ── Inner simulation ──────────────────────────────────────────────────────────

function run_one(seed::Int;
    productivity::Float64,
    initial_hire::Int,
    solo_found_prob::Float64,
    goods_tc::Float64,
    bid_share::Float64,
    grid_min_res_occ::Float64,
    sold_out_premium::Float64,
)
    params = ModelParams(
        seed                                   = seed,
        firm_types                             = make_firm_types(productivity),
        initial_hire_per_firm                  = initial_hire,
        solo_found_prob                        = solo_found_prob,
        goods_travel_cost_per_block            = goods_tc,
        commercial_bid_share                   = bid_share,
        grid_expansion_min_residential_occupancy = grid_min_res_occ,
        sold_out_expansion_premium             = sold_out_premium,
        enable_decision_logging                = false,
        enable_search_logging                  = false,
        enable_market_logging                  = false,
    )

    state    = init_state(params)
    n0       = length(state.active_worker_ids)

    snap100  = (pop=0, emp=0.0, firms=0, expanded=false)
    snap250  = (pop=0, emp=0.0, firms=0, expanded=false)
    snap500  = (pop=0, emp=0.0, firms=0, expanded=false)
    snap750  = (pop=0, emp=0.0, firms=0, expanded=false)

    for t in 1:N_TICKS
        step!(state)
        if t in (100, 250, 500, 750)
            aw  = state.active_worker_ids
            pop = length(aw)
            emp = pop > 0 ? count(w -> !isnothing(state.workers[w].employer_id), aw) / pop : 0.0
            snap = (pop=pop, emp=emp, firms=length(state.active_firm_ids),
                    expanded=state.params.width > params.width)
            t == 100 && (snap100 = snap)
            t == 250 && (snap250 = snap)
            t == 500 && (snap500 = snap)
            t == 750 && (snap750 = snap)
        end
    end

    return (snap100=snap100, snap250=snap250, snap500=snap500, snap750=snap750)
end

# ── Score ─────────────────────────────────────────────────────────────────────
# Weighted composite — max = 7.5:
#   pop growth  (weight 3): most important; want > 4× founding headcount
#   employment  (weight 2): want mean > 0.60
#   expansion   (weight 1.5): grid expanded at all
#   firm growth (weight 1): non-investor firms survived to t=750

function compute_score(pop_growth, mean_emp, grid_expanded, firm_growth)
    3.0 * min(1.0, pop_growth / 4.0) +
    2.0 * clamp(mean_emp, 0.0, 1.0) +
    (grid_expanded ? 1.5 : 0.0) +
    (firm_growth   ? 1.0 : 0.0)
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main()
    rng = Random.MersenneTwister(99991)

    # Sample all configurations up front (before threading, to keep RNG sequential)
    configs = [(
        productivity    = 3.0 + rand(rng) * 5.0,                        # [3.0, 8.0]
        initial_hire    = rand(rng, 3:8),                                # {3..8}
        solo_found_prob = exp(rand(rng) * (log(0.03) - log(0.003)) + log(0.003)),  # log-unif
        goods_tc        = exp(rand(rng) * (log(0.20) - log(0.02)) + log(0.02)),    # log-unif
        bid_share       = 0.05 + rand(rng) * 0.15,                      # [0.05, 0.20]
        grid_min_res_occ = 0.50 + rand(rng) * 0.40,                     # [0.50, 0.90]
        sold_out_premium = 0.20 + rand(rng) * 0.80,                     # [0.20, 1.00]
    ) for _ in 1:N_SAMPLES]

    results = Vector{Any}(undef, N_SAMPLES)
    n_done  = Threads.Atomic{Int}(0)

    println("MC calibration: $N_SAMPLES samples × $N_TICKS ticks × $(length(SEEDS)) seeds")
    println("Threads: $(nthreads())")
    flush(stdout)

    @threads for i in 1:N_SAMPLES
        cfg = configs[i]

        # Run across seeds; collect metrics per seed
        seed_pop_growths  = Float64[]
        seed_mean_emps    = Float64[]
        seed_expandeds    = Bool[]
        seed_firm_growths = Bool[]

        for seed in SEEDS
            try
                r = run_one(seed; cfg...)
                # pop_growth: t=750 vs t=100 — catches boom-bust (low score) vs sustained growth
                pop_growth = r.snap750.pop / max(1, r.snap100.pop)
                mean_emp   = (r.snap250.emp + r.snap500.emp + r.snap750.emp) / 3.0
                expanded   = r.snap750.expanded
                firm_growth = r.snap750.firms > 6   # beyond 6 investor firms

                push!(seed_pop_growths,  pop_growth)
                push!(seed_mean_emps,    mean_emp)
                push!(seed_expandeds,    expanded)
                push!(seed_firm_growths, firm_growth)
            catch
                push!(seed_pop_growths,  0.0)
                push!(seed_mean_emps,    0.0)
                push!(seed_expandeds,    false)
                push!(seed_firm_growths, false)
            end
        end

        pop_growth  = mean(seed_pop_growths)
        mean_emp    = mean(seed_mean_emps)
        expanded    = any(seed_expandeds)
        firm_growth = any(seed_firm_growths)

        results[i] = (
            # parameters
            productivity     = round(cfg.productivity,    digits=4),
            initial_hire     = cfg.initial_hire,
            solo_found_prob  = round(cfg.solo_found_prob, digits=6),
            goods_tc         = round(cfg.goods_tc,        digits=5),
            bid_share        = round(cfg.bid_share,       digits=4),
            grid_min_res_occ = round(cfg.grid_min_res_occ,digits=4),
            sold_out_premium = round(cfg.sold_out_premium,digits=4),
            # outcomes
            pop_growth       = round(pop_growth,  digits=3),
            mean_emp         = round(mean_emp,    digits=3),
            grid_expanded    = expanded,
            firm_growth      = firm_growth,
            score            = round(compute_score(pop_growth, mean_emp, expanded, firm_growth), digits=3),
        )

        done = Threads.atomic_add!(n_done, 1) + 1
        done % 200 == 0 && (println("  $done / $N_SAMPLES"); flush(stdout))
    end

    # ── Write CSV ──────────────────────────────────────────────────────────────
    mkpath("outputs")
    open(OUT, "w") do io
        println(io, join(string.(keys(results[1])), ","))
        for r in results
            println(io, join(values(r), ","))
        end
    end

    # ── Summary stats ──────────────────────────────────────────────────────────
    n_growing  = count(r -> r.pop_growth > 2.0, results)
    n_expanded = count(r -> r.grid_expanded,    results)

    println("\nDone.")
    println("  Growing (>2×):   $n_growing / $N_SAMPLES  ($(round(100n_growing/N_SAMPLES, digits=1))%)")
    println("  Grid expanded:   $n_expanded / $N_SAMPLES  ($(round(100n_expanded/N_SAMPLES, digits=1))%)")
    println("  Results → $OUT")

    # ── Top 20 by score ───────────────────────────────────────────────────────
    sorted = sort(results; by = r -> -r.score)
    println("\nTop 20 by score  (max=7.5):")
    @printf("%-6s %-5s %-9s %-7s %-6s %-8s %-7s  score  pop×  emp%%  firms  exp\n",
        "prod", "hire", "sfp", "gtc", "bid", "res_occ", "soexp")
    for r in first(sorted, 20)
        @printf("%-6.2f %-5d %-9.5f %-7.4f %-6.3f %-8.3f %-7.3f  %5.2f  %4.1f×  %4.0f%%   %s     %s\n",
            r.productivity, r.initial_hire, r.solo_found_prob,
            r.goods_tc, r.bid_share, r.grid_min_res_occ, r.sold_out_premium,
            r.score, r.pop_growth, r.mean_emp * 100,
            r.firm_growth ? "Y" : "N", r.grid_expanded ? "Y" : "N")
    end

    # ── Marginal analysis ─────────────────────────────────────────────────────
    println("\nMean score by productivity bin:")
    for lo in 3.0:1.0:7.0
        hi = lo + 1.0
        sub = filter(r -> lo <= r.productivity < hi, results)
        isempty(sub) && continue
        gr  = count(r -> r.pop_growth > 2.0, sub)
        @printf("  [%.0f, %.0f): mean_score=%.2f  growth_rate=%3.0f%%  n=%d\n",
            lo, hi, mean(r.score for r in sub), 100gr/length(sub), length(sub))
    end

    println("\nMean score by initial_hire_per_firm:")
    for k in 3:8
        sub = filter(r -> r.initial_hire == k, results)
        isempty(sub) && continue
        gr  = count(r -> r.pop_growth > 2.0, sub)
        @printf("  hire=%d: mean_score=%.2f  growth_rate=%3.0f%%  n=%d\n",
            k, mean(r.score for r in sub), 100gr/length(sub), length(sub))
    end

    println("\nGrowth rate by (productivity_bin × initial_hire):")
    @printf("prod\\hire  ")
    for k in 3:8; @printf("  k=%d ", k); end
    println()
    for lo in 3.0:1.0:7.0
        hi = lo + 1.0
        @printf("[%.0f,%.0f)  ", lo, hi)
        for k in 3:8
            sub = filter(r -> lo <= r.productivity < hi && r.initial_hire == k, results)
            if isempty(sub)
                @printf("   -- ")
            else
                gr = count(r -> r.pop_growth > 2.0, sub)
                @printf("  %3.0f%%", 100gr/length(sub))
            end
        end
        println()
    end
end

main()
