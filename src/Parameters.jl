Base.@kwdef struct SearchParams
    poisson_intensity::Float64 = 4.0
    radius::Int = 4
    global_samples::Int = 8
    local_weight::Float64 = 0.75
    max_expansions::Int = 0
    poisson_multiplier::Float64 = 1.5
    radius_step::Int = 2
    global_multiplier::Float64 = 2.0
    local_weight_decay::Float64 = 0.15
end

Base.@kwdef struct FirmTypeParams
    productivity::Float64 = 4.0
    labor_elasticity::Float64 = 0.45
    capital_elasticity::Float64 = 0.30
    space_elasticity::Float64 = 0.25
    capital_rental_rate::Float64 = 0.25
    process_rental_rate::Float64 = 0.60
    supply_tier::Int = 3   # 1=upstream B2B (no inputs), 2=midstream B2B, 3=final B2C (sells to consumers)
    initial_goods_price_min::Float64 = 4.0
    initial_goods_price_max::Float64 = 6.0
end

Base.@kwdef mutable struct ModelParams
    width::Int = 12
    height::Int = 12
    initial_residential_units_per_lot::Int = 1
    initial_commercial_units_per_lot::Int = 0
    initial_commercial_core_radius::Int = 1
    initial_residential_rent_min::Float64 = 1.8
    initial_residential_rent_max::Float64 = 3.0
    initial_commercial_rent_min::Float64 = 3.0
    initial_commercial_rent_max::Float64 = 5.5
    firm_type_count::Int = 6
    seed::Int = 42

    goods_search::SearchParams = SearchParams(max_expansions=1, radius_step=3, global_multiplier=1.75)
    job_search::SearchParams = SearchParams(poisson_intensity=5.0, radius=5, global_samples=10)
    housing_search::SearchParams = SearchParams(poisson_intensity=5.0, radius=5, global_samples=10)
    commercial_search::SearchParams = SearchParams(
        poisson_intensity=8.0,
        radius=12,
        global_samples=48,
        local_weight=0.45,
        max_expansions=2,
        poisson_multiplier=1.75,
        radius_step=8,
        global_multiplier=2.0,
        local_weight_decay=0.20,
    )
    goods_search_target_affordable_candidates::Int = 3
    commercial_search_target_vacant_candidates::Int = 1
    commercial_search_acceptance_multiplier::Float64 = 1.25
    commercial_global_fallback_samples::Int = 64
    goods_travel_cost_per_block::Float64 = 0.10
    goods_choice_sensitivity::Float64 = 4.0
    goods_search_period::Int = 20
    goods_price_weight::Float64 = 1.0
    goods_distance_weight::Float64 = 1.0
    shopping_review_prob::Float64 = 0.05
    shopping_price_increase_tolerance::Float64 = 0.10
    consumer_access_radius::Int = 4
    job_access_radius::Int = 8
    access_distance_decay::Float64 = 1.0
    housing_job_access_weight::Float64 = 0.20
    firm_consumer_access_weight::Float64 = 0.08
    firm_b2b_consumer_access_weight::Float64 = 0.01
    firm_b2b_downstream_access_weight::Float64 = 0.10
    firm_b2b_upstream_access_weight::Float64 = 0.04
    firm_job_access_weight::Float64 = 0.03
    firm_employee_commute_weight::Float64 = 0.25
    commercial_bid_startup_expected_sales::Float64 = 1.0
    commercial_expansion_cash_multiple::Float64 = 3.0
    human_capital_start::Float64 = 1.0
    human_capital_gain_per_tick::Float64 = 0.002
    human_capital_max::Float64 = 2.0
    network_multiplier_weight::Float64 = 0.15
    network_multiplier_cap::Float64 = 0.50
    tie_formation_rate::Float64 = 0.05
    tie_same_firm_decay::Float64 = 0.002
    tie_base_decay::Float64 = 0.01
    tie_distance_decay_weight::Float64 = 0.02
    tie_decay_max::Float64 = 0.15
    tie_min_strength::Float64 = 0.01
    network_spillover_radius::Int = 8

    firm_types::Vector{FirmTypeParams} = [
        FirmTypeParams(supply_tier=1, productivity=6.5, initial_goods_price_min=3.5, initial_goods_price_max=5.0),
        FirmTypeParams(supply_tier=1, productivity=6.5, initial_goods_price_min=3.5, initial_goods_price_max=5.0),
        FirmTypeParams(supply_tier=2, productivity=6.5, initial_goods_price_min=4.5, initial_goods_price_max=6.5),
        FirmTypeParams(supply_tier=2, productivity=6.5, initial_goods_price_min=4.5, initial_goods_price_max=6.5),
        FirmTypeParams(supply_tier=3, productivity=6.5, initial_goods_price_min=5.0, initial_goods_price_max=7.5),
        FirmTypeParams(supply_tier=3, productivity=6.5, initial_goods_price_min=5.0, initial_goods_price_max=7.5),
    ]
    price_raise_rate::Float64 = 0.04
    price_cut_rate::Float64 = 0.04
    wage_raise_rate::Float64 = 0.05
    wage_cut_rate::Float64 = 0.02
    price_review_prob::Float64 = 0.20
    wage_review_prob::Float64 = 0.20
    contraction_review_prob::Float64 = 0.08
    expansion_review_prob::Float64 = 0.12
    sold_out_expansion_premium::Float64 = 0.80
    modal_sales_lookback::Int = 12
    firm_sales_ewma_alpha::Float64 = 0.35
    capacity_buffer_share::Float64 = 0.05
    labor_adjustment_deadband::Int = 1
    marginal_hiring_markup::Float64 = 0.05
    marginal_capital_markup::Float64 = 0.05
    planning_period_ticks::Int = 20
    initial_planning_warmup_periods::Int = 2
    monthly_cash_buffer_pct::Float64 = 0.25
    monthly_buffer_volatility_sensitivity::Float64 = 0.20
    planning_downside_sales_quantile::Float64 = 0.25
    max_labor_change_per_plan::Int = 2
    max_capital_change_per_plan::Int = 1
    expansion_cooldown_plans::Int = 1
    price_cut_min_sales_units::Int = 3
    emergency_cash_floor::Float64 = 0.0
    site_consolidation_k::Int = 3
    base_wage::Float64 = 10.0
    initial_savings_mean::Float64 = 35.0
    initial_savings_sd::Float64 = 10.0
    savings_rate_min::Float64 = 0.10
    savings_rate_max::Float64 = 0.25
    commute_cost_per_block::Float64 = 0.12
    housing_budget_share::Float64 = 0.35
    job_search_prob_unemployed::Float64 = 1.0
    job_search_prob_employed::Float64 = 0.10
    housing_review_prob::Float64 = 0.20

    residential_rent_raise_rate::Float64 = 0.03
    residential_rent_cut_rate::Float64 = 0.03
    commercial_rent_raise_rate::Float64 = 0.03
    commercial_rent_cut_rate::Float64 = 0.03
    residential_vacancy_rent_cut_rate::Float64 = 0.05
    commercial_vacancy_rent_cut_rate::Float64 = 0.15
    residential_add_prob::Float64 = 0.010
    residential_build_min_city_occupancy::Float64 = 0.70
    commercial_add_prob::Float64 = 0.006
    commercial_build_min_city_occupancy::Float64 = 0.70
    commercial_density_rent_multiple::Float64 = 2.0
    commercial_greenfield_prob::Float64 = 0.02
    conversion_prob::Float64 = 0.004
    min_residential_rent::Float64 = 1.0
    min_commercial_rent::Float64 = 1.0

    io_matrix_seed::Int = 0
    io_matrix_density::Float64 = 0.5
    io_matrix_coefficient_min::Float64 = 0.20
    io_matrix_coefficient_max::Float64 = 0.40
    input_price_raise_rate::Float64 = 0.04
    input_price_cut_rate::Float64 = 0.04
    input_travel_cost_per_block::Float64 = 0.20
    input_search::SearchParams = SearchParams(poisson_intensity=5.0, radius=8, global_samples=16)
    outside_input_prices::Vector{Float64} = [4.0, 6.0]
    outside_input_distance::Float64 = 5.0
    outside_wage::Float64 = 8.0

    initial_workers::Int = 0
    solo_found_prob::Float64 = 0.020
    coalition_found_prob::Float64 = 0.006
    solo_startup_savings::Float64 = 120.0
    coalition_startup_savings::Float64 = 3000.0
    coalition_size_min::Int = 2
    coalition_size_max::Int = 10
    outside_goods_price::Float64 = 20.0
    entrepreneur_price_window::Int = 10
    entrepreneur_price_threshold::Float64 = 0.05
    commercial_lease_term::Int = 50
    capital_lease_term::Int = 100
    process_lease_term::Int = 100
    shell_dissolution_ticks::Int = 20
    initial_firm_cash::Float64 = 15_000.0
    investor_initial_firm_cash::Float64 = 50_000.0
    initial_hire_per_firm::Int = 2
    startup_production_target::Int = 2
    min_hire_cash_ticks::Int = 5

    residential_loan_term::Int = 240
    commercial_loan_term::Int = 240
    lending_rate::Float64 = 0.004
    height_cost_base::Float64 = 50.0
    height_cost_multiplier::Float64 = 1.5

    road_speed_scalar::Float64 = 3.0
    road_commute_fee_per_unit::Float64 = 0.08
    road_goods_fee_per_unit::Float64 = 0.08
    road_build_cost::Float64 = 200.0
    road_initial_cash::Float64 = 10000.0
    road_build_every::Int = 25
    road_min_euclidean::Float64 = 4.0
    road_density_radius::Int = 6
    road_candidate_pairs::Int = 30
    road_capacity_base::Float64 = 25.0      # trips/tick per unit of euclidean distance
    congestion_alpha::Float64 = 0.15
    congestion_beta::Float64 = 4.0

    grid_expansion_margin::Int = 2
    grid_expansion_cooldown::Int = 500
    grid_expansion_cbd_rent_ratio::Float64 = 2.0
    grid_expansion_min_ticks::Int = 100
    grid_expansion_min_residential_occupancy::Float64 = 0.70
    grid_expansion_min_commercial_occupancy::Float64 = 0.05

    land_developer_fire_every::Int = 10
    land_developer_rent_threshold::Float64 = 2.5
    residential_developer_rent_threshold::Float64 = 3.5
    commercial_developer_rent_threshold::Float64 = 2.0
    road_developer_fire_every::Int = 10

    worker_exit_threshold::Int = 20
    blender_update_every::Int = 5

    enable_decision_logging::Bool = true
    decision_log_limit::Int = 20_000
    enable_market_logging::Bool = true
    market_log_limit::Int = 100_000
    firm_exit_log_limit::Int = 100_000
    consumer_switch_log_limit::Int = 500_000
    monthly_plan_log_limit::Int = 500_000
    enable_search_logging::Bool = true
    search_log_limit::Int = 100_000
    enable_open_diagnostic_logging::Bool = false
    open_diagnostic_commercial_limit::Int = 100_000
    open_diagnostic_goods_limit::Int = 250_000
end
