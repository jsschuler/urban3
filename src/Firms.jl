function production_capacity(state::ModelState, f::Firm, params::ModelParams)
    !f.active && return 0
    ft = params.firm_types[f.firm_type]
    labor = sum(effective_labor(state, wid) for wid in f.worker_ids; init=0.0)
    capital = f.capital_units
    space = sum(values(f.commercial_units_by_lot))
    processes = max(1, f.process_count)
    labor == 0 || capital == 0 || space == 0 ? (return 0) : nothing
    total = 0.0
    for _ in 1:processes
        l = labor / processes
        k = capital / processes
        s = effective_sites(f, params) / processes
        total += ft.productivity * (l ^ ft.labor_elasticity) * (k ^ ft.capital_elasticity) * (s ^ ft.space_elasticity)
    end
    return max(0, floor(Int, total))
end

function effective_sites(f::Firm, params::ModelParams)
    total = 0.0
    for units in values(f.commercial_units_by_lot)
        total += units + floor(units / params.site_consolidation_k)
    end
    return max(total, 1.0)
end

function hire_worker!(state::ModelState, w::Worker, f::Firm)
    !f.active && return false
    !isnothing(w.employer_id) && return false
    length(f.worker_ids) >= state.params.max_workers_per_firm && return false
    push!(f.worker_ids, w.id)
    f.current_worker_wages[w.id] = f.posted_wage
    w.employer_id = f.id
    w.current_wage = f.posted_wage
    w.moved_job_this_tick = true
    state.events.hires += 1
    return true
end

function fire_worker!(state::ModelState, f::Firm, worker_id::Int)
    filter!(id -> id != worker_id, f.worker_ids)
    delete!(f.current_worker_wages, worker_id)
    w = state.workers[worker_id]
    w.employer_id = nothing
    w.current_wage = 0.0
    state.events.layoffs += 1
end

function firm_reviews!(state::ModelState)
    for f in active_firms(state)
        if rand(state.rng) < state.params.price_review_prob
            sold_out = !isempty(f.realized_sales_history) && f.realized_sales_history[end] >= f.committed_output
            f.goods_price *= sold_out ? (1 + state.params.price_raise_rate) : (1 - state.params.price_cut_rate)
            f.goods_price = max(0.25, f.goods_price)
        end
        if rand(state.rng) < state.params.wage_review_prob
            has_vacancy = length(f.worker_ids) < state.params.max_workers_per_firm
            f.posted_wage *= has_vacancy ? (1 + state.params.wage_raise_rate) : (1 - state.params.wage_cut_rate)
            f.posted_wage = max(1.0, f.posted_wage)
        end
    end
end

function commit_production!(state::ModelState)
    for f in active_firms(state)
        f.committed_output = production_capacity(state, f, state.params)
        f.realized_sales_this_tick = 0
    end
end

function calculate_profits!(state::ModelState)
    for f in active_firms(state)
        revenue = f.realized_sales_this_tick * f.goods_price
        wages = sum(values(f.current_worker_wages); init=0.0)
        rent = sum(state.lots[lid].commercial_rent * n for (lid, n) in f.commercial_units_by_lot; init=0.0)
        profit = revenue - wages - rent
        push!(f.realized_sales_history, f.realized_sales_this_tick)
        push!(f.profit_history, profit)
        if profit > 0
            for (wid, share) in f.ownership_shares
                state.workers[wid].savings += profit * share
            end
        end
    end
end

function firm_contraction_expansion!(state::ModelState)
    for f in copy(active_firms(state))
        if rand(state.rng) < state.params.contraction_review_prob
            recent = last(f.realized_sales_history, min(length(f.realized_sales_history), state.params.modal_sales_lookback))
            target = modal_int(collect(recent))
            while production_capacity(state, f, state.params) > target && length(f.worker_ids) > 1
                highest = f.worker_ids[argmax([f.current_worker_wages[id] for id in f.worker_ids])]
                fire_worker!(state, f, highest)
            end
            while production_capacity(state, f, state.params) > target && f.capital_units > 1
                f.capital_units -= 1
            end
        end
        if rand(state.rng) < state.params.expansion_review_prob
            profitable = !isempty(f.profit_history) && f.profit_history[end] > 0
            sold_out = f.realized_sales_this_tick >= f.committed_output && f.committed_output > 0
            if profitable && sold_out
                f.capital_units += 1
                rand(state.rng) < 0.25 && (f.process_count += 1)
                commercial_space_search!(state, f)
            end
        end
        if length(f.worker_ids) == 0 || f.capital_units == 0
            liquidate_firm!(state, f)
        end
    end
end

function liquidate_firm!(state::ModelState, f::Firm)
    !f.active && return
    for wid in copy(f.worker_ids)
        fire_worker!(state, f, wid)
    end
    for (lid, n) in f.commercial_units_by_lot
        state.lots[lid].occupied_commercial = max(0, state.lots[lid].occupied_commercial - n)
    end
    empty!(f.commercial_units_by_lot)
    f.active = false
    state.events.firm_exits += 1
end

function best_vacant_commercial_candidate(state::ModelState, f::Firm, candidates::Vector{Int})
    best_lot_id = nothing
    vacant_count = 0
    for lid in candidates
        lot = state.lots[lid]
        vacant_commercial(lot) <= 0 && continue
        vacant_count += 1
        if isnothing(best_lot_id)
            best_lot_id = lid
            continue
        end
        current = state.lots[best_lot_id]
        if commercial_location_score(state, f, lid) > commercial_location_score(state, f, best_lot_id)
            best_lot_id = lid
        elseif commercial_location_score(state, f, lid) == commercial_location_score(state, f, best_lot_id) &&
            get(f.commercial_units_by_lot, lid, 0) > get(f.commercial_units_by_lot, best_lot_id, 0)
            best_lot_id = lid
        end
    end
    return best_lot_id, vacant_count
end

function mean_employee_commute_to_lot(state::ModelState, f::Firm, lot_id::Int)
    total = 0.0
    count = 0
    destination = state.lots[lot_id]
    for wid in f.worker_ids
        worker = state.workers[wid]
        isnothing(worker.dwelling_lot_id) && continue
        total += taxicab(state.lots[worker.dwelling_lot_id], destination)
        count += 1
    end
    count == 0 && return 0.0
    return total / count
end

function commercial_location_score(state::ModelState, f::Firm, lot_id::Int)
    lot = state.lots[lot_id]
    consolidation_bonus = get(f.commercial_units_by_lot, lot_id, 0)
    return state.params.firm_consumer_access_weight * state.consumer_access_by_lot[lot_id] +
        state.params.firm_job_access_weight * state.job_access_by_lot[lot_id] +
        state.params.firm_employee_commute_weight * (-mean_employee_commute_to_lot(state, f, lot_id)) +
        consolidation_bonus -
        lot.commercial_rent
end

function cheapest_global_vacant_commercial_lot(state::ModelState, f::Firm)
    best_lot_id = nothing
    for lot in state.lots
        vacant_commercial(lot) <= 0 && continue
        if isnothing(best_lot_id)
            best_lot_id = lot.id
            continue
        end
        current = state.lots[best_lot_id]
        if commercial_location_score(state, f, lot.id) > commercial_location_score(state, f, best_lot_id)
            best_lot_id = lot.id
        elseif commercial_location_score(state, f, lot.id) == commercial_location_score(state, f, best_lot_id) &&
            get(f.commercial_units_by_lot, lot.id, 0) > get(f.commercial_units_by_lot, best_lot_id, 0)
            best_lot_id = lot.id
        end
    end
    return best_lot_id
end

function commercial_search_satisficed(
    state::ModelState,
    f::Firm,
    anchor::Union{Nothing,Int},
    candidates::Vector{Int},
)
    best_lot_id, vacant_count = best_vacant_commercial_candidate(state, f, candidates)
    isnothing(best_lot_id) && return false
    vacant_count < state.params.commercial_search_target_vacant_candidates && return false
    isnothing(anchor) && return true
    anchor_rent = state.lots[anchor].commercial_rent
    acceptable_rent = max(
        state.params.min_commercial_rent,
        anchor_rent * state.params.commercial_search_acceptance_multiplier,
    )
    return state.lots[best_lot_id].commercial_rent <= acceptable_rent
end

function commercial_space_search!(state::ModelState, f::Firm)
    anchor = isempty(f.commercial_units_by_lot) ? nothing : first(keys(f.commercial_units_by_lot))
    candidates = adaptive_candidate_lots(
        state,
        anchor,
        state.params.commercial_search;
        domain=:commercial_space,
        actor_kind=:firm,
        actor_id=f.id,
        accept=(lots, stage) -> commercial_search_satisficed(state, f, anchor, lots),
    )
    chosen_lot_id, _ = best_vacant_commercial_candidate(state, f, candidates)
    evaluated_candidates = candidates

    if isnothing(chosen_lot_id) && state.params.commercial_search_global_rescue
        chosen_lot_id = cheapest_global_vacant_commercial_lot(state, f)
        !isnothing(chosen_lot_id) && (evaluated_candidates = collect(eachindex(state.lots)))
    elseif !isnothing(chosen_lot_id) && !commercial_search_satisficed(state, f, anchor, candidates) &&
        state.params.commercial_search_global_rescue
        rescue_lot_id = cheapest_global_vacant_commercial_lot(state, f)
        if !isnothing(rescue_lot_id) &&
            state.lots[rescue_lot_id].commercial_rent < state.lots[chosen_lot_id].commercial_rent
            chosen_lot_id = rescue_lot_id
            evaluated_candidates = collect(eachindex(state.lots))
        end
    end

    if !isnothing(chosen_lot_id)
        lot = state.lots[chosen_lot_id]
        lot.occupied_commercial += 1
        f.commercial_units_by_lot[chosen_lot_id] = get(f.commercial_units_by_lot, chosen_lot_id, 0) + 1
        log_commercial_space_search!(state, f, evaluated_candidates, chosen_lot_id)
        log_commercial_search_diagnostic!(state, f, anchor, evaluated_candidates, chosen_lot_id)
        return true
    end

    log_commercial_space_search!(state, f, evaluated_candidates, nothing)
    log_commercial_search_diagnostic!(state, f, anchor, evaluated_candidates, nothing)
    return false
end
