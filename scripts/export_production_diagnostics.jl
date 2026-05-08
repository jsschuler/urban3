using UrbanABM

const TICKS = 5000
const OUT = "outputs/overnight/firm_production_diagnostics.csv"

function main()
    p = ModelParams(
        seed=42,
        enable_decision_logging=false,
        enable_search_logging=false,
        enable_open_diagnostic_logging=false,
        enable_market_logging=false,
    )
    s = init_state(p)

    mkpath(dirname(OUT))
    open(OUT, "w") do io
        println(io, "tick,firm_id,firm_type,active,workers,capital,processes,capacity_raw,input_scale,committed_output,realized_sales,unsold_output,sold_out,goods_price,cash")
        for t in 1:TICKS
            step!(s)
            for f in s.firms
                cap = f.active ? UrbanABM.production_capacity(s, f, s.params) : 0
                scale = (f.active && cap > 0) ? UrbanABM.leontief_input_scale(s, f) : 0.0
                unsold = max(0, f.committed_output - f.realized_sales_this_tick)
                soldout = (f.committed_output > 0 && f.realized_sales_this_tick >= f.committed_output) ? 1 : 0
                println(io, join([
                    t,
                    f.id,
                    f.firm_type,
                    f.active ? 1 : 0,
                    length(f.worker_ids),
                    f.capital_units,
                    f.process_count,
                    cap,
                    scale,
                    f.committed_output,
                    f.realized_sales_this_tick,
                    unsold,
                    soldout,
                    f.goods_price,
                    f.cash,
                ], ","))
            end
        end
    end
    println("Wrote ", OUT)
end

main()
