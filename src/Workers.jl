function worker_income(w::Worker, params::ModelParams)
    isnothing(w.employer_id) ? params.outside_wage : w.current_wage
end

function consumption_phase!(state::ModelState)
    remaining = Dict(f.id => f.committed_output for f in active_firms(state) if is_b2c(state, f))
    for w in state.workers
        income = worker_income(w, state.params)
        income <= 0 && continue
        w.savings += income * w.savings_rate
        budget = income * (1 - w.savings_rate)
        while budget >= 0.25
            choice, delivered_cost = choose_good(w, state, remaining, budget)
            isnothing(choice) && break
            f = state.firms[choice]
            budget -= delivered_cost
            remaining[f.id] -= 1
            f.realized_sales_this_tick += 1
            w.preferred_firm_by_type[f.firm_type] = f.id
            w.last_delivered_cost_by_type[f.firm_type] = delivered_cost
        end
    end
end

function choose_good(w::Worker, state::ModelState, remaining::Dict{Int,Int}, budget::Float64)
    habitual_choice = habitual_goods_choice(w, state, remaining, budget)
    if !isnothing(habitual_choice)
        choice_id, choice_score, delivered_cost = habitual_choice
        origin = worker_anchor_lot(w, state)
        log_goods_search_diagnostic!(state, w, origin, budget, Int[], choice_id, choice_score)
        return choice_id, delivered_cost
    end

    origin = worker_anchor_lot(w, state)
    sampled_lots = adaptive_candidate_lots(
        state,
        origin,
        state.params.goods_search;
        domain=:goods,
        actor_kind=:worker,
        actor_id=w.id,
        accept=(lots, stage) -> affordable_sampled_goods_count(w, state, remaining, budget, lots) >=
            state.params.goods_search_target_affordable_candidates,
    )
    choice_id, choice_score, delivered_cost = probabilistic_goods_choice(w, state, remaining, budget, sampled_lots)
    log_goods_search_diagnostic!(state, w, origin, budget, sampled_lots, choice_id, choice_score)
    return choice_id, delivered_cost
end

function delivered_goods_utility(
    w::Worker,
    state::ModelState,
    firm::Firm,
    origin_lot_id::Union{Nothing,Int},
    service_lot_id::Int,
)
    distance = isnothing(origin_lot_id) ? 0 :
        taxicab(state.lots[origin_lot_id], state.lots[service_lot_id])
    return w.utility[firm.firm_type] -
        state.params.goods_price_weight * firm.goods_price -
        state.params.goods_distance_weight * distance * state.params.goods_travel_cost_per_block
end

function delivered_goods_cost(
    state::ModelState,
    firm::Firm,
    origin_lot_id::Union{Nothing,Int},
    service_lot_id::Int,
)
    distance_cost = isnothing(origin_lot_id) ? 0.0 :
        taxicab(state.lots[origin_lot_id], state.lots[service_lot_id]) * state.params.goods_travel_cost_per_block
    return firm.goods_price + distance_cost
end

function habitual_goods_choice(
    w::Worker,
    state::ModelState,
    remaining::Dict{Int,Int},
    budget::Float64,
)
    rand(state.rng) < state.params.shopping_review_prob && return nothing

    preferred_pairs = collect(w.preferred_firm_by_type)
    isempty(preferred_pairs) && return nothing

    sort!(preferred_pairs; by=pair -> w.utility[pair.first], rev=true)
    origin_lot_id = worker_anchor_lot(w, state)

    for (firm_type, firm_id) in preferred_pairs
        firm_id > length(state.firms) && continue
        firm = state.firms[firm_id]
        !firm.active && continue
        get(remaining, firm.id, 0) <= 0 && continue
        isempty(firm.commercial_units_by_lot) && continue
        service_lot_id = isnothing(origin_lot_id) ? first(keys(firm.commercial_units_by_lot)) :
            nearest_firm_lot(firm, origin_lot_id, state)
        isnothing(service_lot_id) && continue
        delivered_cost = delivered_goods_cost(state, firm, origin_lot_id, service_lot_id)
        delivered_cost > budget && continue
        previous_cost = get(w.last_delivered_cost_by_type, firm_type, delivered_cost)
        delivered_cost > previous_cost * (1 + state.params.shopping_price_increase_tolerance) && continue
        utility = delivered_goods_utility(w, state, firm, origin_lot_id, service_lot_id)
        return firm.id, utility, delivered_cost
    end

    return nothing
end

function probabilistic_goods_choice(
    w::Worker,
    state::ModelState,
    remaining::Dict{Int,Int},
    budget::Float64,
    sampled_lots::Vector{Int},
)
    sampled_set = Set(sampled_lots)
    origin_lot_id = worker_anchor_lot(w, state)
    candidate_ids = Int[]
    candidate_scores = Float64[]
    candidate_costs = Float64[]

    for f in active_firms(state)
        get(remaining, f.id, 0) <= 0 && continue
        candidate_lots = [lid for lid in keys(f.commercial_units_by_lot) if lid in sampled_set]
        isempty(candidate_lots) && continue
        service_lot_id = isnothing(origin_lot_id) ? first(candidate_lots) :
            nearest_firm_lot(f, origin_lot_id, state)
        isnothing(service_lot_id) && continue
        delivered_cost = delivered_goods_cost(state, f, origin_lot_id, service_lot_id)
        delivered_cost > budget && continue
        utility = delivered_goods_utility(w, state, f, origin_lot_id, service_lot_id)
        push!(candidate_ids, f.id)
        push!(candidate_scores, utility)
        push!(candidate_costs, delivered_cost)
    end

    isempty(candidate_ids) && return nothing, -Inf, Inf

    max_score = maximum(candidate_scores)
    weights = Float64[]
    for score in candidate_scores
        push!(weights, exp(state.params.goods_choice_sensitivity * (score - max_score)))
    end

    total_weight = sum(weights)
    total_weight <= 0 && return nothing, -Inf, Inf

    draw = rand(state.rng) * total_weight
    cumulative = 0.0
    for (i, weight) in enumerate(weights)
        cumulative += weight
        if draw <= cumulative
            return candidate_ids[i], candidate_scores[i], candidate_costs[i]
        end
    end

    return candidate_ids[end], candidate_scores[end], candidate_costs[end]
end

function affordable_sampled_goods_count(
    w::Worker,
    state::ModelState,
    remaining::Dict{Int,Int},
    budget::Float64,
    sampled_lots::Vector{Int},
)
    sampled_set = Set(sampled_lots)
    count = 0
    origin_lot_id = worker_anchor_lot(w, state)
    for f in active_firms(state)
        get(remaining, f.id, 0) <= 0 && continue
        candidate_lots = [lid for lid in keys(f.commercial_units_by_lot) if lid in sampled_set]
        isempty(candidate_lots) && continue
        service_lot_id = isnothing(origin_lot_id) ? first(candidate_lots) :
            nearest_firm_lot(f, origin_lot_id, state)
        isnothing(service_lot_id) && continue
        travel_cost = isnothing(origin_lot_id) ? 0.0 :
            taxicab(state.lots[origin_lot_id], state.lots[service_lot_id]) * state.params.goods_travel_cost_per_block
        f.goods_price + travel_cost > budget && continue
        count += 1
    end
    return count
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
    return move_to_best_home!(w, state; current_required=false)
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
    if isnothing(w.employer_id)
        income = state.params.outside_wage
        commute = state.params.job_access_radius * state.params.commute_cost_per_block
    else
        income = w.current_wage
        job_lot = nearest_firm_lot(state.firms[w.employer_id], lot_id, state)
        commute = isnothing(job_lot) ? 0.0 : taxicab(lot, state.lots[job_lot]) * state.params.commute_cost_per_block
    end
    disposable = max(0.0, income * (1 - w.savings_rate) - commute)
    return lot.residential_rent <= disposable * state.params.housing_budget_share
end

function home_utility(w::Worker, state::ModelState, lot_id::Int)
    lot = state.lots[lot_id]
    job_lot = isnothing(w.employer_id) ? lot_id : nearest_firm_lot(state.firms[w.employer_id], lot_id, state)
    commute = isnothing(job_lot) ? 0 : taxicab(lot, state.lots[job_lot])
    job_access = state.job_access_by_lot[lot_id]
    return -lot.residential_rent -
        state.params.commute_cost_per_block * commute +
        0.05 * lot_height(lot) +
        state.params.housing_job_access_weight * job_access
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
