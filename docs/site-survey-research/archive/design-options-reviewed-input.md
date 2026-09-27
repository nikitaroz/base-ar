# Base Power Design Options: Reviewed Comparison

## Decision

**Recommend a narrow physical-design project: a customer-duty-driven heat-spreader and external fin-panel optimizer.** Keep battery modules, material choices, the enclosure boundary, and dispatch scenarios fixed. This retains the physical-design goal without making a complete battery redesign the weekend deliverable.

My earlier dispatch recommendation is the safer software fallback, not the best match to the original brief. The attached research is stronger on physical design and on distinguishing simulation from physical evidence; its main weakness is excessive integration scope.

This is an engineering/product judgment, not a measured prediction of hackathon results. We have not installed these dependencies, run a thermal case, contacted a Base engineer, established the team's capabilities, or demonstrated any design improvement in this review.

### Conditions that change the recommendation

- **Choose narrow physical design** if one teammate can own heat-transfer assumptions and solver verification, and geometry changes can drive an auditable thermal calculation by Saturday morning.
- **Choose sizing and reserve-policy software** if working solo without that experience, or if the geometry-to-physics milestone fails. Keep the visual, LEAP-like hardware ambition as a later phase.
- **Choose a liquid cold plate instead** only if a teammate already has a working conjugate heat-transfer case and Base supplies a relevant heat-load map or confirms the problem.

Do not start a full hardware and dispatch co-optimization. Fix one side while optimizing the other, so the demo can attribute improvements to an actual design change.

## Ranking the options

These are qualitative planning assessments under limited time and no proprietary cell, pack, or inverter data. They are not factual claims about Base's internal priorities or judge scores.

| Priority | Option | Original physical-design fit | Credible weekend evidence | Main risk | Decision |
|---|---|---|---|---|---|
| 1 | Narrow heat-spreader/fin-panel optimizer | High | Geometry-linked thermal model, analytical checks, refinement and sensitivity tests | Unknown heat loads and convection | Recommended with an engineering owner |
| 2 | Customer sizing and reserve-policy optimizer | Low–medium | Energy conservation, load/backup scenarios, held-out policy tests | Less distinctive; uncertain tariffs and Base policy | Best fallback and solo choice |
| 3 | Installation/mounting concept generator | High | Geometry checks, center-of-gravity and specified static load cases | Missing site requirements, loads and anchors | Good only if a mentor confirms a real need |
| 4 | Grid-duty-aware hardware sizing | High | Thermal limits mapped to delivered energy under fixed duty cycles | Joint hardware/control search obscures causality | Use as the story for option 1, not a second optimizer |
| 5 | Full thermal-layout plus enclosure co-design | Very high | Too many interacting claims to substantiate quickly | CAD, meshing, thermal, flow, structure, sealing and cost | Reject the proposed breadth |
| 6 | Inverter thermal subassembly | High | A bounded heat sink can be tractable | Unknown loss map, interfaces and cooling boundary | Promote only with relevant Base inputs |
| 7 | Thermal-runaway mitigation | High | Not defensible as a safety result here | Abuse parameters and physical testing | Exclude from claims and optimization |
| 8 | New cell/electrode chemistry | Very high | No lab validation in proposed scope | Cell-specific identification and experiments | Exclude |

For the software option, begin with one or two physical units and a bounded reserve/derating policy, not arbitrary code evolution plus a full ERCOT revenue stack. For the physical option, begin with a subassembly, not per-customer custom factory hardware.

## What each proposal gets right

- **Physical-design proposal:** Keep the fixed-cell concept, explicit assumptions, physics-gated candidate search, CAD outputs, and distinct evidence levels. These are the best parts of either document.
- **Earlier dispatch proposal:** Keep real operating scenarios, transparent baselines, held-out evaluation, and a measurable customer outcome. Remove the promise that simulation establishes physical validity or automatic customer bill savings.
- **Shared principle:** An immutable evaluator must judge candidates; neither the proposer nor a triage model may rewrite heat loads, constraints, test cases, or scoring code to make a candidate look better.

The LEAP 71 connection should be “encode engineering constraints and test generated designs,” not “we recreated Noyron” or “our simulated battery is equivalent to a hot-fired engine.” LEAP 71 describes Noyron as incorporating physics, engineering logic, manufacturing constraints and feedback from actual engine tests ([LEAP 71](https://leap71.com/2025/12/11/leap-71-hot-fires-two-orbital-class-methalox-engines-designed-autonomously-by-noyron/)).

## Corrections that change the decision

### Facts

- **Jev is not OpenEvolve:** Jev evaluates typed questions against state; OpenJev's model card describes a classification/decision model, while OpenEvolve evolves programs using an evaluator ([TypeSafe documentation](https://docs.typesafe.ai/introduction), [OpenJev](https://huggingface.co/AlexWortega/openjev), [OpenEvolve](https://github.com/algorithmicsuperintelligence/openevolve)). My earlier substitution was wrong; treat them as separate architectural options.
- **Power rating is public:** Base lists a residential BESS at 20 kW / 39.2 kWh, without qualifying that power as continuous or peak on the utility page ([Base utility offering](https://www.basepowercompany.com/utilities)). Use it as a reference rating, not confirmation of every Core revision or its charge limits.
- **Aging is not calibrated to Base:** BLAST-Lite warns that its cell models extrapolate from limited-duration aging data, omit important failure modes, and should be treated qualitatively for long-term predictions ([BLAST-Lite](https://github.com/NatLabRockies/BLAST-Lite)). A public LFP model is a sensitivity case, not evidence for a specific Base pack's lifetime.
- **Software compatibility remains untested:** liionpack is in maintenance mode, and its documentation describes turning a 1D PyBaMM model into a pack model ([liionpack](https://github.com/pybamm-team/liionpack)). Do not make it another mandatory layer.

### Reasoning and claims

- **Hardware is not ruled out:** “Power company, not a battery company” is a prompt about value, not a ban on hardware tooling; Base itself describes designing and manufacturing purpose-built hardware ([hackathon guide](https://common-scooter-829.notion.site/Base-AITX-Talent-Hackathon-3e01e636288e80a7b914c993f90ae6c5), [Base utility offering](https://www.basepowercompany.com/utilities)). A hardware tool still needs a named internal user and a customer benefit.
- **Numerical agreement is not reality:** Two models agreeing is useful verification, but shared incorrect assumptions can make both wrong. The demo must separate numerical verification, scenario performance, calibration status, and physical testing.
- **Reserve is mode-dependent:** In the proposed evaluator, grid-connected operation should preserve the chosen reserve; outage operation should release it down to the physical minimum. Otherwise the test defeats the purpose of backup.
- **Customer and operator value differ:** Do not add “member savings” to “arbitrage” unless billing and settlement explain who receives each benefit. Report modeled backup service separately from operator economic scenarios.
- **Optimum needs a qualifier:** Say “best candidate found in this search” or “nondominated among evaluated feasible designs,” not “the optimal battery.”

## The physical MVP I would actually build

### Product and user

Proposed pitch: “BaseForge searches physical thermal-design variants against customer and fleet duty cycles, then shows which concepts deliver more useful energy within declared thermal and packaging limits.”

The first user is a Base thermal or hardware engineer, not a homeowner ordering a bespoke battery. The customer story is reliable backup and less modeled thermal derating; the engineering story is faster concept screening. Whether those are unmet Base needs must be confirmed with a mentor.

### Keep fixed

- **Reference assembly:** Fixed abstract modules, electrical capacity, module positions, enclosure seal boundary and allowed installation clearances. Clearly label it “Base-like reference,” not a reconstruction of Core.
- **Materials:** One declared material for the first run. Any later material alternatives come from a fixed property/cost table, not AI-invented conductivities.
- **Loads:** Identical heat-generation and battery-power traces for all candidates in each scenario.
- **Controls:** One deterministic reserve and temperature-derating rule, unchanged between candidate designs.
- **Uncertainty:** Contact resistance, convection assumptions, heat-load uncertainty and site exposure are test inputs, not free optimization knobs.

### Let the search change five geometric variables

- **Spreader thickness:** Within a declared allowable interval.
- **Thermal bridge width:** Within contact and packaging constraints.
- **External fin count:** Integer choices from a small predefined set.
- **Fin height:** Limited by the installation envelope.
- **Fin thickness:** Limited by manufacturing assumptions and minimum spacing.

Use a fixed topology first. Different counts and dimensions are legitimate parametric physical design, but do not call them unrestricted topology discovery.

### Objective and constraints

Use two primary objectives: worst-case predicted maximum temperature and added material mass. Report temperature spread and modeled energy lost to thermal derating as secondary outcomes. Avoid claiming optimized noise, sealing, fatigue, manufacturing cost, and lifetime unless each has a defined, supported model.

Five proposed hard gates:

- **Envelope and access:** Geometry remains inside the reference envelope and outside service clearances.
- **Geometric integrity:** Positive dimensions, no unintended interference, and valid solids.
- **Feature spacing:** Minimum thickness and fin gaps consistent with an explicitly assumed process.
- **Material budget:** Total added mass below a fixed budget.
- **Scenario temperature:** Predicted temperatures below an explicitly assumed operating threshold across the chosen uncertainty cases.

Gate five is an assumed design-screening limit, not a certified battery safety boundary.

### Three scenarios and one holdout

- **Hot grid-duty day:** Use a declared dispatch trace and ambient profile.
- **Outage after grid duty:** Start from the actual prior simulated state, then measure critical-load service without resetting SOC.
- **Adverse installation:** Higher ambient or poorer heat rejection; model solar exposure only if the heat balance explicitly includes it.
- **Held-out test:** An unseen duty/ambient combination and at least one asymmetric module heat-load case.

Prefer one well-understood customer profile and a few defensible windows over a rushed multi-year ingestion pipeline. If using simulated household profiles, do not label them measured Base telemetry or replay them as a specific historical storm without matching weather.

## The geometry-to-physics bridge

This is the decisive engineering task. A 3D rendering beside an unrelated battery simulator is not a physical-design loop.

The same immutable parameter record must generate CAD and the thermal model. Derive lengths, contact areas, volumes and conductive paths from that record; compute thermal conductances from material and geometry rather than letting an AI assign an attractive thermal resistance.

For a reduced network, use a declared energy balance at each node:

\[
C_i \frac{dT_i}{dt}
= \dot Q_i
+ \sum_j G_{ij}(T_j-T_i)
- h_i A_i (T_i-T_{\mathrm{amb}}).
\]

Here \(C_i\) is thermal capacitance, \(G_{ij}\) a geometry-derived conductance, and \(\dot Q_i\) an externally specified heat source. Add radiation, solar input, cooling parasitics or other terms only if they are actually implemented; list omissions.

This equation is the proposed model, not a validated description of Base Core. Use analytical slab-resistance and transient limiting cases to verify implementation before optimizing it.

Dense fins cannot receive unlimited cooling credit merely because CAD surface area increases. The model must account for fin efficiency and spacing-sensitive convection, or impose conservative spacing bounds and sweep convection uncertainty. If the winner exists only under one optimistic heat-transfer assumption, flag it as inconclusive.

For a lightweight second solver, use a spatially resolved 2D conduction calculation with the same heat loads and explicit convection boundaries. Refine the spatial grid and time step; describe it as a conduction cross-check, not 3D CFD or physical validation. Add OpenFOAM only if a relevant baseline case, mesh, solver and boundary conditions work early enough to compare baseline and finalist consistently.

## Minimal stack and AI roles

| Component | Recommendation | Keep it honest |
|---|---|---|
| Parametric CAD | CadQuery | Documented STEP/STL export supports real geometry deliverables, not certification ([CadQuery](https://cadquery.readthedocs.io/en/latest/importexport.html?highlight=step)) |
| Search | Bounded random search first; optionally Optuna | Always keep the random-search baseline with the same trial budget |
| Thermal evaluator | Geometry-derived network plus independent conduction check | Numerical tests and uncertainty ranges are mandatory |
| Battery heat source | Declared reference model; optional PyBaMM | PyBaMM supplies battery equations/models/parameters; geometry-to-pack mapping is still your implementation responsibility ([PyBaMM](https://docs.pybamm.org/en/stable/source/user_guide/fundamentals/index.html)) |
| AI proposer | Existing accessible LLM returning schema-validated candidate parameters | Never let it edit evaluator, test cases or material properties |
| Jev/OpenJev | Optional candidate prioritization or failure explanation | Typed decisions are not heat-transfer predictions or calibrated engineering confidence ([TypeSafe](https://docs.typesafe.ai/introduction), [OpenJev](https://huggingface.co/AlexWortega/openjev)) |
| Trial records | SQLite or append-only records with design and scenario hashes | Store raw results, errors, solver settings, seed and evidence status |
| Dashboard | One candidate comparison screen | 3D geometry, thermal curves, Pareto points, baseline, evidence card |

Do not require PicoGK, liionpack, OpenMDAO, GridLAB-D, CalculiX, BLAST-Lite and OpenFOAM simultaneously. My recommendation excludes them from the critical path, not because they lack value but because every extra interface needs verification.

A useful AI experiment is to compare bounded random search with LLM-guided proposals under identical evaluation budgets. If AI does not improve the result, report that honestly and demonstrate its contribution to interpreting constraints or failures instead.

Jev should not be added solely for branding. Deterministic code is the right tool for NaNs, temperature thresholds, convergence status and failed constraints; model-based routing is optional when the choice truly requires contextual interpretation.

## Validation and demo contract

Every candidate card should have independent fields, not one green “physics PASS” badge:

- **Geometry checks:** Pass/fail against the declared rules.
- **Numerical checks:** Energy residual, finite outputs, convergence and refinement results.
- **Scenario checks:** Which named scenarios and uncertainty cases passed or failed.
- **Calibration:** Uncalibrated reference, or exactly which measurements were used.
- **Physical evidence:** None unless a real relevant experiment is performed.

Physical testing and product safety evaluation remain outside the proposed software demo; UL 9540A is a test methodology for thermal-runaway fire propagation, not a status obtainable by running a thermal solver ([UL Solutions](https://www.ul.com/services/ul-9540a-test-method)).

Define numerical tolerances before searching and never loosen them for the winner. Compare baseline and finalist at identical heat loads, material budget, duty cycles, initial conditions and boundary assumptions.

For orchestration, give every job a unique design/scenario/version key, persist completion, bound retries, and distinguish solver failure from physics rejection. A timeout is “not evaluated,” not “physically infeasible.” Demonstrate killing a worker and resuming without losing or duplicating completed trials only if claiming the orchestration track.

## Track choice and actual weekend schedule

The guide awards 30 points each for execution and track fit, 20 for value and 20 for innovation; it allows up to two tracks and sets submission at Sunday September 27, 11 AM ([hackathon guide](https://common-scooter-829.notion.site/Base-AITX-Talent-Hackathon-3e01e636288e80a7b914c993f90ae6c5)). From the user's Friday 9:30 PM timestamp that leaves 37.5 wall-clock hours, not a fresh 48-hour build.

- **Orchestration:** Strongest defensible physical-project entry if fault recovery and reproducibility actually work. Independent candidate simulations give a natural workload.
- **Commercializable:** Second choice only after a mentor confirms the internal engineering tool fits the track and identifies its intended user.
- **Open Grid Data:** Do not enter just because a price CSV appears. The project needs a substantive, demonstrated grid-data insight.

These track recommendations are my interpretation, not organizer approval.

| Time, America/Chicago | Deliverable | Decision gate |
|---|---|---|
| Friday night | Fixed scope, one baseline geometry, declared thermal inputs, analytic checks | No new major simulator integrations after this scope decision |
| Saturday 8–10 AM | Geometry-to-thermal mapping and one complete comparison | If it cannot run or explain its physics, switch to software fallback |
| Saturday 10 AM–1 PM | Baseline versus bounded random search, records, mentor feedback | Confirm customer problem and missing parameters |
| Saturday 1–5 PM | AI-guided search if useful, uncertainty cases, held-out scenario, conduction refinement | Discard improvements that disappear under fair comparisons |
| Saturday 5–9 PM | Dashboard, evidence cards, worker recovery, rough video | Feature freeze; no new multiphysics stack |
| Sunday 8–10:15 AM | Final reproducible run, 4–5 minute video, README, submission | Submit early; retain a saved demo replay |

These blocks are scope allocations, not guaranteed implementation times. Allow sleep and split work only if teammates are actually available.

## What to ask Base before committing further

- **Pain point:** “Would screening a thermal subassembly against fleet duty cycles help your team, or is installation/controls a bigger bottleneck?”
- **Reference inputs:** “Can you share a nonproprietary heat-load range, operating duty trace, or permitted reference thermal interface?”
- **Thermal architecture:** “Is passive enclosure heat rejection a relevant research target, or would this be disconnected from your product?”
- **Power interpretation:** “Does the 20 kW reference mean continuous output, and which charge, ambient and duration limits apply?”
- **Value metric:** “What matters most: delivered energy before derating, mass, installation footprint, serviceability, or something else?”
- **Track eligibility:** “Does an internal engineering design tool qualify for Commercializable, and how does the two-week rule apply to model weights and dependency versions?”

If the passive thermal target is not relevant, preserve the pipeline and pivot to the subassembly they name. Do not imply the reference design improves Base Core without the relevant inputs and baseline.

## Review coverage and annotation key

Both proposals were read end to end. This is a decision-focused review, not an exhaustive verification of every paper, reference or software feature: eight pivotal claims were checked, with four verified, two refuted and two inconclusive.

Fifteen material issues are annotated below: eight high-severity and seven medium-severity. No separate low-severity proofreading or privacy finding changes the recommendation.

The original text is preserved in the following sections. Each numbered blockquote is a reviewer comment with a suggested replacement, not an implemented code change; Markdown has no native Word-style tracked changes. Original claims marked below are superseded by the review.

Download this annotated document to view all comments and suggested replacements. If useful, the next step is to choose the physical or fallback route based on team size and who can own thermal verification.

---

## Annotated physical-design proposal

# Base Power Hackathon: AI-Generated Physical Battery Design Options

## Direct recommendation

The strongest physical-design concept is **an AI-driven thermal and packaging co-designer for a Base-like residential battery**. It would generate hundreds of module layouts, thermal spreaders or cold plates, structural supports, and sealed enclosure features; reject invalid candidates with deterministic rules; evaluate viable candidates with progressively higher-fidelity physics; and present a Pareto frontier rather than claiming one magical “AI-designed” answer.

This is close to LEAP 71’s computational-engineering philosophy without pretending to reproduce Noyron. LEAP 71 describes its method as code that encodes physics, engineering logic, manufacturing constraints, and real-world feedback, while PicoGK is an open-source geometry foundation rather than the proprietary engineering intelligence itself.[^1][^2][^3]

For a 48-hour hackathon, do **not** attempt to redesign battery chemistry, certify safety, or build a full multiphysics digital twin. Build a believable vertical slice: parameterized geometry, customer-derived operating scenarios, a fast electrothermal model, optimization across perhaps tens to hundreds of candidates, one or two higher-fidelity thermal validations, and a transparent dashboard that shows why a design won.

## Product constraints

Base Core provides a useful public reference envelope: 39.2 kWh, 120/240 V, a 50-millisecond automatic transfer, a published operating range of -22 to 122°F, dimensions of roughly 35.9 by 30.68 by 22 inches, and whole-home backup lasting approximately 12–18 hours under typical use or up to 36 hours under reduced use. Base also describes its utility product as a 20 kW/39.2 kWh residential BESS that can respond in under a second and participate in bulk peaking, large-load interconnection, and distribution-grid support.[^4][^5][^6]

Those facts point to the real customer problem: the battery must serve two masters. It must preserve household backup and reliability while also cycling for grid value. Base says its systems charge when demand is low, discharge when the grid needs support, and automatically support the home during an outage. A useful design tool therefore should evaluate customer duty cycles—not merely a constant laboratory current.[^7]

Public information is not enough to reconstruct Base Core’s internals. Treat all cell dimensions, module count, cooling architecture, heat-generation coefficients, materials, and costs as **explicit assumptions**, not facts about Base hardware. The demo should be branded as a “Base-like reference system” unless Base supplies internal parameters during the event.

## Design paths

| Option | What the AI changes | Physics to test | Customer or Base value | Hackathon fit |
|---|---|---|---|---|
| Thermal-layout co-design | Module spacing, orientation, heat spreaders, conduction paths, cold-plate channels, sensor positions | Cell heat generation, pack temperature, temperature spread, pressure loss, parasitic cooling energy | Longer life, safer temperature margins, more usable dispatch, lower noise | **Best overall** |
| Sealed enclosure design | Wall thickness, ribs, external fins, internal baffles, seals, feet, lifting and service features | Heat transfer, stiffness, vibration proxy, weather exposure, mass | Outdoor reliability, manufacturability, quieter operation, easier service | **Strong visual add-on** |
| Customer-specific pack sizing | Number of units/modules, usable state-of-charge window, reserve policy, inverter limit | Load-flow, outage runtime, cycle aging, peak demand | Better backup promises and lower total system cost | **Best customer story, less physical** |
| Grid-dispatch-aware hardware sizing | Thermal system, power limit, cell count, cooling capacity sized around actual grid duty | Electrothermal aging plus dispatch simulation | More grid revenue without sacrificing backup | **Best hybrid hardware/software story** |
| Installation and mounting kit | Base plate, anchoring, wall clearance, conduit path, service envelope | Structural loads, tilt, simple wind/flood proxies, installation constraints | Faster installs and fewer site failures | **Practical and buildable** |
| Power electronics thermal design | Inverter placement, busbar/cable routing, heat sinks, fan or pump settings | Electrical losses, hot spots, thermal resistance, voltage drop | Higher continuous power and reliability | **Good but needs missing internal data** |
| Thermal-runaway mitigation | Module spacing, barriers, vent path, sacrificial zones | Abuse heat release, gas generation, propagation | Safety and regulatory value | **High impact, too risky for primary demo** |
| New cell or electrode design | Electrode thickness, porosity, particle size, chemistry parameters | Detailed electrochemistry and degradation | Potential energy-density or lifetime gains | **Poor fit without lab data** |

## Recommended concept

### Name

**Base Forge — Customer-Duty-Driven Battery Co-Designer**

### Core proposition

Given a customer archetype, climate, installation constraints, and fleet-dispatch duty cycle, Base Forge generates a family of manufacturable battery pack and thermal-management concepts. It then runs a physics-gated tournament and returns several non-dominated designs—for example, lowest peak temperature, lowest mass, lowest cooling power, best backup duration, and lowest estimated cost—along with the evidence behind every score.

> Review 6 | MEDIUM | narrative_logic: Rule-compliant CAD is not demonstrated manufacturability or weather sealing. The proposed gates omit process tolerances, assembly, joining, and actual sealing tests.
>
> Suggested replacement: generates a family of battery thermal-management concepts that satisfy specified preliminary geometry and manufacturing rules.


The winning demo should show that the same computational model can produce different valid “phenotypes,” much as LEAP 71 reports generating both bell-nozzle and aerospike engines from shared computational logic. The analogy is not “an LLM drew a battery.” It is “engineering knowledge was encoded once, then reused to generate and test a design family.”[^2]

### What varies

- Module arrangement: rows, columns, orientation, gaps, and symmetry.
- Thermal interfaces: spreader thickness, conductivity, contact resistance, and gap-pad thickness.

> Review 4 | HIGH | narrative_logic: Conductivity and contact resistance cannot be freely improved at no cost by an optimizer. Fix material properties or link them to discrete materials and geometry; treat uncertain interfaces as sensitivity inputs.
>
> Suggested replacement: - Vary geometry and catalog material choices within declared bounds; derive conductivity from material and sample contact resistance as uncertainty.

- Cooling topology: passive conduction, external fins, straight channels, serpentine channels, or branching channels.
- Flow system: inlet/outlet location, channel width, pump rate, and one-sided versus two-sided cooling.
- Enclosure: dimensions within a reference envelope, wall thickness, ribs, service panels, lifting points, mounting feet, and external fin pattern.
- Instrumentation: number and location of temperature sensors.
- Controls: maximum charge/discharge power, state-of-charge reserve, temperature derating threshold, and cooling-control policy.

### Objectives

- Minimize maximum cell temperature.
- Minimize cell-to-cell temperature spread.
- Minimize pumping or fan power.
- Minimize enclosure mass and estimated material cost.
- Minimize degradation over a defined customer/grid duty cycle.
- Maximize outage reserve and delivered grid energy.
- Respect hard constraints for geometry, temperature, pressure drop, service access, power, and manufacturability.

Temperature uniformity matters because cooling topology strongly affects pack temperature distribution. Published work varies tube dimensions, spacing, gap filler, cooling direction, and pump settings, then compares maximum, mean, and temperature spread. Other studies find topology-optimized cold plates can outperform conventional straight or serpentine channels, although irregular channel widths can create manufacturing difficulties. That last caveat is essential: manufacturability must be a hard gate, not an afterthought.[^8][^9][^10][^11][^12]

## Option details

### Thermal-layout co-design

This is the closest match to the “AI-designed rocket engine” inspiration. The system creates geometry, predicts heat generation under realistic duty cycles, runs fast pack-level thermal simulations, and promotes only the best candidates to computational fluid dynamics.

A good first design space uses fixed cells or abstract heat-generating modules and varies only layout and cooling. This avoids unsupported claims about chemistry while still producing distinctive physical geometry. A cooling-guided diffusion model has been demonstrated for generating feasible cell layouts, but that research required more than 100,000 generated configurations; training an equivalent model during a weekend is unrealistic. For the hackathon, use optimization to generate the candidates and reserve a vision model or LLM for explanations, constraint extraction, and failure classification.[^13]

**Demo output:** an interactive 3D pack, a heat map, a candidate leaderboard, and a Pareto plot comparing peak temperature, thermal spread, cooling energy, mass, and cost.

### Sealed enclosure co-design

This path focuses on the visible industrial object: a sealed outdoor cabinet that manages heat, rain, flooding, service access, noise, and structural support. Base publicly highlights outdoor operation over a wide temperature range, IP67 submersion testing, high-pressure water testing, and flash-flood testing, so weather resistance is central to the customer experience.[^4]

The best scope is not a complete certification claim. Generate external fins, internal thermal bridges, ribs, feet, and mounting arrangements while preserving a sealed boundary. Score each concept for thermal resistance, material volume, simple structural deflection, minimum feature size, tool access, and enclosure dimensions.

**Demo output:** three customer-environment variants—hot Austin wall exposure, shaded installation, and flood-prone site—with visibly different but rule-compliant enclosures.

### Customer-specific physical configuration

This option turns home load and climate into a recommended physical configuration: one or two battery units, thermal capacity, reserve policy, and installation placement. Base already indicates that one or two units may provide approximately 36–72 hours under reduced consumption and that actual duration depends on usage.[^14][^15]

Use public ResStock end-use profiles rather than invented household curves. The national dataset includes annual 15-minute profiles separated by end use and is derived from hundreds of thousands of building energy models. The tool can choose representative Texas customer archetypes and test air conditioning, electric water heating, EV charging, and outage scenarios.[^16]

**Demo output:** “For this customer profile and weather week, Concept B preserves critical-load backup while allowing more grid dispatch than Concept A.” This is the clearest customer-facing story but needs the physical-geometry component to feel distinct from an ordinary energy-management project.

### Dispatch-aware hardware sizing

This hybrid option asks: **What hardware design best survives the actual work Base asks it to do?** The optimizer changes thermal capacity, module arrangement, and operating limits while a dispatch simulator alternates between grid services and outage reserve.

It aligns especially well with Base’s vertically integrated model, in which hardware, software, installation, service, and fleet dispatch operate as one system. Its key metric should be lifetime value or energy delivered subject to temperature, degradation, and backup constraints—not raw energy density.[^5][^17]

**Demo output:** compare a “backup-first” pack, a “grid-first” pack, and a Pareto-balanced design using identical customer scenarios.

### Installation hardware

An AI-generated mounting and installation system is less glamorous but may be highly relevant to a company installing hardware at scale. Candidate designs can vary base plates, adjustable feet, anchor locations, cable/conduit channels, lifting points, and required wall clearance.

Use parametric CAD and a simplified structural solver to verify mass, center of gravity, bolt loads, and static deflection. Add deterministic installation rules: technician access, standardized fasteners, minimum tool clearance, flat-pack shipping volume, and no obstruction of service panels.

**Demo output:** automatically adapt a mounting kit to three site scans or manually entered site constraints. This is a strong fallback if detailed battery thermal data is unavailable.

### Power-electronics cooling

A smaller subassembly—an inverter heat sink or cold plate—can produce attractive, LEAP-like branching geometry. It is easier to simulate than a full pack and can be manufactured as a 3D-printed prototype.

The limitation is relevance: without Base’s actual inverter losses, device locations, mounting surface, and coolant or airflow constraints, the result becomes generic. Use this only if mentors provide a real heat-load map or component envelope.

### Safety architecture

Thermal-runaway containment and venting are crucial real-world problems, but a hackathon simulation cannot establish safety. UL describes UL 9540A as the national test method for fire propagation associated with thermal runaway, with cell-, module-, unit-, and installation-level evaluation; residential systems retain unit-level testing.[^18][^19]

A concept tool may visualize module separation, barrier placement, heat flux, and likely vent paths, but it must label these as preliminary engineering analyses. Do not produce a “safe/unsafe” certification score, simulate explosive gases with guessed parameters, or claim compliance.

### Cell and chemistry design

PyBaMM can model electrode-level parameters, degradation mechanisms, and experiments, so it is technically possible to optimize electrode thickness, porosity, particle size, and charge protocols. It is not the right primary hackathon target because useful validation requires cell-specific parameters and laboratory data.[^20][^21]

Keep chemistry fixed to a known public LFP parameter set. If the team wants one chemistry-related feature, optimize the **operating policy**—state-of-charge window, maximum C-rate, and temperature derating—rather than claiming to invent a new cell.

## Open-source stack

| Layer | Recommended tool | Role |
|---|---|---|
| Parametric geometry | CadQuery | Python-native assemblies and STEP/STL export; strong fit for agent-driven iteration[^22][^23] |
| LEAP-style geometry | PicoGK + ShapeKernel | Voxel and implicit geometry for organic channels, fins, and lattices; Apache-2.0, but C# adds integration overhead[^1][^24] |
| Cell physics | PyBaMM | Fast electrochemical, thermal, and degradation models with reusable parameters[^20][^21] |
| Pack network | liionpack | Series/parallel electrical and thermal simulation across many cells using PyBaMM[^25] |
| CFD and conjugate heat transfer | OpenFOAM | Higher-fidelity airflow, coolant flow, and heat-transfer validation[^26][^27][^28] |
| Structural/thermal FEA | CalculiX | Open-source static, dynamic, nonlinear, and thermal finite-element analysis[^29] |
| Grid/customer simulation | GridLAB-D or OpenDSS | Residential loads, DER behavior, batteries, and distribution-system effects[^30][^31] |
| Optimization | Optuna for MVP; OpenMDAO later | Constrained multi-objective search and Pareto analysis; OpenMDAO supports coupled multidisciplinary optimization[^32][^33] |
| Load data | ResStock | Public 15-minute residential end-use load profiles[^34][^16] |
| Decision layer | Jev or an open Jev-style model | Candidate triage, typed scoring, routing, and uncertainty flags—not physics[^35][^36] |

### Geometry choice

Use **CadQuery first** because the whole pipeline can remain in Python and it exports engineering formats such as STEP. Add PicoGK only for one signature element—perhaps an organic cold plate, external fin field, or lattice heat spreader. PicoGK is genuinely open source, but LEAP 71 explicitly distinguishes its foundational geometry libraries from engineering design logic.[^37][^1]

### Physics hierarchy

1. **Rules and geometry checks:** collisions, minimum wall/channel size, envelope, sealing boundary, service clearance, and connector access.
2. **Fast lumped model:** energy balance and thermal-resistance network for every candidate.
3. **PyBaMM/SPMe or equivalent-circuit electrothermal model:** heat generation and voltage behavior for finalists.
4. **liionpack pack model:** electrical and thermal nonuniformity for a small finalist set.
5. **OpenFOAM validation:** detailed thermal/flow analysis for the top one to three designs.

> Review 3 | MEDIUM | narrative_logic: A solver name does not establish higher fidelity: boundary conditions, heat sources, mesh convergence, and the baseline must match. Do not make an unfamiliar CFD integration the critical path; the same assumptions can cause two solvers to agree and still be wrong.
>
> Suggested replacement: 5. Independently cross-check the baseline and finalists with a resolved conduction model and refinement tests; add OpenFOAM only if a working, relevant case is already available.

6. **CalculiX check:** basic enclosure or cold-plate structural/thermal stress for the winner.

This fidelity ladder is what keeps the workflow plausible. High-fidelity simulation on every candidate would be too slow; a pure surrogate would be fast but untrustworthy. Early-stage battery cooling research likewise uses reduced models to preselect candidates before more detailed analysis.[^9][^8]

## Jev’s correct role

Jev is **not a world model, CFD solver, finite-element model, or source of physical truth**. It is designed to turn application state and typed questions into constrained choices, scores, yes/no judgments, and probabilities. OpenJev projects imitate that decision interface; they are independent implementations rather than the official Jev model or verified reproductions of its training.[^35][^38][^39]

Use Jev or an open equivalent for decisions such as:

- Is this solver run numerically trustworthy, suspect, or failed?

> Review 2 | HIGH | narrative_logic: Solver acceptance must come from deterministic residual, convergence, finite-value, and conservation tests, not a learned judgment. Jev can summarize failures or route already-valid candidates, but cannot override a failed numerical gate.
>
> Suggested replacement: - Explain solver failures after deterministic numerical checks; optionally prioritize already-valid candidates for further evaluation.

- Which fidelity level should evaluate this candidate next?
- Which failed constraint best explains rejection?
- Is the design ready for promotion to CFD?
- Which customer scenario is most adversarial for this candidate?
- Does the generated engineering explanation agree with the simulator outputs?

Never let Jev directly declare that a design “works.” A candidate works in the virtual prototype only when deterministic constraints pass and solver outputs remain within declared limits. Physical tests are still necessary; LEAP 71 itself emphasizes feeding hot-fire measurements back into Noyron and reports that real-world transients exposed issues despite successful core predictions.[^40][^2]

## System architecture

```text
Customer archetype + weather + grid duty + product envelope
                         |
                         v
              Requirements compiler
         hard constraints + objective weights
                         |
                         v
       Parametric design generator (CadQuery/PicoGK)
                         |
                         v
       Geometry/manufacturing validity gate
                         |
                         v
  Fast electrothermal evaluation (PyBaMM + reduced pack model)
                         |
             +-----------+-----------+
             |                       |
             v                       v
       Optimizer                 Jev decision layer
   proposes next trials      triages/ranks/explains only
             |                       |
             +-----------+-----------+
                         v
              Pareto candidate set
                         |
                         v
      OpenFOAM/CalculiX finalist validation
                         |
                         v
        3D design + evidence card + assumptions
```

Store every trial as a structured record: input parameters, geometry hash, solver version, mesh settings, convergence result, metrics, constraint violations, and artifact locations. This makes the demo auditable and prevents the AI layer from rewriting history.

## Validation contract

Every design card should show four evidence levels:

- **Geometry-valid:** no collisions; envelope, wall thickness, service, and manufacturing rules pass.
- **Model-valid:** solver converged; mesh/time-step checks pass; energy balance is within tolerance.
- **Scenario-valid:** candidate passes all selected customer, weather, outage, and grid-duty scenarios.
- **Physically validated:** requires bench or field testing and therefore remains false during the hackathon.

This labeling is important because simulation cannot replace certification or physical abuse testing. UL 9540A evaluates real thermal-runaway and fire behavior across battery-system levels.[^41][^18]

## Weekend scope

### Must build

- One parameterized reference pack or thermal subassembly.
- Three to six meaningful design variables.
- Five hard constraints.
- A fast thermal/electrical evaluator.
- Multi-objective optimization.
- A customer/climate duty-cycle selector.
- 3D visualization plus temperature and Pareto views.
- Full assumptions and solver provenance.

### Should build

- One OpenFOAM validation of the baseline and winner.
- One generated STEP/STL artifact.
- Jev-based run triage or candidate promotion.

> Review 7 | MEDIUM | narrative_logic: Keep this optional until the exact dependency/checkpoint is checked against the event's two-week open-source rule. This review has not established OpenJev checkpoint eligibility or API access.
>
> Suggested replacement: - Optional Jev-based prioritization after deterministic checks, contingent on model access and organizer-confirmed dependency eligibility.

- A comparison among baseline, hottest-running candidate, and optimized winner.

### Avoid

- Training a new foundation or diffusion model.
- Full thermal-runaway or gas-explosion simulation with guessed parameters.
- Claiming UL compliance.
- Reconstructing proprietary Base Core internals.
- Running CFD inside the inner optimization loop.
- Letting an LLM generate arbitrary CAD code without geometry and manufacturing gates.

## Build sequence

### Hours 0–4

Lock the concept, assumptions, and judging story. Create a rectangular reference enclosure based on public external dimensions, use abstract modules, define one Texas customer duty cycle, and choose five objectives and five hard constraints.

### Hours 4–12

Implement the parameterized geometry and reduced thermal model. Validate the baseline with hand calculations and unit tests before adding AI.

### Hours 12–24

Connect Optuna, generate candidate records, render the Pareto frontier, and create design cards. Add ResStock-derived or event-provided customer profiles.

### Hours 24–36

Run one or two higher-fidelity cases in OpenFOAM, add the Jev decision layer for promotion and failure classification, and export the finalist geometry.

### Hours 36–48

> Review 5 | MEDIUM | narrative_logic: At the user's Friday 9:30 PM timestamp only 37.5 wall-clock hours remain until Sunday 11 AM, before allowing sleep, recording, and submission. This block extends beyond the deadline.
>
> Suggested replacement: ### Sunday 8–10:15 AM: final checks, recording, and early submission


Freeze the pipeline, rehearse a three-minute story, record backup video, and prepare screenshots in case a live CFD run fails. The live demo should replay stored validated trials rather than depend on completing expensive simulations on stage.

## Pitch narrative

1. **Problem:** residential batteries are designed against generic specifications, but Base batteries experience different climates, household loads, outages, and grid-dispatch patterns.
2. **Insight:** the optimal physical design depends on the customer-duty distribution, not only nominal capacity.
3. **Product:** Base Forge turns customer and fleet scenarios into manufacturable battery concepts and tests them through a physics-fidelity ladder.
4. **Demo:** select a Texas customer archetype; generate candidates; watch invalid designs fail; inspect the Pareto frontier; compare baseline and winner in 3D and thermal views.
5. **Trust:** AI proposes and triages, deterministic rules enforce constraints, numerical solvers evaluate physics, and the interface clearly separates simulation from physical validation.
6. **Business value:** fewer manual concept iterations, earlier detection of thermal and installation problems, hardware tailored to real fleet duty, and a reusable computational model rather than a one-off CAD file.

## Final choice

Build **thermal-layout plus sealed-enclosure co-design**, driven by **customer and grid-duty scenarios**. Use CadQuery, PyBaMM, a reduced thermal network, Optuna, and one OpenFOAM finalist validation; optionally use PicoGK for a visually distinctive cold plate or heat-spreader geometry. Use OpenJev only as a fast typed decision layer for triage and explanation.

> Review 1 | HIGH | narrative_logic: This combines too many interacting design problems for the remaining weekend. Fixed packaging and fixed duty cycles make a single thermal subassembly a more defensible first build.
>
> Suggested replacement: Build one heat-spreader and external fin-panel design family, with fixed modules, enclosure boundary, materials, and customer duty cycles.


If internal parameters are unavailable, stay with a Base-like public reference and make every assumption visible. That gives the project the strongest combination of physical design, customer relevance, feasible weekend scope, and defensible physics.

---

## References

1. [LEAP 71 leap71](https://github.com/leap71) - LEAP 71 is pioneering the new field of Computational Engineering, where sophisticated physical objec...

2. [LEAP 71 hot-fires two orbital-class methalox engines designed ...](https://leap71.com/2025/12/11/leap-71-hot-fires-two-orbital-class-methalox-engines-designed-autonomously-by-noyron/)

3. [Computational Engineering - LEAP 71](https://leap71.com/computationalengineering/)

4. [Base Core | Base Power](https://www.basepowercompany.com/core?base_vid=ac988c4e-f889-4fcd-86c6-d6cbdf8c6704) - Base Core, the home battery system that powers your home and strengthens the grid.

5. [Utility partnerships | Base Power](https://www.basepowercompany.com/utilities?base_vid=554d8706-3adf-4951-b405-5cbe26270e21) - Base delivers demand-side megawatts utilities can dispatch — battery capacity deployed in months, no...

6. [Base Core System Specifications | Home Battery Specs | Base Power](https://www.basepowercompany.com/specs/core?base_vid=2be2fd78-aff7-4aaf-a253-0387d5fdb9e3) - Full technical specs for the Base Core — total energy, backup duration, dimensions, operating temper...

7. [Learn How Base Works](https://www.basepowercompany.com/learn) - You get power from us at competitive rates because our batteries help balance the grid—charging when...

8. [Simulative Investigation of Optimal Multiparameterized ...](https://onlinelibrary.wiley.com/doi/full/10.1002/ente.202300405) - Herein, cooling plate topology optimization for electric vehicles is performed based on different li...

9. [Simulative Investigation of Optimal Multiparameterized Cooling Plate Topologies for Different Battery System Configurations](https://onlinelibrary.wiley.com/doi/10.1002/ente.202300405) - To design an effective battery thermal management system, multiple simulations with different levels...

10. [Pseudo three-dimensional topology optimization of cold plates for electric vehicle power packs](https://www.sciencedirect.com/science/article/abs/pii/S0017931024007968) - This study develops a liquid-cooled cold plate for battery packs in electric vehicles using pseudo t...

11. [Topology optimization design and numerical analysis on cold plates for lithium-ion battery thermal management](https://ui.adsabs.harvard.edu/abs/2022IJHMT.18322087C/abstract) - In this paper, the cold plates are designed to cool the rectangular lithium-ion battery packs by the...

12. [Topology optimization design and numerical analysis on cold plates ...](https://ouci.dntb.gov.ua/en/works/4EnAOnNl/)

13. [Cooling-Guided Diffusion Model for Battery Cell Arrangement ††thanks: Citation: Authors. Title. Pages…. DOI:000000/11111.](https://arxiv.org/html/2403.10566v1)

14. [Base Power: Save money. Stay powered.](https://www.basepowercompany.com/) - One of the largest home batteries 39.2 kWh in every Base Core, All-in energy rate 13.9¢/kWh Rate inc...

15. [Home backup for CenterPoint customers](https://www.basepowercompany.com/centerpoint) - With CenterPoint, Base provides affordable energy and backup power in the Houston area—no solar requ...

16. [End-Use Load Profiles for the U.S. Building Stock](https://www.nlr.gov/buildings/end-use-load-profiles)

17. [Build the future of American power | Base Power Careers](https://www.basepowercompany.com/careers) - Base Power is deploying a network of distributed batteries to protect American families from outages...

18. [UL 9540A Test Method for Battery Energy Storage Systems (BESS)](https://www.ul.com/services/ul-9540a-test-method) - Learn how UL Solutions’ innovative testing under the UL 9540A test method can help accelerate compli...

19. [Installation Codes and Requirements for Energy Storage ...](https://www.ul.com/resources/installation-codes-and-requirements-energy-storage-systems-ess-faqs) - An FAQ overview of US installation codes and standard requirements for ESS, including the 2026 editi...

20. [pybamm-team/PyBaMM: Fast and flexible physics-based ... - GitHub](https://github.com/pybamm-team/PyBaMM) - Fast and flexible physics-based battery models in Python - pybamm-team/PyBaMM

21. [PyBaMM - Homepage](https://pybamm.org/) - The PyBaMM Homepage

22. [CadQuery/cadquery: A python parametric CAD scripting ...](https://github.com/cadquery/cadquery) - A python parametric CAD scripting framework based on OCCT - CadQuery/cadquery

23. [CadQuery | Create parametric CAD models with ... - GitHub Pages](https://cadquery.github.io/) - Create parametric CAD models with Python

24. [Welcome to PicoGK](https://github.com/leap71/PicoGK) - PicoGK (“peacock”) is a compact, open-source geometry kernel developed by LEAP 71. It serves as the ...

25. [[PDF] A Python package for simulating packs of batteries with PyBaMM](https://www.theoj.org/joss-papers/joss.04051/10.21105.joss.04051.pdf)

26. [OpenFOAM: API Guide: src/functionObjects/field/heatTransferCoeff/heatTransferCoeff.H Source File](https://www.openfoam.com/documentation/guides/latest/api/heatTransferCoeff_8H_source.html)

27. [OpenFOAM: User Guide: OpenFOAM®: Open source CFD](https://www.openfoam.com/documentation/guides/latest/doc/)

28. [OpenFOAM: API Guide: src/faOptions/sources/derived/externalHeatFluxSource/externalHeatFluxSource.H Source File](https://www.openfoam.com/documentation/guides/latest/api/externalHeatFluxSource_8H_source.html)

29. [CALCULIX: A Three-Dimensional Structural Finite Elemente ...](https://www.calculix.de/) - CalculiX is a package designed to solve field problems. The method used is the finite element method...

30. [A Survey of Open-Source Power System Dynamic ...](https://arxiv.org/pdf/2412.08065.pdf)

31. [GridLAB-D Documentation](https://gridlab-d.readthedocs.io/en/docs/) - None

32. [OpenMDAO repository.](https://github.com/OpenMDAO/OpenMDAO) - OpenMDAO repository. . Contribute to OpenMDAO/OpenMDAO development by creating an account on GitHub.

33. [Multi-objective Optimization with Optuna - Read the Docs](https://optuna.readthedocs.io/en/stable/tutorial/20_recipes/002_multi_objective.html)

34. [Public Datasets - ResStock - National Laboratory of the Rockies](https://resstock.nlr.gov/datasets)

35. [GitHub - cobanov/awesome-jev: A curated, source-backed list ...](https://github.com/cobanov/awesome-jev) - A curated, source-backed list of projects built with Jev, TypeSafe AI's System One model for typed d...

36. [AlexWortega/openjev](https://huggingface.co/AlexWortega/openjev) - We’re on a journey to advance and democratize artificial intelligence through open source and open s...

37. [leap71/LEAP71_HelixHeatX: A helical heat exchanger ...](https://github.com/leap71/LEAP71_HelixHeatX) - LEAP 71 has open-sourced its foundational technology stack. This includes the voxel-based geometry k...

38. [I read OpenJev and thought of an alternative solution using non ...](https://dev.classmethod.jp/en/articles/openjev-non-generative-ai-alternatives/) - Inspired by Jev, I read through the OpenJev implementation and compared it, organizing the differenc...

39. [Jev Alternatives: Open-Source Clones, LLMs and Classifiers](https://jevaiguide.com/jev-alternatives/) - Open-source Jev alternatives compared: Laya, Kev, SemIf, Von, Bespoke Nimble, tev1, OpenJev and more...

40. [LEAP 71 scales computational rocket engine development to meganew…](https://leap71.com/2025/04/30/leap-71-scales-computational-rocket-engine-development-to-meganewton-class-thrust/)

41. [UL 9540A | UL Standards & Engagement](https://www.shopulstandards.com/ProductDetail.aspx?productId=UL9540A_5_S_20250312)



---

## Annotated earlier dispatch proposal

# Base Power x AITX Hackathon: Game Plan

Working title: **BaseForge**, a computational-engineering loop for Base members' home batteries.
The idea borrows from LEAP 71: an AI proposes a design, physics checks it, the results feed the next round.

Timing: kickoff was Fri Sep 25, 5:30 PM. **Submissions close Sun Sep 27, 11:00 AM.** The office closes at midnight each night (Bennu Coffee next door is open 24/7).

---

## 1. What the event rewards (read first)

Sources: [Hackathon Notion guide](https://common-scooter-829.notion.site/Base-AITX-Talent-Hackathon-3e01e636288e80a7b914c993f90ae6c5), [kickoff slides](https://pitch.com/v/baseaitxhackathon-6zfcrj)

**Tracks.** Pick one. A project can be entered in up to 2.
- **Track 1: Open Grid Data.** Build on ERCOT prices, load, generation, and congestion data. "Show us what you can see in the data that most people miss."
- **Track 2: Orchestration.** Coordinate many independent parts (agents, jobs, workers). Judges care most about how it holds up when parts fail.
- **Track 3: Most Commercializable.** "Base is a power company, not a battery company." Build something that could ship on top of what Base already does. Say who it's for and what problem it solves.

**Scoring (100 points):**
- Technical execution: 30 (15 for completeness, 15 for depth)
- Fit to the track: 30 (15 for the problem, 15 for the "why")
- Value and impact: 20 (10 for insight quality, 10 for "could Base use this tomorrow?")
- Innovation: 20 (10 for creativity and polish, 10 for performance and scale)

**Rules that matter:**
- All code has to be written during the hackathon.
- Open-source code is allowed only if it has been public for at least 2 weeks. PyBaMM, OpenEvolve, gridstatus, and BLAST-Lite all qualify.
- Submit a GitHub link, a project description, and a **3–5 minute Loom demo**. The submission form takes 15–20 minutes.
- Teams can have up to 5 people. No photography inside the office.
- Prizes per track: 1st place gets $1,000 plus **guaranteed interviews for the whole team**. 2nd gets $500 and 3rd gets $250.

**Strategic takeaway.** Base's own words are "power company, not a battery company," so **don't pitch new battery cell chemistry or cell hardware**. Base already makes its hardware ([Base Core, 39.2 kWh, built at Factory 1 in Austin](https://www.businesswire.com/news/home/20260803203117/en/Base-Power-Announces-$1B-Series-D-and-Launches-Base-Core-First-of-its-Kind-Home-Battery-Built-in-the-United-States)). Point the LEAP 71 idea at the part Base can actually use: **the design of how each member's battery system is sized, reserved, and dispatched against ERCOT**, with physics checks so every design is proven workable.

Recommended entry: **Track 1 (Open Grid Data) + Track 3 (Commercializable).**

---

## 2. The LEAP 71 analogy, made concrete

[LEAP 71's Noyron](https://leap71.com/2025/12/11/leap-71-hot-fires-two-orbital-class-methalox-engines-designed-autonomously-by-noyron/) builds first-principles physics, engineering logic, and manufacturing constraints into one model. That model produces a design in minutes. LEAP 71 went from specification to first hot-fire in under three weeks, and every test result is fed back into the model.

| LEAP 71 / Noyron | BaseForge |
|---|---|
| Engine spec (thrust, propellant) | Member spec: home load profile, ZIP/weather zone, utility (Oncor, CenterPoint, etc.), solar yes/no, outage-risk tolerance |
| Physics, engineering logic, manufacturing constraints | Battery electro-thermal and aging physics, inverter and panel limits, ERCOT market rules, backup-reserve requirement |
| Generated geometry | Generated **system design**: number of Cores (1 or 2), reserve SOC schedule, charge/discharge **policy code**, thermal derating rules |
| Hot-fire test | Tiered simulation on a full year of real ERCOT prices plus stress events (Winter Storm Uri in Feb 2021, summer heat peaks) |
| Test data fed back into the model | Evaluator feedback (violations, degradation, and which hours lost money) goes back into the LLM's next mutation |

**One-line pitch:** "An AI engineer that designs and physically validates the optimal battery setup and dispatch strategy for every Base member. It proves the design saves members money, earns fleet revenue, and never breaks a physical or backup constraint."

> Review 12 | HIGH | narrative_logic: Finite simulated scenarios cannot prove real-world safety, physical validation, global optimality, or universal savings. The pitch also conflates operator value with the customer's bill.
>
> Suggested replacement: A simulation-based design assistant that compares candidate battery configurations and policies under declared customer scenarios, reporting modeled tradeoffs, constraint violations, and unvalidated assumptions.


---

## 3. "Open Jev" → OpenEvolve (assumed)

I read "Open Jev" as **OpenEvolve**, the open-source version of DeepMind's AlphaEvolve. If you meant another model or tool, the architecture below still works. Only the "proposer" box changes.

> Review 9 | HIGH | verify_public_data: Jev/OpenJev and OpenEvolve are different tools. Jev makes typed decisions; OpenJev exposes classification/decision interfaces; OpenEvolve evolves program code. See https://docs.typesafe.ai/introduction and https://huggingface.co/AlexWortega/openjev
>
> Suggested replacement: Jev/OpenJev is an optional typed decision layer, not OpenEvolve; OpenEvolve is a separate optional framework for evolving programs.


- Repo: [github.com/algorithmicsuperintelligence/openevolve](https://github.com/algorithmicsuperintelligence/openevolve) (about 7.4k stars). Install with `pip install openevolve`.
- How it works: LLMs rewrite a program. Your **evaluator** scores it and returns metrics plus "artifacts" (errors and feedback), and those go into the next prompt. MAP-Elites and island populations keep the designs varied.
- Features you'll use:
  - `cascade_evaluation: true` runs cheap checks first and expensive physics only on survivors. That is your "can it really work" gate.
  - `feature_dimensions` keeps a varied set of designs: for example, **savings vs. battery wear vs. backup safety**. This gives you a Pareto front instead of a single answer.

> Review 15 | MEDIUM | narrative_logic: Binning feature dimensions alone does not establish a nondominated frontier. Explicitly calculate Pareto dominance over feasible candidates and retain raw metrics; verify any framework-specific multi-objective mode.
>
> Suggested replacement: This maintains candidate diversity; calculate the feasible nondominated frontier explicitly from the reported objective metrics.

  - `enable_artifacts` sends constraint violations back to the LLM so it learns from failed designs.
- LLM backends: it works with any OpenAI-compatible API, and local models are supported through [PyPI docs](https://pypi.org/project/openevolve/). Use a fast, cheap model for most mutations and a stronger model for about 20%.

**Hybrid trick (big speed win).** Let OpenEvolve evolve the **structure** of the dispatch policy (the logic and rules). Inside the evaluator, tune the policy's **numbers** (thresholds, reserve levels) with Optuna or CMA-ES. The LLM does the creative work and the optimizer does the precise work.

---

## 4. Open-source physics and data stack

All of these are public and older than 2 weeks, so they are allowed.

### Battery physics
| Tool | Role in BaseForge | Notes |
|---|---|---|
| [PyBaMM](https://github.com/pybamm-team/PyBaMM) | **Tier 3 "truth check."** Electrochemical plus thermal simulation of top candidates on stress days | SPM/SPMe/DFN models, many degradation mechanisms, LFP parameter sets available. Current docs are v26.x ([PyBaMM docs](https://docs.pybamm.org/en/stable/source/user_guide/fundamentals/index.html)) |
| [liionpack](https://github.com/pybamm-team/liionpack) | Optional pack-level check (series/parallel cell imbalance) | In maintenance mode, but it works. Only use it if you have time |
| [NREL BLAST-Lite](https://github.com/NREL/BLAST-Lite/blob/main/README.md) | **Tier 2 aging.** Converts a year of SOC and temperature data into capacity fade | `pip install blast-lite`. Includes a **250 Ah LFP-Gr** and a Sony Murata LFP model, which match Base's LFP chemistry ([Teardown](https://www.teardown.ai/companies/base-power-company)) |
| [PyBOP](https://github.com/pybop-team/PyBOP) | Stretch goal: fit PyBaMM parameters to data | Skip unless Base shares data |

> Review 11 | MEDIUM | verify_public_data: Maintenance status is documented, but this review has not run an installation or compatibility test. Pinning and a smoke test are needed before promising integration. See https://github.com/pybamm-team/liionpack
>
> Suggested replacement: In maintenance mode; compatibility with the selected environment must be tested before inclusion.


> Review 10 | HIGH | verify_public_data: A shared chemistry label does not establish cell or pack calibration, and no Base-specific fit has been verified. BLAST-Lite itself advises treating long-term predictions qualitatively. See https://github.com/NatLabRockies/BLAST-Lite
>
> Suggested replacement: Includes public LFP models usable as explicitly uncalibrated sensitivity cases, not as verified Base Core lifetime predictors


### Grid, home, and weather data
| Source | Use |
|---|---|
| [gridstatus](https://github.com/gridstatus/gridstatus) (Python) | ERCOT real-time and day-ahead settlement point prices, load, fuel mix. **Pull and cache data tonight.** Some ERCOT endpoints may need a free ERCOT API key |
| [NREL ResStock / End-Use Load Profiles](https://catalog.data.gov/dataset/end-use-load-profiles-for-the-u-s-building-stock) | Realistic 15-minute home load profiles for Texas homes (HVAC-heavy summer, heat strips during Uri) = your "synthetic Base members" |
| [Open-Meteo Historical API](https://open-meteo.com/en/docs/historical-weather-api) | Hourly temperature by ZIP, free, no key. Drives thermal derating and HVAC load |

### Base Core specs to build in
- **39.2 kWh per Core, or 78.4 kWh with two.** Operating range is −22 to 122 °F. Supports up to 200 A panels. Solar buyback is 4¢/kWh ([Base specs](https://www.basepowercompany.com/specs/core)).
- The Gen 1 unit was **11.4 kW / 25 kWh** ([ESS News](https://www.ess-news.com/2025/12/11/base-power-residential-batteries-texas-farmers-cooperative-deal-ercot-grid/)). Base Core's kW rating isn't published. **Ask at Saturday office hours (11 AM–1 PM).** Until then, keep it as a setting you can change.

> Review 8 | MEDIUM | verify_public_data: Base's utility page publicly lists a 20 kW / 39.2 kWh residential BESS. It does not specify continuous versus peak power, and the applicable product revision still needs confirmation. See https://www.basepowercompany.com/utilities
>
> Suggested replacement: Base publicly lists a 20 kW / 39.2 kWh residential BESS; confirm the applicable revision, continuous/peak interpretation, and charge limits with Base.

- The business model is roughly an 8.5¢/kWh retail rate against 3–5¢ wholesale, plus arbitrage around the 4–9 PM peak, plus ancillary services through ERCOT's ADER pilot ([Teardown](https://www.teardown.ai/companies/base-power-company)). **Your score function should reflect all three.**

---

## 5. System architecture

```
Member spec (load profile, ZIP, utility, solar, risk)
        │
        ▼
┌─────────────── OpenEvolve controller ────────────────┐
│ LLM ensemble mutates policy.py (sizing + dispatch)    │
│ MAP-Elites over [savings, degradation, backup margin] │
└──────────────┬───────────────────────────────────────┘
               ▼  candidate design
   ┌──────── Cascade evaluator (the physics gate) ────────┐
   │ T0  Static checks: runs, returns valid actions, <X ms │  → reject fast
   │ T1  Fast year sim (NumPy, 15-min steps, vectorized):  │
   │     energy balance, SOC 0–100%, kW limits, efficiency,│
   │     reserve for outages, thermal derate vs. temp      │  → hard-constraint violations = score 0
   │ T2  BLAST-Lite LFP aging on T1's SOC/temp trace       │  → $ degradation cost
   │ T3  PyBaMM SPMe+thermal on 3 stress days (top-k only) │  → cell temp, voltage limits, agrees with T1?
   └──────────────┬───────────────────────────────────────┘
                  ▼
   Score = member savings + fleet arbitrage/AS value

> Review 13 | HIGH | narrative_logic: This can double-count value and assumes settlement, tariffs, ancillary-service qualification, and revenue rights that are not modeled. Keep operator dispatch value and customer resilience separate; exclude ancillary revenue from the MVP.
>
> Suggested replacement: Report operator energy-dispatch value under an explicit settlement model, separately from customer backup metrics; do not claim bill savings without tariff-based billing calculations.

           − degradation $ − backup-risk penalty
   Artifacts → "violated reserve at 18:15 on 2021-02-15" → fed back to LLM
                  ▼
Baselines: naive fixed schedule | perfect-foresight LP (upper bound, cvxpy)
                  ▼
Dashboard: per-member "Design Card" + Pareto front + evolution replay
```

**Physics validation checklist (the "can it really work" part):**
1. **Hard constraints are never softened.** Any SOC, power, or reserve violation scores zero.

> Review 14 | HIGH | narrative_logic: A zero score may outrank feasible negative scores. A reserve floor that never releases during an outage also prevents the battery from delivering the backup being evaluated.
>
> Suggested replacement: Use a separate feasibility flag and constraint-first ranking. Enforce grid-connected reserve policy, allow reserved energy to serve the home during outages down to physical minimum SOC, and report unserved load.

2. **Cross-check the fidelity tiers.** Run top designs through PyBaMM and show the fast T1 model agrees within a few percent on energy and stays inside temperature limits. If they disagree, flag the design.
3. **Test out of sample.** Evolve on 2023 prices and report results on 2024–2025 plus the Uri week. This proves you didn't overfit to one year's price spikes.
4. **No future data.** Policies only see past prices and forecasts. Compare against the perfect-foresight LP to report "% of theoretical max captured."
5. **State your assumptions in the UI.** List every parameter you guessed (for example, Core kW rating and round-trip efficiency).

---

## 6. Demo outputs

1. **Member Design Card.** Example: "Round Rock, 2,400 sq ft, electric heat, no solar → 1 Core. Reserve 35% on Jun–Sep weekdays and 60% when a freeze is forecast. Evolved policy saves $X per year, captures Y% of the LP optimum, and costs Z% capacity fade over 10 years. Physics check: PASS."
2. **Non-obvious insight (Track 1 points).** Look for things like: "In ERCOT, 70% of arbitrage value comes from fewer than 50 hours a year. The evolved policy learned to hold charge on high-net-load, low-wind afternoons instead of discharging every day at 4 PM, which cuts degradation by N%."
3. **Evolution replay.** An animated chart of score by generation, with example LLM-written policies at gens 1, 20, and 100, and the constraint violations it learned to avoid.
4. **Fleet view (bonus).** Run 200 synthetic members and show the total fleet flexibility (MW) available for ADER or ancillary services by hour.

---

## 7. Timeline (about 38 hours)

**Fri tonight (9 PM–midnight): set up and pull data**
- Create the repo and environment (Python 3.12, `pybamm`, `blast-lite`, `openevolve`, `gridstatus`, `numpy`, `pandas`, `cvxpy`, `optuna`, `fastapi` or `streamlit`).
- **Pull and cache** ERCOT real-time settlement point prices (Houston/North/South hubs or LZ_*) for 2021–2025, Open-Meteo data for 4 Texas cities, and 20–50 ResStock Texas load profiles. Save as Parquet.
- Write the T1 fast simulator and a hand-written baseline policy. Goal: one full-year sim in under 1 second.

**Sat 8 AM–noon: core loop**
- LP oracle (cvxpy) as the upper bound. BLAST-Lite T2 aging with the LFP model.
- OpenEvolve config plus the cascade evaluator. Run the first 50-iteration evolution.
- **11 AM office hours:** ask Base engineers the questions in section 9.

**Sat noon–6 PM: physics and scale**
- PyBaMM T3 check on stress days for the top-k designs.
- Out-of-sample test harness. Run the evolution in parallel across 5–10 member archetypes.
- Start the dashboard.

**Sat 6 PM–midnight: product layer**
- Design Card UI, Pareto chart, evolution replay, fleet view.
- **Record a rough Loom before midnight** (advice from the kickoff slides).

**Sun 8–10 AM: polish and submit**
- Final evolution results, clean README (architecture diagram, how to run, assumptions), final Loom (4:30 max).
- **Submit by 10:15 AM.** Don't cut it close, since the form takes 15–20 minutes.

---

## 8. Team roles (up to 5)

| Role | Owns |
|---|---|
| Physics lead | T1 simulator, BLAST-Lite, PyBaMM cross-check, validation report |
| Evolution/ML lead | OpenEvolve config, evaluator, prompt templates, Optuna inner loop, LP oracle |
| Data lead | gridstatus/ERCOT, ResStock, Open-Meteo pipelines, finding the insight |
| Product/front-end | Dashboard, Design Card, evolution replay, fleet view |
| Storyteller (can be shared) | README, demo script, Loom, Base Q&A |

If you're solo or a team of 2, drop PyBaMM T3 and the fleet view. Keep T1, BLAST-Lite, OpenEvolve, the LP oracle, and one Design Card.

---

## 9. Questions for Base office hours (Sat 11 AM–1 PM)

- What is Base Core's continuous and peak kW rating and its round-trip efficiency?
- What minimum backup reserve do you hold, and how does it change for weather events?
- Is the member's value measured on their bill, on fleet revenue, or both? How do you split retail margin vs. wholesale vs. ancillary services today?
- Which ERCOT settlement points or load zones matter most for your fleet?
- How do you think about degradation cost (in $/kWh throughput) internally?
- Would a per-member sizing recommendation (1 vs. 2 Cores) be useful to your sales or install team?

---

## 10. Demo video script (4:30)

1. **0:00–0:30 Hook.** "LEAP 71's AI designed a rocket engine that fired on the first try because physics was built into the loop. We did the same for every Base member's battery."
2. **0:30–1:15 Problem and why.** Every home, weather zone, and price pattern is different. One-size-fits-all dispatch leaves money on the table and wears out the battery.
3. **1:15–3:00 Live run.** Enter a member, watch the evolution, see physics rejections, then the Design Card. Show the out-of-sample and Uri-week results and the % of LP optimum captured.
4. **3:00–3:45 Insight and fleet.** The non-obvious ERCOT finding, plus the fleet flexibility chart.
5. **3:45–4:30 Ship it.** Who uses it tomorrow (the Base sales team for sizing, the ops team for dispatch strategies), plus the architecture and repo.

---

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| PyBaMM too slow inside the loop | Only use it at T3, on the top-k designs, over short stress windows. Use SPMe instead of DFN |
| LLM writes broken or slow code | T0 sandbox with timeout. The error text goes back as an artifact |
| Overfitting to 2021/2023 price spikes | Report on held-out years. Show results both with and without Uri |
| Unknown Base specs | Keep them as settings, list them in the UI, update after office hours |
| ERCOT API friction | Pull data tonight and commit the cache (or a download script) |
| Scope creep | Freeze features Sat 6 PM. After that, only the dashboard and the video |

## Alternate angle (Track 2)

If your team leans toward infrastructure, frame the same system as **fault-tolerant orchestration**. Run hundreds of evaluator workers across many member archetypes, with retries, timeouts, and checkpointed evolution state. Demo it by killing workers mid-run and showing no progress is lost.
