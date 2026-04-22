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

lot_id_at(x::Int, y::Int, width::Int) = (y - 1) * width + x

function candidate_lots(state::ModelState, origin::Union{Nothing,Int}, params::SearchParams)
    rng = state.rng
    out = Int[]
    if !isnothing(origin) && rand(rng) <= params.local_weight
        o = state.lots[origin]
        n = max(1, poisson(rng, params.poisson_intensity))
        for _ in 1:n
            dx = rand(rng, -params.radius:params.radius)
            dy = rand(rng, -params.radius:params.radius)
            if abs(dx) + abs(dy) <= params.radius
                x = clamp(o.x + dx, 1, state.params.width)
                y = clamp(o.y + dy, 1, state.params.height)
                push!(out, lot_id_at(x, y, state.params.width))
            end
        end
    end
    for _ in 1:params.global_samples
        push!(out, rand(rng, eachindex(state.lots)))
    end
    return unique(out)
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
