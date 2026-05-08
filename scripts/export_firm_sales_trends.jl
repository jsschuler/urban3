using UrbanABM
using Printf

const TICKS = 5000
const OUT_DIR = "outputs/overnight"
const OUT_CSV = joinpath(OUT_DIR, "firm_sales_by_tick.csv")

function main()
    params = ModelParams(
        seed                           = 42,
        enable_decision_logging        = false,
        enable_search_logging          = false,
        enable_open_diagnostic_logging = false,
        enable_market_logging          = false,
    )

    mkpath(OUT_DIR)
    state = init_state(params)

    open(OUT_CSV, "w") do io
        println(io, "tick,firm_id,firm_type,active,workers,committed_output,realized_sales,cash")
        for t in 1:TICKS
            step!(state)
            # record every known firm each tick; inactive firms stay for lifecycle visibility
            for f in state.firms
                active = f.active ? 1 : 0
                workers = length(f.worker_ids)
                cash = round(f.cash, digits=6)
                println(io, join([
                    t,
                    f.id,
                    f.firm_type,
                    active,
                    workers,
                    f.committed_output,
                    f.realized_sales_this_tick,
                    cash,
                ], ","))
            end
        end
    end

    @printf("Wrote %s\n", OUT_CSV)
end

main()
