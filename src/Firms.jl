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
        isempty(required_input_types(state, f)) || continue
        f.committed_output = production_capacity(state, f, state.params)
        f.realized_sales_this_tick = 0
    end
end

function commit_b2b_with_inputs!(state::ModelState)
    for f in active_firms(state)
        f.founded_tick == state.tick && continue
        is_b2c(state, f) && continue
        isempty(required_input_types(state, f)) && continue
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
    space = sum(length(v) for v in values(f.commercial_units_by_lot); init=0)
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
    for ticks_list in values(f.commercial_units_by_lot)
        units = length(ticks_list)
        total += units + floor(units / params.site_consolidation_k)
    end
    return max(total, 1.0)
end

function hire_worker!(state::ModelState, w::Worker, f::Firm)
    !f.active && return false
    !isnothing(w.employer_id) && return false
    # Established firms don't hire beyond their demand-implied optimal headcount,
    # which grows naturally as they expand capital and commercial space.
    # Gate only activates once the firm has at least initial_hire_per_firm workers,
    # so vacancy-driven immigration can seed each firm on startup.
    if !f.startup_pending && length(f.worker_ids) >= state.params.initial_hire_per_firm
        length(f.worker_ids) >= labor_target_for_wage_review(state, f) && return false
    end
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
    # When the firm was sold out last tick and profitable, apply an expansion premium
    # so labor_target exceeds current workers and vacancies open for growth.
    # realized_sales_this_tick and committed_output still hold last tick's values here
    # because the commit phase hasn't run yet.
    sold_out = f.realized_sales_this_tick >= f.committed_output && f.committed_output > 0
    profitable = !isempty(f.profit_history) && f.profit_history[end] > 0
    if sold_out && profitable && state.params.sold_out_expansion_premium > 0
        target_sales = round(Int, target_sales * (1 + state.params.sold_out_expansion_premium))
    end
    current_workers = length(f.worker_ids)
    current_capacity = production_capacity(state, f, state.params)
    if current_workers <= 0 || current_capacity <= 0
        return 1
    end
    output_per_worker = current_capacity / current_workers
    output_per_worker <= 0 && return 1
    target_workers = ceil(Int, target_sales / output_per_worker)
    return max(1, target_workers)
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
            f.posted_wage = max(state.params.outside_wage, f.posted_wage)
        end
    end
end

function commit_production!(state::ModelState)
    for f in active_firms(state)
        f.founded_tick == state.tick && continue
        is_b2b(state, f) && continue
        cap = production_capacity(state, f, state.params)
        scale = leontief_input_scale(state, f)
        f.committed_output = floor(Int, scale * cap)
        f.realized_sales_this_tick = 0
    end
end

function calculate_profits!(state::ModelState)
    for f in active_firms(state)
        ft = state.params.firm_types[f.firm_type]
        revenue = f.realized_sales_this_tick * f.goods_price
        wages = sum(values(f.current_worker_wages); init=0.0)
        commercial_rent = sum(sum(rents) for rents in values(f.commercial_rent_paid_by_lot); init=0.0)
        capital_rental = f.capital_units * ft.capital_rental_rate
        process_rental = f.process_count * ft.process_rental_rate
        input_costs = f.input_cost_this_tick
        profit = revenue - wages - commercial_rent - capital_rental - process_rental - input_costs
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
        f.founded_tick == state.tick && continue
        if f.cash < 0
            liquidate_firm!(state, f)
            continue
        end

        # Spaceless: release workers, let leases expire, count down to dissolution
        if isempty(f.commercial_units_by_lot)
            for wid in copy(f.worker_ids)
                fire_worker!(state, f, wid)
            end
            filter!(t -> state.tick - t < state.params.capital_lease_term, f.capital_lease_ticks)
            f.capital_units = length(f.capital_lease_ticks)
            filter!(t -> state.tick - t < state.params.process_lease_term, f.process_lease_ticks)
            f.process_count = length(f.process_lease_ticks)
            if isempty(f.capital_lease_ticks) && isempty(f.process_lease_ticks)
                f.shell_ticks += 1
                if f.shell_ticks >= state.params.shell_dissolution_ticks
                    dissolve_firm!(state, f)
                end
            end
            continue
        end

        # Auto-renew expiring leases for firms with commercial space
        n_capital = f.capital_units
        filter!(t -> state.tick - t < state.params.capital_lease_term, f.capital_lease_ticks)
        for _ in (length(f.capital_lease_ticks) + 1):n_capital
            push!(f.capital_lease_ticks, state.tick)
        end
        n_process = f.process_count
        filter!(t -> state.tick - t < state.params.process_lease_term, f.process_lease_ticks)
        for _ in (length(f.process_lease_ticks) + 1):n_process
            push!(f.process_lease_ticks, state.tick)
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
                popfirst!(f.capital_lease_ticks)
                f.capital_units -= 1
            end
        end

        if rand(state.rng) < state.params.expansion_review_prob
            profitable = !isempty(f.profit_history) && f.profit_history[end] > 0
            sold_out = f.realized_sales_this_tick >= f.committed_output && f.committed_output > 0
            if profitable && sold_out
                ft = state.params.firm_types[f.firm_type]
                if f.cash >= ft.capital_rental_rate * state.params.capital_lease_term
                    push!(f.capital_lease_ticks, state.tick)
                    f.capital_units += 1
                    if rand(state.rng) < 0.25
                        if f.cash >= ft.process_rental_rate * state.params.process_lease_term
                            push!(f.process_lease_ticks, state.tick)
                            f.process_count += 1
                        end
                    end
                    commercial_space_search!(state, f)
                end
            end
        end

        # Pre-expiry search: one tick before a commercial lease expires, look for better space
        if has_expiring_commercial_lease(state, f)
            commercial_space_search_if_better!(state, f)
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
    for (lid, ticks_list) in f.commercial_units_by_lot
        state.lots[lid].occupied_commercial =
            max(0, state.lots[lid].occupied_commercial - length(ticks_list))
    end
    empty!(f.commercial_units_by_lot)
    empty!(f.commercial_rent_paid_by_lot)
    f.active = false
    delete!(state.active_firm_ids, f.id)
    state.events.firm_exits += 1
end

function dissolve_firm!(state::ModelState, f::Firm)
    !f.active && return
    if f.cash > 0
        active_owners = [(wid, share) for (wid, share) in f.ownership_shares
                         if wid <= length(state.workers) && wid in state.active_worker_ids]
        total_active_share = sum(share for (_, share) in active_owners; init=0.0)
        if total_active_share > 0
            for (wid, share) in active_owners
                state.workers[wid].savings += f.cash * (share / total_active_share)
            end
        end
    end
    f.cash = 0.0
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
        length(get(f.commercial_units_by_lot, lot_id, Int[])) -
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

function has_expiring_commercial_lease(state::ModelState, f::Firm)
    lt = state.params.commercial_lease_term
    for ticks_list in values(f.commercial_units_by_lot)
        for t in ticks_list
            state.tick + 1 - t >= lt && return true
        end
    end
    return false
end

function commercial_space_search_if_better!(state::ModelState, f::Firm)
    isempty(f.commercial_units_by_lot) && return false
    anchor = first(keys(f.commercial_units_by_lot))
    current_score = commercial_location_score_fast(state, f, anchor)
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
    isnothing(chosen_lot_id) && return false
    chosen_score = commercial_location_score_fast(state, f, chosen_lot_id)
    chosen_score <= current_score && return false
    bid = commercial_bid_amount(state, f, chosen_lot_id)
    push!(state.commercial_bid_buffer, CommercialBidProposal(f.id, chosen_lot_id, bid))
    return true
end

function firm_anchor_consumer_access(state::ModelState, f::Firm)
    isempty(f.commercial_units_by_lot) && return mean(state.consumer_access_by_lot)
    total_units = 0
    weighted_access = 0.0
    for (lot_id, ticks_list) in f.commercial_units_by_lot
        units = length(ticks_list)
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
    return max(
        state.params.min_commercial_rent,
        state.params.commercial_bid_share * base_sales * access_scale * f.goods_price,
    )
end

function release_expired_leases!(state::ModelState)
    lt = state.params.commercial_lease_term
    for f in active_firms(state)
        for (lot_id, ticks_list) in collect(f.commercial_units_by_lot)
            rent_list = f.commercial_rent_paid_by_lot[lot_id]
            n_expiring = count(t -> state.tick - t >= lt, ticks_list)
            n_expiring == 0 && continue
            state.lots[lot_id].occupied_commercial =
                max(0, state.lots[lot_id].occupied_commercial - n_expiring)
            expiry_indices = sort!([i for i in eachindex(ticks_list) if state.tick - ticks_list[i] >= lt])
            for i in reverse(expiry_indices)
                deleteat!(ticks_list, i)
                deleteat!(rent_list, i)
            end
            if isempty(ticks_list)
                delete!(f.commercial_units_by_lot, lot_id)
                delete!(f.commercial_rent_paid_by_lot, lot_id)
            end
            push!(state.rofr_buffer, RofrEntry(f.id, lot_id, n_expiring))
        end
    end
end

function _award_units_to_bidders!(state::ModelState, lot::Lot,
                                   max_units::Int,
                                   sorted_bids::Vector{CommercialBidProposal},
                                   won_firm_ids::Set{Int})
    awarded = 0
    for proposal in sorted_bids
        awarded >= max_units && break
        vacant_commercial(lot) <= 0 && break
        firm = state.firms[proposal.firm_id]
        firm.active || continue
        push!(get!(firm.commercial_units_by_lot, proposal.lot_id, Int[]), state.tick)
        push!(get!(firm.commercial_rent_paid_by_lot, proposal.lot_id, Float64[]), proposal.bid)
        lot.occupied_commercial += 1
        proposal.bid > lot.commercial_rent && (lot.commercial_rent = proposal.bid)
        awarded += 1
        push!(won_firm_ids, proposal.firm_id)
        if firm.startup_pending
            firm.startup_pending = false
            state.events.firm_entries += 1
        end
    end
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
            lot.commercial_rent = max(state.params.min_commercial_rent, bid)
            push!(get!(f.commercial_units_by_lot, rescue_lot_id, Int[]), state.tick)
            push!(get!(f.commercial_rent_paid_by_lot, rescue_lot_id, Float64[]), bid)
        end
        f.startup_pending = false
        state.events.firm_entries += 1
    end
end

function resolve_commercial_bids!(state::ModelState)
    bids = state.commercial_bid_buffer

    rofr_by_lot = Dict{Int,Vector{RofrEntry}}()
    for entry in state.rofr_buffer
        push!(get!(rofr_by_lot, entry.lot_id, RofrEntry[]), entry)
    end
    rofr_lot_ids = Set(keys(rofr_by_lot))

    bids_by_lot = Dict{Int,Vector{CommercialBidProposal}}()
    for proposal in bids
        push!(get!(bids_by_lot, proposal.lot_id, CommercialBidProposal[]), proposal)
    end
    for (_, lot_bids) in bids_by_lot
        sort!(lot_bids; by=b -> (-b.bid, b.firm_id))
    end

    # Pass 1: non-ROFR lots
    won_firm_ids = Set{Int}()
    for (lot_id, lot_bids) in bids_by_lot
        lot_id in rofr_lot_ids && continue
        lot = state.lots[lot_id]
        vacant_units = vacant_commercial(lot)
        vacant_units <= 0 && continue
        _award_units_to_bidders!(state, lot, vacant_units, lot_bids, won_firm_ids)
    end

    # Pass 2: ROFR lots
    for (lot_id, entries) in rofr_by_lot
        lot = state.lots[lot_id]
        lot_bids = get(bids_by_lot, lot_id, CommercialBidProposal[])
        for entry in entries
            firm = state.firms[entry.firm_id]
            if !firm.active || entry.firm_id in won_firm_ids
                _award_units_to_bidders!(state, lot, entry.n_units, lot_bids, won_firm_ids)
                continue
            end
            competing_bids = filter(b -> b.firm_id != entry.firm_id, lot_bids)
            max_competing = isempty(competing_bids) ? 0.0 : competing_bids[1].bid
            own_bid = commercial_bid_amount(state, firm, lot_id)
            rofr_rent = max(max_competing, own_bid, state.params.min_commercial_rent)
            if firm.cash >= rofr_rent * state.params.commercial_lease_term
                lot.occupied_commercial += entry.n_units
                for _ in 1:entry.n_units
                    push!(get!(firm.commercial_units_by_lot, lot_id, Int[]), state.tick)
                    push!(get!(firm.commercial_rent_paid_by_lot, lot_id, Float64[]), rofr_rent)
                end
                lot.commercial_rent = max(lot.commercial_rent, rofr_rent)
                _award_units_to_bidders!(state, lot, vacant_commercial(lot), competing_bids, won_firm_ids)
            else
                _award_units_to_bidders!(state, lot, entry.n_units, lot_bids, won_firm_ids)
            end
        end
    end

    # Vacancy decay for lots that received no bids
    lots_with_bids = Set(keys(bids_by_lot))
    for lot in state.lots
        lot.commercial_units == 0 && continue
        lot.id in lots_with_bids && continue
        vacant_commercial(lot) > 0 || continue
        lot.commercial_rent = max(
            state.params.min_commercial_rent,
            lot.commercial_rent * (1 - state.params.commercial_vacancy_rent_cut_rate),
        )
    end

    empty!(state.commercial_bid_buffer)
    empty!(state.rofr_buffer)
    finalize_pending_startup_firms!(state)
end
