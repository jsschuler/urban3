function primary_work_lot_id(state::ModelState, worker::Worker)
    isnothing(worker.employer_id) && return nothing
    firm = state.firms[worker.employer_id]
    isempty(firm.commercial_units_by_lot) && return nothing
    return first(keys(firm.commercial_units_by_lot))
end

function workplace_distance(state::ModelState, worker_a::Worker, worker_b::Worker)
    lot_a = primary_work_lot_id(state, worker_a)
    lot_b = primary_work_lot_id(state, worker_b)
    (isnothing(lot_a) || isnothing(lot_b)) && return nothing
    return taxicab(state.lots[lot_a], state.lots[lot_b])
end

function human_capital_phase!(state::ModelState)
    for wid in state.active_worker_ids
        worker = state.workers[wid]
        isnothing(worker.employer_id) && continue
        worker.experience_ticks += 1
        worker.human_capital = min(
            state.params.human_capital_max,
            worker.human_capital + state.params.human_capital_gain_per_tick,
        )
    end
end

function decay_worker_ties!(state::ModelState)
    for wid in state.active_worker_ids
        worker = state.workers[wid]
        tie_ids = collect(keys(worker.social_ties))
        for other_id in tie_ids
            other_id > length(state.workers) && (delete!(worker.social_ties, other_id); continue)
            other = state.workers[other_id]
            decay = if !isnothing(worker.employer_id) && worker.employer_id == other.employer_id
                state.params.tie_same_firm_decay
            else
                distance = workplace_distance(state, worker, other)
                isnothing(distance) ? state.params.tie_decay_max :
                    min(state.params.tie_decay_max, state.params.tie_base_decay + state.params.tie_distance_decay_weight * distance)
            end
            new_strength = worker.social_ties[other_id] * (1 - decay)
            if new_strength < state.params.tie_min_strength
                delete!(worker.social_ties, other_id)
            else
                worker.social_ties[other_id] = new_strength
            end
        end
    end
end

function form_coworker_ties!(state::ModelState)
    for firm in active_firms(state)
        ids = firm.worker_ids
        n = length(ids)
        n < 2 && continue
        for i in 1:(n - 1)
            wid_i = ids[i]
            for j in (i + 1):n
                wid_j = ids[j]
                worker_i = state.workers[wid_i]
                worker_j = state.workers[wid_j]
                worker_i.social_ties[wid_j] = min(1.0, get(worker_i.social_ties, wid_j, 0.0) + state.params.tie_formation_rate)
                worker_j.social_ties[wid_i] = min(1.0, get(worker_j.social_ties, wid_i, 0.0) + state.params.tie_formation_rate)
            end
        end
    end
end

function social_ties_phase!(state::ModelState)
    decay_worker_ties!(state)
    form_coworker_ties!(state)
end

function network_score(state::ModelState, worker_id::Int)
    worker = state.workers[worker_id]
    total = 0.0
    for (other_id, strength) in worker.social_ties
        other_id > length(state.workers) && continue
        other = state.workers[other_id]
        if !isnothing(worker.employer_id) && worker.employer_id == other.employer_id
            total += strength
            continue
        end
        distance = workplace_distance(state, worker, other)
        !isnothing(distance) && distance <= state.params.network_spillover_radius && (total += strength)
    end
    return total
end

function network_multiplier(state::ModelState, worker_id::Int)
    score = network_score(state, worker_id)
    return 1 + min(state.params.network_multiplier_cap, state.params.network_multiplier_weight * score)
end

function effective_labor(state::ModelState, worker_id::Int)
    worker = state.workers[worker_id]
    return worker.human_capital * network_multiplier(state, worker_id)
end
