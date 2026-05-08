function poisson(rng::AbstractRNG, λ::Float64)::Int
    λ <= 0 && return 0
    L = exp(-λ)
    k = 0
    p = 1.0
    while p > L
        k += 1
        p *= rand(rng)
    end
    return k - 1
end

function draw_candidate_lots(
    state::ModelState,
    origin::Union{Nothing,Int},
    params::SearchParams,
)
    rng = state.rng
    out = Int[]
    local_draw_count = 0
    if !isnothing(origin) && rand(rng) <= params.local_weight
        o = state.lots[origin]
        n = max(1, poisson(rng, params.poisson_intensity))
        for _ in 1:n
            dx = rand(rng, -params.radius:params.radius)
            dy = rand(rng, -params.radius:params.radius)
            if abs(dx) + abs(dy) <= params.radius
                x = clamp(o.x + dx, 1, state.params.width)
                y = clamp(o.y + dy, 1, state.params.height)
                lid = get(state.lot_by_position, (x, y), 0)
                lid > 0 && push!(out, lid)
                local_draw_count += 1
            end
        end
    end
    for _ in 1:params.global_samples
        push!(out, rand(rng, eachindex(state.lots)))
    end
    return out, local_draw_count
end

function escalated_search_params(state::ModelState, params::SearchParams, stage::Int)
    stage <= 0 && return params
    max_radius = max(state.params.width, state.params.height)
    SearchParams(
        poisson_intensity=params.poisson_intensity * (params.poisson_multiplier ^ stage),
        radius=min(max_radius, params.radius + stage * params.radius_step),
        global_samples=max(1, ceil(Int, params.global_samples * (params.global_multiplier ^ stage))),
        local_weight=max(0.0, params.local_weight - stage * params.local_weight_decay),
        max_expansions=params.max_expansions,
        poisson_multiplier=params.poisson_multiplier,
        radius_step=params.radius_step,
        global_multiplier=params.global_multiplier,
        local_weight_decay=params.local_weight_decay,
    )
end

function finalize_candidate_lot_search!(
    state::ModelState,
    origin::Union{Nothing,Int},
    raw_lot_ids::Vector{Int};
    domain::Symbol = :generic,
    actor_kind::Symbol = :unknown,
    actor_id::Int = 0,
    local_draw_count::Int = 0,
    global_draw_count::Int = 0,
)
    unique_lots = unique(raw_lot_ids)
    log_search_coverage!(
        state;
        domain=domain,
        actor_kind=actor_kind,
        actor_id=actor_id,
        origin_lot_id=origin,
        raw_lot_ids=raw_lot_ids,
        unique_lot_ids=unique_lots,
        local_draw_count=local_draw_count,
        global_draw_count=global_draw_count,
    )
    return unique_lots
end

function candidate_lots(
    state::ModelState,
    origin::Union{Nothing,Int},
    params::SearchParams;
    domain::Symbol = :generic,
    actor_kind::Symbol = :unknown,
    actor_id::Int = 0,
)
    out, local_draw_count = draw_candidate_lots(state, origin, params)
    return finalize_candidate_lot_search!(
        state,
        origin,
        out;
        domain=domain,
        actor_kind=actor_kind,
        actor_id=actor_id,
        local_draw_count=local_draw_count,
        global_draw_count=params.global_samples,
    )
end

function adaptive_candidate_lots(
    state::ModelState,
    origin::Union{Nothing,Int},
    params::SearchParams;
    domain::Symbol = :generic,
    actor_kind::Symbol = :unknown,
    actor_id::Int = 0,
    accept = (lots, stage) -> true,
)
    raw_lot_ids = Int[]
    total_local_draws = 0
    total_global_draws = 0
    unique_lots = Int[]

    for stage in 0:params.max_expansions
        stage_params = escalated_search_params(state, params, stage)
        stage_draws, local_draw_count = draw_candidate_lots(state, origin, stage_params)
        append!(raw_lot_ids, stage_draws)
        total_local_draws += local_draw_count
        total_global_draws += stage_params.global_samples
        unique_lots = unique(raw_lot_ids)
        accept(unique_lots, stage) && break
    end

    return finalize_candidate_lot_search!(
        state,
        origin,
        raw_lot_ids;
        domain=domain,
        actor_kind=actor_kind,
        actor_id=actor_id,
        local_draw_count=total_local_draws,
        global_draw_count=total_global_draws,
    )
end

function worker_anchor_lot(w::Worker, state::ModelState)
    !isnothing(w.dwelling_lot_id) && return w.dwelling_lot_id
    if !isnothing(w.employer_id) && !isempty(state.firms[w.employer_id].commercial_units_by_lot)
        return first(keys(state.firms[w.employer_id].commercial_units_by_lot))
    end
    return nothing
end

function nearest_firm_lot(f::Firm, worker_lot::Union{Nothing,Int}, state::ModelState)
    isempty(f.commercial_units_by_lot) && return nothing
    ids = collect(keys(f.commercial_units_by_lot))
    isnothing(worker_lot) && return ids[1]
    origin = state.lots[worker_lot]
    return ids[argmin([taxicab(origin, state.lots[id]) for id in ids])]
end

function modal_int(xs::Vector{Int})
    isempty(xs) && return 0
    counts = Dict{Int,Int}()
    for x in xs
        counts[x] = get(counts, x, 0) + 1
    end
    best = first(keys(counts))
    best_count = counts[best]
    for (x, c) in counts
        if c > best_count || (c == best_count && x < best)
            best = x
            best_count = c
        end
    end
    return best
end
