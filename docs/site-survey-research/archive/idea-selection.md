# Base Power: Which Product Idea to Build

Assessment dated September 26, 2026. This compares four directions: enrollment/site-photo capture, physical-design optimization, Base OS, and battery-enabled competition with Arbor.

## Executive assessment

**The strongest next build is enrollment completion and site-evidence quality, using the existing Base Site Survey app as the starting point.** The useful product is not “an AR battery viewer.” It is a guided workflow that helps a homeowner produce a reviewable site packet without repeated requests, while leaving installation approval to Base.

**The strongest second direction is a narrow Base OS feature: outage-mode coordination of household loads.** A general home operating system is too broad, and an integration dashboard alone is not sufficiently differentiated.

**The Arbor-inspired idea becomes credible when reframed as battery-aware offer intelligence, not automatic switching of Base battery customers among providers.** It could help Base demonstrate its total customer value or help its commercial team evaluate offers. A neutral, supplier-switching product would require a materially different commercial arrangement.

**Physical design remains worthwhile as a separate engineering project, but ranks last for this remaining hackathon window without an experienced thermal owner, relevant Base inputs, and a working evaluator.** This does not negate the attached review: that review selected a narrow thermal project within a more constrained hardware-versus-dispatch choice. The expanded option set and existing enrollment code change the decision.

These are product judgments, not measured conversion forecasts, verified Base priorities, or predictions of judging outcomes. Team size, physical-device readiness, Base API access, and actual funnel data remain unknown.

## Decision frame and ranking

The event requires a working system and allocates 30 points to technical execution, 30 to track fit, 20 to value, and 20 to innovation/execution; submissions are due Sunday, September 27 at 11 AM. ([Official hackathon guide](https://common-scooter-829.notion.site/Base-AITX-Talent-Hackathon-3e01e636288e80a7b914c993f90ae6c5)) At the request timestamp, Saturday at 12:31 PM CDT, that leaves approximately 22.5 wall-clock hours, not a fresh 48-hour build.

I therefore prioritize a demonstrable workflow, low dependency risk, a named user, and a credible validation path over theoretical market size. Existing code matters because it shortens time to evidence, not because sunk effort must be preserved.

| Rank for this weekend | Buildable version | Customer/problem clarity | Remaining dependency risk | Evidence obtainable quickly | Recommendation |
|---|---|---|---|---|---|
| 1 | Guided site-photo capture plus review packet | High; severity still needs validation | Low–medium | High: completeness, completion time, reviewer usability | Finish and validate |
| 2 | Base OS: outage-mode load coordinator | High when narrowed to outage endurance | High without authorized telemetry and a controllable device | Medium; high with working hardware | Best alternative if access is ready |
| 3 | Battery-aware offer/value comparison | Medium–high when tied to a specific market and buyer | Medium–high: tariffs, settlement, commercial terms | Medium for bill arithmetic; low for actual savings | Prototype later or pivot only if Base names pricing as the bottleneck |
| 4 | Narrow heat-spreader/fin optimizer | Clear engineering user, unconfirmed Base pain | High: thermal assumptions and calibration | Low–medium without an existing solver | Defer unless engineering prerequisites already exist |

The table is a qualitative assessment. In the original broad forms, “connect all home software” and “automatically switch Base customers among providers” are weaker than the narrowed versions ranked here.

### What would change the ranking?

- **Enrollment loses first place:** Base reports that photo rework and abandonment are negligible, or a quick usability test shows the app adds more friction than it removes.
- **Base OS moves to first:** A teammate already has authorized, sufficiently fresh telemetry and a working thermostat or EV-charger integration, and Base confirms outage load reduction as a priority.
- **Offer intelligence moves up:** Base says price objections are a larger conversion bottleneck than photos and supplies a usable tariff/offer baseline.
- **Physical design moves up:** A thermal engineer already has a verified geometry-linked evaluator, and Base identifies the subassembly and supplies relevant boundary conditions.

## Findings that materially change the choice

### The photo task exists; the size of the enrollment gap is unproven

Base explicitly says it sends customers a photo-submission link after signup and that engineering reviews those images for installation suitability. ([Base photo-review guidance](https://help.basepowercompany.com/en/articles/10280641)) Its guidance says clear photos can avoid further requests and specifically warns that missing the external disconnect delays review. ([Base photo-review guidance](https://help.basepowercompany.com/en/articles/10280641))

That establishes a real operational workflow, not the magnitude of a business problem. No Base funnel dataset was provided or analyzed here, so abandonment rate, resubmission rate, reviewer minutes, and lost installations remain unknown.

The key distinction is among three hypotheses:

- **Instructions problem:** Customers do not know what to photograph. Guided framing and examples could help.
- **Evidence problem:** Customers submit blurry, incomplete, or poorly contextualized images. Quality checks and reviewer feedback could help.
- **Motivation problem:** Customers stop because of pricing, installation uncertainty, effort, or low intent. Better photography software alone may not solve this.

Before building more AR, establish which hypothesis is most important. A beautiful capture interface can still optimize the wrong step.

### Arbor and Base have different economic roles

Arbor describes a service that finds and enrolls customers in electricity supply plans and receives referral fees from participating suppliers. ([Arbor how it works](https://www.joinarbor.com/how-it-works)) Base describes a battery-backed energy service in which batteries charge and discharge for grid support and provide home backup during outages. ([Base how it works](https://www.basepowercompany.com/how-it-works))

My interpretation: Arbor primarily changes the customer's purchasing choice; Base can also change the physical demand that must be served. That is a meaningful distinction, but not a newly discovered business model for Base.

Base already describes using home batteries to reduce the cost of serving customers during peak-demand periods in its Illinois launch. ([Base Illinois launch](https://www.basepowercompany.com/illinois-press)) Consequently, “use batteries to offer cheaper electricity” is too close to Base's existing proposition to be a differentiated project by itself.

### Provider switching conflicts with the published retail arrangement

Base's agreement FAQ says, “You must continue to use Base as your energy provider in order to have a Base battery,” while expressly exempting customers who cannot choose their provider and are served through a utility partnership. ([Base agreements](https://help.basepowercompany.com/en/articles/10283073)) Base also says its structure varies by service territory, with the utility remaining in place in co-op and municipal arrangements. ([Base how it works](https://www.basepowercompany.com/how-it-works))

Treat exclusivity as a blocking assumption for a retail-switching MVP, not as a universal statement about every Base contract in every state. Obtain the applicable customer agreement before claiming that a particular customer can keep the battery after switching suppliers.

### Texas is not a verified current Arbor market

Arbor's general how-it-works page discusses energy-choice states including Texas, but its specific service-area page lists Texas as “Not available yet” and “Coming soon.” ([Arbor how it works](https://www.joinarbor.com/how-it-works), [Arbor service areas](https://www.joinarbor.com/resources/where-arbor-works)) The more specific page supports treating Texas as a prospective competitive market, not an established head-to-head Arbor market.

Illinois/ComEd is a better documented comparison setting: Arbor lists ComEd coverage, and Base announced its Chicagoland launch in June 2026. ([Arbor service areas](https://www.joinarbor.com/resources/where-arbor-works), [Base Illinois launch](https://www.basepowercompany.com/illinois-press)) Exact address eligibility and current offers still need checking before a customer-facing recommendation.

Also, “deregulated” or “retail-choice” is more accurate than “unregulated”: ERCOT explains that PUCT licenses and monitors providers and enforces consumer protections. ([ERCOT retail-market explainer](https://www.ercot.com/files/docs/2025/11/17/ERCOT-Grid-Insights-Retail-Market.pdf)) Multiple providers offer multiple plans, so a count of providers across a market is not a count of available choices for a particular household. ([ERCOT retail-market explainer](https://www.ercot.com/files/docs/2025/11/17/ERCOT-Grid-Insights-Retail-Market.pdf))

### Smart-home connectivity is not an empty category

Home Assistant already supports cross-brand energy monitoring and energy-related automations. ([Home Assistant energy documentation](https://www.home-assistant.io/docs/energy/)) A public, unofficial Base integration documents battery state, usage, grid status, backup estimates, and other sensors through Base's private API. ([Unofficial Base integration](https://github.com/jerrit/ha-base-power))

That integration describes five-minute polling, 15-minute state-of-charge data, and a 25-kWh-per-unit capacity assumption. ([Unofficial Base integration](https://github.com/jerrit/ha-base-power)) It is not evidence of an official supported interface, compatibility with every Base hardware revision, or sufficiently fast outage control.

The opportunity is therefore not “make Base data visible for the first time.” A more defensible opportunity is dependable, user-approved energy coordination with freshness checks, failure recovery, and a clear household benefit.

## Enrollment: the best immediate project

### Product and buyer

Proposed positioning: **“Help Base members capture a complete site packet on the first attempt, and help reviewers request only what is missing.”** The homeowner is the capture user; Base onboarding or installation operations is the operational buyer.

The distinctive workflow should connect both sides:

1. Guide the homeowner through applicable evidence.
2. Check image quality and packet coverage.
3. Suggest extracted identifiers, with explicit confirmation.
4. Optionally preview battery placement.
5. Produce a traceable packet.
6. Let a reviewer accept evidence or request a targeted retake.

The product should optimize “review-ready evidence,” not “customer self-approval.” Base reserves installation evaluation and final siting to its engineering and installation process. ([Base photo-review guidance](https://help.basepowercompany.com/en/articles/10280641), [Base siting guidance](https://help.basepowercompany.com/en/articles/10280705))

### What the repository actually provides

I reviewed the source at commit `dea7be5fc66a5e58e7df83ac5bcd41e0ea0418ef`, not just its README. ([Reviewed commit](https://github.com/nikitaroz/base-ar/commit/dea7be5fc66a5e58e7df83ac5bcd41e0ea0418ef)) This was static inspection: I did not compile the iOS project, run its tests, or validate AR and OCR on a physical iPhone.

| Area | Source-level finding | Product implication |
|---|---|---|
| Capture and review | Meter/breaker capture, local survey state, AR placement, review, and JSON/photo export are present. ([Repository](https://github.com/nikitaroz/base-ar)) | There is a meaningful foundation to finish |
| OCR | The reviewed commit wires Apple Vision OCR into `SurveyStore`; the README's “always returns nil” description is stale. ([Reviewed commit](https://github.com/nikitaroz/base-ar/commit/dea7be5fc66a5e58e7df83ac5bcd41e0ea0418ef)) | Test and harden it rather than rebuilding it |
| Evidence provenance | The commit adds units, device/build provenance, timestamps, and a distinct attestation tone. ([Reviewed commit](https://github.com/nikitaroz/base-ar/commit/dea7be5fc66a5e58e7df83ac5bcd41e0ea0418ef)) | Preserve this distinction throughout the reviewer workflow |
| Photo coverage | The repository documents missing wide meter-area and breaker-context compositions. ([Repository](https://github.com/nikitaroz/base-ar)) | This is more important to the core job than more AR polish |
| Backend handoff | Export is local; the app does not submit a packet into Base's systems. ([Repository](https://github.com/nikitaroz/base-ar)) | Demonstrate a separate reviewer/import workflow or label the handoff honestly |
| Tests | In the reviewed checkout, `BaseARTests.swift` contains only a trivial module-load test using `XCTAssertTrue(true)`. ([Repository](https://github.com/nikitaroz/base-ar)) | Do not describe the pipeline as meaningfully tested |

The repository's older comparison report also lags the code on ownership, generator questions, and planned battery count; these are present in the reviewed source. ([Repository](https://github.com/nikitaroz/base-ar)) This is why the recommendation is based on actual code inspection rather than counting TODOs in prose.

### The most valuable scope correction

Base's public guidance specifies nine photo categories, including conditional fence and breaker-area context, not merely a meter close-up and a breaker photo. ([Base photo-review guidance](https://help.basepowercompany.com/en/articles/10280641)) Do not mechanically require exactly nine files: support conditional applicability and reviewer-confirmed coverage when a composition genuinely covers multiple needs.

Prioritize these additions:

- **Guided photo checklist:** Explicit slots for meter detail, surrounding area, left/right context, adjacent wall, fence context when applicable, breaker overview, disconnect detail, and breaker-area context.
- **Retake guidance:** Explain “number unreadable,” “need wider context,” or “disconnect not visible,” rather than a generic failed score.
- **Confirmation:** Present OCR as a suggestion beside its source image. Keep manual correction and “cannot read” available.
- **Reviewer packet:** Show evidence thumbnails, missing items, user-confirmed fields, measurement provenance, and rule-version metadata.
- **Targeted rework:** Reviewer requests one missing view; the customer returns to that task rather than restarting.
- **Draft recovery:** Save progress and restore it after app termination; a written JSON file alone is not a demonstrated resume workflow.
- **Optional AR:** Keep visualization as a helpful preview, not a compulsory hurdle before sending useful photos.

A one-time enrollment tool must justify requiring an app download. My production recommendation is a low-friction mobile capture link with optional native AR; my weekend recommendation is to finish the existing native prototype rather than rewrite it now.

### Technical issues worth fixing before the demo

These findings come from static inspection of the reviewed repository snapshot; they are not reproduced runtime failures. ([Repository](https://github.com/nikitaroz/base-ar))

- **OCR acceptance:** The source ranks digit candidates by text height and confidence and fills an empty meter-number field automatically. ([Reviewed commit](https://github.com/nikitaroz/base-ar/commit/dea7be5fc66a5e58e7df83ac5bcd41e0ea0418ef)) Add explicit user acceptance, retain candidate evidence, and handle multiple plausible numbers.
- **OCR error completion:** `handler.perform` is wrapped in `try?`, while the continuation is resumed in the request callback. ([Reviewed commit](https://github.com/nikitaroz/base-ar/commit/dea7be5fc66a5e58e7df83ac5bcd41e0ea0418ef)) Explicitly handle thrown errors and ensure the async operation completes exactly once.
- **Stale image results:** Capture launches an asynchronous OCR task without an obvious photo-version guard in the reviewed source. ([Repository](https://github.com/nikitaroz/base-ar)) Bind the result to the photo hash/version so an earlier photo cannot populate a later capture.
- **Provenance semantics:** Shared pass/conflict constructors mark evidence as measured, including checks driven by manually entered breaker amperage. ([Repository](https://github.com/nikitaroz/base-ar)) Separate “entered,” “OCR-suggested,” “user-confirmed,” “AR-estimated,” and “reviewer-verified.”
- **Distance semantics:** Meter and gas distances are computed between placed anchor positions, while wall clearance uses battery corners and detected planes. ([Repository](https://github.com/nikitaroz/base-ar)) Label these correctly and obtain Base's required measurement convention before interpreting them as compliance clearances.
- **Jurisdiction:** The rule set uses Austin-specific breaker thresholds. ([Repository](https://github.com/nikitaroz/base-ar)) Do not silently apply Austin rules to every address.

Use “evidence complete,” “needs review,” and “possible conflict,” rather than a prominent “approved” result. Never encourage a homeowner to remove covers, touch wiring, or manipulate energized equipment; if a label cannot be photographed safely, route it to human support.

### Business case and measurement

The commercial hypothesis is that less photo rework can reduce operations time and help more otherwise-qualified households reach installation. It is not yet a measured outcome.

Use a transparent value model:

\[
\text{Incremental value} \approx
N\,\Delta p\,M
+N\,\Delta t\,w
-C_{\mathrm{software}}
-C_{\mathrm{support}}
-C_{\mathrm{errors}}.
\]

Here \(N\) is eligible survey starts, \(\Delta p\) is absolute improvement in eventual installation completion, \(M\) is incremental contribution per installed member, \(\Delta t\) is reviewer time saved per start, and \(w\) is labor cost per unit of time. Keep accelerated installations separate from genuinely incremental installations; if crews are capacity-constrained, more completed photo packets may initially increase the queue rather than deployments.

Proposed validation:

- **Weekend test:** Have three to five consenting testers follow the existing written instructions versus the guided flow, using comparable tasks and counterbalanced order where practical.
- **Reviewer check:** Ask a Base reviewer, ideally blinded to capture method, whether each packet is sufficient and how many follow-up questions remain.
- **Operational pilot:** Compare review-ready packets per assigned eligible lead, completion time, retake rate, reviewer minutes, and downstream installation rate.
- **Guardrails:** Track false “ready” classifications, device exclusion, permission failures, privacy complaints, and human escalations.

A tiny usability test can uncover friction; it cannot establish a statistically reliable conversion lift. Report counts and observed examples, not a generalized “X% improvement” from a handful of people.

## Base OS: promising only when narrowed

### The strongest version

Proposed positioning: **“When the grid fails, Base coordinates approved household loads so the battery lasts longer without sacrificing essential needs.”** Begin with one thermostat or EV charger and one outage/recovery workflow, not every app or device in the home.

Base recommends reducing high-draw appliances to extend backup duration and says it manages battery charging and discharging itself. ([Base backup guidance](https://help.basepowercompany.com/en/categories/2347329)) A community post describes manually building notification-triggered thermostat adjustments for this exact purpose, which is useful qualitative demand evidence but not proof of broad adoption or current official support. ([Community outage-automation discussion](https://www.reddit.com/r/BasePowerUsers/comments/1o74nb1/smart_home_automation_with_android_and_ifttt/))

The product would control authorized household loads around the battery, not override Base's battery dispatch. That distinction preserves a plausible operating boundary and avoids building two competing battery controllers.

### Why not “the battery is the computer for the whole home”?

The reviewed materials do not establish an approved application runtime, spare compute resources, or a supported app-installation mechanism on Base hardware. Treat running third-party software on the battery as unverified, not as a free deployment platform.

A sensible prototype could run on an existing local hub or an external service. Its differentiator should be the energy policy and recovery behavior, not a claim that electrical connection grants software control of every appliance.

### Minimum credible demo

- **Consent:** User specifies the device, comfort limits, protected loads, and override behavior.
- **Outage detection:** Consume an authorized signal with a visible freshness timestamp; clearly label replayed events.
- **Action:** Pause one nonessential load or make a bounded thermostat change.
- **Verification:** Read back the device's actual state instead of treating “command sent” as success.
- **Recovery:** Restore the prior state after stable grid return, unless the user has since overridden it.
- **Failure handling:** Demonstrate duplicate events, stale telemetry, device disconnect, and a failed command.

Do not automate medically necessary equipment, invent safe temperature ranges, or assume the internet remains available during an outage. A production controller needs local connectivity, power for its hub/network equipment, explicit user limits, and a safe fallback.

### Evidence and defensibility

For an illustrative constant-load model only, 24 kWh of usable energy lasts six hours at 4 kW and eight hours at 3 kW. That arithmetic is not a Base performance claim; actual runtime requires battery availability, changing loads, efficiency, and operating constraints.

A meaningful evaluation compares the same outage trace with and without control, measuring energy served, time within user comfort bounds, command success, and recovery correctness. If savings or runtime gains are only simulated, say so.

The unofficial integration is a possible research lead, not a dependable production control surface: it uses a private API, has relatively coarse telemetry, and documents older capacity assumptions. ([Unofficial Base integration](https://github.com/jerrit/ha-base-power)) Without approved access and at least one working device, this direction risks becoming a polished dashboard connected to mocks.

Its best hackathon track is Orchestration, provided failure recovery genuinely works. That aligns with the guide's emphasis on systems holding up when independent parts fail. ([Official hackathon guide](https://common-scooter-829.notion.site/Base-AITX-Talent-Hackathon-3e01e636288e80a7b914c993f90ae6c5))

## The Arbor-inspired direction: distinguish three different products

The phrase “use Base devices to compete with Arbor” could describe several businesses. They should not be evaluated as one idea because their buyers, permissions, and economics differ.

| Interpretation | Proposed product | Assessment |
|---|---|---|
| Help consumers understand Base versus alternatives | Transparent total-cost and backup-value comparison | Plausible acquisition tool; easiest version |
| Help Base offer more competitive plans | Battery-aware cost-to-serve and offer scenario engine | Strategically valuable, but needs internal cost/settlement data |
| Keep Base hardware while switching suppliers automatically | Neutral battery-aware procurement service | Commercially blocked unless contracts and operating rights change |

### Best near-term version: transparent offer intelligence

Proposed positioning: **“Compare the household's actual electricity cost under available offers, then show Base's battery-backed proposition without hiding fees or valuing backup as guaranteed cash savings.”**

For a minimal prototype, select one territory and three manually verified, timestamped tariff documents. Accept monthly consumption for flat-rate comparisons; require interval data where time-of-use rates or dispatch materially affect the bill.

Keep three separate outputs:

- **Customer bill:** Supply, delivery, recurring fees, applicable credits, taxes, and explicit transition costs over the same horizon.
- **Backup benefit:** Explain what service is included and show user-selected scenarios; do not turn backup into a dollar benefit without an explicit user valuation.
- **Base economics:** Procurement and grid-service effects, battery capital/service costs, losses, degradation, and customer-acquisition costs.

Arbor says it receives supplier referral fees, but the reviewed pages do not establish comprehensive access to every market offer. ([Arbor how it works](https://www.joinarbor.com/how-it-works)) A comparison tool should disclose its own coverage and compensation equally clearly and should sometimes conclude that Base is not the cheapest option for that household.

### Important modeling traps

- **Fixed rate versus wholesale price:** A lower wholesale procurement cost does not automatically reduce an existing customer's flat-rate bill. Only pass through savings that the actual customer tariff specifies.
- **Battery charging:** Distinguish native household load from battery imports/exports. Do not compare the customer's current bill with a counterfactual that silently changes who pays for charging.
- **Nonlinear plans:** Model usage credits, minimum-use charges, time windows, and recurring fees from the actual tariff rather than ranking headline cents per kWh.
- **Fair baseline:** Compare the same usage period, territory, enrollment eligibility, contract horizon, and treatment of installation fees.
- **No double counting:** Do not add customer bill reductions and operator dispatch revenue unless the payment flows show distinct benefits.
- **No perfect-foresight claims:** A strategy optimized with future prices is a benchmark, not deployable performance.
- **Rights and settlement:** Verify who owns the battery, buys charging energy, controls dispatch, receives export/market payments, and bears imbalance or operational costs.

These are design requirements for a credible evaluator. No tariff engine or savings backtest was built in this assessment.

### Strategic judgment

There is a potentially attractive business in jointly considering customer load, flexible devices, and contract economics. But the incremental product must be more specific than the underlying Base model, and a comparison without a data or distribution advantage may remain a feature rather than a standalone company.

If the aim is an independent startup rather than a Base hackathon entry, hardware-neutral optimization deserves a separate evaluation. If the aim is to win credibility with Base this weekend, the enrollment workflow has fewer external dependencies.

## Physical design: retain the idea, change the timing

The attached reviewed comparison already makes the right scope correction: one heat-spreader/external-fin family, fixed materials and modules, fixed duty cycles, an immutable evaluator, and honest separation of numerical verification from physical validation. Preserve those constraints if this direction is resumed.

Its potential benefit is substantial if it helps an engineer reduce iteration time, material, or thermal derating. Its current weakness is that neither the attachment nor this assessment establishes a validated Base-specific thermal bottleneck, internal geometry, heat-load map, or baseline design.

Base publicly describes designing and manufacturing purpose-built hardware, so physical engineering is not strategically irrelevant merely because the event calls Base a power company. ([Base utility offering](https://www.basepowercompany.com/utilities)) The question is whether this particular tool addresses an engineer's actual next decision.

Required promotion gates:

- **Problem owner:** A Base engineer identifies the target subassembly and desired output.
- **Baseline:** A fixed, relevant reference case exists.
- **Physics:** Geometry actually drives thermal conductance and area, rather than appearing beside an unrelated simulation.
- **Verification:** Analytical limiting cases, energy balance, time/grid refinement, and sensitivity tests pass.
- **Comparison:** Baseline and candidate use identical loads, budgets, and boundary assumptions.
- **Claims:** Results are labeled “best evaluated candidate under these assumptions,” not a physically validated or globally optimal battery.

If these gates are not already mostly satisfied, switching now would spend the remaining window recreating an evaluator rather than demonstrating customer value. Retain the work as a later engineering project rather than adding it to the enrollment demo.

## What to build before submission

### Core scope

Name can remain **Base Site Survey**; the pitch should emphasize a review-ready site packet. Do not add Base OS or a tariff marketplace to this build.

Recommended priority order:

1. **Validate the problem:** Ask a Base onboarding/install reviewer which missing images create the most rework.
2. **Complete capture coverage:** Add the wide/context categories and conditional applicability.
3. **Harden evidence:** OCR confirmation, safe failure, draft recovery, and clear provenance.
4. **Close the review loop:** Import/view the packet and request a specific retake; if no Base integration exists, explicitly show a prototype reviewer workflow.
5. **Test on a physical phone:** Permissions, photo retakes, interruptions, export, AR failure, and non-LiDAR behavior.
6. **Demonstrate honestly:** Complete one good packet and recover one deliberately incomplete packet.

### Remaining-time allocation

This is a proposed schedule, not a delivery-time guarantee. Preserve sleep, recording time, and an early submission margin.

| Window, CDT | Deliverable | Cut line |
|---|---|---|
| Next 30–45 minutes | Base reviewer feedback; agree on evidence categories and reviewer output | No new product direction without decisive evidence |
| Saturday early afternoon | Complete photo checklist, conditional slots, progress, and OCR confirmation | AR is optional |
| Saturday late afternoon | Reviewer packet, specific retake flow, draft/error handling | Local import/export is acceptable if labeled |
| Saturday evening | Physical-device tests and a few observed user sessions | Stop adding integrations |
| Saturday night | Freeze, fix blocking failures, record backup demo | No new physics or pricing engine |
| Sunday morning | Reproducible walkthrough, README updates, final video, submission | Target completion before the 11 AM deadline |

The official guide lists a five-minute demo video and codebase link as required deliverables. ([Official hackathon guide](https://common-scooter-829.notion.site/Base-AITX-Talent-Hackathon-3e01e636288e80a7b914c993f90ae6c5)) Confirm any separate submission-form and code-eligibility rules with organizers; repository creation time alone does not establish compliance or permission to use another team's work.

### Demo narrative

- **Problem:** Explain that site qualification depends on usable evidence, with no invented funnel-loss statistics.
- **Capture:** Show a poor image producing a useful retake instruction.
- **Evidence:** Confirm a meter identifier and complete the required context views.
- **AR:** Briefly show the battery preview as optional context, not an approval engine.
- **Review:** Open the packet, distinguish measurements from declarations, and request one missing item.
- **Recovery:** Resume and fix that item without losing the rest of the survey.
- **Outcome:** State what was measured in testing and what remains unvalidated.

Enter Most Commercializable as the primary track. Add Orchestration only if durable state, interrupted work, retries, and recovery are truly implemented; multiple API calls alone are not the contribution.

## Questions worth asking Base immediately

These are decision questions, not a request for a large data project. One conversation could confirm or overturn the recommendation.

- **Funnel:** “Of otherwise-qualified signups, how many never finish photos, and how many need a second request?”
- **Root cause:** “Which missing shot or misunderstanding produces the most rework?”
- **Reviewer output:** “What would make a packet usable by your team tomorrow?”
- **AR value:** “Would preliminary measurements help, or would clearer wide-angle photos be more valuable?”
- **Rules:** “Which requirements vary by battery generation, territory, or installation method?”
- **Adoption:** “Would you accept a capture link or app export into the current process, and who would own a pilot?”
- **Alternative opportunity:** “Is outage-load coordination or tariff explanation a more important unsolved problem than photo collection?”

## Bottom line and evidence limits

The recommendation is to build the enrollment workflow now, retain outage coordination as a separate next product, and treat tariff intelligence and physical optimization as distinct projects requiring their own data and validation. Connecting all four into one “platform” this weekend would obscure the evidence and multiply dependencies.

Confidence is high that the official photo workflow exists and that the current repository is a useful starting point; confidence is only moderate that it is Base's highest-value bottleneck. I did not interview Base, access its funnel metrics, sign into its member portal, test an iPhone build, validate the unofficial integration, or calculate real customer savings.

The strongest proof by tomorrow is not “we built more AI.” It is “a homeowner completed usable evidence, a reviewer understood it, and the workflow recovered cleanly when something was missing.”
