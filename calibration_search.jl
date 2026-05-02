using UrbanABM
using Base.Threads
using Printf
using Statistics

# ── Parameter grid ────────────────────────────────────────────────────────────
# Sweeping the four levers most relevant to employment dynamics after the
# vacancy-driven immigration / investor-agent architecture rewrite.

solo_found_probs          = [0.010, 0.020, 0.050]
sold_out_expansion_premia = [0.25,  0.50,  1.00]
outside_wages             = [6.0,   8.0,  10.0]
seeds                     = [12, 42, 77]

configs = vec([(fp, ep, ow, s)
    for fp in solo_found_probs,
        ep in sold_out_expansion_premia,
        ow in outside_wages,
        s  in seeds])

n = length(configs)
results = Vector{NamedTuple}(undef, n)
progress = Threads.Atomic{Int}(0)

println("Running $n configs on $(nthreads()) threads...")
flush(stdout)

# ── Main sweep ────────────────────────────────────────────────────────────────

@threads for i in eachindex(configs)
    found_prob, exp_premium, out_wage, seed = configs[i]

    params = ModelParams(
        seed                       = seed,
        solo_found_prob            = found_prob,
        sold_out_expansion_premium = exp_premium,
        outside_wage               = out_wage,
        enable_decision_logging    = false,
        enable_search_logging      = false,
        enable_market_logging      = false,
    )

    snap250 = nothing
    snap500 = nothing

    try
        state = init_state(params)
        for t in 1:500
            step!(state)
            if t == 250; snap250 = metrics_snapshot(state); end
            if t == 500; snap500 = metrics_snapshot(state); end
        end
    catch err
        # record as crashed — leave snaps nothing
    end

    g(m, k, d) = isnothing(m) ? d : get(m, k, d)

    pop5   = g(snap500, "population",              0)
    emp5   = g(snap500, "employment",              0)
    firms5 = g(snap500, "firm_count",              0)
    wage5  = g(snap500, "mean_wage",               0.0)
    crent5 = g(snap500, "mean_commercial_rent",    0.0)
    rrent5 = g(snap500, "mean_residential_rent",   0.0)

    # Feasible: city survives, employment ≥ 25%, wages above reservation
    feasible = !isnothing(snap500) &&
        pop5   >= 30 &&
        firms5 >= 4  &&
        (pop5 > 0 && emp5 / pop5 >= 0.25) &&
        wage5  >= out_wage

    results[i] = (
        solo_found_prob            = found_prob,
        sold_out_expansion_premium = exp_premium,
        outside_wage               = out_wage,
        seed                       = seed,
        # tick 250
        pop_250   = g(snap250, "population",  -1),
        emp_250   = g(snap250, "employment",  -1),
        firms_250 = g(snap250, "firm_count",  -1),
        wage_250  = g(snap250, "mean_wage",   -1.0),
        crent_250 = g(snap250, "mean_commercial_rent", -1.0),
        rrent_250 = g(snap250, "mean_residential_rent", -1.0),
        # tick 500
        pop_500   = pop5,
        emp_500   = emp5,
        firms_500 = firms5,
        wage_500  = wage5,
        crent_500 = crent5,
        rrent_500 = rrent5,
        emp_rate_500 = pop5 > 0 ? emp5 / pop5 : -1.0,
        feasible  = feasible,
    )

    done = Threads.atomic_add!(progress, 1) + 1
    done % 20 == 0 && println("  $done / $n done")
    flush(stdout)
end

# ── Write CSV ─────────────────────────────────────────────────────────────────

outpath = "outputs/calibration_search.csv"
mkpath("outputs")
open(outpath, "w") do io
    println(io, join(string.(keys(results[1])), ","))
    for r in results
        println(io, join(values(r), ","))
    end
end

n_feasible = count(r -> r.feasible, results)
println("\nDone. Feasible: $n_feasible / $n")
println("Results → $outpath")

# ── Summary: feasibility rate by solo_found_prob × exp_premium ────────────────

println("\nFeasibility rate by solo_found_prob × sold_out_expansion_premium:")
@printf("fp \\ premium ")
for ep in sold_out_expansion_premia; @printf("  %4.2f", ep); end
println()
for fp in solo_found_probs
    @printf("  %.3f       ", fp)
    for ep in sold_out_expansion_premia
        sub = filter(r -> r.solo_found_prob == fp && r.sold_out_expansion_premium == ep, results)
        rate = isempty(sub) ? 0.0 : count(r -> r.feasible, sub) / length(sub)
        @printf("  %4.2f", rate)
    end
    println()
end

# ── Summary: mean employment rate by outside_wage × solo_found_prob ──────────

println("\nMean emp_rate_500 (all runs) by outside_wage × solo_found_prob:")
@printf("ow \\ fp      ")
for fp in solo_found_probs; @printf("  %5.3f", fp); end
println()
for ow in outside_wages
    @printf("  %4.1f        ", ow)
    for fp in solo_found_probs
        sub = filter(r -> r.outside_wage == ow && r.solo_found_prob == fp, results)
        avg = isempty(sub) ? NaN : mean(r.emp_rate_500 for r in sub if r.emp_rate_500 >= 0)
        isnan(avg) ? @printf("   ---") : @printf("  %5.2f", avg)
    end
    println()
end

# ── Summary: mean wage at t=500 by solo_found_prob × outside_wage ─────────────

println("\nMean wage_500 (feasible only) by solo_found_prob × outside_wage:")
@printf("fp \\ ow      ")
for ow in outside_wages; @printf("  %5.1f", ow); end
println()
for fp in solo_found_probs
    @printf("  %.3f       ", fp)
    for ow in outside_wages
        sub = filter(r -> r.solo_found_prob == fp && r.outside_wage == ow && r.feasible, results)
        avg = isempty(sub) ? NaN : mean(r.wage_500 for r in sub)
        isnan(avg) ? @printf("    ---") : @printf("  %5.2f", avg)
    end
    println()
end

# ── Top 10 feasible configs by employment rate ────────────────────────────────

feasible_results = filter(r -> r.feasible, results)
sort!(feasible_results; by = r -> -r.emp_rate_500)
println("\nTop 10 feasible configs by emp_rate at t=500:")
@printf("%-6s %-7s %-5s %-4s  emp   wage  firms  pop\n",
    "fp", "premium", "ow", "seed")
for r in first(feasible_results, 10)
    @printf("%.3f  %.2f     %.1f   %-4d  %.2f  %5.2f  %-5d  %d\n",
        r.solo_found_prob, r.sold_out_expansion_premium,
        r.outside_wage, r.seed,
        r.emp_rate_500, r.wage_500, r.firms_500, r.pop_500)
end
