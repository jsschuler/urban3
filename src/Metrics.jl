function metrics_snapshot(state::ModelState)
    workers = length(state.active_worker_ids)
    employed = count(wid -> !isnothing(state.workers[wid].employer_id), state.active_worker_ids)
    housed = count(wid -> !isnothing(state.workers[wid].dwelling_lot_id), state.active_worker_ids)
    active = active_firms(state)
    res_units = sum(l.residential_units for l in state.lots)
    com_units = sum(l.commercial_units for l in state.lots)
    occ_res = sum(l.occupied_residential for l in state.lots)
    occ_com = sum(l.occupied_commercial for l in state.lots)
    wages = [state.workers[wid].current_wage for wid in state.active_worker_ids if !isnothing(state.workers[wid].employer_id)]
    rents_r = [l.residential_rent for l in state.lots]
    rents_c = [l.commercial_rent for l in state.lots]
    prices = [f.goods_price for f in active if is_b2c(state, f)]
    commutes = commute_distances(state)
    Dict(
        "type" => "diagnostic_snapshot",
        "tick" => state.tick,
        "population" => workers,
        "employment" => employed,
        "unemployment" => workers - employed,
        "unhoused" => workers - housed,
        "firm_count" => length(active),
        "firm_entries" => state.events.firm_entries,
        "firm_exits" => state.events.firm_exits,
        "hires" => state.events.hires,
        "layoffs" => state.events.layoffs,
        "residential_units" => res_units,
        "commercial_units" => com_units,
        "residential_vacancy_rate" => res_units == 0 ? 0.0 : (res_units - occ_res) / res_units,
        "commercial_vacancy_rate" => com_units == 0 ? 0.0 : (com_units - occ_com) / com_units,
        "mean_residential_rent" => isempty(rents_r) ? 0.0 : mean(rents_r),
        "mean_commercial_rent" => isempty(rents_c) ? 0.0 : mean(rents_c),
        "mean_wage" => isempty(wages) ? 0.0 : mean(wages),
        "mean_price" => isempty(prices) ? 0.0 : mean(prices),
        "mean_commute" => isempty(commutes) ? 0.0 : mean(commutes),
        "firm_size_distribution" => [length(f.worker_ids) for f in active],
        "goods_sales_by_type" => sales_by_type(state),
        "input_market_summary" => input_market_summary(state),
        "tier_diagnostics" => tier_diagnostics(state),
        "decision_summary" => decision_summary(state),
        "market_failure_summary" => market_failure_summary(state),
        "search_coverage_summary" => search_coverage_summary(state),
        "lots" => [lot_dict(l) for l in state.lots],
    )
end

function commute_distances(state::ModelState)
    out = Float64[]
    for wid in state.active_worker_ids
        w = state.workers[wid]
        isnothing(w.dwelling_lot_id) && continue
        isnothing(w.employer_id) && continue
        lid = nearest_firm_lot(state.firms[w.employer_id], w.dwelling_lot_id, state)
        isnothing(lid) && continue
        push!(out, taxicab(state.lots[w.dwelling_lot_id], state.lots[lid]))
    end
    return out
end

function sales_by_type(state::ModelState)
    out = Dict(string(i) => 0 for i in 1:state.params.firm_type_count)
    for f in active_firms(state)
        out[string(f.firm_type)] += f.realized_sales_this_tick
    end
    return out
end

function input_market_summary(state::ModelState)
    b2b = [f for f in active_firms(state) if is_b2b(state, f)]
    b2c = [f for f in active_firms(state) if is_b2c(state, f)]
    fill_rates = Float64[]
    for f in active_firms(state)
        isempty(required_input_types(state, f)) && continue
        push!(fill_rates, leontief_input_scale(state, f))
    end
    input_prices = Dict(string(f.firm_type) => f.goods_price for f in b2b)
    Dict(
        "b2b_firm_count" => length(b2b),
        "b2c_firm_count" => length(b2c),
        "mean_input_fill_rate" => isempty(fill_rates) ? 1.0 : mean(fill_rates),
        "zero_fill_rate_share" => isempty(fill_rates) ? 0.0 : count(x -> x == 0.0, fill_rates) / length(fill_rates),
        "mean_input_price_by_type" => input_prices,
        "b2b_sold_out_share" => isempty(b2b) ? 0.0 :
            count(f -> f.realized_sales_this_tick >= f.committed_output && f.committed_output > 0, b2b) / length(b2b),
    )
end

function tier_diagnostics(state::ModelState)
    max_tier = max_supply_tier(state)
    counts   = Dict(t => 0       for t in 1:max_tier)
    fills    = Dict(t => Float64[] for t in 1:max_tier)
    sold_out = Dict(t => Float64[] for t in 1:max_tier)
    prices   = Dict(t => Float64[] for t in 1:max_tier)
    for f in active_firms(state)
        t = firm_supply_tier(state, f)
        counts[t] += 1
        push!(prices[t], f.goods_price)
        if f.committed_output > 0
            push!(sold_out[t], f.realized_sales_this_tick >= f.committed_output ? 1.0 : 0.0)
        end
        isempty(required_input_types(state, f)) && continue
        push!(fills[t], leontief_input_scale(state, f))
    end
    cash_neg = Dict(t => 0 for t in 1:max_tier)
    for f in active_firms(state)
        f.cash < 0 && (cash_neg[firm_supply_tier(state, f)] += 1)
    end
    out = Dict{String,Any}()
    for t in 1:max_tier
        out["firms_t$t"]      = counts[t]
        out["fill_t$t"]       = isempty(fills[t])    ? 1.0 : mean(fills[t])
        out["sold_out_t$t"]   = isempty(sold_out[t]) ? 0.0 : mean(sold_out[t])
        out["mean_price_t$t"] = isempty(prices[t])   ? 0.0 : mean(prices[t])
        out["insolvent_t$t"]  = cash_neg[t]
    end
    return out
end
