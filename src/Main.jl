using UrbanABM

params = ModelParams()
runtime = start_server(params=params)

println("Open gui/index.html in a browser. Press Ctrl-C to stop Julia.")
wait()
