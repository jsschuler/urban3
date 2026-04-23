function entrepreneurship_phase!(state::ModelState)
    for w in state.workers
        isempty(w.ownership_shares) || continue
        if w.savings >= state.params.solo_startup_savings && rand(state.rng) < state.params.solo_found_prob
            found_firm!(state, [w.id]; startup_capital=state.params.solo_startup_savings)
        end
    end
    if rand(state.rng) < state.params.coalition_found_prob
        candidates = [w for w in state.workers if isempty(w.ownership_shares) && w.savings > 0]
        sort!(candidates; by=w -> w.savings, rev=true)
        n = min(length(candidates), rand(state.rng, state.params.coalition_size_min:state.params.coalition_size_max))
        if n >= state.params.coalition_size_min && sum(w.savings for w in candidates[1:n]) >= state.params.coalition_startup_savings
            found_firm!(state, [w.id for w in candidates[1:n]]; startup_capital=state.params.coalition_startup_savings)
        end
    end
end

function found_firm!(state::ModelState, founder_ids::Vector{Int}; startup_capital::Float64)
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
        2, 1, Dict{Int,Int}(),
        4.0 + rand(state.rng) * 2.0,
        0, 0, Int[], Float64[], true, true)
    push!(state.firms, firm)
    for (id, share) in shares
        state.workers[id].ownership_shares[firm_id] = share
    end
    commercial_space_search!(state, firm)
    return firm
end

function outside_entry!(state::ModelState)
    n = poisson(state.rng, state.params.outside_entry_rate)
    for _ in 1:n
        id = length(state.workers) + 1
        push!(state.workers, draw_worker(id, state.params, state.rng))
        state.events.outside_entries += 1
    end
end
