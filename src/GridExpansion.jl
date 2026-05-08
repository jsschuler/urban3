function cbd_lot_id(state::ModelState)
    best_id = 0
    best_rent = -Inf
    for l in state.lots
        l.commercial_units > 0 || continue
        if l.commercial_rent > best_rent
            best_rent = l.commercial_rent
            best_id = l.id
        end
    end
    return best_id
end

function should_expand_grid(state::ModelState)::Bool
    p = state.params
    state.tick < p.grid_expansion_min_ticks && return false
    (state.tick - state.last_expansion_tick) < p.grid_expansion_cooldown && return false

    # Occupancy conditions: both residential and commercial stock must be sufficiently occupied
    res_units = sum(l.residential_units for l in state.lots)
    occ_res   = sum(l.occupied_residential for l in state.lots)
    res_units > 0 && (occ_res / res_units) < p.grid_expansion_min_residential_occupancy && return false

    com_units = sum(l.commercial_units for l in state.lots)
    occ_com   = sum(l.occupied_commercial for l in state.lots)
    com_units > 0 && (occ_com / com_units) < p.grid_expansion_min_commercial_occupancy && return false

    # Rent concentration condition: CBD must be forming
    rents = Float64[]
    for l in state.lots
        l.occupied_commercial > 0 || continue
        push!(rents, l.commercial_rent)
    end
    length(rents) < 5 && return false
    mean_rent = sum(rents) / length(rents)
    mean_rent <= 0.0 && return false
    return maximum(rents) / mean_rent >= p.grid_expansion_cbd_rent_ratio
end

function expand_grid!(state::ModelState)
    p = state.params
    M = p.grid_expansion_margin
    W = p.width
    H = p.height

    cbd_id = cbd_lot_id(state)
    cbd_id == 0 && return

    cbd = state.lots[cbd_id]
    new_W = W + 2 * M
    new_H = H + 2 * M

    # Shift that centers the CBD in the new grid, clamped so no lot leaves bounds
    dx = clamp(round(Int, (new_W + 1) / 2.0 - cbd.x), 0, 2 * M)
    dy = clamp(round(Int, (new_H + 1) / 2.0 - cbd.y), 0, 2 * M)

    for l in state.lots
        l.x += dx
        l.y += dy
    end

    p.width = new_W
    p.height = new_H

    empty!(state.lot_by_position)
    for l in state.lots
        state.lot_by_position[(l.x, l.y)] = l.id
    end

    # Add empty lots for all new grid positions not already occupied
    new_id = length(state.lots) + 1
    for y in 1:new_H, x in 1:new_W
        haskey(state.lot_by_position, (x, y)) && continue
        rent_res = p.initial_residential_rent_min +
            (p.initial_residential_rent_max - p.initial_residential_rent_min) * rand(state.rng)
        rent_com = p.initial_commercial_rent_min +
            (p.initial_commercial_rent_max - p.initial_commercial_rent_min) * rand(state.rng)
        l = Lot(new_id, x, y,
            p.initial_residential_units_per_lot,
            p.initial_commercial_units_per_lot,
            0, 0, rent_res,
            p.initial_commercial_units_per_lot > 0 ? rent_com : p.min_commercial_rent)
        push!(state.lots, l)
        state.lot_by_position[(x, y)] = new_id
        new_id += 1
    end

    # Extend access arrays (new elements are zero — no access yet for periphery)
    old_n = length(state.consumer_access_by_lot)
    n_lots = length(state.lots)
    resize!(state.consumer_access_by_lot, n_lots)
    resize!(state.job_access_by_lot, n_lots)
    state.consumer_access_by_lot[old_n+1:end] .= 0.0
    state.job_access_by_lot[old_n+1:end] .= 0.0

    state.last_expansion_tick = state.tick
end

function maybe_expand_grid!(state::ModelState)
    should_expand_grid(state) || return
    expand_grid!(state)
    refresh_spatial_access!(state)
end
