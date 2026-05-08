using UrbanABM

output = get(ENV, "URBAN_ABM_LOT_CSV", "outputs/diagnostics/lots_latest.csv")
mkpath(dirname(output))

params = ModelParams(
    width = parse(Int, get(ENV, "URBAN_ABM_WIDTH", "40")),
    height = parse(Int, get(ENV, "URBAN_ABM_HEIGHT", "40")),
    initial_workers = parse(Int, get(ENV, "URBAN_ABM_INITIAL_WORKERS", "2000")),
    initial_firms = parse(Int, get(ENV, "URBAN_ABM_INITIAL_FIRMS", "120")),
    outside_entry_rate = parse(Float64, get(ENV, "URBAN_ABM_OUTSIDE_ENTRY_RATE", "12.0")),
    seed = parse(Int, get(ENV, "URBAN_ABM_SEED", "12")),
)

ticks = parse(Int, get(ENV, "URBAN_ABM_TICKS", "250"))

state = init_state(params)
run!(state, ticks)
write_lot_csv(state, output)

metrics = metrics_snapshot(state)
println("wrote=", output)
println("tick=", metrics["tick"])
println("population=", metrics["population"])
println("firm_count=", metrics["firm_count"])
println("mean_residential_rent=", metrics["mean_residential_rent"])
println("mean_commercial_rent=", metrics["mean_commercial_rent"])
println("residential_vacancy_rate=", metrics["residential_vacancy_rate"])
println("commercial_vacancy_rate=", metrics["commercial_vacancy_rate"])
