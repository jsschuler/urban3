function production_capacity(f::Firm, params::ModelParams)
    !f.active && return 0
    ft = params.firm_types[f.firm_type]
    labor = length(f.worker_ids)
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
        f.committed_output = production_capacity(f, state.params)
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
            while production_capacity(f, state.params) > target && length(f.worker_ids) > 1
                highest = f.worker_ids[argmax([f.current_worker_wages[id] for id in f.worker_ids])]
                fire_worker!(state, f, highest)
            end
            while production_capacity(f, state.params) > target && f.capital_units > 1
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

function commercial_space_search!(state::ModelState, f::Firm)
    anchor = isempty(f.commercial_units_by_lot) ? nothing : first(keys(f.commercial_units_by_lot))
    candidates = candidate_lots(
        state,
        anchor,
        state.params.commercial_search;
        domain=:commercial_space,
        actor_kind=:firm,
        actor_id=f.id,
    )
    sort!(candidates; by = lid -> (state.lots[lid].commercial_rent, -get(f.commercial_units_by_lot, lid, 0)))
    for lid in candidates
        lot = state.lots[lid]
        vacant_commercial(lot) <= 0 && continue
        lot.occupied_commercial += 1
        f.commercial_units_by_lot[lid] = get(f.commercial_units_by_lot, lid, 0) + 1
        log_commercial_space_search!(state, f, candidates, lid)
        return true
    end
    log_commercial_space_search!(state, f, candidates, nothing)
    return false
end
