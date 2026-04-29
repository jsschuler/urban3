using UrbanABM
import UrbanABM: FirmTypeParams
using Base.Threads
using Printf

# ── Parameter grid ────────────────────────────────────────────────────────────

productivities = [4.0, 5.5, 7.0, 9.0]
io_densities   = [0.2, 0.4, 0.6, 0.8]
entry_rates    = [1.0, 2.0, 4.0]
found_probs    = [0.005, 0.010, 0.020]
seeds          = [12, 42, 77]

# Price ranges calibrated per tier; kept fixed so productivity variation is clean.
# T1 break-even at prod=6.5 ≈ 2.3; T3 worker budget ≈ 8.5.
tier_prices = [
    (supply_tier=1, price_min=2.5, price_max=4.0),
    (supply_tier=1, price_min=2.5, price_max=4.0),
    (supply_tier=2, price_min=3.5, price_max=5.5),
    (supply_tier=2, price_min=3.5, price_max=5.5),
    (supply_tier=3, price_min=4.0, price_max=6.5),
    (supply_tier=3, price_min=4.0, price_max=6.5),
]

configs = vec([(p, d, e, f, s)
    for p in productivities, d in io_densities,
        e in entry_rates, f in found_probs, s in seeds])

n = length(configs)
results = Vector{NamedTuple}(undef, n)
progress = Threads.Atomic{Int}(0)

println("Running $n configs on $(nthreads()) threads...")
flush(stdout)

# ── Main sweep ────────────────────────────────────────────────────────────────

@threads for i in eachindex(configs)
    prod, density, entry_rate, found_prob, seed = configs[i]

    firm_types = [FirmTypeParams(
        supply_tier = t.supply_tier,
        productivity = prod,
        initial_goods_price_min = t.price_min,
        initial_goods_price_max = t.price_max,
    ) for t in tier_prices]

    params = ModelParams(
        width=40, height=40,
        initial_workers=2000, initial_firms=120,
        outside_entry_rate=entry_rate,
        solo_found_prob=found_prob,
        io_matrix_density=density,
        seed=seed,
        firm_types=firm_types,
        enable_decision_logging=false,
        enable_search_logging=false,
        enable_market_logging=false,
    )

    snap500  = nothing
    snap1000 = nothing

    try
        state = init_state(params)
        for t in 1:1000
            step!(state)
            if t == 500;  snap500  = metrics_snapshot(state); end
            if t == 1000; snap1000 = metrics_snapshot(state); end
        end
    catch err
        # record as crashed — leave snaps nothing
    end

    function extract(m, field, default)
        isnothing(m) ? default : m[field]
    end

    pop10   = extract(snap1000, "population",              0)
    emp10   = extract(snap1000, "employment",              0)
    firms10 = extract(snap1000, "firm_count",              0)
    cvac10  = extract(snap1000, "commercial_vacancy_rate", 1.0)
    crent10 = extract(snap1000, "mean_commercial_rent",    0.0)

    feasible = !isnothing(snap1000) &&
        firms10 >= 50 &&
        (pop10 > 0 && emp10 / pop10 >= 0.20) &&
        cvac10  <= 0.85 &&
        crent10 >  1.1

    results[i] = (
        productivity  = prod,
        io_density    = density,
        entry_rate    = entry_rate,
        found_prob    = found_prob,
        seed          = seed,
        # tick 500
        firms_500     = extract(snap500,  "firm_count",              -1),
        emp_rate_500  = let p = extract(snap500, "population", 0)
                            p > 0 ? extract(snap500, "employment", 0) / p : -1.0
                        end,
        com_vac_500   = extract(snap500,  "commercial_vacancy_rate", -1.0),
        com_rent_500  = extract(snap500,  "mean_commercial_rent",    -1.0),
        pop_500       = extract(snap500,  "population",              -1),
        # tick 1000
        firms_1000    = firms10,
        emp_rate_1000 = pop10 > 0 ? emp10 / pop10 : -1.0,
        com_vac_1000  = cvac10,
        com_rent_1000 = crent10,
        pop_1000      = pop10,
        feasible      = feasible,
    )

    done = Threads.atomic_add!(progress, 1) + 1
    done % 20 == 0 && println("  $done / $n done")
    flush(stdout)
end

# ── Write CSV ─────────────────────────────────────────────────────────────────

outpath = "outputs/feasibility_search.csv"
open(outpath, "w") do io
    println(io, join(string.(keys(results[1])), ","))
    for r in results
        println(io, join(values(r), ","))
    end
end

n_feasible = count(r -> r.feasible, results)
println("\nDone. Feasible: $n_feasible / $n")
println("Results → $outpath")

# ── Quick summary: feasible rate by productivity × io_density ─────────────────

println("\nFeasibility rate by productivity × io_density (rows=prod, cols=density):")
print("prod \\ density")
for d in io_densities; @printf("  %4.1f", d); end
println()
for p in productivities
    @printf("  %4.1f         ", p)
    for d in io_densities
        subset = filter(r -> r.productivity == p && r.io_density == d, results)
        rate = isempty(subset) ? 0.0 : count(r -> r.feasible, subset) / length(subset)
        @printf("  %4.2f", rate)
    end
    println()
end
