function has_active_ownership(state::ModelState, w::Worker)
    for firm_id in keys(w.ownership_shares)
        firm_id > length(state.firms) && continue
        state.firms[firm_id].active && return true
    end
    return false
end

function entrepreneurship_phase!(state::ModelState)
    for wid in state.active_worker_ids
        w = state.workers[wid]
        if w.savings >= state.params.solo_startup_savings && rand(state.rng) < state.params.solo_found_prob
            found_firm!(state, [w.id]; startup_capital=state.params.solo_startup_savings)
        end
    end
    if rand(state.rng) < state.params.coalition_found_prob
        candidates = [state.workers[wid] for wid in state.active_worker_ids if state.workers[wid].savings > 0]
        sort!(candidates; by=w -> w.savings, rev=true)
        n = min(length(candidates), rand(state.rng, state.params.coalition_size_min:state.params.coalition_size_max))
        if n >= state.params.coalition_size_min && sum(w.savings for w in candidates[1:n]) >= state.params.coalition_startup_savings
            found_firm!(state, [w.id for w in candidates[1:n]]; startup_capital=state.params.coalition_startup_savings)
        end
    end
end

function found_firm!(state::ModelState, founder_ids::Vector{Int}; startup_capital::Float64, initial_cash::Float64=startup_capital)
    isempty(founder_ids) && return nothing
    firm_id = length(state.firms) + 1
    total_savings = sum(state.workers[id].savings for id in founder_ids)
    total_savings <= 0 && return nothing
    shares = Dict(id => state.workers[id].savings / total_savings for id in founder_ids)
    if startup_capital > 0
        for id in founder_ids
            state.workers[id].savings = max(0.0, state.workers[id].savings - startup_capital * shares[id])
        end
    end
    ftype = rand(state.rng, 1:state.params.firm_type_count)
    firm = Firm(firm_id, ftype, copy(founder_ids), shares,
        state.params.base_wage * (0.9 + 0.2 * rand(state.rng)),
        Int[], Dict{Int,Float64}(),
        2, fill(state.tick, 2),
        1, [state.tick],
        Dict{Int,Vector{Int}}(), Dict{Int,Vector{Float64}}(), 0,
        state.params.firm_types[ftype].initial_goods_price_min +
            rand(state.rng) * (state.params.firm_types[ftype].initial_goods_price_max - state.params.firm_types[ftype].initial_goods_price_min),
        0, 0, Int[], Float64[], true, true,
        state.tick,
        Dict{Int,Int}(), 0.0, initial_cash)
    push!(state.firms, firm)
    push!(state.active_firm_ids, firm_id)
    for (id, share) in shares
        state.workers[id].ownership_shares[firm_id] = share
    end
    commercial_space_search!(state, firm)
    return firm
end

function investor_found_firm!(state::ModelState, ftype::Int)
    firm_id = length(state.firms) + 1
    ft = state.params.firm_types[ftype]
    firm = Firm(firm_id, ftype, Int[], Dict{Int,Float64}(),
        state.params.base_wage * (0.9 + 0.2 * rand(state.rng)),
        Int[], Dict{Int,Float64}(),
        2, fill(state.tick, 2),
        1, [state.tick],
        Dict{Int,Vector{Int}}(), Dict{Int,Vector{Float64}}(), 0,
        ft.initial_goods_price_min + rand(state.rng) * (ft.initial_goods_price_max - ft.initial_goods_price_min),
        0, 0, Int[], Float64[], true, true,
        state.tick,
        Dict{Int,Int}(), 0.0, state.params.investor_initial_firm_cash)
    push!(state.firms, firm)
    push!(state.active_firm_ids, firm_id)
    commercial_space_search!(state, firm)
    return firm
end

function investor_phase!(state::ModelState)
    for ftype in 1:state.params.firm_type_count
        fid = get(state.investor_firm_by_type, ftype, 0)
        if fid == 0 || !state.firms[fid].active
            f = investor_found_firm!(state, ftype)
            !isnothing(f) && (state.investor_firm_by_type[ftype] = f.id)
        end
    end
end
