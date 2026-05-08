using UrbanABM
using Statistics

output_dir = get(ENV, "URBAN_ABM_OPEN_DIAGNOSTIC_DIR", "outputs/diagnostics/open_diagnostic")
mkpath(output_dir)

params = ModelParams(
    width = parse(Int, get(ENV, "URBAN_ABM_WIDTH", "40")),
    height = parse(Int, get(ENV, "URBAN_ABM_HEIGHT", "40")),
    initial_workers = parse(Int, get(ENV, "URBAN_ABM_INITIAL_WORKERS", "2000")),
    initial_firms = parse(Int, get(ENV, "URBAN_ABM_INITIAL_FIRMS", "120")),
    outside_entry_rate = parse(Float64, get(ENV, "URBAN_ABM_OUTSIDE_ENTRY_RATE", "12.0")),
    seed = parse(Int, get(ENV, "URBAN_ABM_SEED", "12")),
    enable_decision_logging = false,
    enable_market_logging = true,
    market_log_limit = parse(Int, get(ENV, "URBAN_ABM_MARKET_LOG_LIMIT", "10000")),
    enable_search_logging = false,
    enable_open_diagnostic_logging = true,
    open_diagnostic_commercial_limit = parse(Int, get(ENV, "URBAN_ABM_OPEN_COMMERCIAL_LIMIT", "100000")),
    open_diagnostic_goods_limit = parse(Int, get(ENV, "URBAN_ABM_OPEN_GOODS_LIMIT", "250000")),
)

ticks = parse(Int, get(ENV, "URBAN_ABM_TICKS", "250"))
state = init_state(params)
t0 = time()

checkpoints = Set([50, 100, 150, 200, 250, 500, 1000, 2000, 5000])
for t in 1:ticks
    step!(state)
    if t in checkpoints
        metrics = metrics_snapshot(state)
        market = market_failure_summary(state)
        println(
            "checkpoint tick=", t,
            " elapsed=", round(time() - t0, digits=2),
            " population=", metrics["population"],
            " employment=", metrics["employment"],
            " firm_count=", metrics["firm_count"],
            " mean_commercial_rent=", round(metrics["mean_commercial_rent"], digits=3),
            " unsold_output=", get(market, "goods_excess_supply", 0),
        )
        flush(stdout)
    end
end

commercial_path = joinpath(output_dir, "commercial_search.csv")
goods_path = joinpath(output_dir, "goods_search.csv")
market_path = joinpath(output_dir, "market_log.csv")
lots_path = joinpath(output_dir, "lots_final.csv")

write_commercial_search_diagnostics_csv(state, commercial_path)
write_goods_search_diagnostics_csv(state, goods_path)
write_market_log_csv(state, market_path)
write_lot_csv(state, lots_path)

commercial_records = state.open_diagnostic_log.commercial_search_records
goods_records = state.open_diagnostic_log.goods_search_records

commercial_chosen = [r for r in commercial_records if !isnothing(r.chosen_lot_id)]
commercial_with_cheaper_unsampled = [r for r in commercial_chosen if r.cheaper_unsampled_vacant_count > 0]
commercial_gap = [
    r.chosen_rent - r.best_global_vacant_rent
    for r in commercial_chosen
    if !isnan(r.chosen_rent) && !isnan(r.best_global_vacant_rent)
]

goods_choices = [r for r in goods_records if !isnothing(r.chosen_firm_id)]
goods_with_better_unsampled = [r for r in goods_choices if r.better_unsampled_count > 0]
goods_score_gap = [
    r.best_global_score - r.chosen_score
    for r in goods_choices
    if !isnan(r.best_global_score) && !isnan(r.chosen_score)
]
goods_no_choice_despite_affordable = [
    r for r in goods_records
    if isnothing(r.chosen_firm_id) && r.affordable_global_count > 0
]

println("wrote_commercial_search=", commercial_path)
println("wrote_goods_search=", goods_path)
println("wrote_market_log=", market_path)
println("wrote_lots=", lots_path)
println("elapsed=", round(time() - t0, digits=3))
println("tick=", state.tick)
println("mean_commercial_rent=", metrics_snapshot(state)["mean_commercial_rent"])
println("commercial_events=", length(commercial_records))
println("commercial_chosen_events=", length(commercial_chosen))
println("commercial_with_cheaper_unsampled=", length(commercial_with_cheaper_unsampled))
println(
    "commercial_with_cheaper_unsampled_share=",
    isempty(commercial_chosen) ? 0.0 : length(commercial_with_cheaper_unsampled) / length(commercial_chosen),
)
println(
    "commercial_mean_rent_gap_to_best_global=",
    isempty(commercial_gap) ? NaN : mean(commercial_gap),
)
println("goods_events=", length(goods_records))
println("goods_choice_events=", length(goods_choices))
println("goods_with_better_unsampled=", length(goods_with_better_unsampled))
println(
    "goods_with_better_unsampled_share=",
    isempty(goods_choices) ? 0.0 : length(goods_with_better_unsampled) / length(goods_choices),
)
println(
    "goods_mean_score_gap_to_best_global=",
    isempty(goods_score_gap) ? NaN : mean(goods_score_gap),
)
println("goods_no_choice_despite_affordable=", length(goods_no_choice_despite_affordable))
