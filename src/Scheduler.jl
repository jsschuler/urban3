function reset_tick_flags!(state::ModelState)
    state.events = reset_events!()
    for w in state.workers
        w.moved_job_this_tick = false
        w.moved_home_this_tick = false
    end
end

function step!(state::ModelState)
    reset_tick_flags!(state)
    state.tick += 1
    firm_reviews!(state)
    commit_production!(state)
    consumption_phase!(state)
    calculate_profits!(state)
    firm_contraction_expansion!(state)
    worker_job_search!(state)
    worker_housing_search!(state)
    developer_update!(state)
    entrepreneurship_phase!(state)
    outside_entry!(state)
    return state
end

function run!(state::ModelState, n::Int; on_tick=nothing)
    for _ in 1:n
        step!(state)
        isnothing(on_tick) || on_tick(state)
    end
    return state
end
