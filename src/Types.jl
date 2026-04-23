abstract type EmploymentState end
struct Employed <: EmploymentState end
struct Unemployed <: EmploymentState end

abstract type HousingState end
struct Housed <: HousingState end
struct Unhoused <: HousingState end

mutable struct Lot
    id::Int
    x::Int
    y::Int
    residential_units::Int
    commercial_units::Int
    occupied_residential::Int
    occupied_commercial::Int
    residential_rent::Float64
    commercial_rent::Float64
end

mutable struct Worker
    id::Int
    employer_id::Union{Nothing,Int}
    dwelling_lot_id::Union{Nothing,Int}
    current_wage::Float64
    savings::Float64
    savings_rate::Float64
    utility::Vector{Float64}
    ownership_shares::Dict{Int,Float64}
    moved_job_this_tick::Bool
    moved_home_this_tick::Bool
end

mutable struct Firm
    id::Int
    firm_type::Int
    owner_manager_ids::Vector{Int}
    ownership_shares::Dict{Int,Float64}
    posted_wage::Float64
    worker_ids::Vector{Int}
    current_worker_wages::Dict{Int,Float64}
    capital_units::Int
    process_count::Int
    commercial_units_by_lot::Dict{Int,Int}
    goods_price::Float64
    committed_output::Int
    realized_sales_this_tick::Int
    realized_sales_history::Vector{Int}
    profit_history::Vector{Float64}
    active::Bool
end

mutable struct TickEvents
    firm_entries::Int
    firm_exits::Int
    hires::Int
    layoffs::Int
    residential_units_added::Int
    commercial_units_added::Int
    conversions::Int
    outside_entries::Int
end

mutable struct DecisionRecord
    tick::Int
    actor_kind::Symbol
    actor_id::Int
    decision::Symbol
    considered_count::Int
    viable_count::Int
    chosen_kind::Symbol
    chosen_id::Union{Nothing,Int}
    reason::Symbol
    min_candidate_value::Float64
    max_candidate_value::Float64
end

mutable struct DecisionLog
    records::Vector{DecisionRecord}
    max_records::Int
    commercial_vacant_considered_counts::Dict{Int,Int}
    commercial_vacant_chosen_counts::Dict{Int,Int}
end

mutable struct MarketSnapshot
    tick::Int
    population::Int
    employed::Int
    unemployed::Int
    housed::Int
    unhoused::Int
    residential_units::Int
    vacant_residential_units::Int
    commercial_units::Int
    vacant_commercial_units::Int
    active_firms::Int
    firm_job_vacancies::Int
    firms_with_job_vacancies::Int
    committed_output::Int
    realized_sales::Int
    unsold_output::Int
    sold_out_firms::Int
    mean_wage::Float64
    mean_residential_rent::Float64
    mean_commercial_rent::Float64
    mean_goods_price::Float64
end

mutable struct MarketLog
    records::Vector{MarketSnapshot}
    max_records::Int
end

mutable struct SearchCoverageRecord
    tick::Int
    domain::Symbol
    actor_kind::Symbol
    actor_id::Int
    origin_lot_id::Union{Nothing,Int}
    raw_draw_count::Int
    unique_lot_count::Int
    local_draw_count::Int
    global_draw_count::Int
end

mutable struct SearchCoverageLog
    records::Vector{SearchCoverageRecord}
    max_records::Int
    lot_counts_by_domain::Dict{Symbol,Dict{Int,Int}}
    event_counts_by_domain::Dict{Symbol,Int}
    raw_draw_counts_by_domain::Dict{Symbol,Int}
    unique_draw_counts_by_domain::Dict{Symbol,Int}
end

mutable struct ModelState
    tick::Int
    params::ModelParams
    rng::AbstractRNG
    lots::Vector{Lot}
    workers::Vector{Worker}
    firms::Vector{Firm}
    events::TickEvents
    decision_log::DecisionLog
    market_log::MarketLog
    search_log::SearchCoverageLog
end

employment_state(w::Worker) = isnothing(w.employer_id) ? Unemployed() : Employed()
housing_state(w::Worker) = isnothing(w.dwelling_lot_id) ? Unhoused() : Housed()
vacant_residential(l::Lot) = max(0, l.residential_units - l.occupied_residential)
vacant_commercial(l::Lot) = max(0, l.commercial_units - l.occupied_commercial)
lot_height(l::Lot) = l.residential_units + l.commercial_units
taxicab(a::Lot, b::Lot) = abs(a.x - b.x) + abs(a.y - b.y)

function reset_events!()
    TickEvents(0, 0, 0, 0, 0, 0, 0, 0)
end

function init_decision_log(limit::Int)
    DecisionLog(DecisionRecord[], limit, Dict{Int,Int}(), Dict{Int,Int}())
end

function init_market_log(limit::Int)
    MarketLog(MarketSnapshot[], limit)
end

function init_search_coverage_log(limit::Int)
    SearchCoverageLog(
        SearchCoverageRecord[],
        limit,
        Dict{Symbol,Dict{Int,Int}}(),
        Dict{Symbol,Int}(),
        Dict{Symbol,Int}(),
        Dict{Symbol,Int}(),
    )
end
