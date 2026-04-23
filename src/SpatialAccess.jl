function access_weight(distance::Int, radius::Int, decay::Float64)
    distance > radius && return 0.0
    return 1.0 / ((1 + distance) ^ decay)
end

function refresh_consumer_access!(state::ModelState)
    fill!(state.consumer_access_by_lot, 0.0)
    radius = state.params.consumer_access_radius
    decay = state.params.access_distance_decay
    housed_counts = zeros(Float64, length(state.lots))
    for w in state.workers
        isnothing(w.dwelling_lot_id) && continue
        housed_counts[w.dwelling_lot_id] += 1.0
    end
    occupied_ids = findall(>(0.0), housed_counts)
    for lot in state.lots
        total = 0.0
        for origin_id in occupied_ids
            d = taxicab(lot, state.lots[origin_id])
            total += housed_counts[origin_id] * access_weight(d, radius, decay)
        end
        state.consumer_access_by_lot[lot.id] = total
    end
end

function refresh_job_access!(state::ModelState)
    fill!(state.job_access_by_lot, 0.0)
    radius = state.params.job_access_radius
    decay = state.params.access_distance_decay
    vacancy_by_lot = zeros(Float64, length(state.lots))
    for f in active_firms(state)
        vacancies = max(0, state.params.max_workers_per_firm - length(f.worker_ids))
        vacancies <= 0 && continue
        for (lid, units) in f.commercial_units_by_lot
            vacancy_by_lot[lid] += vacancies * max(units, 1)
        end
    end
    vacancy_ids = findall(>(0.0), vacancy_by_lot)
    for lot in state.lots
        total = 0.0
        for origin_id in vacancy_ids
            d = taxicab(lot, state.lots[origin_id])
            total += vacancy_by_lot[origin_id] * access_weight(d, radius, decay)
        end
        state.job_access_by_lot[lot.id] = total
    end
end

function refresh_spatial_access!(state::ModelState)
    refresh_consumer_access!(state)
    refresh_job_access!(state)
end
