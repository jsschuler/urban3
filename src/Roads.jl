function init_road_network(initial_cash::Float64)
    RoadNetwork(
        RoadSegment[],
        Int[],
        Dict{Int,Int}(),
        Matrix{Float64}(undef, 0, 0),
        Matrix{Int}(undef, 0, 0),
        Dict{Tuple{Int,Int},Int}(),
        Dict{Int,Vector{Tuple{Int,Float64}}}(),
        initial_cash,
        0.0,
    )
end

function lot_euclidean(a::Lot, b::Lot)
    sqrt(Float64((a.x - b.x)^2 + (a.y - b.y)^2))
end

# Returns (t, px, py): projection of (lx,ly) onto segment A->B, clamped to [0,1].
function project_onto_segment(lx::Float64, ly::Float64,
                               ax::Float64, ay::Float64,
                               bx::Float64, by::Float64)
    dx = bx - ax
    dy = by - ay
    len2 = dx * dx + dy * dy
    if len2 < 1e-10
        return 0.0, ax, ay
    end
    t = clamp(((lx - ax) * dx + (ly - ay) * dy) / len2, 0.0, 1.0)
    return t, ax + t * dx, ay + t * dy
end

function euclid2d(ax::Float64, ay::Float64, bx::Float64, by::Float64)
    sqrt((ax - bx)^2 + (ay - by)^2)
end

# Rebuild shortest-path matrix using congested_length weights.
# Also builds next_hop (for path reconstruction) and segment_lookup.
function rebuild_road_graph!(net::RoadNetwork)
    nodes = sort!(collect(keys(net.adj)))
    net.road_node_lot_ids = nodes
    net.road_node_index = Dict(lid => i for (i, lid) in enumerate(nodes))
    K = length(nodes)
    D = fill(Inf, K, K)
    NX = zeros(Int, K, K)
    for i in 1:K
        D[i, i] = 0.0
        NX[i, i] = i
    end

    net.segment_lookup = Dict{Tuple{Int,Int},Int}()
    for (seg_idx, seg) in enumerate(net.segments)
        i = get(net.road_node_index, seg.from_lot_id, 0)
        j = get(net.road_node_index, seg.to_lot_id, 0)
        (i == 0 || j == 0) && continue
        net.segment_lookup[(seg.from_lot_id, seg.to_lot_id)] = seg_idx
        net.segment_lookup[(seg.to_lot_id, seg.from_lot_id)] = seg_idx
        cl = seg.congested_length
        if cl < D[i, j]
            D[i, j] = cl
            D[j, i] = cl
            NX[i, j] = j
            NX[j, i] = i
        end
    end

    for k in 1:K, i in 1:K, j in 1:K
        if D[i, k] + D[k, j] < D[i, j]
            D[i, j] = D[i, k] + D[k, j]
            NX[i, j] = NX[i, k]
        end
    end

    net.shortest_road_dist = D
    net.next_hop = NX
end

function add_road_segment!(net::RoadNetwork, from_lot_id::Int, to_lot_id::Int,
                           lots::Vector{Lot}, scalar::Float64, capacity_base::Float64)
    from_lot = lots[from_lot_id]
    to_lot = lots[to_lot_id]
    ed = lot_euclidean(from_lot, to_lot)
    rl = ed / scalar
    cap = capacity_base * ed
    seg = RoadSegment(length(net.segments) + 1, from_lot_id, to_lot_id, ed, rl, rl, cap, 0)
    push!(net.segments, seg)
    push!(get!(net.adj, from_lot_id, Tuple{Int,Float64}[]), (to_lot_id, rl))
    push!(get!(net.adj, to_lot_id, Tuple{Int,Float64}[]), (from_lot_id, rl))
    rebuild_road_graph!(net)
end

# Minimum cost for lot L to reach road node at index `node_idx`.
# Returns (total_cost, road_fee_component, best_segment_idx).
# best_segment_idx == 0 means direct walk was cheapest (no segment used).
function access_cost_to_node(
    lot::Lot, node_idx::Int,
    net::RoadNetwork, lots::Vector{Lot},
    walk_rate::Float64, road_rate::Float64,
)
    ni = net.road_node_lot_ids[node_idx]
    node_lot = lots[ni]
    best_cost    = Float64(taxicab(lot, node_lot)) * walk_rate
    best_fee     = 0.0
    best_seg_idx = 0

    lx = Float64(lot.x)
    ly = Float64(lot.y)

    for (seg_idx, seg) in enumerate(net.segments)
        if seg.from_lot_id == ni
            other = lots[seg.to_lot_id]
            t, px, py = project_onto_segment(lx, ly,
                Float64(node_lot.x), Float64(node_lot.y),
                Float64(other.x), Float64(other.y))
            walk_dist = euclid2d(lx, ly, px, py)
            road_dist = t * seg.congested_length
            cost = walk_dist * walk_rate + road_dist * road_rate
            if cost < best_cost
                best_cost    = cost
                best_fee     = road_dist * road_rate
                best_seg_idx = seg_idx
            end
        elseif seg.to_lot_id == ni
            other = lots[seg.from_lot_id]
            t, px, py = project_onto_segment(lx, ly,
                Float64(other.x), Float64(other.y),
                Float64(node_lot.x), Float64(node_lot.y))
            walk_dist = euclid2d(lx, ly, px, py)
            road_dist = (1.0 - t) * seg.congested_length
            cost = walk_dist * walk_rate + road_dist * road_rate
            if cost < best_cost
                best_cost    = cost
                best_fee     = road_dist * road_rate
                best_seg_idx = seg_idx
            end
        end
    end

    return best_cost, best_fee, best_seg_idx
end

# Walk next_hop from node i to node j, incrementing usage on each traversed segment.
function record_trip_usage!(net::RoadNetwork, i::Int, j::Int)
    curr = i
    while curr != j
        nxt = net.next_hop[curr, j]
        (nxt == 0 || nxt == curr) && break
        from_lid = net.road_node_lot_ids[curr]
        to_lid   = net.road_node_lot_ids[nxt]
        seg_idx  = get(net.segment_lookup, (from_lid, to_lid), 0)
        seg_idx > 0 && (net.segments[seg_idx].usage_this_tick += 1)
        curr = nxt
    end
end

# Effective travel cost from origin lot to dest lot given the road network.
# Returns (total_cost, road_fee).
# When record_usage=true, increments usage on all road segments used by the best path
# (access feeder segments at both ends plus road-network traversal segments).
function effective_travel_cost(
    origin_id::Int, dest_id::Int,
    walk_rate::Float64, road_rate::Float64,
    state::ModelState;
    record_usage::Bool = false,
)
    O = state.lots[origin_id]
    D = state.lots[dest_id]
    walk_cost = Float64(taxicab(O, D)) * walk_rate

    net = state.road_network
    K = length(net.road_node_lot_ids)
    K == 0 && return walk_cost, 0.0

    best_cost     = walk_cost
    best_road_fee = 0.0
    best_i        = 0
    best_j        = 0
    best_seg_o    = 0   # access segment at origin end
    best_seg_d    = 0   # access segment at destination end

    for i in 1:K
        ac_o, fee_o, seg_o = access_cost_to_node(O, i, net, state.lots, walk_rate, road_rate)
        ac_o >= best_cost && continue
        for j in 1:K
            rd = net.shortest_road_dist[i, j]
            isinf(rd) && continue
            ac_d, fee_d, seg_d = access_cost_to_node(D, j, net, state.lots, walk_rate, road_rate)
            road_fee = fee_o + rd * road_rate + fee_d
            total = ac_o + rd * road_rate + ac_d
            if total < best_cost
                best_cost     = total
                best_road_fee = road_fee
                best_i        = i
                best_j        = j
                best_seg_o    = seg_o
                best_seg_d    = seg_d
            end
        end
    end

    if record_usage && best_i > 0
        best_seg_o > 0 && (net.segments[best_seg_o].usage_this_tick += 1)
        record_trip_usage!(net, best_i, best_j)
        best_seg_d > 0 && best_seg_d != best_seg_o && (net.segments[best_seg_d].usage_this_tick += 1)
    end

    return best_cost, best_road_fee
end

# Score a candidate road from lot A to lot B.
function score_road_candidate(from_id::Int, to_id::Int, state::ModelState)
    from_lot = state.lots[from_id]
    to_lot   = state.lots[to_id]
    ed = lot_euclidean(from_lot, to_lot)
    ed < state.params.road_min_euclidean && return 0.0

    p  = state.params
    r  = p.road_density_radius
    cr = p.commute_cost_per_block  # price signal: walk cost per block

    demand_from = 0.0
    demand_to   = 0.0

    for wid in state.active_worker_ids
        w = state.workers[wid]
        isnothing(w.dwelling_lot_id) && continue
        wl = state.lots[w.dwelling_lot_id]
        df = taxicab(from_lot, wl)
        dt = taxicab(to_lot,   wl)
        df <= r && (demand_from += df * cr)
        dt <= r && (demand_to   += dt * cr)
    end

    for fid in state.active_firm_ids
        f = state.firms[fid]
        workers = Float64(length(f.worker_ids) + 1)
        for lid in keys(f.commercial_units_by_lot)
            fl = state.lots[lid]
            df = taxicab(from_lot, fl)
            dt = taxicab(to_lot,   fl)
            df <= r && (demand_from += df * cr * workers)
            dt <= r && (demand_to   += dt * cr * workers)
        end
    end

    return demand_from * demand_to / ed
end

function road_firm_phase!(state::ModelState)
    p = state.params
    net = state.road_network

    # Collect commute road revenue; record segment usage for BPR update
    for wid in state.active_worker_ids
        w = state.workers[wid]
        isnothing(w.employer_id) && continue
        isnothing(w.dwelling_lot_id) && continue
        f = state.firms[w.employer_id]
        job_lot = nearest_firm_lot(f, w.dwelling_lot_id, state)
        isnothing(job_lot) && continue
        _, road_fee = effective_travel_cost(
            w.dwelling_lot_id, job_lot,
            p.commute_cost_per_block, p.road_commute_fee_per_unit, state;
            record_usage = true,
        )
        net.revenue_this_tick += road_fee
    end

    # Distribute all revenue as dividends to active workers
    tick_revenue = net.revenue_this_tick
    net.revenue_this_tick = 0.0
    n_workers = length(state.active_worker_ids)
    if n_workers > 0 && tick_revenue > 0.0
        per_worker = tick_revenue / n_workers
        for wid in state.active_worker_ids
            state.workers[wid].savings += per_worker
        end
    end

    # BPR congestion update: recompute congested lengths from this tick's usage, then rebuild
    if !isempty(net.segments)
        for seg in net.segments
            v_c = seg.capacity > 0.0 ? seg.usage_this_tick / seg.capacity : 0.0
            seg.congested_length = seg.road_length * (1.0 + p.congestion_alpha * v_c^p.congestion_beta)
            seg.usage_this_tick = 0
        end
        rebuild_road_graph!(net)
    end

    # Build one road every road_build_every ticks if cash allows
    state.tick % p.road_build_every != 0 && return
    net.cash < p.road_build_cost && return
    isempty(state.lots) && return

    n_lots = length(state.lots)
    best_score = 0.0
    best_from = 0
    best_to = 0

    for _ in 1:p.road_candidate_pairs
        from_id = rand(state.rng, 1:n_lots)
        to_id = rand(state.rng, 1:n_lots)
        from_id == to_id && continue
        score = score_road_candidate(from_id, to_id, state)
        if score > best_score
            best_score = score
            best_from = from_id
            best_to = to_id
        end
    end

    if best_from > 0 && best_score > 0.0
        add_road_segment!(net, best_from, best_to, state.lots, p.road_speed_scalar, p.road_capacity_base)
        net.cash -= p.road_build_cost
    end
end
