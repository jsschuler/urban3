function push_decision!(state::ModelState, record::DecisionRecord)
    state.params.enable_decision_logging || return
    log = state.decision_log
    push!(log.records, record)
    overflow = length(log.records) - log.max_records
    overflow > 0 && deleteat!(log.records, 1:overflow)
end

function log_commercial_space_search!(
    state::ModelState,
    firm::Firm,
    candidates::Vector{Int},
    chosen_lot_id::Union{Nothing,Int},
)
    state.params.enable_decision_logging || return

    vacant_ids = Int[]
    rents = Float64[]
    for lid in candidates
        lot = state.lots[lid]
        push!(rents, lot.commercial_rent)
        if vacant_commercial(lot) > 0
            push!(vacant_ids, lid)
            state.decision_log.commercial_vacant_considered_counts[lid] =
                get(state.decision_log.commercial_vacant_considered_counts, lid, 0) + 1
        end
    end

    if !isnothing(chosen_lot_id)
        state.decision_log.commercial_vacant_chosen_counts[chosen_lot_id] =
            get(state.decision_log.commercial_vacant_chosen_counts, chosen_lot_id, 0) + 1
    end

    reason = if isnothing(chosen_lot_id)
        isempty(vacant_ids) ? :no_vacant_candidate : :no_choice
    else
        :selected_lowest_rent_candidate
    end

    push_decision!(state, DecisionRecord(
        state.tick,
        :firm,
        firm.id,
        :commercial_space_search,
        length(candidates),
        length(vacant_ids),
        :lot,
        chosen_lot_id,
        reason,
        isempty(rents) ? NaN : minimum(rents),
        isempty(rents) ? NaN : maximum(rents),
    ))
end

function vacant_commercial_lot_considered(state::ModelState, lot_id::Int)
    get(state.decision_log.commercial_vacant_considered_counts, lot_id, 0) > 0
end

function decision_summary(state::ModelState)
    by_decision = Dict{String,Int}()
    for record in state.decision_log.records
        key = string(record.decision)
        by_decision[key] = get(by_decision, key, 0) + 1
    end
    Dict(
        "records_retained" => length(state.decision_log.records),
        "records_by_decision" => by_decision,
        "commercial_vacant_lots_considered" => length(state.decision_log.commercial_vacant_considered_counts),
        "commercial_vacant_considerations" => sum(values(state.decision_log.commercial_vacant_considered_counts); init=0),
        "commercial_vacant_lots_chosen" => length(state.decision_log.commercial_vacant_chosen_counts),
        "commercial_vacant_choices" => sum(values(state.decision_log.commercial_vacant_chosen_counts); init=0),
    )
end
