Base.@kwdef struct SearchParams
    poisson_intensity::Float64 = 4.0
    radius::Int = 4
    global_samples::Int = 8
    local_weight::Float64 = 0.75
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

    goods_search::SearchParams = SearchParams()
    job_search::SearchParams = SearchParams(poisson_intensity=5.0, radius=5, global_samples=10)
    housing_search::SearchParams = SearchParams(poisson_intensity=5.0, radius=5, global_samples=10)
    commercial_search::SearchParams = SearchParams(poisson_intensity=4.0, radius=5, global_samples=8)

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
end
