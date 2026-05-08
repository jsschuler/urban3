using UrbanABM
using Statistics

output = get(ENV, "URBAN_ABM_FIRM_REVENUE_CSV", "outputs/diagnostics/firm_revenue_latest.csv")
mkpath(dirname(output))

params = ModelParams(
    width = parse(Int, get(ENV, "URBAN_ABM_WIDTH", "40")),
    height = parse(Int, get(ENV, "URBAN_ABM_HEIGHT", "40")),
    initial_workers = parse(Int, get(ENV, "URBAN_ABM_INITIAL_WORKERS", "3000")),
    initial_firms = parse(Int, get(ENV, "URBAN_ABM_INITIAL_FIRMS", "150")),
    outside_entry_rate = parse(Float64, get(ENV, "URBAN_ABM_OUTSIDE_ENTRY_RATE", "2.0")),
    seed = parse(Int, get(ENV, "URBAN_ABM_SEED", "77")),
    enable_decision_logging = false,
    enable_market_logging = true,
    market_log_limit = parse(Int, get(ENV, "URBAN_ABM_MARKET_LOG_LIMIT", "100000")),
)

ticks = parse(Int, get(ENV, "URBAN_ABM_TICKS", "2000"))

function firm_rent_bill(state, firm)
    sum(state.lots[lid].commercial_rent * units for (lid, units) in firm.commercial_units_by_lot; init=0.0)
end

function firm_wage_bill(firm)
    sum(values(firm.current_worker_wages); init=0.0)
end

function write_firm_row(io, state, firm)
    revenue = firm.realized_sales_this_tick * firm.goods_price
    wage_bill = firm_wage_bill(firm)
    rent_bill = firm_rent_bill(state, firm)
    profit = isempty(firm.profit_history) ? revenue - wage_bill - rent_bill : firm.profit_history[end]
    commercial_units = sum(values(firm.commercial_units_by_lot); init=0)
    sold_out = firm.committed_output > 0 && firm.realized_sales_this_tick >= firm.committed_output
    println(io, join([
        state.tick,
        firm.id,
        firm.firm_type,
        firm.active,
        length(firm.worker_ids),
        firm.capital_units,
        firm.process_count,
        commercial_units,
        firm.goods_price,
        firm.committed_output,
        firm.realized_sales_this_tick,
        max(0, firm.committed_output - firm.realized_sales_this_tick),
        sold_out,
        revenue,
        wage_bill,
        rent_bill,
        profit,
    ], ","))
end

state = init_state(params)
t0 = time()

open(output, "w") do io
    println(io, join([
        "tick",
        "firm_id",
        "firm_type",
        "active",
        "workers",
        "capital_units",
        "process_count",
        "commercial_units",
        "goods_price",
        "committed_output",
        "realized_sales",
        "unsold_output",
        "sold_out",
        "revenue",
        "wage_bill",
        "rent_bill",
        "profit",
    ], ","))

    checkpoints = Set([100, 500, 1000, 2000, 3000, 4000, 5000])
    for t in 1:ticks
        step!(state)
        for firm in UrbanABM.active_firms(state)
            write_firm_row(io, state, firm)
        end
        if t in checkpoints
            firms = UrbanABM.active_firms(state)
            revenues = [f.realized_sales_this_tick * f.goods_price for f in firms]
            mean_revenue = isempty(revenues) ? 0.0 : mean(revenues)
            sd_revenue = length(revenues) < 2 ? 0.0 : std(revenues)
            cv_revenue = mean_revenue == 0 ? NaN : sd_revenue / mean_revenue
            println(
                "checkpoint tick=", t,
                " elapsed=", round(time() - t0, digits=2),
                " firms=", length(firms),
                " mean_revenue=", round(mean_revenue, digits=3),
                " cv_revenue=", round(cv_revenue, digits=3),
            )
            flush(stdout)
        end
    end
end

write_market_log_csv(state, replace(output, ".csv" => "_market_log.csv"))

metrics = metrics_snapshot(state)
println("wrote=", output)
println("wrote_market_log=", replace(output, ".csv" => "_market_log.csv"))
println("elapsed=", round(time() - t0, digits=3))
println("tick=", metrics["tick"])
println("population=", metrics["population"])
println("employment=", metrics["employment"])
println("firm_count=", metrics["firm_count"])
println("mean_wage=", metrics["mean_wage"])
println("mean_price=", metrics["mean_price"])
