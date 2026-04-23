function draw_worker(id::Int, params::ModelParams, rng::AbstractRNG)
    u = rand(rng, params.firm_type_count)
    u ./= sum(u)
    savings = max(0.0, params.initial_savings_mean + params.initial_savings_sd * randn(rng))
    rate = params.savings_rate_min + rand(rng) * (params.savings_rate_max - params.savings_rate_min)
    Worker(
        id,
        nothing,
        nothing,
        0.0,
        savings,
        rate,
        collect(u),
        Dict{Int,Float64}(),
        Dict{Int,Int}(),
        Dict{Int,Float64}(),
        0,
        params.human_capital_start,
        Dict{Int,Float64}(),
        false,
        false,
    )
end

function init_state(params::ModelParams=ModelParams())
    rng = MersenneTwister(params.seed)
    lots = Lot[]
    id = 1
    for y in 1:params.height, x in 1:params.width
        push!(lots, Lot(id, x, y,
            params.initial_residential_units_per_lot,
            params.initial_commercial_units_per_lot,
            0, 0,
            params.initial_residential_rent_min +
                (params.initial_residential_rent_max - params.initial_residential_rent_min) * rand(rng),
            params.initial_commercial_rent_min +
                (params.initial_commercial_rent_max - params.initial_commercial_rent_min) * rand(rng)))
        id += 1
    end
    workers = [draw_worker(i, params, rng) for i in 1:params.initial_workers]
    state = ModelState(0, params, rng, lots, workers, Firm[], reset_events!(),
        init_decision_log(params.decision_log_limit),
        init_market_log(params.market_log_limit),
        init_search_coverage_log(params.search_log_limit),
        init_open_diagnostic_log(
            params.open_diagnostic_commercial_limit,
            params.open_diagnostic_goods_limit,
        ),
        zeros(Float64, length(lots)),
        zeros(Float64, length(lots)),
        CommercialBidProposal[])
    for _ in 1:params.initial_firms
        found_firm!(state, [rand(rng, eachindex(state.workers))]; startup_capital=0.0)
    end
    resolve_commercial_bids!(state)
    initial_hire!(state)
    initial_house!(state)
    refresh_spatial_access!(state)
    return state
end

function active_firms(state::ModelState)
    [f for f in state.firms if f.active]
end

function initial_hire!(state::ModelState)
    firms = active_firms(state)
    isempty(firms) && return
    for w in state.workers
        f = firms[rand(state.rng, eachindex(firms))]
        length(f.worker_ids) >= state.params.max_workers_per_firm && continue
        hire_worker!(state, w, f)
    end
end

function initial_house!(state::ModelState)
    for w in state.workers
        housing_search!(housing_state(w), employment_state(w), w, state; force=true)
    end
end
