using UrbanABM
using Printf

# ── Configuration ─────────────────────────────────────────────────────────────

const TICKS          = 5000
const REPORT_EVERY   = 250
const LOT_SNAP_EVERY = 500
const OUT_DIR        = "outputs/overnight"

function main()
    params = ModelParams(
        seed                           = 42,
        initial_workers                = 40,
        worker_exit_threshold          = 500,
        outside_wage                   = 10.0,
        enable_decision_logging        = false,
        enable_search_logging          = false,
        enable_open_diagnostic_logging = false,
        enable_market_logging          = true,
        market_log_limit               = 200_000,
    )

    mkpath(OUT_DIR)
    state = init_state(params)

    expansion_rows   = String["tick,old_width,old_height,new_width,new_height,old_lots,new_lots,cbd_x,cbd_y"]
    event_rows       = String["tick,firm_entries,firm_exits,hires,layoffs,residential_units_added,commercial_units_added,conversions,immigrants"]
    gradient_rows    = String["tick,distance,mean_commercial_rent,mean_residential_rent,n_commercial_lots,n_residential_lots,cbd_x,cbd_y"]
    prev_width  = state.params.width
    prev_height = state.params.height
    prev_n_lots = length(state.lots)

    println("Starting $TICKS-tick overnight run  (grid starts $(prev_width)×$(prev_height))")
    flush(stdout)

    t0 = time()

    for t in 1:TICKS
        step!(state)
        push!(event_rows, join([
            t,
            state.events.firm_entries,
            state.events.firm_exits,
            state.events.hires,
            state.events.layoffs,
            state.events.residential_units_added,
            state.events.commercial_units_added,
            state.events.conversions,
            state.events.immigrants,
        ], ","))

        # Detect grid expansion
        if state.params.width != prev_width
            new_W = state.params.width
            new_H = state.params.height
            cbd_id = 0
            best_rent = -Inf
            for l in state.lots
                l.commercial_units > 0 || continue
                if l.commercial_rent > best_rent
                    best_rent = l.commercial_rent
                    cbd_id = l.id
                end
            end
            cbd_x = cbd_id > 0 ? state.lots[cbd_id].x : -1
            cbd_y = cbd_id > 0 ? state.lots[cbd_id].y : -1

            row = join([t, prev_width, prev_height, new_W, new_H,
                        prev_n_lots, length(state.lots), cbd_x, cbd_y], ",")
            push!(expansion_rows, row)
            @printf("t=%-5d  EXPANSION %d×%d → %d×%d  lots %d → %d  CBD=(%d,%d)\n",
                t, prev_width, prev_height, new_W, new_H,
                prev_n_lots, length(state.lots), cbd_x, cbd_y)
            flush(stdout)
            prev_width  = new_W
            prev_height = new_H
            prev_n_lots = length(state.lots)
        end

        # Lot-level snapshot + rent gradient
        if t % LOT_SNAP_EVERY == 0
            write_lot_csv(state, joinpath(OUT_DIR, "lots_t$(lpad(t, 5, '0')).csv"))

            # Find CBD: commercial lot with highest commercial rent
            cbd_x, cbd_y = -1, -1
            best_cr = -Inf
            for l in state.lots
                l.commercial_units > 0 || continue
                if l.commercial_rent > best_cr
                    best_cr = l.commercial_rent
                    cbd_x, cbd_y = l.x, l.y
                end
            end

            if cbd_x > 0
                # Accumulate rent sums by Manhattan distance from CBD
                com_sum   = Dict{Int,Float64}()
                com_count = Dict{Int,Int}()
                res_sum   = Dict{Int,Float64}()
                res_count = Dict{Int,Int}()
                for l in state.lots
                    d = abs(l.x - cbd_x) + abs(l.y - cbd_y)
                    if l.commercial_units > 0
                        com_sum[d]   = get(com_sum, d, 0.0) + l.commercial_rent
                        com_count[d] = get(com_count, d, 0) + 1
                    end
                    if l.residential_units > 0
                        res_sum[d]   = get(res_sum, d, 0.0) + l.residential_rent
                        res_count[d] = get(res_count, d, 0) + 1
                    end
                end
                all_distances = sort(collect(union(keys(com_sum), keys(res_sum))))
                for d in all_distances
                    nc = get(com_count, d, 0)
                    nr = get(res_count, d, 0)
                    mean_cr = nc > 0 ? com_sum[d] / nc : 0.0
                    mean_rr = nr > 0 ? res_sum[d] / nr : 0.0
                    push!(gradient_rows, "$t,$d,$(round(mean_cr,digits=4)),$(round(mean_rr,digits=4)),$nc,$nr,$cbd_x,$cbd_y")
                end
            end
        end

        # Progress report
        if t % REPORT_EVERY == 0
            aw  = state.active_worker_ids
            pop = length(aw)
            emp = count(w -> !isnothing(state.workers[w].employer_id), aw)
            n_roads = length(state.road_network.segments)
            rents_c = [l.commercial_rent for l in state.lots if l.commercial_units > 0]
            max_cr  = isempty(rents_c) ? 0.0 : maximum(rents_c)
            elapsed = time() - t0
            @printf("t=%-5d  pop=%-4d  emp=%3.0f%%  firms=%-3d  grid=%d×%d  roads=%-3d  max_com_rent=%6.2f  (%.0fs)\n",
                t, pop,
                pop > 0 ? 100.0 * emp / pop : 0.0,
                length(state.active_firm_ids),
                state.params.width, state.params.height,
                n_roads, max_cr, elapsed)
            flush(stdout)
        end
    end

    # ── Outputs ──────────────────────────────────────────────────────────────

    write_lot_csv(state, joinpath(OUT_DIR, "lots_final.csv"))
    write_market_log_csv(state, joinpath(OUT_DIR, "market_log.csv"))
    write_market_log_delta_csv(state, joinpath(OUT_DIR, "market_log_deltas.csv"))
    write_firm_exit_log_csv(state, joinpath(OUT_DIR, "firm_failures.csv"))
    write_consumer_switch_log_csv(state, joinpath(OUT_DIR, "consumer_switch_log.csv"))
    write_monthly_plan_log_csv(state, joinpath(OUT_DIR, "monthly_plan_log.csv"))

    open(joinpath(OUT_DIR, "roads_final.csv"), "w") do io
        println(io, "id,from_lot_id,to_lot_id,from_x,from_y,to_x,to_y,euclidean_dist,road_length,congested_length,capacity,usage_last_tick")
        for seg in state.road_network.segments
            fl = state.lots[seg.from_lot_id]
            tl = state.lots[seg.to_lot_id]
            @printf(io, "%d,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.2f,%d\n",
                seg.id, seg.from_lot_id, seg.to_lot_id,
                fl.x, fl.y, tl.x, tl.y,
                seg.euclidean_dist, seg.road_length, seg.congested_length,
                seg.capacity, seg.usage_this_tick)
        end
    end

    open(joinpath(OUT_DIR, "expansions.csv"), "w") do io
        for row in expansion_rows
            println(io, row)
        end
    end

    open(joinpath(OUT_DIR, "tick_events.csv"), "w") do io
        for row in event_rows
            println(io, row)
        end
    end

    open(joinpath(OUT_DIR, "rent_gradient.csv"), "w") do io
        for row in gradient_rows
            println(io, row)
        end
    end

    elapsed = time() - t0
    @printf("\nDone in %.1f minutes. Outputs in %s/\n", elapsed / 60.0, OUT_DIR)
    println("  market_log.csv    — per-tick aggregate time series")
    println("  market_log_deltas.csv — per-tick additive deltas for aggregate state reconstruction")
    println("  firm_failures.csv — event log for firm exits with pre-exit economics and reason")
    println("  consumer_switch_log.csv — per-purchase provider switching with trigger and fallback reason")
    println("  monthly_plan_log.csv — per-plan budget pass/fail and projected cash/buffer metrics")
    println("  tick_events.csv   — per-tick event counts (entries/exits/hires/layoffs/build/immigration)")
    println("  lots_tNNNNN.csv   — lot-level spatial snapshots every $(LOT_SNAP_EVERY) ticks")
    println("  lots_final.csv    — final lot state")
    println("  roads_final.csv   — final road network")
    println("  expansions.csv    — one row per grid expansion event")
    println("  rent_gradient.csv — mean commercial/residential rent by Manhattan distance from CBD, every $(LOT_SNAP_EVERY) ticks")
    flush(stdout)
end

main()
