function tick_snapshot(state::ModelState)
    Dict(
        "type" => "tick_snapshot",
        "tick" => state.tick,
        "diagnostics" => metrics_snapshot(state),
    )
end

function lot_dict(l::Lot)
    Dict(
        "id" => l.id, "x" => l.x, "y" => l.y,
        "residential_units" => l.residential_units,
        "commercial_units" => l.commercial_units,
        "occupied_residential" => l.occupied_residential,
        "occupied_commercial" => l.occupied_commercial,
        "residential_rent" => l.residential_rent,
        "commercial_rent" => l.commercial_rent,
    )
end

function blender_snapshot(state::ModelState)
    Dict(
        "type" => "blender_snapshot",
        "tick" => state.tick,
        "lot_scale" => 2,
        "width" => state.params.width,
        "height" => state.params.height,
        "lots" => [lot_dict(l) for l in state.lots],
    )
end

function write_lot_csv(state::ModelState, path::AbstractString)
    open(path, "w") do io
        println(io, join([
            "tick",
            "lot_id",
            "x",
            "y",
            "residential_units",
            "commercial_units",
            "occupied_residential",
            "occupied_commercial",
            "vacant_residential",
            "vacant_commercial",
            "residential_rent",
            "commercial_rent",
        ], ","))
        for l in state.lots
            println(io, join([
                state.tick,
                l.id,
                l.x,
                l.y,
                l.residential_units,
                l.commercial_units,
                l.occupied_residential,
                l.occupied_commercial,
                vacant_residential(l),
                vacant_commercial(l),
                l.residential_rent,
                l.commercial_rent,
            ], ","))
        end
    end
    return path
end
