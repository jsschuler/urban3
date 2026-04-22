function metrics_snapshot(state::ModelState)
    workers = length(state.workers)
    employed = count(w -> !isnothing(w.employer_id), state.workers)
    housed = count(w -> !isnothing(w.dwelling_lot_id), state.workers)
    active = active_firms(state)
    res_units = sum(l.residential_units for l in state.lots)
    com_units = sum(l.commercial_units for l in state.lots)
    occ_res = sum(l.occupied_residential for l in state.lots)
    occ_com = sum(l.occupied_commercial for l in state.lots)
    wages = [w.current_wage for w in state.workers if !isnothing(w.employer_id)]
    rents_r = [l.residential_rent for l in state.lots]
    rents_c = [l.commercial_rent for l in state.lots]
    prices = [f.goods_price for f in active]
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
        "lots" => [lot_dict(l) for l in state.lots],
    )
end

function commute_distances(state::ModelState)
    out = Float64[]
    for w in state.workers
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
