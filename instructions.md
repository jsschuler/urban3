# Urbanization ABM Implementation Brief

## Purpose

Implement an agent-based urbanization model in **Julia**. The model should generate endogenous urban structure through decentralized interactions among workers, firms, a master developer, and outside entrants. The software architecture should support:

- a high-performance Julia simulation core
- behavior implemented through `struct`s and **multiple dispatch**
- parallel execution where safe
- an **HTML / JavaScript GUI** for control and diagnostics
- a **Blender Python client** for 3D visualization
- communication among components via **web sockets**

The Julia simulation is the **authoritative state owner**. The GUI and Blender are clients.

---

# 1. Core modeling principles

## 1.1 Endogeneity
Do **not** hard-code a city center, suburbs, or price gradients. These should emerge from:

- firm production and hiring
- worker job and housing choice
- local rents
- commercial and residential development
- consumer demand
- outside entry
- firm formation and liquidation

## 1.2 Simplicity first
This is a first version. Prefer the simplest rule consistent with the model logic.

## 1.3 Parameters
Anything that plausibly varies across experiments should be parameterized.

## 1.4 No inventories
Firms commit output for the tick. Unsold output is discarded.

## 1.5 No demolition
Units are added or converted, but not demolished in this version.

---

# 2. Software architecture

## 2.1 Main components

### Julia simulation server
Responsible for:
- authoritative state
- all model transitions
- all scheduling
- all diagnostics
- websocket communication

### HTML / JavaScript GUI
Responsible for:
- start / pause / step / reset controls
- parameter editing
- viewing plots and diagnostics
- setting the **Blender update tick count**
- receiving streamed simulation state summaries and diagnostics

### Blender Python client
Responsible for:
- receiving spatial snapshots over websockets
- rendering lots, mixed-use stacking, occupancy, and land-use colors

## 2.2 Communication
All components communicate through **web sockets**.

Suggested message types:
- `control_command`
- `parameter_update`
- `tick_snapshot`
- `diagnostic_snapshot`
- `blender_snapshot`
- `event_log`
- `run_status`

Use JSON for v1.

## 2.3 Authoritative state
The Julia simulation is authoritative:
- GUI never computes model logic
- Blender never computes model logic
- all state transitions happen in Julia only

---

# 3. Julia design requirements

## 3.1 Language and style
Use Julia with:

- `struct`s for type definitions
- `mutable struct` where state mutation is necessary
- **multiple dispatch** for behavior rules
- clear module separation

## 3.2 Suggested module layout

- `Types.jl`
- `Parameters.jl`
- `State.jl`
- `Search.jl`
- `Workers.jl`
- `Firms.jl`
- `Developer.jl`
- `Entrepreneurship.jl`
- `Scheduler.jl`
- `Metrics.jl`
- `Serialization.jl`
- `WebSocketServer.jl`
- `Main.jl`

Optionally break these into folders later.

## 3.3 Dispatch expectations
Use multiple dispatch for:
- worker job search by employment / housing state
- worker housing search by state
- firm review actions by review type
- developer rent adjustment and conversion logic
- entrepreneurship by solo vs coalition founding
- search behaviors by search domain

---

# 4. Parallel execution requirements

## 4.1 Goal
Run in parallel where possible.

## 4.2 Safety rule
Neighborhood Poisson ticks partition neighborhoods in a way that should permit parallel work **without race conditions**.

Use the following general pattern:
- shared memory may be read broadly
- writes during a phase should go to local buffers
- then perform a synchronized commit / merge step

## 4.3 Candidate parallel phases
Potentially parallelize:
- consumer search and purchase proposal generation
- worker job search proposal generation
- worker housing search proposal generation
- firm commercial-space search proposal generation
- diagnostics aggregation
- local developer review proposal generation

## 4.4 Conflict resolution
Conflicts must be resolved before commit, especially for:
- multiple workers trying to rent the same residential unit
- multiple firms trying to rent the same commercial unit
- multiple workers applying to the same firm vacancy
- multiple consumers competing for scarce committed output if needed

---

# 5. Spatial model

## 5.1 Lots
The city consists of spatial lots.

Each lot has:
- integer coordinates `(x, y)`
- residential unit count
- commercial unit count
- occupied residential count
- occupied commercial count
- local residential rent
- local commercial rent

Each lot corresponds to **4 Blender squares**.

## 5.2 Mixed use
Residential and commercial units may both exist on the same lot and may be vertically stacked.

## 5.3 Height
Lot height is:
- total residential units + total commercial units

## 5.4 Distance
Use **taxicab distance** between lots:
- `abs(x1 - x2) + abs(y1 - y2)`

Use this for commuting in v1.

---

# 6. Agent classes

## 6.1 Workers
Each worker should minimally track:
- unique id
- employment status
- housing status
- employer id or `nothing`
- dwelling lot id or `nothing`
- current wage
- savings
- savings rate
- fixed utility vector over goods
- ownership shares in any firms
- job-review clock data
- housing-review clock data
- search parameters / seeds as needed

Workers are identical in productivity for v1.

## 6.2 Firms
Each firm should minimally track:
- unique id
- firm type / good type
- owner-manager ids
- ownership shares
- posted wage for new hires
- worker ids
- current worker wages
- integer capital units
- integer production process count
- commercial units occupied by lot
- total commercial units
- goods price
- committed output for the tick
- realized sales history
- profit history
- review clocks for:
  - price
  - wage
  - labor
  - capital
  - process
  - liquidation
  - commercial-space search

## 6.3 Master developer
There is one master developer routine controlling all lots. Do not model separate developer agents.

---

# 7. Firm types and goods

## 7.1 Firm types
Each firm belongs to a fixed type.

Firm type determines:
- good produced
- production function parameters
- production process purchase price
- capital unit price

## 7.2 Goods
Goods are differentiated by firm type.

Each firm produces exactly one good type.

## 7.3 Fixed technologies
Technology is fixed in v1. Do not model endogenous innovation.

---

# 8. Production

## 8.1 Inputs
Firm production depends on:
- labor
- integer capital units
- commercial space
- discrete production processes

## 8.2 Process-level production
For a process, use a diminishing-returns production function. The intended form is:

- process productivity fixed by firm type
- decreasing returns within a process
- commercial space included as an input

## 8.3 Equal allocation across processes
Inputs are evenly balanced across processes:
- labor split as evenly as possible
- capital split as evenly as possible
- commercial units split as evenly as possible

Because of diminishing returns, this equal allocation rule is the default.

## 8.4 Integer capital
Capital must be **integer-valued**. This is required for meaningful marginal buying and selling behavior.

---

# 9. Commercial-space consolidation

## 9.1 Multi-lot occupation
Firms may occupy commercial space on multiple lots.

## 9.2 Consolidation preference
Firms should prefer to consolidate when possible.

## 9.3 Effective site rule
Introduce a parameter:

- every `k` commercial units on the same lot are equivalent to an extra effective lot / site for production purposes

This should be implemented as a parameterized rule, not hard-coded.

Use this to reward spatial consolidation without forbidding fragmentation.

## 9.4 Commercial search
Firms search for commercial units using the same general search architecture as workers and consumers:
- Poisson neighborhood search
- plus random global sampling

---

# 10. Output commitment, sales, and waste

## 10.1 Commitment
At the beginning of the production phase, a firm commits to a production quantity not exceeding current productive capacity.

## 10.2 Sales
The firm sells as much of the committed output as it can at its posted price.

## 10.3 Waste
Any unsold output is discarded.

## 10.4 No inventory
Do not carry goods over to later ticks.

---

# 11. Firm pricing and wage rules

## 11.1 Goods price
Firms adjust goods prices on their price-review ticks.

Use a simple rule:
- if committed output is fully sold, raise price
- if not all committed output is sold, lower price

Adjustment sizes should be parameters.

## 11.2 Posted wage
Firms post a wage for new hires.

Use a simple rule:
- if hiring fails, raise the posted wage

Keep incumbent wages explicitly stored per worker.

---

# 12. Firm contraction, review, and liquidation

## 12.1 Loss tolerance
Firms do not instantly shrink every tick.

They accept losses until a review arrives on a **Poisson clock** or equivalent stochastic review process.

## 12.2 Modal sales target
At contraction / liquidation review, firms look back over recent realized sales and use the **modal sales count** as the target output level.

If the exact mode is unstable because of continuous values, use discrete / rounded sales counts.

## 12.3 Marginal contraction
Firms sell capital and fire workers at the margin until they are producing at or below the target implied by modal sales.

Because inputs are balanced across processes, marginal cuts are meaningful.

## 12.4 Firing rule
Workers are identical, so firms should fire the **highest-wage workers first**.

## 12.5 Exit rule
A firm exits if it reaches:
- zero workers, or
- zero capital units

This implies nothing operable can be produced.

When a firm exits:
- all workers are laid off
- all commercial units are vacated
- all production processes disappear into the broader economy
- do not assign resale value for liquidating processes

---

# 13. Worker income, savings, and consumption

## 13.1 Income
Worker income consists of:
- wage income
- profit distributions from firm ownership shares

## 13.2 Savings
Each worker sets aside a fixed share of income as savings.

## 13.3 Consumption budget
The remainder is the consumption budget for the tick.

## 13.4 Sequential purchases
Workers consume by buying goods **one unit at a time** until:
- budget is exhausted, or
- no acceptable affordable good is found

This is important. Do not use fixed aggregate demand curves.

---

# 14. Consumer goods choice

## 14.1 Fixed utility vectors
Each worker has a fixed utility vector over goods. Draw this once at initialization or entry and never redraw it.

## 14.2 Search
For each purchase step, the worker samples sellers using:
- Poisson neighborhood search
- plus random global search

This should be parameterized so the model can interpolate between:
- neighborhood-only search
- global search

## 14.3 Choice rule
Among sampled affordable goods, buy the good with:
- highest utility
- at the lowest effective price
- subject to non-exhaustive search

This should be implemented directly, not via a pre-specified demand curve.

---

# 15. Worker labor-market behavior

## 15.1 Unemployment
The model must include unemployment.

Workers become unemployed if:
- they are fired
- their firm exits

## 15.2 Job switching
Workers may change jobs, but not in the same tick as a housing move.

## 15.3 Job search
Use Poisson neighborhood search plus random global sampling for job search.

## 15.4 Homeless / unhoused rule
Workers may be unhoused.

Important sequencing rule:
- if a worker is both **unemployed and unhoused**, they must become **employed first**, then housed later

This avoids simultaneous job and housing coordination.

Use the transition logic:
- unemployed + unhoused -> employed + unhoused -> employed + housed

Do not allow the unemployed + unhoused state to house first in v1.

## 15.5 Outside entry mirrors this logic
Outside entrants should follow the same structure:
- job first
- housing later

---

# 16. Worker housing behavior

## 16.1 Housing search
Workers search for housing on housing-review ticks only.

## 16.2 No simultaneous job and housing move
Workers never switch jobs and dwellings in the same tick.

## 16.3 Search rule
Housing search uses:
- Poisson neighborhood search
- plus random global search

## 16.4 Choice rule
Workers rent the **highest-utility affordable unit** among sampled options.

## 16.5 Commute cost
Commute cost uses **taxicab distance** between home and work lot.

## 16.6 Affordability
Use the simple affordability rule already agreed:
- housing must be affordable after savings and commute costs

Do not overcomplicate this in v1.

## 16.7 Becoming unhoused
A worker becomes unhoused when current rent becomes unaffordable.

---

# 17. Developer rules

## 17.1 Master developer
Use one master developer controlling all lots.

## 17.2 Local rents
Residential and commercial rents are lot-specific.

## 17.3 Rent adjustment
Use a simple rule:
- if units are vacant, rent falls every tick the vacancy persists
- if units are full, rent rises

Vacancy markdowns must be explicit parameters. Use separate parameters for:

- residential full-occupancy rent increase
- commercial full-occupancy rent increase
- residential vacancy rent cut
- commercial vacancy rent cut

The intended v1 vacancy rule is:

- if a lot has any vacant units of a use type, multiply that use type's rent by `1 - vacancy_rent_cut_rate` during the developer update for that tick

This prevents rents from remaining path-dependent after units become vacant.

## 17.4 Unit creation
Residential and commercial units are created **one unit at a time**.

This happens on developer review ticks, with offsets / staggered timing as needed.

## 17.5 Conversion
Commercial and residential units may be converted into one another, but:

- only **vacant** units may be converted
- no demolition in v1

## 17.6 Mixed use
Residential and commercial units may be mixed and stacked on the same lot.

---

# 18. Entrepreneurship and coalition founding

## 18.1 Rare founding
Entrepreneurship should be rare.

Use infrequent review opportunities.

## 18.2 Savings condition
Agents who have accumulated sufficient savings may found firms.

## 18.3 Solo founding
Allow solo founding if savings exceed the required startup threshold.

## 18.4 Coalition founding
Allow coalition formation.

Coalitions should be formed using:
- a Poisson draw
- from the wealthiest agents not currently running firms

## 18.5 Ownership
Ownership shares are assigned by ownership portion.

Profits are redistributed to owners according to ownership shares.

## 18.6 Founders are managers
In v1, owners are managers.

## 18.7 Dissolution
Coalitions only dissolve through bankruptcy in v1.

## 18.8 Firm type choice
Firm type choice should be parameterized.

---

# 19. Outside entry

## 19.1 Entry
Agents may move into the city.

## 19.2 Motivation
This is one reason to avoid fixed demand curves: the city can grow through endogenous entry.

## 19.3 Entry sequencing
Outside entrants should follow the same logic as unhoused unemployed workers:
- first become employed
- then seek housing

---

# 20. Scheduler and tick order

Use the following within-tick order:

1. firm price and wage reviews
2. firm production commitment
3. consumer goods search and purchases
4. realized firm sales and profit calculation
5. firm contraction / expansion reviews
6. layoffs / hiring completion
7. entrepreneurship / coalition formation
8. worker job search
9. worker housing search
10. rent updates by master developer
11. unit additions / conversions
12. outside entry

Entrepreneurship must occur before worker job search so newly founded firms can participate in the same tick's labor market. Otherwise zero-worker entrants can be liquidated before receiving a hiring opportunity.

Keep this fixed unless later experiments intentionally vary it.

---

# 21. Parameters

Anything plausibly variable should be a parameter.

At minimum include parameter groups for:

## 21.1 Spatial
- city dimensions
- lot count or layout
- Blender scaling

## 21.2 Search
- neighborhood search Poisson intensity
- neighborhood radius
- random global sample count
- local/global interpolation weights

Use this same framework for:
- goods search
- job search
- housing search
- commercial-space search

## 21.3 Firms
- goods price adjustment rates
- wage adjustment rates
- review clock rates
- modal-sales lookback window
- startup requirements
- process purchase price by type
- capital unit price by type
- site-consolidation threshold `k`

## 21.4 Technology
- production-function parameters by firm type

## 21.5 Workers
- savings rates
- initial savings distribution
- utility-vector generation parameters

## 21.6 Development
- residential rent adjustment rates
- commercial rent adjustment rates
- residential vacancy rent cut rate
- commercial vacancy rent cut rate
- unit-addition rates
- conversion rates

## 21.7 Entrepreneurship
- solo founding rates
- coalition founding rates
- coalition size limits
- type-selection rules

## 21.8 Entry
- outside entry rates
- outside conditions if modeled explicitly

---

# 22. GUI requirements

The HTML / JavaScript GUI must support:

## 22.1 Run controls
- start
- pause
- single-step
- reset

## 22.2 Parameter controls
- edit parameter values
- load/save parameter sets
- random seed control if implemented

## 22.3 Diagnostics
Include useful diagnostics and plots, at minimum:
- population
- employment
- unemployment
- unhoused count
- firm count
- firm entry / exit
- rents
- wages
- prices
- vacancy rates
- firm size distribution
- commute distances
- goods sales by type
- housing stock and commercial stock
- profit distribution if practical
- market-clearing time series for labor, housing, commercial space, and goods
- search coverage by domain for Poisson/local and random/global search processes
- firm revenue stability and firm lifetime diagnostics

## 22.4 Spatial plots
Include useful spatial diagnostics where practical:
- occupancy maps
- rent maps
- height / density maps
- land-use mix maps

## 22.5 Blender update tick count
The GUI **must** include a control for **Blender update tick count**.

This should allow the user to specify how often the Julia core sends a Blender snapshot, for example:
- every tick
- every 5 ticks
- every 10 ticks
- etc.

This is required.

---

# 23. Blender client requirements

## 23.1 Input
The Blender Python program receives websocket snapshots from Julia.

## 23.2 Visualization
Each lot should be rendered based on:
- lot coordinates
- residential unit count
- commercial unit count
- occupied residential count
- occupied commercial count

## 23.3 Visual mapping
At minimum:
- height = total units on lot
- residential vs commercial distinguished by color

Optional later:
- occupancy distinguished by color shade or transparency

## 23.4 Geometry
Remember:
- each lot corresponds to **4 Blender squares**

---

# 24. Implementation strategy

## 24.1 First milestone
Implement a headless Julia simulation with:
- core types
- scheduler
- basic worker / firm / developer logic
- metrics

## 24.2 Second milestone
Add websocket server and JSON snapshots.

## 24.3 Third milestone
Add HTML / JS GUI.

## 24.4 Fourth milestone
Add Blender Python visualization client.

## 24.5 Fifth milestone
Add parallel execution where safe using partitioned phases and buffered writes.

---

# 25. Coding style expectations

- keep the simulation core modular
- prefer clarity over cleverness
- use strong type definitions
- use multiple dispatch consistently
- keep all behavioral rules parameterized where agreed
- write code so later extension is easy
- keep GUI, Blender, and simulation logic separate

---

# 26. What to preserve from this brief

Do not simplify away these design commitments:

- endogenous urban emergence
- differentiated firm types
- fixed worker utility vectors
- one-unit-at-a-time consumer purchases
- unemployment and unhoused states
- job-first rule for unemployed + unhoused workers
- commercial space as a production input
- integer capital units
- firm liquidation at zero workers or zero capital
- persistent vacancies cut local rent every tick by parameterized vacancy markdown rates
- only vacant units may be converted
- no demolition in v1
- one master developer
- owners as managers in v1
- coalition formation via Poisson draw of wealthiest non-owner agents
- websocket communication among Julia, GUI, and Blender
- GUI control for Blender update tick count

---

# 27. Request to the coding assistant

Please implement this system incrementally, starting with a minimal but working Julia simulation core that respects the model logic and scheduler. Then add websocket communication, GUI support, and Blender integration in modular stages.

---

# 28. Firm supplier network

## 28.1 Motivation

Firms should sell intermediate inputs to other firms as well as final goods to consumers. This creates input-output linkages between firm types and gives firms a direct spatial incentive to locate near their suppliers and customers — an agglomeration force independent of consumer access. Without this, the commercial rent gradient is weaker than the residential gradient, contrary to empirical patterns in real cities.

## 28.2 Firm roles: B2B and B2C

Each firm type is assigned one of two roles:

- **B2B**: sells intermediate goods exclusively to other firms; does not sell to consumers
- **B2C**: sells final goods exclusively to consumers; buys intermediate inputs from B2B firms

There is no hybrid role in this version. A firm type is one or the other.

B2B firms use only labor, capital, and commercial space as inputs. They do not themselves require intermediate inputs. This keeps the supply network shallow (one tier of intermediates feeding final goods producers). Depth can be added later.

## 28.3 Input-output network

The input-output network is defined at the firm-type level as a matrix of input requirements:

- the matrix is fully parameterized: every B2C type may require inputs from every B2B type
- coefficients are drawn randomly at initialization and fixed for the run
- each coefficient specifies units of a given B2B good required per unit of B2C output
- zero coefficients are allowed (a B2C type may not require all B2B types)

Do not hardcode a specific network topology. Generate the matrix from parameters and a seed so it can be varied across experiments.

Do not model self-supply. Firms must buy inputs from other active firms on the market.

## 28.4 Leontief production for B2C firms

B2C production uses Leontief scaling over input availability:

- compute the fill rate for each required input type: `fill_rate = units_acquired / units_required`
- the binding fill rate is the minimum across all required input types
- production capacity is scaled by the binding fill rate
- if any required input has fill rate zero, production is zero

There is no input substitution. Record that this is a Leontief assumption so it can be revisited later.

## 28.5 Input markets

Intermediate goods are traded in a separate market from consumer goods:

- B2B firms commit intermediate output at the start of the production phase, before B2C firms purchase
- B2C firms search for and purchase inputs before committing their own output
- input purchases are settled before B2C production commitment
- unsold intermediate output is discarded at end of tick — no inventory (consistent with section 10.4)

## 28.6 Input search

B2C firms search for each required input type using the same architecture as all other search:
- Poisson neighborhood search
- plus random global sampling

Firms prefer nearby suppliers: proximity reduces effective input cost via a parameterized input travel cost per block (taxicab distance). Among sampled suppliers of a given type, prefer the one with lowest effective cost (posted price plus travel cost).

Input search is batch, not one-unit-at-a-time. Each tick a B2C firm searches for and purchases its full required quantity of each input type from the best available sampled supplier of that type.

## 28.7 Input pricing

B2B firms post an input price. Use the same simple adjustment rule as consumer goods (section 11.1):
- if all committed intermediate output is sold, raise input price
- if not all committed intermediate output is sold, lower input price

Input prices are tracked separately from consumer goods prices. Use separate adjustment rate parameters.

## 28.8 Agglomeration mechanism

The input travel cost creates an endogenous agglomeration force with no hard-coded center:

- B2C firms face lower effective input costs when located near B2B suppliers
- B2B firms earn more sales when located near dense clusters of B2C buyers
- both forces pull toward spatial co-location of B2B and B2C commercial activity
- this should steepen the commercial rent gradient relative to residential, correcting the current ordering

## 28.9 Entrepreneurship

B2B firms follow the same founding rules as B2C firms (section 18). Agents with sufficient savings may found a B2B or B2C firm. Firm type — including role — is drawn according to the parameterized type-selection rule.

## 28.10 Scheduler changes

Insert an input purchasing phase between price reviews and production commitment:

1. firm price and wage reviews (including input price reviews for B2B firms)
2. B2B firm production commitment (intermediate output)
3. B2C firm input search and purchases
4. B2C firm production commitment (scaled by Leontief fill rate)
5. consumer goods search and purchases
6. realized firm sales and profit calculation (both B2B and B2C)
7. firm contraction / expansion reviews
8. layoffs / hiring completion
9. entrepreneurship / coalition formation
10. worker job search
11. worker housing search
12. rent updates by master developer
13. unit additions / conversions
14. outside entry

## 28.11 Parameters

Add the following parameter groups:

- `io_matrix`: input requirement coefficients (B2C type × B2B type → units per output unit); generated randomly from a seed and density parameter
- `io_matrix_seed`: random seed for matrix generation
- `io_matrix_density`: probability any given B2C–B2B pair has a nonzero coefficient
- `input_price_increase_rate`: B2B price increase when sold out
- `input_price_decrease_rate`: B2B price decrease when unsold output remains
- `input_travel_cost_per_block`: effective cost penalty per taxicab block between buyer and supplier commercial lots
- `input_search`: `SearchParams` for firm-to-firm input search (reuse existing structure)

## 28.12 Architectural changes required

Key changes across modules:

- `Types.jl`: add `firm_role` (`:b2b` or `:b2c`) to `FirmType`; add `input_price`, `committed_intermediate_output`, `intermediate_sales_history`, and `inputs_acquired` to `Firm`
- `Parameters.jl`: add io_matrix and input search/pricing parameters
- `Firms.jl`: add B2B output commitment, B2C input search and purchase, input price adjustment, Leontief scaling of production capacity
- `Scheduler.jl`: add B2B commitment phase and B2C input purchasing phase in correct tick positions
- `Metrics.jl`: add input market diagnostics — input fill rate by type, mean input price by type, intermediate sales by type
- `Search.jl`: reuse existing search architecture for input search; no structural changes expected
