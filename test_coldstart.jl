using UrbanABM, Statistics

params = ModelParams(
    width=40, height=40, initial_workers=3000, initial_firms=150,
    outside_entry_rate=2.0, seed=42,
    enable_decision_logging=false, enable_search_logging=false,
    enable_market_logging=false)
state = init_state(params)
t0 = time()

function tier_report(state, t)
    max_tier = UrbanABM.max_supply_tier(state)
    af = collect(UrbanABM.active_firms(state))
    for tier in 1:max_tier
        fs = [f for f in af if UrbanABM.firm_supply_tier(state, f) == tier]
        isempty(fs) && continue
        n = length(fs)
        # only firms with workers
        alive = [f for f in fs if length(f.worker_ids) > 0]
        dead  = n - length(alive)
        wages_posted = [f.posted_wage for f in fs]
        nw    = [length(f.worker_ids) for f in fs]
        cash  = [f.cash for f in fs]
        # hiring threshold = (payroll + posted_wage) * min_hire_cash_ticks
        thresholds = [(sum(values(f.current_worker_wages); init=0.0) + f.posted_wage) * state.params.min_hire_cash_ticks for f in fs]
        can_hire = count(i -> cash[i] >= thresholds[i], eachindex(fs))
        println("  T$tier (n=$n, dead=$dead): workers=$(round(mean(nw),digits=2)) posted_wage=$(round(mean(wages_posted),digits=1)) cash=$(round(mean(cash),digits=0)) hire_thresh=$(round(mean(thresholds),digits=0)) can_hire=$can_hire")
    end
end

for t in 1:500
    step!(state)
    if t in [10, 50, 100, 200, 300, 500]
        m = metrics_snapshot(state)
        el = round(time()-t0, digits=1)
        println("=== tick=$t  pop=$(m["population"])  elapsed=$(el)s ===")
        tier_report(state, t)
        flush(stdout)
    end
end
println("DONE")
