function reset_tick_flags!(state::ModelState)
    state.events = reset_events!()
    empty!(state.commercial_bid_buffer)
    for w in state.workers
        w.moved_job_this_tick = false
        w.moved_home_this_tick = false
    end
end

function step!(state::ModelState)
    reset_tick_flags!(state)
    state.tick += 1
    refresh_spatial_access!(state)
    human_capital_phase!(state)
    social_ties_phase!(state)
    firm_reviews!(state)
    commit_production!(state)
    consumption_phase!(state)
    calculate_profits!(state)
    refresh_spatial_access!(state)
    firm_contraction_expansion!(state)
    entrepreneurship_phase!(state)
    resolve_commercial_bids!(state)
    refresh_spatial_access!(state)
    worker_job_search!(state)
    refresh_spatial_access!(state)
    worker_housing_search!(state)
    developer_update!(state)
    outside_entry!(state)
    refresh_spatial_access!(state)
    record_market_snapshot!(state)
    return state
end

function run!(state::ModelState, n::Int; on_tick=nothing)
    for _ in 1:n
        step!(state)
        isnothing(on_tick) || on_tick(state)
    end
    return state
end
