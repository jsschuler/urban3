# Wide Monte Carlo viability search — no model loading required.
#
# Jointly samples ALL calibration parameters and evaluates 3 viability
# conditions analytically. Reports: overall feasibility rate, marginal
# distributions of viable vs all samples, and candidate recommendations.
#
# Key constraint added vs prior version:
#   outside_wage is parameterized as a RATIO of base_wage (reservation wage
#   ratio). This prevents the search from finding "solutions" where unemployed
#   workers earn more than employed ones, which is economically incoherent.
#
# Viability conditions (evaluated at L=1, the most labor-efficient firm size):
#   C1: T1 break-even price < outside_eff_t1   (local T1 can undercut outside)
#   C2: T2 break-even price < outside_eff_t2   (local T2 can undercut outside,
#                                                worst-case using outside T1)
#   C3: unemployed worker shopping budget ≥ T3 break-even + shopping travel
#       (demand floor holds; workers on outside_wage can afford B2C goods)

using Statistics, Random, Printf

# ── Production structure (not searchable) ────────────────────────────────────
const LABOR_E   = 0.45
const CAPITAL_E = 0.30
const SPACE_E   = 0.25
const CAPITAL   = 2.0
const SPACE     = 1.0

cap(prod) = max(0, floor(Int, prod * 1.0^LABOR_E * CAPITAL^CAPITAL_E * SPACE^SPACE_E))

function be_t1(prod, base_wage, rent)
    c = cap(prod); c == 0 && return Inf
    (base_wage + rent) / c
end

function be_t2(prod, base_wage, rent, coeff, eff_t1)
    c = cap(prod); c == 0 && return Inf
    (base_wage + rent + ceil(Int, coeff * c) * eff_t1) / c
end

function be_t3(prod, base_wage, rent, coeff, eff_t2)
    c = cap(prod); c == 0 && return Inf
    (base_wage + rent + ceil(Int, coeff * c) * eff_t2) / c
end

# ── Searchable parameter ranges ───────────────────────────────────────────────
# (name, lo, hi, current_value)
# outside_wage replaced by ow_ratio = outside_wage / base_wage ∈ [0.40, 0.95]
PARAMS = [
    (:productivity,      4.0,  10.0,  5.5),
    (:base_wage,         5.0,  15.0, 10.0),
    (:ow_ratio,          0.40,  0.95,  0.80),  # outside_wage / base_wage
    (:op1,               1.0,   8.0,  3.5),    # outside_input_prices[1]
    (:op2,               2.0,  10.0,  5.0),    # outside_input_prices[2]  ← updated default
    (:outside_distance,  1.0,  20.0,  5.0),
    (:input_tc,          0.05,  0.60,  0.20),
    (:goods_tc,          0.05,  0.60,  0.35),
    (:coeff_lo,          0.05,  0.60,  0.20),  # io_matrix_coefficient_min ← updated default
    (:coeff_hi,          0.10,  0.80,  0.40),  # io_matrix_coefficient_max ← updated default
    (:rent_lo,           1.0,   8.0,  4.5),
    (:rent_hi,           2.0,  12.0,  7.5),
    (:sr_lo,             0.02,  0.20,  0.05),
    (:sr_hi,             0.08,  0.45,  0.25),
    (:travel_max,        0.5,   8.0,  4.0),
]

PARAM_NAMES = [p[1] for p in PARAMS]
PARAM_LO    = [p[2] for p in PARAMS]
PARAM_HI    = [p[3] for p in PARAMS]
PARAM_CUR   = [p[4] for p in PARAMS]
N_PARAMS    = length(PARAMS)

# ── Single viability evaluation ───────────────────────────────────────────────
function evaluate(θ, rng, K_inner)
    prod, base_wage, ow_ratio, op1, op2, out_dist, in_tc, g_tc,
        c_lo, c_hi, r_lo, r_hi, s_lo, s_hi, t_max = θ

    # Enforce ordering and ratio constraints
    (c_hi <= c_lo || r_hi <= r_lo || s_hi <= s_lo) && return 0.0

    outside_wage = ow_ratio * base_wage
    eff_t1 = op1 + in_tc * out_dist
    eff_t2 = op2 + in_tc * out_dist

    pass = 0
    for _ in 1:K_inner
        c12    = c_lo + rand(rng) * (c_hi - c_lo)
        c23    = c_lo + rand(rng) * (c_hi - c_lo)
        rent   = r_lo + rand(rng) * (r_hi - r_lo)
        sr     = s_lo + rand(rng) * (s_hi - s_lo)
        travel = rand(rng) * t_max

        p1 = be_t1(prod, base_wage, rent)
        p2 = be_t2(prod, base_wage, rent, c12, eff_t1)
        p3 = be_t3(prod, base_wage, rent, c23, eff_t2)

        budget    = outside_wage * (1 - sr)
        delivered = p3 + g_tc * travel

        c1 = p1 < eff_t1
        c2 = p2 < eff_t2
        c3 = budget >= delivered

        pass += (c1 && c2 && c3) ? 1 : 0
    end
    return pass / K_inner
end

# ── Mean-environment diagnostic for a parameter set ──────────────────────────
function diagnose(θ)
    prod, base_wage, ow_ratio, op1, op2, out_dist, in_tc, g_tc,
        c_lo, c_hi, r_lo, r_hi, s_lo, s_hi, t_max = θ

    outside_wage = ow_ratio * base_wage
    eff_t1 = op1 + in_tc * out_dist
    eff_t2 = op2 + in_tc * out_dist
    coeff  = (c_lo + c_hi) / 2
    rent   = (r_lo + r_hi) / 2
    sr     = (s_lo + s_hi) / 2
    travel = t_max / 2

    c = cap(prod)
    p1 = be_t1(prod, base_wage, rent)
    p2 = be_t2(prod, base_wage, rent, coeff, eff_t1)
    p3 = be_t3(prod, base_wage, rent, coeff, eff_t2)
    budget    = outside_wage * (1 - sr)
    delivered = p3 + g_tc * travel

    return (cap=c, eff_t1=eff_t1, eff_t2=eff_t2,
            be_t1=p1, be_t2=p2, be_t3=p3,
            outside_wage=outside_wage,
            budget=budget, delivered=delivered,
            c1=p1<eff_t1, c2=p2<eff_t2, c3=budget>=delivered)
end

function print_diag(label, θ, score)
    d = diagnose(θ)
    println(label)
    @printf "  outside_wage=%.2f (ratio=%.2f)  cap=%d  eff_t1=%.2f  eff_t2=%.2f\n" d.outside_wage θ[3] d.cap d.eff_t1 d.eff_t2
    @printf "  C1 be_t1=%.2f < %.2f  → %s\n" d.be_t1 d.eff_t1 (d.c1 ? "PASS" : "FAIL")
    @printf "  C2 be_t2=%.2f < %.2f  → %s\n" d.be_t2 d.eff_t2 (d.c2 ? "PASS" : "FAIL")
    @printf "  C3 budget=%.2f ≥ %.2f (be_t3=%.2f + travel=%.2f)  → %s\n" d.budget d.delivered d.be_t3 (θ[8]*(θ[15]/2)) (d.c3 ? "PASS" : "FAIL")
    @printf "  MC viability = %.1f%%\n\n" (score * 100)
end

# ── Run ───────────────────────────────────────────────────────────────────────
N_OUTER = 300_000
K_INNER = 30
rng     = MersenneTwister(42)

println("=== Wide MC Viability Search (with reservation-wage ratio constraint) ===")
println("$N_OUTER outer parameter samples × $K_INNER inner environment draws")
println("$(N_PARAMS) free parameters; outside_wage = ow_ratio × base_wage")
println()

# Prior params (before this session's changes)
prior = copy(PARAM_CUR)
prior[3] = 5.0 / 10.0   # ow_ratio = 0.50 (outside_wage=5, base_wage=10)
prior[5] = 7.0           # op2 = 7.0
prior[9] = 0.50          # coeff_lo
prior[10] = 0.75         # coeff_hi
prior_score = evaluate(prior, MersenneTwister(1), 10_000)
print_diag("PRIOR PARAMS (outside_wage=5, op2=7, coeff=[0.50,0.75]):", prior, prior_score)

# Updated params (current defaults after this session's changes)
cur_score = evaluate(PARAM_CUR, MersenneTwister(1), 10_000)
print_diag("UPDATED PARAMS (outside_wage=8, op2=5, coeff=[0.20,0.40]):", PARAM_CUR, cur_score)

# ── Sample ────────────────────────────────────────────────────────────────────
println("Scanning $N_OUTER samples...")
samples = Vector{Float64}[]
scores  = Float64[]

for _ in 1:N_OUTER
    θ = [PARAM_LO[i] + rand(rng) * (PARAM_HI[i] - PARAM_LO[i]) for i in 1:N_PARAMS]
    s = evaluate(θ, rng, K_INNER)
    push!(samples, θ)
    push!(scores, s)
end

viable_mask = scores .>= 0.90
n_viable    = sum(viable_mask)
n_marginal  = sum(scores .>= 0.50)

@printf "Overall results:\n"
@printf "  robust viable (≥90%%): %d / %d  (%.2f%%)\n" n_viable N_OUTER (100*n_viable/N_OUTER)
@printf "  marginal viable (≥50%%): %d / %d  (%.2f%%)\n\n" n_marginal N_OUTER (100*n_marginal/N_OUTER)

# ── Marginal distributions ────────────────────────────────────────────────────
function pct(v, p); quantile(v, p/100) end

viable_samples = samples[viable_mask]

if n_viable > 0
    println("Parameter distributions — viable (≥90%) vs full sample:")
    println("(q10/q50/q90; * = viable median shifted >15% of range from midpoint)")
    @printf "  %-20s  %-22s  %-22s  current\n" "parameter" "viable q10/q50/q90" "full q10/q50/q90"
    for (i, (name, lo, hi, cur_val)) in enumerate(PARAMS)
        av = [s[i] for s in samples]
        vv = [s[i] for s in viable_samples]
        aq10,aq50,aq90 = pct(av,10), pct(av,50), pct(av,90)
        vq10,vq50,vq90 = pct(vv,10), pct(vv,50), pct(vv,90)
        flag = abs(vq50 - (lo+hi)/2) > 0.15*(hi-lo) ? " *" : "  "
        @printf "  %-20s  %5.2f / %5.2f / %5.2f    %5.2f / %5.2f / %5.2f    %.2f%s\n" name vq10 vq50 vq90 aq10 aq50 aq90 cur_val flag
    end
    println()
end

# ── Condition pass rates ──────────────────────────────────────────────────────
println("Condition pass rates across all samples (at mean environment):")
function pass_rates(samples)
    c1n=c2n=c3n=0
    for s in samples
        d = diagnose(s)
        c1n += d.c1; c2n += d.c2; c3n += d.c3
    end
    n = length(samples)
    c1n/n, c2n/n, c3n/n
end
r1,r2,r3 = pass_rates(samples)
@printf "  C1 (T1 beats outside): %.1f%%\n" (100*r1)
@printf "  C2 (T2 beats outside): %.1f%%\n" (100*r2)
@printf "  C3 (worker afford B2C): %.1f%%\n\n" (100*r3)

# ── Top candidates closest to updated current params ─────────────────────────
if n_viable > 0
    norm_dist = [sqrt(sum(((samples[i][j]-PARAM_CUR[j])/(PARAM_HI[j]-PARAM_LO[j]))^2
                          for j in 1:N_PARAMS) / N_PARAMS)
                 for i in eachindex(samples)]
    combined = [viable_mask[i] ? scores[i]*0.5 + (1-norm_dist[i])*0.5 : 0.0
                for i in eachindex(samples)]
    order = sortperm(combined; rev=true)

    function show_top(order, samples, scores, n=12)
        @printf "  %-5s %-5s %-5s %-5s %-5s %-6s %-5s %-5s %-5s %-5s  %s\n" "prod" "wage" "ratio" "op1" "op2" "odist" "i_tc" "g_tc" "c_lo" "c_hi" "viab"
        shown = 0
        for idx in order
            scores[idx] < 0.90 && continue
            shown += 1; shown > n && break
            θ = samples[idx]
            @printf "  %-5.2f %-5.2f %-5.3f %-5.2f %-5.2f %-6.2f %-5.3f %-5.3f %-5.3f %-5.3f  %.0f%%\n" θ[1] θ[2] θ[3] θ[4] θ[5] θ[6] θ[7] θ[8] θ[9] θ[10] (scores[idx]*100)
        end
    end

    println("Top 12 robust-viable candidates closest to updated parameters:")
    show_top(order, samples, scores)
    println()

    best_idx = argmax(scores)
    println("Highest-viability candidate:")
    θ = samples[best_idx]
    print_diag("  ", θ, scores[best_idx])
end
