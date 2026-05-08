function record_market_snapshot!(state::ModelState)
    state.params.enable_market_logging || return

    firms = active_firms(state)
    population = length(state.active_worker_ids)
    employed = count(wid -> !isnothing(state.workers[wid].employer_id), state.active_worker_ids)
    housed = count(wid -> !isnothing(state.workers[wid].dwelling_lot_id), state.active_worker_ids)
    residential_units = sum(l.residential_units for l in state.lots)
    vacant_residential_units = sum(vacant_residential(l) for l in state.lots)
    commercial_units = sum(l.commercial_units for l in state.lots)
    vacant_commercial_units = sum(vacant_commercial(l) for l in state.lots)
    firm_job_vacancies = 0
    firms_with_job_vacancies = 0
    committed_output = sum(f.committed_output for f in firms; init=0)
    realized_sales = sum(f.realized_sales_this_tick for f in firms; init=0)
    unsold_output = sum(max(0, f.committed_output - f.realized_sales_this_tick) for f in firms; init=0)
    sold_out_firms = count(f -> f.committed_output > 0 && f.realized_sales_this_tick >= f.committed_output, firms)
    wages = [state.workers[wid].current_wage for wid in state.active_worker_ids if !isnothing(state.workers[wid].employer_id)]
    residential_rents = [l.residential_rent for l in state.lots]
    commercial_rents = [l.commercial_rent for l in state.lots if l.commercial_units > 0 && l.occupied_commercial > 0]
    goods_prices = [f.goods_price for f in firms]

    push!(state.market_log.records, MarketSnapshot(
        state.tick,
        population,
        employed,
        population - employed,
        housed,
        population - housed,
        residential_units,
        vacant_residential_units,
        commercial_units,
        vacant_commercial_units,
        length(firms),
        firm_job_vacancies,
        firms_with_job_vacancies,
        committed_output,
        realized_sales,
        unsold_output,
        sold_out_firms,
        isempty(wages) ? 0.0 : mean(wages),
        isempty(residential_rents) ? 0.0 : mean(residential_rents),
        isempty(commercial_rents) ? 0.0 : mean(commercial_rents),
        isempty(goods_prices) ? 0.0 : mean(goods_prices),
    ))

    overflow = length(state.market_log.records) - state.market_log.max_records
    overflow > 0 && deleteat!(state.market_log.records, 1:overflow)
end

function market_failure_summary(state::ModelState)
    isempty(state.market_log.records) && return Dict{String,Any}()
    r = state.market_log.records[end]
    Dict(
        "tick" => r.tick,
        "labor_excess_supply" => r.unemployed,
        "labor_excess_demand" => r.firm_job_vacancies,
        "housing_excess_supply" => r.vacant_residential_units,
        "housing_excess_demand" => r.unhoused,
        "commercial_space_excess_supply" => r.vacant_commercial_units,
        "goods_excess_supply" => r.unsold_output,
        "goods_sold_out_firms" => r.sold_out_firms,
    )
end

function write_market_log_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "population",
            "employed",
            "unemployed",
            "housed",
            "unhoused",
            "residential_units",
            "vacant_residential_units",
            "commercial_units",
            "vacant_commercial_units",
            "active_firms",
            "firm_job_vacancies",
            "firms_with_job_vacancies",
            "committed_output",
            "realized_sales",
            "unsold_output",
            "sold_out_firms",
            "mean_wage",
            "mean_residential_rent",
            "mean_commercial_rent",
            "mean_goods_price",
        ], ","))
        for r in state.market_log.records
            println(io, join([
                r.tick,
                r.population,
                r.employed,
                r.unemployed,
                r.housed,
                r.unhoused,
                r.residential_units,
                r.vacant_residential_units,
                r.commercial_units,
                r.vacant_commercial_units,
                r.active_firms,
                r.firm_job_vacancies,
                r.firms_with_job_vacancies,
                r.committed_output,
                r.realized_sales,
                r.unsold_output,
                r.sold_out_firms,
                r.mean_wage,
                r.mean_residential_rent,
                r.mean_commercial_rent,
                r.mean_goods_price,
            ], ","))
        end
    end
    return path
end
