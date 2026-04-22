# Urban ABM

This is the first incremental implementation of the urbanization ABM described in `instructions.md`.

The Julia simulation is the authoritative state owner. Browser and Blender clients communicate over websockets and do not compute model transitions.

## Layout

- `src/` Julia model modules
- `gui/index.html` browser control and diagnostics client
- `blender/blender_client.py` Blender websocket visualization client

## Run

Julia is not available on this machine's current `PATH`, so this was not executed locally here. Once Julia is installed:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. src/Main.jl
```

Then open `gui/index.html`.

The GUI websocket defaults to `ws://127.0.0.1:8766`.
The Blender websocket defaults to `ws://127.0.0.1:8765`.

## Headless Use

```julia
using UrbanABM

state = init_state(ModelParams(initial_workers=200, initial_firms=20))
run!(state, 100)
metrics_snapshot(state)
```
