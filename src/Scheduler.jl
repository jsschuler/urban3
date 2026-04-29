function reset_tick_flags!(state::ModelState)
    state.events = reset_events!()
    for wid in state.active_worker_ids
        w = state.workers[wid]
        w.moved_job_this_tick = false
        w.moved_home_this_tick = false
    end
end

function step!(state::ModelState)
    reset_tick_flags!(state)
    state.tick += 1
    human_capital_phase!(state)
    social_ties_phase!(state)
    firm_reviews!(state)
    entrepreneurship_phase!(state)
    resolve_commercial_bids!(state)
    refresh_spatial_access!(state)
    worker_job_search!(state)
    commit_intermediate_output!(state)                          # tier 1 B2B commits (no inputs)
    input_purchasing_phase!(state, 2)                           # tier 2 B2B buys from tier 1
    commit_b2b_with_inputs!(state)                              # tier 2 B2B commits Leontief-scaled
    input_purchasing_phase!(state, max_supply_tier(state))      # B2C buys from tier 2
    commit_production!(state)                                   # B2C commits Leontief-scaled
    consumption_phase!(state)
    calculate_profits!(state)
    firm_contraction_expansion!(state)
    refresh_spatial_access!(state)
    worker_housing_search!(state)
    worker_exit!(state)
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
