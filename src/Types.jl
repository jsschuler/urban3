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
    preferred_firm_by_type::Dict{Int,Int}
    last_delivered_cost_by_type::Dict{Int,Float64}
    experience_ticks::Int
    human_capital::Float64
    social_ties::Dict{Int,Float64}
    moved_job_this_tick::Bool
    moved_home_this_tick::Bool
    inactive_ticks::Int
    goods_search_offset::Int
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
    capital_lease_ticks::Vector{Int}          # acquisition tick per capital unit
    process_count::Int
    process_lease_ticks::Vector{Int}          # acquisition tick per process
    commercial_units_by_lot::Dict{Int,Vector{Int}}     # lot_id => acquisition ticks per unit
    commercial_rent_paid_by_lot::Dict{Int,Vector{Float64}}  # lot_id => per-unit rent paid
    shell_ticks::Int                          # ticks spent as shell (spaceless, all leases expired)
    goods_price::Float64
    committed_output::Int
    realized_sales_this_tick::Int
    realized_sales_history::Vector{Int}
    profit_history::Vector{Float64}
    active::Bool
    startup_pending::Bool
    founded_tick::Int
    inputs_acquired::Dict{Int,Int}
    input_cost_this_tick::Float64
    cash::Float64
    planned_worker_target::Int
    last_plan_tick::Int
    planning_offset::Int
    last_plan_passed::Bool
    last_plan_projected_end_cash::Float64
    last_plan_total_cost::Float64
    last_plan_buffer::Float64
end

mutable struct DeveloperState
    cash::Float64
    residential_debt::Float64
    commercial_debt::Float64
    construction_cost_by_lot::Dict{Int,Float64}           # cumulative residential cost per lot
    commercial_construction_cost_by_lot::Dict{Int,Float64} # cumulative commercial cost per lot
    interest_paid_this_tick::Float64
    rent_collected_this_tick::Float64
end

mutable struct RoadSegment
    id::Int
    from_lot_id::Int
    to_lot_id::Int
    euclidean_dist::Float64
    road_length::Float64        # free-flow: euclidean_dist / road_speed_scalar
    congested_length::Float64   # current effective length updated by BPR each tick
    capacity::Float64           # road_capacity_base × euclidean_dist
    usage_this_tick::Int        # trips accumulated this tick
end

mutable struct RoadNetwork
    segments::Vector{RoadSegment}
    road_node_lot_ids::Vector{Int}                   # sorted lot ids that are road endpoints
    road_node_index::Dict{Int,Int}                   # lot_id => index in road_node_lot_ids
    shortest_road_dist::Matrix{Float64}              # K×K all-pairs shortest congested distances
    next_hop::Matrix{Int}                            # K×K: next node index on shortest path i→j (0=no path)
    segment_lookup::Dict{Tuple{Int,Int},Int}         # (from_lot_id, to_lot_id) => segment index (bidirectional)
    adj::Dict{Int,Vector{Tuple{Int,Float64}}}        # lot_id => [(neighbor_lot_id, road_length)]
    cash::Float64
    revenue_this_tick::Float64
end

struct RofrEntry
    firm_id::Int
    lot_id::Int
    n_units::Int
end

mutable struct TickEvents
    firm_entries::Int
    firm_exits::Int
    hires::Int
    layoffs::Int
    residential_units_added::Int
    commercial_units_added::Int
    conversions::Int
    immigrants::Int
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

mutable struct FirmExitRecord
    tick::Int
    firm_id::Int
    firm_type::Int
    reason::Symbol
    cash_before_exit::Float64
    revenue_this_tick::Float64
    wages_this_tick::Float64
    commercial_rent_this_tick::Float64
    capital_rental_this_tick::Float64
    process_rental_this_tick::Float64
    input_cost_this_tick::Float64
    profit_this_tick::Float64
    worker_count::Int
    capital_units::Int
    process_count::Int
    commercial_units::Int
    last_plan_tick::Int
    last_plan_passed::Bool
    last_plan_projected_end_cash::Float64
    last_plan_total_cost::Float64
    last_plan_buffer::Float64
end

mutable struct FirmExitLog
    records::Vector{FirmExitRecord}
    max_records::Int
end

mutable struct ConsumerSwitchRecord
    tick::Int
    worker_id::Int
    firm_type::Int
    previous_firm_id::Union{Nothing,Int}
    chosen_firm_id::Union{Nothing,Int}
    switched::Bool
    trigger::Symbol
    fallback_reason::Symbol
    previous_delivered_cost::Float64
    chosen_delivered_cost::Float64
    budget::Float64
end

mutable struct ConsumerSwitchLog
    records::Vector{ConsumerSwitchRecord}
    max_records::Int
end

mutable struct MonthlyPlanRecord
    tick::Int
    firm_id::Int
    firm_type::Int
    workers_before::Int
    workers_after::Int
    capital_before::Int
    capital_after::Int
    projected_end_cash_before::Float64
    projected_end_cash_after::Float64
    total_cost_before::Float64
    total_cost_after::Float64
    buffer_before::Float64
    buffer_after::Float64
    plan_passed_before::Bool
    plan_passed_after::Bool
end

mutable struct MonthlyPlanLog
    records::Vector{MonthlyPlanRecord}
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

mutable struct CommercialSearchDiagnosticRecord
    tick::Int
    firm_id::Int
    origin_lot_id::Union{Nothing,Int}
    sampled_count::Int
    sampled_vacant_count::Int
    chosen_lot_id::Union{Nothing,Int}
    chosen_rent::Float64
    best_sampled_vacant_lot_id::Union{Nothing,Int}
    best_sampled_vacant_rent::Float64
    best_global_vacant_lot_id::Union{Nothing,Int}
    best_global_vacant_rent::Float64
    cheaper_unsampled_vacant_count::Int
end

mutable struct GoodsSearchDiagnosticRecord
    tick::Int
    worker_id::Int
    origin_lot_id::Union{Nothing,Int}
    budget::Float64
    sampled_count::Int
    chosen_firm_id::Union{Nothing,Int}
    chosen_firm_type::Union{Nothing,Int}
    chosen_price::Float64
    chosen_score::Float64
    best_sampled_firm_id::Union{Nothing,Int}
    best_sampled_score::Float64
    best_global_firm_id::Union{Nothing,Int}
    best_global_score::Float64
    best_global_price::Float64
    better_unsampled_count::Int
    affordable_global_count::Int
end

mutable struct OpenDiagnosticLog
    commercial_search_records::Vector{CommercialSearchDiagnosticRecord}
    goods_search_records::Vector{GoodsSearchDiagnosticRecord}
    max_commercial_records::Int
    max_goods_records::Int
end

mutable struct CommercialBidProposal
    firm_id::Int
    lot_id::Int
    bid::Float64
end

mutable struct EntrepreneurAgent
    price_history::Dict{Int, Vector{Float64}}  # firm_type → recent mean posted prices
    active_sector::Int                          # 0 = watching; >0 = assembling coalition
end

mutable struct ModelState
    tick::Int
    params::ModelParams
    rng::AbstractRNG
    lots::Vector{Lot}
    workers::Vector{Worker}
    firms::Vector{Firm}
    active_firm_ids::Set{Int}
    active_worker_ids::Set{Int}
    events::TickEvents
    decision_log::DecisionLog
    market_log::MarketLog
    firm_exit_log::FirmExitLog
    consumer_switch_log::ConsumerSwitchLog
    monthly_plan_log::MonthlyPlanLog
    search_log::SearchCoverageLog
    open_diagnostic_log::OpenDiagnosticLog
    consumer_access_by_lot::Vector{Float64}
    job_access_by_lot::Vector{Float64}
    commercial_bid_buffer::Vector{CommercialBidProposal}
    rofr_buffer::Vector{RofrEntry}
    io_matrix::Matrix{Float64}
    investor_firm_by_type::Dict{Int,Int}
    road_network::RoadNetwork
    lot_by_position::Dict{Tuple{Int,Int}, Int}
    last_expansion_tick::Int
    developer::DeveloperState
    entrepreneur::EntrepreneurAgent
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

function init_firm_exit_log(limit::Int)
    FirmExitLog(FirmExitRecord[], limit)
end

function init_consumer_switch_log(limit::Int)
    ConsumerSwitchLog(ConsumerSwitchRecord[], limit)
end

function init_monthly_plan_log(limit::Int)
    MonthlyPlanLog(MonthlyPlanRecord[], limit)
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

function init_open_diagnostic_log(commercial_limit::Int, goods_limit::Int)
    OpenDiagnosticLog(
        CommercialSearchDiagnosticRecord[],
        GoodsSearchDiagnosticRecord[],
        commercial_limit,
        goods_limit,
    )
end
