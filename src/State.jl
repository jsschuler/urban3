function draw_worker(id::Int, params::ModelParams, rng::AbstractRNG)
    u = rand(rng, params.firm_type_count)
    u ./= sum(u)
    savings = max(0.0, params.initial_savings_mean + params.initial_savings_sd * randn(rng))
    rate = params.savings_rate_min + rand(rng) * (params.savings_rate_max - params.savings_rate_min)
    period = max(1, params.goods_search_period)
    goods_offset = rand(rng, 0:(period - 1))
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
        0,
        goods_offset,
    )
end

function generate_io_matrix(params::ModelParams)
    n = params.firm_type_count
    rng_io = MersenneTwister(params.io_matrix_seed)
    mat = zeros(Float64, n, n)
    draw_coeff() = params.io_matrix_coefficient_min +
        rand(rng_io) * (params.io_matrix_coefficient_max - params.io_matrix_coefficient_min)
    max_tier = maximum(ft.supply_tier for ft in params.firm_types)
    for buyer_tier in 2:max_tier
        buyers = [i for i in 1:n if params.firm_types[i].supply_tier == buyer_tier]
        suppliers = [i for i in 1:n if params.firm_types[i].supply_tier == buyer_tier - 1]
        for buyer in buyers, supplier in suppliers
            if rand(rng_io) < params.io_matrix_density
                mat[buyer, supplier] = draw_coeff()
            end
        end
        # Coverage guards: avoid orphan buyer and orphan supplier types.
        for buyer in buyers
            has_input = any(mat[buyer, supplier] > 0.0 for supplier in suppliers)
            has_input && continue
            forced_supplier = suppliers[rand(rng_io, eachindex(suppliers))]
            mat[buyer, forced_supplier] = draw_coeff()
        end
        for supplier in suppliers
            has_downstream = any(mat[buyer, supplier] > 0.0 for buyer in buyers)
            has_downstream && continue
            forced_buyer = buyers[rand(rng_io, eachindex(buyers))]
            mat[forced_buyer, supplier] = draw_coeff()
        end
    end
    return mat
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
    # Seed commercial units in a small central cluster so investor firms can open.
    # All other lots start with 0 commercial units; the developer expands supply from here.
    cx = (params.width + 1) ÷ 2
    cy = (params.height + 1) ÷ 2
    for l in lots
        if abs(l.x - cx) + abs(l.y - cy) <= params.initial_commercial_core_radius
            l.commercial_units = 1
        else
            # Lots with no commercial capacity get floor rent so conversion never fires spuriously.
            l.commercial_rent = params.min_commercial_rent
        end
    end

    lot_by_position = Dict{Tuple{Int,Int}, Int}()
    for l in lots
        lot_by_position[(l.x, l.y)] = l.id
    end
    state = ModelState(0, params, rng, lots, Worker[], Firm[], Set{Int}(), Set{Int}(), reset_events!(),
        init_decision_log(params.decision_log_limit),
        init_market_log(params.market_log_limit),
        init_firm_exit_log(params.firm_exit_log_limit),
        init_consumer_switch_log(params.consumer_switch_log_limit),
        init_monthly_plan_log(params.monthly_plan_log_limit),
        init_search_coverage_log(params.search_log_limit),
        init_open_diagnostic_log(
            params.open_diagnostic_commercial_limit,
            params.open_diagnostic_goods_limit,
        ),
        zeros(Float64, length(lots)),
        zeros(Float64, length(lots)),
        CommercialBidProposal[],
        RofrEntry[],
        generate_io_matrix(params),
        Dict{Int,Int}(),
        init_road_network(params.road_initial_cash),
        lot_by_position,
        -params.grid_expansion_cooldown,
        DeveloperState(0.0, 0.0, 0.0, Dict{Int,Float64}(), Dict{Int,Float64}(), 0.0, 0.0),
        EntrepreneurAgent(Dict{Int, Vector{Float64}}(), 0))
    # Investor founds one firm per output type; workers arrive via vacancy-driven immigration
    for ftype in 1:params.firm_type_count
        f = investor_found_firm!(state, ftype)
        !isnothing(f) && (state.investor_firm_by_type[ftype] = f.id)
    end
    resolve_commercial_bids!(state)
    # Stagger initial leases so all initial firms don't expire on the same tick
    for f in state.firms
        cap_offset = rand(rng, 0:(params.capital_lease_term - 1))
        f.capital_lease_ticks .= -cap_offset
        f.process_lease_ticks .= -cap_offset
        for (_, ticks_list) in f.commercial_units_by_lot
            com_offset = rand(rng, 0:(params.commercial_lease_term - 1))
            ticks_list .= -com_offset
        end
    end
    # Pre-hire initial workers across all firm types (round-robin).
    # Sets planned_worker_target = actual headcount to protect headcount during warmup.
    begin
    b2c_fids = collect(state.active_firm_ids)
    end
    for i in 1:params.initial_workers
        id = length(state.workers) + 1
        w = draw_worker(id, params, rng)
        push!(state.workers, w)
        push!(state.active_worker_ids, id)
        f = state.firms[b2c_fids[(i - 1) % length(b2c_fids) + 1]]
        push!(f.worker_ids, id)
        f.current_worker_wages[id] = f.posted_wage
        w.employer_id = f.id
        w.current_wage = f.posted_wage
        f.planned_worker_target = length(f.worker_ids)
    end
    refresh_spatial_access!(state)
    return state
end

function active_firms(state::ModelState)
    [state.firms[id] for id in state.active_firm_ids]
end

function active_workers(state::ModelState)
    [state.workers[id] for id in state.active_worker_ids]
end
