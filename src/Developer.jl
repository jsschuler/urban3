function developer_update!(state::ModelState)
    for lot in state.lots
        if lot.residential_units > 0
            if vacant_residential(lot) > 0
                lot.residential_rent *= (1 - state.params.residential_vacancy_rent_cut_rate)
            elseif lot.occupied_residential >= lot.residential_units
                lot.residential_rent *= (1 + state.params.residential_rent_raise_rate)
            end
            lot.residential_rent = max(state.params.min_residential_rent, lot.residential_rent)
        end

        if rand(state.rng) < state.params.residential_add_prob && vacant_residential(lot) == 0
            lot.residential_units += 1
            state.events.residential_units_added += 1
        end
        if rand(state.rng) < state.params.commercial_add_prob && vacant_commercial(lot) == 0
            lot.commercial_units += 1
            state.events.commercial_units_added += 1
        end
        maybe_convert_vacant_unit!(state, lot)
    end
end

function maybe_convert_vacant_unit!(state::ModelState, lot::Lot)
    rand(state.rng) >= state.params.conversion_prob && return false
    if vacant_residential(lot) > 0 && lot.commercial_rent > lot.residential_rent * 1.25
        lot.residential_units -= 1
        lot.commercial_units += 1
        state.events.conversions += 1
        return true
    elseif vacant_commercial(lot) > 0 && lot.residential_rent > lot.commercial_rent * 1.25
        lot.commercial_units -= 1
        lot.residential_units += 1
        state.events.conversions += 1
        return true
    end
    return false
end
