using CSV, DataFrames, Statistics

base = "outputs/overnight"
ff = CSV.read(joinpath(base, "firm_failures.csv"), DataFrame)
prod = CSV.read(joinpath(base, "firm_production_diagnostics.csv"), DataFrame)
sw = CSV.read(joinpath(base, "consumer_switch_log.csv"), DataFrame)

window = 40

# Pre-index by firm for speed
prod_by_firm = Dict{Int, DataFrame}()
for g in groupby(prod, :firm_id)
    prod_by_firm[g.firm_id[1]] = g
end
sw_prev_by_firm = Dict{Int, DataFrame}()
for g in groupby(sw, :previous_firm_id)
    k = g.previous_firm_id[1]
    ismissing(k) && continue
    sw_prev_by_firm[Int(k)] = g
end
sw_chosen_by_firm = Dict{Int, DataFrame}()
for g in groupby(sw, :chosen_firm_id)
    k = g.chosen_firm_id[1]
    ismissing(k) && continue
    sw_chosen_by_firm[Int(k)] = g
end

rows = DataFrame(
    failure_tick=Int[], firm_id=Int[], firm_type=Int[],
    pre_revenue_mean=Float64[], pre_revenue_slope=Float64[], pre_revenue_cv=Float64[],
    pre_sales_mean=Float64[], pre_sales_slope=Float64[], pre_sales_cv=Float64[],
    pre_capacity_mean=Float64[], pre_sellthrough_mean=Float64[], pre_stockout_share=Float64[],
    pre_input_scale_mean=Float64[], pre_unsold_mean=Float64[],
    pre_profit_proxy_mean=Float64[],
    pre_switch_out=Int[], pre_switch_in=Int[], pre_net_switch=Int[],
    pre_switch_out_stockout=Int[], pre_switch_out_inactive=Int[], pre_switch_out_over_budget=Int[],
    pre_switch_out_cheaper_share=Float64[],
)

function slope(x::Vector{Float64}, y::Vector{Float64})
    n = length(x)
    n < 2 && return 0.0
    xm = mean(x); ym = mean(y)
    denom = sum((x .- xm).^2)
    denom <= 1e-9 && return 0.0
    return sum((x .- xm) .* (y .- ym)) / denom
end

for r in eachrow(ff)
    fid = Int(r.firm_id)
    ftick = Int(r.tick)
    ftype = Int(r.firm_type)
    lo = max(1, ftick - window)
    hi = ftick - 1

    if !haskey(prod_by_firm, fid)
        continue
    end
    pf = prod_by_firm[fid]
    pwin = pf[(pf.tick .>= lo) .& (pf.tick .<= hi), :]
    n = nrow(pwin)
    n == 0 && continue

    t = Float64.(pwin.tick)
    sales = Float64.(pwin.realized_sales)
    price = Float64.(pwin.goods_price)
    rev = sales .* price
    cap = Float64.(pwin.capacity_raw)
    comm = Float64.(pwin.committed_output)
    sellthrough = rev .* 0.0
    for i in eachindex(sales)
        denom = max(1.0, comm[i])
        sellthrough[i] = sales[i] / denom
    end
    soldout = Float64.(pwin.sold_out)
    input_scale = Float64.(pwin.input_scale)
    unsold = Float64.(pwin.unsold_output)

    # Profit proxy from failure-row cost profile (pre-window cost baseline)
    wage = Float64(r.wages_this_tick)
    crent = Float64(r.commercial_rent_this_tick)
    krent = Float64(r.capital_rental_this_tick)
    prent = Float64(r.process_rental_this_tick)
    incost = Float64(r.input_cost_this_tick)
    cost_baseline = wage + crent + krent + prent + incost
    profit_proxy = rev .- cost_baseline

    out_n = 0
    in_n = 0
    out_stockout = 0
    out_inactive = 0
    out_budget = 0
    cheaper = 0
    priced = 0

    if haskey(sw_prev_by_firm, fid)
        swf = sw_prev_by_firm[fid]
        sww = swf[(swf.tick .>= lo) .& (swf.tick .<= hi) .& (swf.switched .== 1), :]
        out_n = nrow(sww)
        if out_n > 0
            out_stockout = count(==("preferred_stockout"), coalesce.(sww.fallback_reason, ""))
            out_inactive = count(==("preferred_inactive"), coalesce.(sww.fallback_reason, ""))
            out_budget = count(==("over_budget"), coalesce.(sww.fallback_reason, ""))
            for rr in eachrow(sww)
                pc = rr.previous_delivered_cost
                cc = rr.chosen_delivered_cost
                if !ismissing(pc) && !ismissing(cc) && isfinite(pc) && isfinite(cc)
                    priced += 1
                    if cc < pc
                        cheaper += 1
                    end
                end
            end
        end
    end
    if haskey(sw_chosen_by_firm, fid)
        swi = sw_chosen_by_firm[fid]
        swwi = swi[(swi.tick .>= lo) .& (swi.tick .<= hi) .& (swi.switched .== 1), :]
        in_n = nrow(swwi)
    end

    push!(rows, (
        ftick, fid, ftype,
        mean(rev), slope(t, rev), (mean(rev) > 1e-9 ? std(rev)/mean(rev) : 0.0),
        mean(sales), slope(t, sales), (mean(sales) > 1e-9 ? std(sales)/mean(sales) : 0.0),
        mean(cap), mean(sellthrough), mean(soldout),
        mean(input_scale), mean(unsold),
        mean(profit_proxy),
        out_n, in_n, in_n - out_n,
        out_stockout, out_inactive, out_budget,
        (priced > 0 ? cheaper / priced : NaN),
    ))
end

# Cause labels based only on pre-window signals
rows[!, :cause_label] = fill("mixed", nrow(rows))
for i in 1:nrow(rows)
    r = rows[i, :]
    demand_crash = (r.pre_sales_slope < -0.10 && r.pre_sellthrough_mean < 0.50)
    churn_outflow = (r.pre_net_switch < -5)
    stockout_churn = (r.pre_switch_out_stockout >= 5 || r.pre_stockout_share > 0.25)
    input_bottleneck = (r.pre_input_scale_mean < 0.85)
    high_vol = (r.pre_sales_cv > 1.0 || r.pre_revenue_cv > 1.0)

    label = if input_bottleneck && stockout_churn
        "input_bottleneck_stockout"
    elseif stockout_churn
        "stockout_service_failure"
    elseif churn_outflow && demand_crash
        "churn_led_demand_crash"
    elseif demand_crash
        "demand_collapse"
    elseif high_vol
        "high_volatility_margin_thin"
    else
        "mixed_margin_failure"
    end
    rows[i, :cause_label] = label
end

outdir = joinpath(base, "plots")
mkpath(outdir)
CSV.write(joinpath(outdir, "precollapse_failure_rootcause_by_event.csv"), rows)

summary = combine(groupby(rows, :cause_label), nrow => :n_failures)
summary.share = summary.n_failures ./ max(1, nrow(rows))
sort!(summary, :n_failures, rev=true)
CSV.write(joinpath(outdir, "precollapse_failure_rootcause_summary.csv"), summary)

# Core means by label
label_stats = combine(groupby(rows, :cause_label),
    :pre_revenue_slope => mean => :mean_pre_revenue_slope,
    :pre_sales_slope => mean => :mean_pre_sales_slope,
    :pre_sellthrough_mean => mean => :mean_pre_sellthrough,
    :pre_input_scale_mean => mean => :mean_pre_input_scale,
    :pre_net_switch => mean => :mean_pre_net_switch,
    nrow => :n_failures,
)
sort!(label_stats, :n_failures, rev=true)
CSV.write(joinpath(outdir, "precollapse_failure_rootcause_label_stats.csv"), label_stats)

println("wrote: precollapse_failure_rootcause_by_event.csv")
println("wrote: precollapse_failure_rootcause_summary.csv")
println("wrote: precollapse_failure_rootcause_label_stats.csv")
