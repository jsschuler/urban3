function log_search_coverage!(
    state::ModelState;
    domain::Symbol,
    actor_kind::Symbol,
    actor_id::Int,
    origin_lot_id::Union{Nothing,Int},
    raw_lot_ids::Vector{Int},
    unique_lot_ids::Vector{Int},
    local_draw_count::Int,
    global_draw_count::Int,
)
    state.params.enable_search_logging || return
    log = state.search_log

    log.event_counts_by_domain[domain] = get(log.event_counts_by_domain, domain, 0) + 1
    log.raw_draw_counts_by_domain[domain] = get(log.raw_draw_counts_by_domain, domain, 0) + length(raw_lot_ids)
    log.unique_draw_counts_by_domain[domain] = get(log.unique_draw_counts_by_domain, domain, 0) + length(unique_lot_ids)

    lot_counts = get!(log.lot_counts_by_domain, domain, Dict{Int,Int}())
    for lot_id in unique_lot_ids
        lot_counts[lot_id] = get(lot_counts, lot_id, 0) + 1
    end

    push!(log.records, SearchCoverageRecord(
        state.tick,
        domain,
        actor_kind,
        actor_id,
        origin_lot_id,
        length(raw_lot_ids),
        length(unique_lot_ids),
        local_draw_count,
        global_draw_count,
    ))

    overflow = length(log.records) - log.max_records
    overflow > 0 && deleteat!(log.records, 1:overflow)
end

function search_coverage_summary(state::ModelState)
    rows = Dict{String,Any}[]
    total_lots = length(state.lots)
    for domain in sort(collect(keys(state.search_log.event_counts_by_domain)); by=string)
        events = state.search_log.event_counts_by_domain[domain]
        covered = length(get(state.search_log.lot_counts_by_domain, domain, Dict{Int,Int}()))
        raw_draws = get(state.search_log.raw_draw_counts_by_domain, domain, 0)
        unique_draws = get(state.search_log.unique_draw_counts_by_domain, domain, 0)
        push!(rows, Dict{String,Any}(
            "domain" => string(domain),
            "events" => events,
            "lots_covered" => covered,
            "lot_coverage_share" => total_lots == 0 ? 0.0 : covered / total_lots,
            "raw_draws" => raw_draws,
            "unique_draws" => unique_draws,
            "mean_raw_draws_per_event" => events == 0 ? 0.0 : raw_draws / events,
            "mean_unique_lots_per_event" => events == 0 ? 0.0 : unique_draws / events,
        ))
    end
    return rows
end

function write_search_coverage_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "domain",
            "events",
            "lots_covered",
            "lot_coverage_share",
            "raw_draws",
            "unique_draws",
            "mean_raw_draws_per_event",
            "mean_unique_lots_per_event",
        ], ","))
        for row in search_coverage_summary(state)
            println(io, join([
                row["domain"],
                row["events"],
                row["lots_covered"],
                row["lot_coverage_share"],
                row["raw_draws"],
                row["unique_draws"],
                row["mean_raw_draws_per_event"],
                row["mean_unique_lots_per_event"],
            ], ","))
        end
    end
    return path
end
