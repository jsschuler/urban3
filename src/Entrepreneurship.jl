# Build commercial supply driven by rent signals.
# Density trigger: highest-rent fully-occupied lot above commercial_developer_rent_threshold.
# Greenfield trigger: any active firm has no space (direct market failure).
# Builds at most one unit per tick to prevent burst oversupply.
function commercial_developer_phase!(state::ModelState)
    p   = state.params
    dev = state.developer

    n_spaceless = count(fid -> isempty(state.firms[fid].commercial_units_by_lot),
                        state.active_firm_ids)

    # Density expansion: add a unit to the highest-rent fully-occupied commercial lot
    # when that lot's rent exceeds the pricing threshold.
    best_lid  = 0
    best_rent = p.commercial_developer_rent_threshold
    for l in state.lots
        l.commercial_units > 0 || continue
        vacant_commercial(l) == 0 || continue
        if l.commercial_rent > best_rent
            best_rent = l.commercial_rent
            best_lid  = l.id
        end
    end
    if best_lid > 0
        lot      = state.lots[best_lid]
        mc       = marginal_construction_cost(lot.commercial_units, p)
        min_rent = mc * (p.lending_rate + 1.0 / p.commercial_loan_term)
        if lot.commercial_rent >= min_rent
            lot.commercial_units += 1
            dev.commercial_debt  += mc
            state.events.commercial_units_added += 1
            new_total = get(dev.commercial_construction_cost_by_lot, lot.id, 0.0) + mc
            dev.commercial_construction_cost_by_lot[lot.id] = new_total
            avg_floor = new_total * (p.lending_rate + 1.0 / p.commercial_loan_term) /
                lot.commercial_units
            lot.commercial_rent = max(lot.commercial_rent, avg_floor)
            return
        end
    end

    # Greenfield: when a firm has no space at all, open a unit on the most-accessible
    # undeveloped lot so the firm can claim it next search cycle.
    n_spaceless == 0 && return
    best_lid    = 0
    best_access = -Inf
    for lot in state.lots
        lot.commercial_units > 0 && continue
        a = state.consumer_access_by_lot[lot.id]
        if a > best_access
            best_access = a
            best_lid    = lot.id
        end
    end
    if best_lid > 0
        lot = state.lots[best_lid]
        mc  = marginal_construction_cost(0, p)
        lot.commercial_units = 1
        dev.commercial_debt  += mc
        state.events.commercial_units_added += 1
        new_total = get(dev.commercial_construction_cost_by_lot, lot.id, 0.0) + mc
        dev.commercial_construction_cost_by_lot[lot.id] = new_total
        avg_floor = new_total * (p.lending_rate + 1.0 / p.commercial_loan_term)
        lot.commercial_rent = max(lot.commercial_rent, avg_floor)
    end
end

# Add one residential lot per firing at the innermost unfilled Manhattan ring from the CBD.
# "Ring first" means: complete all positions at distance R before placing any at R+1.
# Among candidates at the same ring distance, prefer the one adjacent to the highest-access lot.
# Fires when mean residential rent of occupied lots exceeds land_developer_rent_threshold,
# indicating genuine housing scarcity rather than a transient occupancy fluctuation.
function land_developer_phase!(state::ModelState)
    p = state.params
    state.tick % p.land_developer_fire_every != 0 && return

    occupied_rents = [l.residential_rent
                      for l in state.lots
                      if l.residential_units > 0 && l.occupied_residential > 0]
    isempty(occupied_rents) && return
    mean_res_rent = sum(occupied_rents) / length(occupied_rents)
    mean_res_rent < p.land_developer_rent_threshold && return

    cbd_x, cbd_y = -1, -1
    best_cr = -Inf
    for l in state.lots
        l.commercial_units > 0 || continue
        if l.commercial_rent > best_cr
            best_cr = l.commercial_rent
            cbd_x, cbd_y = l.x, l.y
        end
    end
    cbd_x < 0 && return

    min_ring      = typemax(Int)
    best_pos      = nothing
    best_nb_access = -Inf
    for l in state.lots
        for (dx, dy) in ((1,0),(-1,0),(0,1),(0,-1))
            nx, ny = l.x + dx, l.y + dy
            (nx < 1 || ny < 1) && continue
            haskey(state.lot_by_position, (nx, ny)) && continue
            nd = abs(nx - cbd_x) + abs(ny - cbd_y)
            nb_access = state.consumer_access_by_lot[l.id]
            if nd < min_ring
                min_ring       = nd
                best_pos       = (nx, ny)
                best_nb_access = nb_access
            elseif nd == min_ring && nb_access > best_nb_access
                best_pos       = (nx, ny)
                best_nb_access = nb_access
            end
        end
    end
    isnothing(best_pos) && return

    rng    = state.rng
    new_id = length(state.lots) + 1
    rent_res = p.initial_residential_rent_min +
        (p.initial_residential_rent_max - p.initial_residential_rent_min) * rand(rng)
    lot = Lot(new_id, best_pos[1], best_pos[2],
              p.initial_residential_units_per_lot, 0, 0, 0,
              rent_res, p.min_commercial_rent)
    push!(state.lots, lot)
    state.lot_by_position[best_pos] = new_id
    push!(state.consumer_access_by_lot, 0.0)
    push!(state.job_access_by_lot, 0.0)
    p.width  = max(p.width,  best_pos[1])
    p.height = max(p.height, best_pos[2])
    state.events.residential_units_added += p.initial_residential_units_per_lot
end

# Connect frontier lots (no road endpoint) to the nearest road node, one segment per firing.
# Fires every road_developer_fire_every ticks when disconnected lots exist and cash allows.
function road_developer_phase!(state::ModelState)
    p   = state.params
    net = state.road_network
    state.tick % p.road_developer_fire_every != 0 && return
    net.cash < p.road_build_cost && return
    isempty(net.road_node_lot_ids) && return

    connected = Set{Int}(net.road_node_lot_ids)

    best_from = 0
    best_to   = 0
    best_dist = typemax(Int)
    for l in state.lots
        l.id ∈ connected && continue
        l.residential_units == 0 && l.commercial_units == 0 && continue
        for cid in connected
            cl = state.lots[cid]
            d  = abs(l.x - cl.x) + abs(l.y - cl.y)
            if d < best_dist
                best_dist = d
                best_from = l.id
                best_to   = cid
            end
        end
    end
    best_from == 0 && return

    add_road_segment!(net, best_from, best_to, state.lots, p.road_speed_scalar, p.road_capacity_base)
    net.cash -= p.road_build_cost
end

function has_active_ownership(state::ModelState, w::Worker)
    for firm_id in keys(w.ownership_shares)
        firm_id > length(state.firms) && continue
        state.firms[firm_id].active && return true
    end
    return false
end

# Update the entrepreneur's rolling price history and attempt to found a firm if
# a price appreciation signal is active. Called once per tick from the scheduler.
function entrepreneur_phase!(state::ModelState)
    p   = state.params
    ent = state.entrepreneur

    # Step 1: record mean posted price per firm type this tick
    for ftype in 1:p.firm_type_count
        prices = [state.firms[fid].goods_price
                  for fid in state.active_firm_ids
                  if state.firms[fid].firm_type == ftype]
        price  = isempty(prices) ? p.outside_goods_price : sum(prices) / length(prices)
        hist   = get!(ent.price_history, ftype, Float64[])
        push!(hist, price)
        length(hist) > p.entrepreneur_price_window && popfirst!(hist)
    end

    # Step 2: if already working on a coalition, try to assemble and return
    if ent.active_sector > 0
        _attempt_coalition_founding!(state)
        return
    end

    # Step 3: scan for the highest-appreciation sector above threshold.
    # Sectors with no active firms are treated as maximum priority (appreciation = Inf)
    # so persistent scarcity doesn't fall silent once prices have been at ceiling 10+ ticks.
    best_sector       = 0
    best_appreciation = -Inf
    active_types = Set(state.firms[fid].firm_type for fid in state.active_firm_ids)
    for ftype in 1:p.firm_type_count
        if ftype ∉ active_types
            if Inf > best_appreciation
                best_appreciation = Inf
                best_sector = ftype
            end
            continue
        end
        hist = get(ent.price_history, ftype, Float64[])
        length(hist) < p.entrepreneur_price_window && continue
        p0 = hist[1]
        p0 <= 0.0 && continue
        appreciation = (hist[end] - p0) / p0
        if appreciation >= p.entrepreneur_price_threshold && appreciation > best_appreciation
            best_appreciation = appreciation
            best_sector = ftype
        end
    end

    if best_sector > 0
        ent.active_sector = best_sector
        _attempt_coalition_founding!(state)
    end
end

# Try to assemble a coalition for the active sector. Selects the top workers by
# savings until coalition_startup_savings is covered, then founds the firm.
# If the population doesn't yet have enough savings, waits until next tick.
function _attempt_coalition_founding!(state::ModelState)
    p    = state.params
    ent  = state.entrepreneur
    ftype = ent.active_sector

    candidates = sort!(
        filter(wid -> state.workers[wid].savings > 0.0, collect(state.active_worker_ids)),
        by = wid -> state.workers[wid].savings,
        rev = true,
    )

    selected    = Int[]
    accumulated = 0.0
    for wid in candidates
        push!(selected, wid)
        accumulated += state.workers[wid].savings
        length(selected) >= p.coalition_size_max && break
    end

    if accumulated >= p.coalition_startup_savings && length(selected) >= p.coalition_size_min
        # enter at current market price (not initial_goods_price_max) so the new firm
        # is competitive with surviving incumbents rather than immediately over-priced
        hist = get(ent.price_history, ftype, Float64[])
        market_price = isempty(hist) ? p.firm_types[ftype].initial_goods_price_max : hist[end]
        entry_price = min(p.firm_types[ftype].initial_goods_price_max, market_price)
        # invest all selected savings so firm capital scales with worker wealth
        found_firm!(state, selected; startup_capital = accumulated,
                    ftype_override = ftype, initial_price = entry_price)
        ent.active_sector = 0
    end
    # Otherwise: not enough savings in population yet — try again next tick
end

function found_firm!(state::ModelState, founder_ids::Vector{Int};
                     startup_capital::Float64,
                     initial_cash::Float64 = startup_capital,
                     ftype_override::Int   = 0,
                     initial_price::Float64 = 0.0)
    isempty(founder_ids) && return nothing
    total_savings = sum(state.workers[id].savings for id in founder_ids)
    total_savings <= 0 && return nothing
    shares = Dict(id => state.workers[id].savings / total_savings for id in founder_ids)
    if startup_capital > 0
        for id in founder_ids
            state.workers[id].savings = max(0.0, state.workers[id].savings - startup_capital * shares[id])
        end
    end
    ftype = ftype_override > 0 ? ftype_override : rand(state.rng, 1:state.params.firm_type_count)
    firm_id        = length(state.firms) + 1
    planning_period = max(1, state.params.planning_period_ticks)
    planning_offset = rand(state.rng, 0:(planning_period - 1))
    ft = state.params.firm_types[ftype]
    goods_price = initial_price > 0.0 ? initial_price : ft.initial_goods_price_max
    firm = Firm(firm_id, ftype, copy(founder_ids), shares,
        state.params.base_wage * (0.9 + 0.2 * rand(state.rng)),
        Int[], Dict{Int,Float64}(),
        2, fill(state.tick, 2),
        1, [state.tick],
        Dict{Int,Vector{Int}}(), Dict{Int,Vector{Float64}}(), 0,
        goods_price,
        0, 0, Int[], Float64[], true, true,
        state.tick,
        Dict{Int,Int}(), 0.0, initial_cash,
        state.params.initial_hire_per_firm, state.tick, planning_offset,
        true, initial_cash, 0.0, 0.0)
    push!(state.firms, firm)
    push!(state.active_firm_ids, firm_id)
    for (id, share) in shares
        state.workers[id].ownership_shares[firm_id] = share
    end
    commercial_space_search!(state, firm)
    return firm
end

function investor_found_firm!(state::ModelState, ftype::Int)
    firm_id = length(state.firms) + 1
    ft = state.params.firm_types[ftype]
    planning_period = max(1, state.params.planning_period_ticks)
    planning_offset = rand(state.rng, 0:(planning_period - 1))
    firm = Firm(firm_id, ftype, Int[], Dict{Int,Float64}(),
        state.params.base_wage * (0.9 + 0.2 * rand(state.rng)),
        Int[], Dict{Int,Float64}(),
        2, fill(state.tick, 2),
        1, [state.tick],
        Dict{Int,Vector{Int}}(), Dict{Int,Vector{Float64}}(), 0,
        ft.initial_goods_price_max,
        0, 0, Int[], Float64[], true, true,
        state.tick,
        Dict{Int,Int}(), 0.0, state.params.investor_initial_firm_cash,
        state.params.initial_hire_per_firm, state.tick, planning_offset,
        true, state.params.investor_initial_firm_cash, 0.0, 0.0)
    push!(state.firms, firm)
    push!(state.active_firm_ids, firm_id)
    commercial_space_search!(state, firm)
    return firm
end
