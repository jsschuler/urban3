function marginal_construction_cost(current_units::Int, p::ModelParams)
    p.height_cost_base * p.height_cost_multiplier ^ current_units
end

# Collect residential rents from housed workers (deducted from their savings)
# and commercial rents from active firms (already deducted from firm cash in
# calculate_profits!; here we credit the developer's cash account).
function developer_collect_rents!(state::ModelState)
    dev = state.developer
    dev.rent_collected_this_tick = 0.0

    for wid in state.active_worker_ids
        w = state.workers[wid]
        isnothing(w.dwelling_lot_id) && continue
        rent = state.lots[w.dwelling_lot_id].residential_rent
        dev.cash += rent
        dev.rent_collected_this_tick += rent
    end

    for fid in state.active_firm_ids
        f = state.firms[fid]
        total = sum(sum(rents) for rents in values(f.commercial_rent_paid_by_lot); init=0.0)
        dev.cash += total
        dev.rent_collected_this_tick += total
    end
end

# Pay interest on outstanding debt to the (unconstrained) lender and amortize
# principal proportionally each tick.
function developer_service_debt!(state::ModelState)
    p = state.params
    dev = state.developer
    dev.interest_paid_this_tick = p.lending_rate * (dev.residential_debt + dev.commercial_debt)
    dev.cash -= dev.interest_paid_this_tick
    dev.residential_debt *= (1.0 - 1.0 / p.residential_loan_term)
    dev.commercial_debt  *= (1.0 - 1.0 / p.commercial_loan_term)
end

function developer_update!(state::ModelState)
    p   = state.params
    dev = state.developer

    for lot in state.lots
        # ── Residential rent adjustment ───────────────────────────────────────
        if lot.residential_units > 0
            if vacant_residential(lot) > 0
                lot.residential_rent *= (1 - p.residential_vacancy_rent_cut_rate)
            elseif lot.occupied_residential >= lot.residential_units
                lot.residential_rent *= (1 + p.residential_rent_raise_rate)
            end
            # Floor: must cover average debt-service on construction cost
            if haskey(dev.construction_cost_by_lot, lot.id)
                avg_floor = dev.construction_cost_by_lot[lot.id] *
                    (p.lending_rate + 1.0 / p.residential_loan_term) / lot.residential_units
                lot.residential_rent = max(lot.residential_rent, avg_floor)
            end
            lot.residential_rent = max(p.min_residential_rent, lot.residential_rent)
        end

        # ── Add residential unit (rent-signal triggered) ─────────────────────
        if lot.residential_units > 0 && vacant_residential(lot) == 0 &&
                lot.residential_rent >= p.residential_developer_rent_threshold
            mc       = marginal_construction_cost(lot.residential_units, p)
            min_rent = mc * (p.lending_rate + 1.0 / p.residential_loan_term)
            if lot.residential_rent >= min_rent
                lot.residential_units += 1
                dev.residential_debt  += mc
                state.events.residential_units_added += 1
                new_total = get(dev.construction_cost_by_lot, lot.id, 0.0) + mc
                dev.construction_cost_by_lot[lot.id] = new_total
                avg_floor = new_total * (p.lending_rate + 1.0 / p.residential_loan_term) /
                    lot.residential_units
                lot.residential_rent = max(lot.residential_rent, avg_floor)
            end
        end

        maybe_convert_vacant_unit!(state, lot)
    end
end

function maybe_convert_vacant_unit!(state::ModelState, lot::Lot)
    rand(state.rng) >= state.params.conversion_prob && return false
    if vacant_commercial(lot) > 0 && lot.residential_rent > lot.commercial_rent * 1.25
        lot.commercial_units  -= 1
        lot.residential_units += 1
        state.events.conversions += 1
        return true
    end
    return false
end
