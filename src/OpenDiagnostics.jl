function push_commercial_search_diagnostic!(state::ModelState, record::CommercialSearchDiagnosticRecord)
    state.params.enable_open_diagnostic_logging || return
    log = state.open_diagnostic_log
    push!(log.commercial_search_records, record)
    overflow = length(log.commercial_search_records) - log.max_commercial_records
    overflow > 0 && deleteat!(log.commercial_search_records, 1:overflow)
end

function push_goods_search_diagnostic!(state::ModelState, record::GoodsSearchDiagnosticRecord)
    state.params.enable_open_diagnostic_logging || return
    log = state.open_diagnostic_log
    push!(log.goods_search_records, record)
    overflow = length(log.goods_search_records) - log.max_goods_records
    overflow > 0 && deleteat!(log.goods_search_records, 1:overflow)
end

function log_commercial_search_diagnostic!(
    state::ModelState,
    firm::Firm,
    origin_lot_id::Union{Nothing,Int},
    candidates::Vector{Int},
    chosen_lot_id::Union{Nothing,Int},
)
    state.params.enable_open_diagnostic_logging || return

    sampled_vacant_ids = Int[]
    for lid in candidates
        vacant_commercial(state.lots[lid]) > 0 && push!(sampled_vacant_ids, lid)
    end

    best_sampled_vacant_lot_id = isempty(sampled_vacant_ids) ? nothing :
        sampled_vacant_ids[argmin([state.lots[lid].commercial_rent for lid in sampled_vacant_ids])]

    global_vacant_ids = Int[]
    for lot in state.lots
        vacant_commercial(lot) > 0 && push!(global_vacant_ids, lot.id)
    end

    best_global_vacant_lot_id = isempty(global_vacant_ids) ? nothing :
        global_vacant_ids[argmin([state.lots[lid].commercial_rent for lid in global_vacant_ids])]

    chosen_rent = isnothing(chosen_lot_id) ? NaN : state.lots[chosen_lot_id].commercial_rent
    best_sampled_vacant_rent = isnothing(best_sampled_vacant_lot_id) ? NaN : state.lots[best_sampled_vacant_lot_id].commercial_rent
    best_global_vacant_rent = isnothing(best_global_vacant_lot_id) ? NaN : state.lots[best_global_vacant_lot_id].commercial_rent

    cheaper_unsampled_vacant_count = 0
    if !isnan(chosen_rent)
        sampled_set = Set(candidates)
        for lid in global_vacant_ids
            (lid in sampled_set) && continue
            state.lots[lid].commercial_rent < chosen_rent && (cheaper_unsampled_vacant_count += 1)
        end
    end

    push_commercial_search_diagnostic!(state, CommercialSearchDiagnosticRecord(
        state.tick,
        firm.id,
        origin_lot_id,
        length(candidates),
        length(sampled_vacant_ids),
        chosen_lot_id,
        chosen_rent,
        best_sampled_vacant_lot_id,
        best_sampled_vacant_rent,
        best_global_vacant_lot_id,
        best_global_vacant_rent,
        cheaper_unsampled_vacant_count,
    ))
end

function log_goods_search_diagnostic!(
    state::ModelState,
    worker::Worker,
    origin_lot_id::Union{Nothing,Int},
    budget::Float64,
    sampled_lots::Vector{Int},
    chosen_firm_id::Union{Nothing,Int},
    chosen_score::Float64,
)
    state.params.enable_open_diagnostic_logging || return

    sampled_set = Set(sampled_lots)
    best_sampled_firm_id = nothing
    best_sampled_score = -Inf
    best_global_firm_id = nothing
    best_global_score = -Inf
    best_global_price = NaN
    affordable_global_count = 0
    better_unsampled_count = 0

    chosen_firm_type = nothing
    chosen_price = NaN
    if !isnothing(chosen_firm_id)
        chosen_firm = state.firms[chosen_firm_id]
        chosen_firm_type = chosen_firm.firm_type
        chosen_price = chosen_firm.goods_price
    end

    for firm in active_firms(state)
        available = max(0, firm.committed_output - firm.realized_sales_this_tick)
        available <= 0 && continue
        service_lot_id = isnothing(origin_lot_id) ? first(keys(firm.commercial_units_by_lot)) :
            nearest_firm_lot(firm, origin_lot_id, state)
        isnothing(service_lot_id) && continue
        travel_cost = isnothing(origin_lot_id) ? 0.0 :
            taxicab(state.lots[origin_lot_id], state.lots[service_lot_id]) * state.params.goods_travel_cost_per_block
        effective_price = firm.goods_price + travel_cost
        effective_price > budget && continue

        affordable_global_count += 1
        score = worker.utility[firm.firm_type] / effective_price

        if score > best_global_score
            best_global_score = score
            best_global_firm_id = firm.id
            best_global_price = effective_price
        end

        sampled = any(lid -> lid in sampled_set, keys(firm.commercial_units_by_lot))
        if sampled && score > best_sampled_score
            best_sampled_score = score
            best_sampled_firm_id = firm.id
        end
    end

    if !isnothing(chosen_firm_id)
        for firm in active_firms(state)
            available = max(0, firm.committed_output - firm.realized_sales_this_tick)
            available <= 0 && continue
            service_lot_id = isnothing(origin_lot_id) ? first(keys(firm.commercial_units_by_lot)) :
                nearest_firm_lot(firm, origin_lot_id, state)
            isnothing(service_lot_id) && continue
            travel_cost = isnothing(origin_lot_id) ? 0.0 :
                taxicab(state.lots[origin_lot_id], state.lots[service_lot_id]) * state.params.goods_travel_cost_per_block
            effective_price = firm.goods_price + travel_cost
            effective_price > budget && continue
            sampled = any(lid -> lid in sampled_set, keys(firm.commercial_units_by_lot))
            sampled && continue
            score = worker.utility[firm.firm_type] / effective_price
            score > chosen_score && (better_unsampled_count += 1)
        end
    end

    push_goods_search_diagnostic!(state, GoodsSearchDiagnosticRecord(
        state.tick,
        worker.id,
        origin_lot_id,
        budget,
        length(sampled_lots),
        chosen_firm_id,
        chosen_firm_type,
        chosen_price,
        chosen_score,
        best_sampled_firm_id,
        best_sampled_score,
        best_global_firm_id,
        best_global_score,
        best_global_price,
        better_unsampled_count,
        affordable_global_count,
    ))
end

function write_commercial_search_diagnostics_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "firm_id",
            "origin_lot_id",
            "sampled_count",
            "sampled_vacant_count",
            "chosen_lot_id",
            "chosen_rent",
            "best_sampled_vacant_lot_id",
            "best_sampled_vacant_rent",
            "best_global_vacant_lot_id",
            "best_global_vacant_rent",
            "cheaper_unsampled_vacant_count",
        ], ","))
        for r in state.open_diagnostic_log.commercial_search_records
            println(io, join([
                r.tick,
                r.firm_id,
                something(r.origin_lot_id, ""),
                r.sampled_count,
                r.sampled_vacant_count,
                something(r.chosen_lot_id, ""),
                r.chosen_rent,
                something(r.best_sampled_vacant_lot_id, ""),
                r.best_sampled_vacant_rent,
                something(r.best_global_vacant_lot_id, ""),
                r.best_global_vacant_rent,
                r.cheaper_unsampled_vacant_count,
            ], ","))
        end
    end
    return path
end

function write_goods_search_diagnostics_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "worker_id",
            "origin_lot_id",
            "budget",
            "sampled_count",
            "chosen_firm_id",
            "chosen_firm_type",
            "chosen_price",
            "chosen_score",
            "best_sampled_firm_id",
            "best_sampled_score",
            "best_global_firm_id",
            "best_global_score",
            "best_global_price",
            "better_unsampled_count",
            "affordable_global_count",
        ], ","))
        for r in state.open_diagnostic_log.goods_search_records
            println(io, join([
                r.tick,
                r.worker_id,
                something(r.origin_lot_id, ""),
                r.budget,
                r.sampled_count,
                something(r.chosen_firm_id, ""),
                something(r.chosen_firm_type, ""),
                r.chosen_price,
                r.chosen_score,
                something(r.best_sampled_firm_id, ""),
                r.best_sampled_score,
                something(r.best_global_firm_id, ""),
                r.best_global_score,
                r.best_global_price,
                r.better_unsampled_count,
                r.affordable_global_count,
            ], ","))
        end
    end
    return path
end
