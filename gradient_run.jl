using UrbanABM
using Printf
using Statistics

# ── Parameters ────────────────────────────────────────────────────────────────

params = ModelParams(
    seed                       = 42,
    solo_found_prob            = 0.010,
    sold_out_expansion_premium = 0.50,
    outside_wage               = 10.0,
    enable_decision_logging    = false,
    enable_search_logging      = false,
    enable_market_logging      = false,
)

const TICKS       = 3000
const BURNIN      = 500
const REPORT_EVERY = 500

# ── Run + accumulate ──────────────────────────────────────────────────────────

function run_gradient(params)
    state  = init_state(params)
    n_lots = length(state.lots)

    acc_res_rent   = zeros(Float64, n_lots)
    acc_com_rent   = zeros(Float64, n_lots)
    acc_occ_res    = zeros(Float64, n_lots)
    acc_occ_com    = zeros(Float64, n_lots)
    acc_job_access = zeros(Float64, n_lots)
    acc_n = 0

    println("Running $TICKS ticks (burn-in $BURNIN)...")
    flush(stdout)

    for t in 1:TICKS
        step!(state)

        if t > BURNIN
            for l in state.lots
                acc_res_rent[l.id]   += l.residential_rent
                acc_com_rent[l.id]   += l.commercial_rent
                acc_occ_res[l.id]    += l.occupied_residential
                acc_occ_com[l.id]    += l.occupied_commercial
                acc_job_access[l.id] += state.job_access_by_lot[l.id]
            end
            acc_n += 1
        end

        if t % REPORT_EVERY == 0
            aw  = state.active_worker_ids
            pop = length(aw)
            emp = count(w -> !isnothing(state.workers[w].employer_id), aw)
            wages = [state.workers[w].current_wage for w in aw
                     if !isnothing(state.workers[w].employer_id)]
            mw = isempty(wages) ? 0.0 : mean(wages)
            @printf("t=%-4d  pop=%-4d  firms=%-3d  emp=%.2f  mean_w=%.2f\n",
                t, pop, length(state.active_firm_ids), pop > 0 ? emp/pop : 0.0, mw)
            flush(stdout)
        end
    end

    return state, acc_res_rent ./ acc_n, acc_com_rent ./ acc_n,
                  acc_occ_res ./ acc_n, acc_occ_com ./ acc_n,
                  acc_job_access ./ acc_n
end

state, avg_res_rent, avg_com_rent, avg_occ_res, avg_occ_com, avg_job_access =
    run_gradient(params)

# ── Distance from grid centre (taxicab) ───────────────────────────────────────

cx = (params.width  + 1) / 2.0
cy = (params.height + 1) / 2.0
dist = [abs(l.x - cx) + abs(l.y - cy) for l in state.lots]

# ── Per-lot CSV ───────────────────────────────────────────────────────────────

mkpath("outputs")
outpath = "outputs/gradient_run.csv"
open(outpath, "w") do io
    println(io, "lot_id,x,y,dist_centre,avg_res_rent,avg_com_rent,avg_occ_res,avg_occ_com,avg_job_access")
    for l in state.lots
        @printf(io, "%d,%d,%d,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f\n",
            l.id, l.x, l.y, dist[l.id],
            avg_res_rent[l.id], avg_com_rent[l.id],
            avg_occ_res[l.id],  avg_occ_com[l.id],
            avg_job_access[l.id])
    end
end
println("\nPer-lot CSV → $outpath")

# ── Distance-bin gradient table ───────────────────────────────────────────────

max_dist   = maximum(dist)
n_bins     = 10
bin_edges  = range(0.0, max_dist + 0.001; length = n_bins + 1)

function bin_mean(vals, lo, hi)
    mask = (dist .>= lo) .& (dist .< hi)
    any(mask) ? mean(vals[mask]) : NaN
end

println("\nGradients by taxicab distance from centre (t=$(BURNIN+1):$TICKS time-avg):")
@printf("%-14s  %-5s  %-9s  %-9s  %-7s  %-7s  %-10s\n",
    "dist_bin", "lots", "res_rent", "com_rent", "occ_res", "occ_com", "job_access")
println(repeat("-", 70))
for b in 1:n_bins
    lo, hi = bin_edges[b], bin_edges[b+1]
    mask = (dist .>= lo) .& (dist .< hi)
    sum(mask) == 0 && continue
    @printf("[%5.1f,%5.1f)   %-5d  %-9.3f  %-9.3f  %-7.4f  %-7.4f  %-10.4f\n",
        lo, hi, sum(mask),
        bin_mean(avg_res_rent, lo, hi),
        bin_mean(avg_com_rent, lo, hi),
        bin_mean(avg_occ_res,  lo, hi),
        bin_mean(avg_occ_com,  lo, hi),
        bin_mean(avg_job_access, lo, hi))
end

# ── Pearson correlations with distance ────────────────────────────────────────

function pearson(x, y)
    x̄, ȳ = mean(x), mean(y)
    num = sum((x .- x̄) .* (y .- ȳ))
    den = sqrt(sum((x .- x̄).^2) * sum((y .- ȳ).^2))
    den ≈ 0 ? 0.0 : num / den
end

println("\nCorrelation (Pearson r) with distance from centre:")
@printf("  res_rent    %+.3f\n", pearson(dist, avg_res_rent))
@printf("  com_rent    %+.3f\n", pearson(dist, avg_com_rent))
@printf("  occ_res     %+.3f\n", pearson(dist, avg_occ_res))
@printf("  occ_com     %+.3f\n", pearson(dist, avg_occ_com))
@printf("  job_access  %+.3f\n", pearson(dist, avg_job_access))

println("\nCorrelation job_access with rent / occupancy:")
@printf("  job_access × res_rent  %+.3f\n", pearson(avg_job_access, avg_res_rent))
@printf("  job_access × occ_res   %+.3f\n", pearson(avg_job_access, avg_occ_res))
@printf("  job_access × com_rent  %+.3f\n", pearson(avg_job_access, avg_com_rent))
@printf("  job_access × occ_com   %+.3f\n", pearson(avg_job_access, avg_occ_com))
