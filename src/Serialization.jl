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
