function start_server(args...; kwargs...)
    @eval begin
        using HTTP
        using JSON3
    end
    return _start_server(args...; kwargs...)
end

mutable struct ServerRuntime
    state::ModelState
    running::Base.RefValue{Bool}
    gui_clients::Vector{Any}
    blender_clients::Vector{Any}
end

function _send_ws(ws, payload)
    @eval using JSON3
    HTTP.WebSockets.send(ws, JSON3.write(payload))
end

function broadcast!(clients::Vector{Any}, payload)
    dead = Int[]
    for (i, ws) in enumerate(clients)
        try
            _send_ws(ws, payload)
        catch
            push!(dead, i)
        end
    end
    isempty(dead) || deleteat!(clients, dead)
end

function _start_server(; params::ModelParams=ModelParams(), gui_port::Int=8766, blender_port::Int=8765)
    runtime = ServerRuntime(init_state(params), Ref(false), Any[], Any[])

    @async HTTP.WebSockets.listen("127.0.0.1", UInt16(gui_port)) do ws
        push!(runtime.gui_clients, ws)
        _send_ws(ws, merge(metrics_snapshot(runtime.state), Dict("type" => "diagnostic_snapshot")))
        try
            for msg in ws
                data = JSON3.read(msg, Dict{String,Any})
                handle_gui_message!(runtime, data)
            end
        finally
            filter!(x -> x !== ws, runtime.gui_clients)
        end
    end

    @async HTTP.WebSockets.listen("127.0.0.1", UInt16(blender_port)) do ws
        push!(runtime.blender_clients, ws)
        _send_ws(ws, blender_snapshot(runtime.state))
        try
            for _ in ws
            end
        finally
            filter!(x -> x !== ws, runtime.blender_clients)
        end
    end

    @async simulation_loop!(runtime)
    println("GUI websocket: ws://127.0.0.1:$gui_port")
    println("Blender websocket: ws://127.0.0.1:$blender_port")
    return runtime
end

function handle_gui_message!(runtime::ServerRuntime, data)
    cmd = string(get(data, "command", ""))
    if cmd == "start"
        runtime.running[] = true
        broadcast!(runtime.gui_clients, Dict("type" => "run_status", "running" => true))
    elseif cmd == "pause"
        runtime.running[] = false
        broadcast!(runtime.gui_clients, Dict("type" => "run_status", "running" => false))
    elseif cmd == "step"
        step_and_broadcast!(runtime)
    elseif cmd == "reset"
        runtime.state = init_state(runtime.state.params)
        broadcast!(runtime.gui_clients, metrics_snapshot(runtime.state))
        broadcast!(runtime.blender_clients, blender_snapshot(runtime.state))
    elseif cmd == "parameter_update"
        apply_parameter_update!(runtime.state.params, get(data, "parameters", Dict()))
        broadcast!(runtime.gui_clients, Dict("type" => "event_log", "message" => "parameters updated"))
    end
end

function apply_parameter_update!(params::ModelParams, updates)
    for (k, v) in updates
        s = Symbol(k)
        hasproperty(params, s) || continue
        cur = getproperty(params, s)
        if cur isa Int
            setproperty!(params, s, Int(v))
        elseif cur isa Float64
            setproperty!(params, s, Float64(v))
        end
    end
end

function simulation_loop!(runtime::ServerRuntime)
    while true
        if runtime.running[]
            step_and_broadcast!(runtime)
            sleep(0.02)
        else
            sleep(0.10)
        end
    end
end

function step_and_broadcast!(runtime::ServerRuntime)
    step!(runtime.state)
    broadcast!(runtime.gui_clients, metrics_snapshot(runtime.state))
    if runtime.state.params.blender_update_every > 0 &&
       runtime.state.tick % runtime.state.params.blender_update_every == 0
        broadcast!(runtime.blender_clients, blender_snapshot(runtime.state))
    end
end
