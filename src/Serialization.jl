function tick_snapshot(state::ModelState)
    Dict(
        "type" => "tick_snapshot",
        "tick" => state.tick,
        "diagnostics" => metrics_snapshot(state),
    )
end

function lot_dict(l::Lot)
    Dict(
        "id" => l.id, "x" => l.x, "y" => l.y,
        "residential_units" => l.residential_units,
        "commercial_units" => l.commercial_units,
        "occupied_residential" => l.occupied_residential,
        "occupied_commercial" => l.occupied_commercial,
        "residential_rent" => l.residential_rent,
        "commercial_rent" => l.commercial_rent,
    )
end

function road_dict(seg::RoadSegment, lots::Vector{Lot})
    from = lots[seg.from_lot_id]
    to = lots[seg.to_lot_id]
    Dict(
        "id" => seg.id,
        "from_x" => from.x, "from_y" => from.y,
        "to_x" => to.x, "to_y" => to.y,
    )
end

function blender_snapshot(state::ModelState)
    Dict(
        "type" => "blender_snapshot",
        "tick" => state.tick,
        "lot_scale" => 2,
        "width" => state.params.width,
        "height" => state.params.height,
        "lots" => [lot_dict(l) for l in state.lots],
        "roads" => [road_dict(seg, state.lots) for seg in state.road_network.segments],
    )
end

function write_lot_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "lot_id",
            "x",
            "y",
            "residential_units",
            "commercial_units",
            "occupied_residential",
            "occupied_commercial",
            "vacant_residential",
            "vacant_commercial",
            "residential_rent",
            "commercial_rent",
        ], ","))
        for l in state.lots
            println(io, join([
                state.tick,
                l.id,
                l.x,
                l.y,
                l.residential_units,
                l.commercial_units,
                l.occupied_residential,
                l.occupied_commercial,
                vacant_residential(l),
                vacant_commercial(l),
                l.residential_rent,
                l.commercial_rent,
            ], ","))
        end
    end
    return path
end

function write_firm_exit_log_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "firm_id",
            "firm_type",
            "reason",
            "cash_before_exit",
            "revenue_this_tick",
            "wages_this_tick",
            "commercial_rent_this_tick",
            "capital_rental_this_tick",
            "process_rental_this_tick",
            "input_cost_this_tick",
            "profit_this_tick",
            "worker_count",
            "capital_units",
            "process_count",
            "commercial_units",
            "last_plan_tick",
            "last_plan_passed",
            "last_plan_projected_end_cash",
            "last_plan_total_cost",
            "last_plan_buffer",
        ], ","))
        for r in state.firm_exit_log.records
            println(io, join([
                r.tick,
                r.firm_id,
                r.firm_type,
                String(r.reason),
                r.cash_before_exit,
                r.revenue_this_tick,
                r.wages_this_tick,
                r.commercial_rent_this_tick,
                r.capital_rental_this_tick,
                r.process_rental_this_tick,
                r.input_cost_this_tick,
                r.profit_this_tick,
                r.worker_count,
                r.capital_units,
                r.process_count,
                r.commercial_units,
                r.last_plan_tick,
                r.last_plan_passed ? 1 : 0,
                r.last_plan_projected_end_cash,
                r.last_plan_total_cost,
                r.last_plan_buffer,
            ], ","))
        end
    end
    return path
end

function write_monthly_plan_log_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick","firm_id","firm_type",
            "workers_before","workers_after",
            "capital_before","capital_after",
            "projected_end_cash_before","projected_end_cash_after",
            "total_cost_before","total_cost_after",
            "buffer_before","buffer_after",
            "plan_passed_before","plan_passed_after",
        ], ","))
        for r in state.monthly_plan_log.records
            println(io, join([
                r.tick, r.firm_id, r.firm_type,
                r.workers_before, r.workers_after,
                r.capital_before, r.capital_after,
                r.projected_end_cash_before, r.projected_end_cash_after,
                r.total_cost_before, r.total_cost_after,
                r.buffer_before, r.buffer_after,
                r.plan_passed_before ? 1 : 0,
                r.plan_passed_after ? 1 : 0,
            ], ","))
        end
    end
    return path
end

function write_market_log_delta_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "d_population",
            "d_employed",
            "d_unemployed",
            "d_housed",
            "d_unhoused",
            "d_residential_units",
            "d_vacant_residential_units",
            "d_commercial_units",
            "d_vacant_commercial_units",
            "d_active_firms",
            "d_firm_job_vacancies",
            "d_firms_with_job_vacancies",
            "d_committed_output",
            "d_realized_sales",
            "d_unsold_output",
            "d_sold_out_firms",
            "d_mean_wage",
            "d_mean_residential_rent",
            "d_mean_commercial_rent",
            "d_mean_goods_price",
        ], ","))
        prev = nothing
        for r in state.market_log.records
            if isnothing(prev)
                println(io, join([
                    r.tick, r.population, r.employed, r.unemployed, r.housed, r.unhoused,
                    r.residential_units, r.vacant_residential_units, r.commercial_units, r.vacant_commercial_units,
                    r.active_firms, r.firm_job_vacancies, r.firms_with_job_vacancies,
                    r.committed_output, r.realized_sales, r.unsold_output, r.sold_out_firms,
                    r.mean_wage, r.mean_residential_rent, r.mean_commercial_rent, r.mean_goods_price,
                ], ","))
            else
                p = prev::MarketSnapshot
                println(io, join([
                    r.tick,
                    r.population - p.population,
                    r.employed - p.employed,
                    r.unemployed - p.unemployed,
                    r.housed - p.housed,
                    r.unhoused - p.unhoused,
                    r.residential_units - p.residential_units,
                    r.vacant_residential_units - p.vacant_residential_units,
                    r.commercial_units - p.commercial_units,
                    r.vacant_commercial_units - p.vacant_commercial_units,
                    r.active_firms - p.active_firms,
                    r.firm_job_vacancies - p.firm_job_vacancies,
                    r.firms_with_job_vacancies - p.firms_with_job_vacancies,
                    r.committed_output - p.committed_output,
                    r.realized_sales - p.realized_sales,
                    r.unsold_output - p.unsold_output,
                    r.sold_out_firms - p.sold_out_firms,
                    r.mean_wage - p.mean_wage,
                    r.mean_residential_rent - p.mean_residential_rent,
                    r.mean_commercial_rent - p.mean_commercial_rent,
                    r.mean_goods_price - p.mean_goods_price,
                ], ","))
            end
            prev = r
        end
    end
    return path
end

function write_consumer_switch_log_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "worker_id",
            "firm_type",
            "previous_firm_id",
            "chosen_firm_id",
            "switched",
            "trigger",
            "fallback_reason",
            "previous_delivered_cost",
            "chosen_delivered_cost",
            "budget",
        ], ","))
        for r in state.consumer_switch_log.records
            println(io, join([
                r.tick,
                r.worker_id,
                r.firm_type,
                something(r.previous_firm_id, ""),
                something(r.chosen_firm_id, ""),
                r.switched ? 1 : 0,
                String(r.trigger),
                String(r.fallback_reason),
                r.previous_delivered_cost,
                r.chosen_delivered_cost,
                r.budget,
            ], ","))
        end
    end
    return path
end
