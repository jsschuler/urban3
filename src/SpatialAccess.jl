function access_weight(distance::Int, radius::Int, decay::Float64)
    distance > radius && return 0.0
    return 1.0 / ((1 + distance) ^ decay)
end

function scatter_access!(dest::Vector{Float64}, source_by_lot::Vector{Float64},
                         lots::Vector{Lot}, width::Int, height::Int,
                         radius::Int, decay::Float64)
    fill!(dest, 0.0)
    for origin_id in eachindex(source_by_lot)
        source_by_lot[origin_id] == 0.0 && continue
        weight = source_by_lot[origin_id]
        o = lots[origin_id]
        for dy in -radius:radius
            y = o.y + dy
            (y < 1 || y > height) && continue
            dx_max = radius - abs(dy)
            for dx in -dx_max:dx_max
                x = o.x + dx
                (x < 1 || x > width) && continue
                lid = lot_id_at(x, y, width)
                dest[lid] += weight * access_weight(abs(dx) + abs(dy), radius, decay)
            end
        end
    end
end

function refresh_consumer_access!(state::ModelState)
    housed_counts = zeros(Float64, length(state.lots))
    for wid in state.active_worker_ids
        w = state.workers[wid]
        isnothing(w.dwelling_lot_id) && continue
        housed_counts[w.dwelling_lot_id] += 1.0
    end
    scatter_access!(state.consumer_access_by_lot, housed_counts,
                    state.lots, state.params.width, state.params.height,
                    state.params.consumer_access_radius, state.params.access_distance_decay)
end

function refresh_job_access!(state::ModelState)
    vacancy_by_lot = zeros(Float64, length(state.lots))
    for f in active_firms(state)
        weight = length(f.worker_ids) + 1
        for (lid, ticks_list) in f.commercial_units_by_lot
            vacancy_by_lot[lid] += weight * max(length(ticks_list), 1)
        end
    end
    scatter_access!(state.job_access_by_lot, vacancy_by_lot,
                    state.lots, state.params.width, state.params.height,
                    state.params.job_access_radius, state.params.access_distance_decay)
end

function refresh_spatial_access!(state::ModelState)
    refresh_consumer_access!(state)
    refresh_job_access!(state)
end
