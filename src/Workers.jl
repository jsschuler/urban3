function worker_income(w::Worker)
    isnothing(w.employer_id) ? 0.0 : w.current_wage
end

function consumption_phase!(state::ModelState)
    remaining = Dict(f.id => f.committed_output for f in active_firms(state))
    for w in state.workers
        income = worker_income(w)
        income <= 0 && continue
        w.savings += income * w.savings_rate
        budget = income * (1 - w.savings_rate)
        while budget >= 0.25
            choice = choose_good(w, state, remaining, budget)
            isnothing(choice) && break
            f = state.firms[choice]
            budget -= f.goods_price
            remaining[f.id] -= 1
            f.realized_sales_this_tick += 1
        end
    end
end

function choose_good(w::Worker, state::ModelState, remaining::Dict{Int,Int}, budget::Float64)
    origin = worker_anchor_lot(w, state)
    sampled_lots = candidate_lots(
        state,
        origin,
        state.params.goods_search;
        domain=:goods,
        actor_kind=:worker,
        actor_id=w.id,
    )
    best_id = nothing
    best_score = -Inf
    for f in active_firms(state)
        get(remaining, f.id, 0) <= 0 && continue
        f.goods_price > budget && continue
        any(lid -> lid in sampled_lots, keys(f.commercial_units_by_lot)) || continue
        score = w.utility[f.firm_type] / f.goods_price
        if score > best_score
            best_score = score
            best_id = f.id
        end
    end
    return best_id
end

function worker_job_search!(state::ModelState)
    for w in state.workers
        rand(state.rng) > state.params.job_review_prob && continue
        job_search!(employment_state(w), housing_state(w), w, state)
    end
end

function job_search!(::Unemployed, ::Unhoused, w::Worker, state::ModelState)
    return apply_best_job!(w, state)
end

function job_search!(::Unemployed, ::Housed, w::Worker, state::ModelState)
    return apply_best_job!(w, state)
end

function job_search!(::Employed, ::Unhoused, w::Worker, state::ModelState)
    return false
end

function job_search!(::Employed, ::Housed, w::Worker, state::ModelState)
    w.moved_home_this_tick && return false
    current = w.current_wage
    best = best_job(w, state)
    isnothing(best) && return false
    f = state.firms[best]
    if f.posted_wage > current * 1.08
        old = state.firms[w.employer_id]
        fire_worker!(state, old, w.id)
        return hire_worker!(state, w, f)
    end
    return false
end

function apply_best_job!(w::Worker, state::ModelState)
    best = best_job(w, state)
    isnothing(best) && return false
    return hire_worker!(state, w, state.firms[best])
end

function best_job(w::Worker, state::ModelState)
    origin = worker_anchor_lot(w, state)
    sampled = candidate_lots(
        state,
        origin,
        state.params.job_search;
        domain=:job,
        actor_kind=:worker,
        actor_id=w.id,
    )
    best_id = nothing
    best_net = -Inf
    for f in active_firms(state)
        length(f.worker_ids) >= state.params.max_workers_per_firm && continue
        lid = nearest_firm_lot(f, origin, state)
        isnothing(lid) && continue
        lid in sampled || continue
        commute = isnothing(w.dwelling_lot_id) ? 0.0 : taxicab(state.lots[w.dwelling_lot_id], state.lots[lid]) * state.params.commute_cost_per_block
        net = f.posted_wage - commute
        if net > best_net
            best_net = net
            best_id = f.id
        end
    end
    return best_id
end

function worker_housing_search!(state::ModelState)
    for w in state.workers
        rand(state.rng) > state.params.housing_review_prob && continue
        housing_search!(housing_state(w), employment_state(w), w, state)
    end
end

function housing_search!(::Unhoused, ::Unemployed, w::Worker, state::ModelState; force=false)
    return false
end

function housing_search!(::Unhoused, ::Employed, w::Worker, state::ModelState; force=false)
    return move_to_best_home!(w, state; current_required=false)
end

function housing_search!(::Housed, ::Unemployed, w::Worker, state::ModelState; force=false)
    if !housing_affordable(w, state, w.dwelling_lot_id)
        vacate_home!(w, state)
    end
    return false
end

function housing_search!(::Housed, ::Employed, w::Worker, state::ModelState; force=false)
    w.moved_job_this_tick && !force && return false
    if !housing_affordable(w, state, w.dwelling_lot_id)
        vacate_home!(w, state)
        return move_to_best_home!(w, state; current_required=false)
    end
    return move_to_best_home!(w, state; current_required=true)
end

function housing_affordable(w::Worker, state::ModelState, lot_id::Union{Nothing,Int})
    isnothing(lot_id) && return false
    lot = state.lots[lot_id]
    job_lot = isnothing(w.employer_id) ? nothing : nearest_firm_lot(state.firms[w.employer_id], lot_id, state)
    commute = isnothing(job_lot) ? 0.0 : taxicab(lot, state.lots[job_lot]) * state.params.commute_cost_per_block
    disposable = max(0.0, w.current_wage * (1 - w.savings_rate) - commute)
    return lot.residential_rent <= disposable * state.params.housing_budget_share
end

function home_utility(w::Worker, state::ModelState, lot_id::Int)
    lot = state.lots[lot_id]
    job_lot = isnothing(w.employer_id) ? lot_id : nearest_firm_lot(state.firms[w.employer_id], lot_id, state)
    commute = isnothing(job_lot) ? 0 : taxicab(lot, state.lots[job_lot])
    return -lot.residential_rent - state.params.commute_cost_per_block * commute + 0.05 * lot_height(lot)
end

function move_to_best_home!(w::Worker, state::ModelState; current_required::Bool)
    origin = worker_anchor_lot(w, state)
    candidates = candidate_lots(
        state,
        origin,
        state.params.housing_search;
        domain=:housing,
        actor_kind=:worker,
        actor_id=w.id,
    )
    best_lot = nothing
    best_u = current_required && !isnothing(w.dwelling_lot_id) ? home_utility(w, state, w.dwelling_lot_id) : -Inf
    for lid in candidates
        lot = state.lots[lid]
        vacant_residential(lot) <= 0 && continue
        housing_affordable(w, state, lid) || continue
        u = home_utility(w, state, lid)
        if u > best_u
            best_u = u
            best_lot = lid
        end
    end
    isnothing(best_lot) && return false
    !isnothing(w.dwelling_lot_id) && vacate_home!(w, state)
    state.lots[best_lot].occupied_residential += 1
    w.dwelling_lot_id = best_lot
    w.moved_home_this_tick = true
    return true
end

function vacate_home!(w::Worker, state::ModelState)
    isnothing(w.dwelling_lot_id) && return
    lot = state.lots[w.dwelling_lot_id]
    lot.occupied_residential = max(0, lot.occupied_residential - 1)
    w.dwelling_lot_id = nothing
end
