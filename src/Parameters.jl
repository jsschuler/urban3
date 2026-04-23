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
    process_price::Float64 = 60.0
    capital_price::Float64 = 25.0
end

Base.@kwdef mutable struct ModelParams
    width::Int = 24
    height::Int = 24
    initial_workers::Int = 160
    initial_firms::Int = 16
    initial_residential_units_per_lot::Int = 1
    initial_commercial_units_per_lot::Int = 1
    initial_residential_rent_min::Float64 = 1.8
    initial_residential_rent_max::Float64 = 3.0
    initial_commercial_rent_min::Float64 = 4.5
    initial_commercial_rent_max::Float64 = 7.5
    firm_type_count::Int = 3
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
    commercial_search_target_vacant_candidates::Int = 3
    commercial_search_acceptance_multiplier::Float64 = 1.25
    commercial_search_global_rescue::Bool = true
    goods_travel_cost_per_block::Float64 = 0.35
    goods_choice_sensitivity::Float64 = 4.0
    goods_price_weight::Float64 = 1.0
    goods_distance_weight::Float64 = 1.0
    shopping_review_prob::Float64 = 0.05
    shopping_price_increase_tolerance::Float64 = 0.10
    consumer_access_radius::Int = 8
    job_access_radius::Int = 8
    access_distance_decay::Float64 = 1.0
    housing_job_access_weight::Float64 = 0.20
    firm_consumer_access_weight::Float64 = 0.08
    firm_job_access_weight::Float64 = 0.03
    firm_employee_commute_weight::Float64 = 0.25
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

    firm_types::Vector{FirmTypeParams} = [FirmTypeParams(), FirmTypeParams(productivity=3.4), FirmTypeParams(productivity=4.8)]
    price_raise_rate::Float64 = 0.04
    price_cut_rate::Float64 = 0.04
    wage_raise_rate::Float64 = 0.05
    wage_cut_rate::Float64 = 0.02
    price_review_prob::Float64 = 0.20
    wage_review_prob::Float64 = 0.20
    contraction_review_prob::Float64 = 0.08
    expansion_review_prob::Float64 = 0.12
    modal_sales_lookback::Int = 12
    site_consolidation_k::Int = 3
    max_workers_per_firm::Int = 18

    base_wage::Float64 = 10.0
    initial_savings_mean::Float64 = 35.0
    initial_savings_sd::Float64 = 10.0
    savings_rate_min::Float64 = 0.05
    savings_rate_max::Float64 = 0.25
    commute_cost_per_block::Float64 = 0.12
    housing_budget_share::Float64 = 0.35
    job_review_prob::Float64 = 0.20
    housing_review_prob::Float64 = 0.20

    residential_rent_raise_rate::Float64 = 0.03
    residential_rent_cut_rate::Float64 = 0.03
    commercial_rent_raise_rate::Float64 = 0.03
    commercial_rent_cut_rate::Float64 = 0.03
    residential_vacancy_rent_cut_rate::Float64 = 0.05
    commercial_vacancy_rent_cut_rate::Float64 = 0.15
    residential_add_prob::Float64 = 0.010
    commercial_add_prob::Float64 = 0.006
    conversion_prob::Float64 = 0.004
    min_residential_rent::Float64 = 1.0
    min_commercial_rent::Float64 = 1.0

    solo_found_prob::Float64 = 0.010
    coalition_found_prob::Float64 = 0.006
    solo_startup_savings::Float64 = 120.0
    coalition_startup_savings::Float64 = 180.0
    coalition_size_min::Int = 2
    coalition_size_max::Int = 5

    outside_entry_rate::Float64 = 3.0
    blender_update_every::Int = 5

    enable_decision_logging::Bool = true
    decision_log_limit::Int = 20_000
    enable_market_logging::Bool = true
    market_log_limit::Int = 100_000
    enable_search_logging::Bool = true
    search_log_limit::Int = 100_000
    enable_open_diagnostic_logging::Bool = false
    open_diagnostic_commercial_limit::Int = 100_000
    open_diagnostic_goods_limit::Int = 250_000
end
