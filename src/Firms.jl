firm_supply_tier(state::ModelState, f::Firm) = state.params.firm_types[f.firm_type].supply_tier
max_supply_tier(state::ModelState) = maximum(ft.supply_tier for ft in state.params.firm_types)
is_b2b(state::ModelState, f::Firm) = firm_supply_tier(state, f) < max_supply_tier(state)
is_b2c(state::ModelState, f::Firm) = firm_supply_tier(state, f) == max_supply_tier(state)

function required_input_types(state::ModelState, f::Firm)
    row = @view state.io_matrix[f.firm_type, :]
    [(i, row[i]) for i in eachindex(row) if row[i] > 0.0]
end

function buyer_anchor_lot_id(state::ModelState, f::Firm)
    isempty(f.commercial_units_by_lot) && return nothing
    return first(keys(f.commercial_units_by_lot))
end

function min_supplier_distance(state::ModelState, buyer::Firm, supplier::Firm)
    buyer_lot_id = buyer_anchor_lot_id(state, buyer)
    isnothing(buyer_lot_id) && return 0
    buyer_lot = state.lots[buyer_lot_id]
    min_d = typemax(Int)
    for lid in keys(supplier.commercial_units_by_lot)
        min_d = min(min_d, taxicab(buyer_lot, state.lots[lid]))
    end
    return min_d == typemax(Int) ? 0 : min_d
end

function effective_input_cost(state::ModelState, buyer::Firm, supplier::Firm)
    dist = min_supplier_distance(state, buyer, supplier)
    return supplier.goods_price + state.params.input_travel_cost_per_block * dist
end

function sample_input_suppliers(state::ModelState, buyer::Firm, b2b_type::Int)
    p = state.params.input_search
    buyer_lot_id = buyer_anchor_lot_id(state, buyer)
    out = Firm[]
    for f in active_firms(state)
        f.firm_type == b2b_type || continue
        is_b2b(state, f) || continue
        f.committed_output > f.realized_sales_this_tick || continue
        push!(out, f)
    end
    isempty(out) && return out
    local_set = Firm[]
    if !isnothing(buyer_lot_id)
        buyer_lot = state.lots[buyer_lot_id]
        for f in out
            if any(taxicab(buyer_lot, state.lots[lid]) <= p.radius for lid in keys(f.commercial_units_by_lot))
                push!(local_set, f)
            end
        end
    end
    n_global = min(length(out), p.global_samples)
    global_set = out[randperm(state.rng, length(out))[1:n_global]]
    return unique(vcat(local_set, global_set))
end

function leontief_input_scale(state::ModelState, f::Firm)
    inputs = required_input_types(state, f)
    isempty(inputs) && return 1.0
    cap = production_capacity(state, f, state.params)
    cap == 0 && return 0.0
    min_fill = 1.0
    for (b2b_type, coeff) in inputs
        needed = coeff * cap
        needed <= 0 && continue
        acquired = get(f.inputs_acquired, b2b_type, 0)
        min_fill = min(min_fill, acquired / needed)
    end
    return min_fill
end

function commit_intermediate_output!(state::ModelState)
    for f in active_firms(state)
        f.founded_tick == state.tick && continue
        is_b2c(state, f) && continue
        isempty(required_input_types(state, f)) || continue   # skip tiers with input requirements
        f.committed_output = production_capacity(state, f, state.params)
        f.realized_sales_this_tick = 0
    end
end

function commit_b2b_with_inputs!(state::ModelState)
    for f in active_firms(state)
        f.founded_tick == state.tick && continue
        is_b2c(state, f) && continue
        isempty(required_input_types(state, f)) && continue   # skip tier 1 (no inputs)
        cap = production_capacity(state, f, state.params)
        scale = leontief_input_scale(state, f)
        f.committed_output = floor(Int, scale * cap)
        f.realized_sales_this_tick = 0
    end
end

function input_purchasing_phase!(state::ModelState, buyer_tier::Int)
    for f in active_firms(state)
        firm_supply_tier(state, f) != buyer_tier && continue
        empty!(f.inputs_acquired)
        f.input_cost_this_tick = 0.0
        cap = production_capacity(state, f, state.params)
        cap == 0 && continue
        for (b2b_type, coeff) in required_input_types(state, f)
            units_needed = ceil(Int, coeff * cap)
            units_needed == 0 && continue
            supplier_tier = state.params.firm_types[b2b_type].supply_tier
            outside_base = supplier_tier <= length(state.params.outside_input_prices) ?
                state.params.outside_input_prices[supplier_tier] : Inf
            outside_eff = outside_base + state.params.input_travel_cost_per_block *
                state.params.outside_input_distance
            units_bought = 0
            candidates = sample_input_suppliers(state, f, b2b_type)
            if !isempty(candidates)
                sort!(candidates; by = sup -> effective_input_cost(state, f, sup))
                for supplier in candidates
                    units_bought >= units_needed && break
                    effective_input_cost(state, f, supplier) > outside_eff && break
                    available = supplier.committed_output - supplier.realized_sales_this_tick
                    available == 0 && continue
                    to_buy = min(units_needed - units_bought, available)
                    supplier.realized_sales_this_tick += to_buy
                    f.inputs_acquired[b2b_type] = get(f.inputs_acquired, b2b_type, 0) + to_buy
                    dist = min_supplier_distance(state, f, supplier)
                    f.input_cost_this_tick += to_buy * supplier.goods_price +
                        state.params.input_travel_cost_per_block * dist * to_buy
                    units_bought += to_buy
                end
            end
            remaining = units_needed - units_bought
            if remaining > 0 && isfinite(outside_eff)
                f.inputs_acquired[b2b_type] = get(f.inputs_acquired, b2b_type, 0) + remaining
                f.input_cost_this_tick += remaining * outside_eff
            end
        end
    end
end

function production_capacity(state::ModelState, f::Firm, params::ModelParams)
    !f.active && return 0
    ft = params.firm_types[f.firm_type]
    labor = sum(effective_labor(state, wid) for wid in f.worker_ids; init=0.0)
    capital = f.capital_units
    space = sum(values(f.commercial_units_by_lot))
    processes = max(1, f.process_count)
    labor == 0 || capital == 0 || space == 0 ? (return 0) : nothing
    total = 0.0
    for _ in 1:processes
        l = labor / processes
        k = capital / processes
        s = effective_sites(f, params) / processes
        total += ft.productivity * (l ^ ft.labor_elasticity) * (k ^ ft.capital_elasticity) * (s ^ ft.space_elasticity)
    end
    return max(0, floor(Int, total))
end

function effective_sites(f::Firm, params::ModelParams)
    total = 0.0
    for units in values(f.commercial_units_by_lot)
        total += units + floor(units / params.site_consolidation_k)
    end
    return max(total, 1.0)
end

function hire_worker!(state::ModelState, w::Worker, f::Firm)
    !f.active && return false
    !isnothing(w.employer_id) && return false
    length(f.worker_ids) >= state.params.max_workers_per_firm && return false
    current_payroll = sum(values(f.current_worker_wages); init=0.0)
    f.cash < (current_payroll + f.posted_wage) * state.params.min_hire_cash_ticks && return false
    push!(f.worker_ids, w.id)
    f.current_worker_wages[w.id] = f.posted_wage
    w.employer_id = f.id
    w.current_wage = f.posted_wage
    w.moved_job_this_tick = true
    state.events.hires += 1
    return true
end

function fire_worker!(state::ModelState, f::Firm, worker_id::Int)
    filter!(id -> id != worker_id, f.worker_ids)
    delete!(f.current_worker_wages, worker_id)
    w = state.workers[worker_id]
    w.employer_id = nothing
    w.current_wage = 0.0
    state.events.layoffs += 1
end

function labor_target_for_wage_review(state::ModelState, f::Firm)
    target_sales = if length(f.realized_sales_history) >= state.params.modal_sales_lookback
        recent = last(f.realized_sales_history, state.params.modal_sales_lookback)
        modal_int(collect(recent))
    else
        max(state.params.startup_production_target, f.committed_output)
    end

    current_workers = length(f.worker_ids)
    current_capacity = production_capacity(state, f, state.params)
    if current_workers <= 0 || current_capacity <= 0
        return clamp(1, 1, state.params.max_workers_per_firm)
    end

    output_per_worker = current_capacity / current_workers
    output_per_worker <= 0 && return clamp(1, 1, state.params.max_workers_per_firm)
    target_workers = ceil(Int, target_sales / output_per_worker)
    return clamp(max(1, target_workers), 1, state.params.max_workers_per_firm)
end

function firm_reviews!(state::ModelState)
    for f in active_firms(state)
        if rand(state.rng) < state.params.price_review_prob
            last_sales = isempty(f.realized_sales_history) ? 0 : f.realized_sales_history[end]
            sold_out = last_sales >= f.committed_output && f.committed_output > 0
            raise = is_b2b(state, f) ? state.params.input_price_raise_rate : state.params.price_raise_rate
            cut   = is_b2b(state, f) ? state.params.input_price_cut_rate   : state.params.price_cut_rate
            do_cut = if is_b2b(state, f)
                last_sales == 0 && f.committed_output > 0
            else
                last_sales > 0
            end
            if sold_out
                f.goods_price *= (1 + raise)
            elseif do_cut
                f.goods_price *= (1 - cut)
            end
            f.goods_price = max(0.25, f.goods_price)
        end
        if rand(state.rng) < state.params.wage_review_prob
            labor_target = labor_target_for_wage_review(state, f)
            has_demand_vacancy = length(f.worker_ids) < labor_target
            if has_demand_vacancy
                proposed_wage = f.posted_wage * (1 + state.params.wage_raise_rate)
                current_payroll = sum(values(f.current_worker_wages); init=0.0)
                can_afford = f.cash >= (current_payroll + proposed_wage) * state.params.min_hire_cash_ticks
                if can_afford
                    f.posted_wage = proposed_wage
                else
                    f.posted_wage *= (1 - state.params.wage_cut_rate)
                end
            else
                f.posted_wage *= (1 - state.params.wage_cut_rate)
            end
            f.posted_wage = max(1.0, f.posted_wage)
        end
    end
end

function commit_production!(state::ModelState)
    for f in active_firms(state)
        f.founded_tick == state.tick && continue
        is_b2b(state, f) && continue  # already committed in commit_intermediate_output!
        cap = production_capacity(state, f, state.params)
        scale = leontief_input_scale(state, f)
        f.committed_output = floor(Int, scale * cap)
        f.realized_sales_this_tick = 0
    end
end

function calculate_profits!(state::ModelState)
    for f in active_firms(state)
        revenue = f.realized_sales_this_tick * f.goods_price
        wages = sum(values(f.current_worker_wages); init=0.0)
        rent = sum(state.lots[lid].commercial_rent * n for (lid, n) in f.commercial_units_by_lot; init=0.0)
        input_costs = f.input_cost_this_tick
        profit = revenue - wages - rent - input_costs
        f.cash += profit
        push!(f.realized_sales_history, f.realized_sales_this_tick)
        push!(f.profit_history, profit)
        if profit > 0
            for (wid, share) in f.ownership_shares
                state.workers[wid].savings += profit * share
            end
        end
    end
end

function firm_contraction_expansion!(state::ModelState)
    for f in copy(active_firms(state))
        # Startup grace: do not liquidate or force contractions on birth tick.
        f.founded_tick == state.tick && continue
        if f.cash < 0
            liquidate_firm!(state, f)
            continue
        end
        if rand(state.rng) < state.params.contraction_review_prob &&
                length(f.realized_sales_history) >= state.params.modal_sales_lookback
            recent = last(f.realized_sales_history, state.params.modal_sales_lookback)
            target = modal_int(collect(recent))
            while production_capacity(state, f, state.params) > target && length(f.worker_ids) > 1
                highest = f.worker_ids[argmax([f.current_worker_wages[id] for id in f.worker_ids])]
                fire_worker!(state, f, highest)
            end
            while production_capacity(state, f, state.params) > target && f.capital_units > 1
                f.capital_units -= 1
            end
        end
        if rand(state.rng) < state.params.expansion_review_prob
            profitable = !isempty(f.profit_history) && f.profit_history[end] > 0
            sold_out = f.realized_sales_this_tick >= f.committed_output && f.committed_output > 0
            if profitable && sold_out
                cap_cost = state.params.firm_types[f.firm_type].capital_price
                if f.cash >= cap_cost
                    f.cash -= cap_cost
                    f.capital_units += 1
                    if rand(state.rng) < 0.25
                        proc_cost = state.params.firm_types[f.firm_type].process_price
                        if f.cash >= proc_cost
                            f.cash -= proc_cost
                            f.process_count += 1
                        end
                    end
                    commercial_space_search!(state, f)
                end
            end
        end
        if f.capital_units == 0
            liquidate_firm!(state, f)
        end
    end
end

function liquidate_firm!(state::ModelState, f::Firm)
    !f.active && return
    for wid in copy(f.worker_ids)
        fire_worker!(state, f, wid)
    end
    for (lid, n) in f.commercial_units_by_lot
        state.lots[lid].occupied_commercial = max(0, state.lots[lid].occupied_commercial - n)
    end
    empty!(f.commercial_units_by_lot)
    f.active = false
    delete!(state.active_firm_ids, f.id)
    state.events.firm_exits += 1
end

function commercial_location_score_fast(state::ModelState, f::Firm, lot_id::Int)
    tier = firm_supply_tier(state, f)
    max_tier = max_supply_tier(state)
    access = state.consumer_access_by_lot[lot_id]
    w = tier == max_tier ? state.params.firm_consumer_access_weight : state.params.firm_b2b_consumer_access_weight
    return w * access +
        state.params.firm_job_access_weight * state.job_access_by_lot[lot_id] +
        get(f.commercial_units_by_lot, lot_id, 0) -
        state.lots[lot_id].commercial_rent
end

function best_vacant_candidate_fast(state::ModelState, f::Firm, candidates::Vector{Int})
    best_lot_id = nothing
    best_score = -Inf
    for lid in candidates
        vacant_commercial(state.lots[lid]) <= 0 && continue
        score = commercial_location_score_fast(state, f, lid)
        if score > best_score
            best_score = score
            best_lot_id = lid
        end
    end
    return best_lot_id
end

function commercial_space_search!(state::ModelState, f::Firm)
    anchor = isempty(f.commercial_units_by_lot) ? nothing : first(keys(f.commercial_units_by_lot))
    candidates = adaptive_candidate_lots(
        state,
        anchor,
        state.params.commercial_search;
        domain=:commercial_space,
        actor_kind=:firm,
        actor_id=f.id,
        accept=(lots, stage) -> any(vacant_commercial(state.lots[lid]) > 0 for lid in lots),
    )
    chosen_lot_id = best_vacant_candidate_fast(state, f, candidates)

    if isnothing(chosen_lot_id)
        n = min(state.params.commercial_global_fallback_samples, length(state.lots))
        fallback = randperm(state.rng, length(state.lots))[1:n]
        chosen_lot_id = best_vacant_candidate_fast(state, f, fallback)
    end

    if !isnothing(chosen_lot_id)
        bid = commercial_bid_amount(state, f, chosen_lot_id)
        push!(state.commercial_bid_buffer, CommercialBidProposal(f.id, chosen_lot_id, bid))
        log_commercial_space_search!(state, f, candidates, chosen_lot_id)
        log_commercial_search_diagnostic!(state, f, anchor, candidates, chosen_lot_id)
        return true
    end

    log_commercial_space_search!(state, f, candidates, nothing)
    log_commercial_search_diagnostic!(state, f, anchor, candidates, nothing)
    return false
end

function firm_anchor_consumer_access(state::ModelState, f::Firm)
    isempty(f.commercial_units_by_lot) && return mean(state.consumer_access_by_lot)
    total_units = 0
    weighted_access = 0.0
    for (lot_id, units) in f.commercial_units_by_lot
        weighted_access += state.consumer_access_by_lot[lot_id] * units
        total_units += units
    end
    total_units == 0 && return mean(state.consumer_access_by_lot)
    return weighted_access / total_units
end

function recent_mean_sales(f::Firm, lookback::Int)
    isempty(f.realized_sales_history) && return 0.0
    window = last(f.realized_sales_history, min(length(f.realized_sales_history), lookback))
    return mean(window)
end

function commercial_bid_amount(state::ModelState, f::Firm, lot_id::Int)
    access = state.consumer_access_by_lot[lot_id]
    mean_access = mean(state.consumer_access_by_lot)
    base_sales = isempty(f.realized_sales_history) ?
        state.params.commercial_bid_startup_expected_sales :
        max(1.0, recent_mean_sales(f, state.params.commercial_bid_recent_sales_lookback))
    access_scale = (access + 1.0) / (mean_access + 1.0)
    raw_bid = state.params.commercial_bid_share * base_sales * access_scale * f.goods_price
    return clamp(raw_bid, state.params.min_commercial_rent, state.params.commercial_bid_cap)
end

function finalize_pending_startup_firms!(state::ModelState)
    for f in state.firms
        !f.active && continue
        !f.startup_pending && continue
        if isempty(f.commercial_units_by_lot)
            n = min(state.params.commercial_global_fallback_samples, length(state.lots))
            fallback = randperm(state.rng, length(state.lots))[1:n]
            rescue_lot_id = best_vacant_candidate_fast(state, f, fallback)
            if isnothing(rescue_lot_id)
                f.active = false
                f.startup_pending = false
                delete!(state.active_firm_ids, f.id)
                continue
            end
            bid = commercial_bid_amount(state, f, rescue_lot_id)
            lot = state.lots[rescue_lot_id]
            lot.occupied_commercial += 1
            lot.commercial_rent = max(
                state.params.min_commercial_rent,
                (1 - state.params.commercial_rent_bid_adjustment_rate) * lot.commercial_rent +
                    state.params.commercial_rent_bid_adjustment_rate * bid,
            )
            f.commercial_units_by_lot[rescue_lot_id] = get(f.commercial_units_by_lot, rescue_lot_id, 0) + 1
        end
        f.startup_pending = false
        state.events.firm_entries += 1
    end
end

function resolve_commercial_bids!(state::ModelState)
    bids = state.commercial_bid_buffer
    if isempty(bids)
        finalize_pending_startup_firms!(state)
        return
    end

    bids_by_lot = Dict{Int,Vector{CommercialBidProposal}}()
    for proposal in bids
        push!(get!(bids_by_lot, proposal.lot_id, CommercialBidProposal[]), proposal)
    end

    for (lot_id, lot_bids) in bids_by_lot
        vacant_units = vacant_commercial(state.lots[lot_id])
        vacant_units <= 0 && continue
        sort!(lot_bids; by=proposal -> (-proposal.bid, proposal.firm_id))
        award_count = min(vacant_units, length(lot_bids))
        award_count == 0 && continue

        winners = lot_bids[1:award_count]
        lot = state.lots[lot_id]
        lot.occupied_commercial += award_count

        winning_bids = Float64[]
        for proposal in winners
            push!(winning_bids, proposal.bid)
            firm = state.firms[proposal.firm_id]
            firm.active || continue
            firm.commercial_units_by_lot[lot_id] = get(firm.commercial_units_by_lot, lot_id, 0) + 1
            if firm.startup_pending
                firm.startup_pending = false
                state.events.firm_entries += 1
            end
        end

        mean_bid = mean(winning_bids)
        α = state.params.commercial_rent_bid_adjustment_rate
        lot.commercial_rent = max(
            state.params.min_commercial_rent,
            (1 - α) * lot.commercial_rent + α * mean_bid,
        )
    end

    empty!(state.commercial_bid_buffer)
    finalize_pending_startup_firms!(state)
end
