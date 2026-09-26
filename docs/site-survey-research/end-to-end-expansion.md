# Base Site Survey: End-to-End Expansion and Installation Rules

Research snapshot: September 26, 2026. Repository baseline reviewed: `605a6474deca0fbf9b0cd1675820857b14763404`.

## Product direction

Keep the native Swift repository and expand it into an **adaptive pre-installation survey**: identify the property's utility and Base program, guide the homeowner through the right photographs, extract component-specific labels, identify possible siting conflicts, and produce a complete engineering-review packet. The product should reduce missing evidence and unnecessary repeat visits, not claim to approve electrical work from a camera.

Base already asks homeowners for a nine-composition photo kit and has engineers review equipment and spacing; its published instructions explicitly encourage wide views that let the team find alternative installation locations ([Base photo-review instructions](https://help.basepowercompany.com/en/articles/10280641)). That supports an expanded workflow that says “show this label,” “capture the other side,” or “try another placement,” rather than only displaying a virtual battery.

Three boundaries are essential:

- **Utility program is not market type:** Confirm the named utility and Base program before choosing the expected connection arrangement.
- **Equipment evidence is not electrical diagnosis:** A meter number, meter class, panel bus rating, and main-breaker rating must remain separate.
- **Research rules are not approved installation rules:** Maintain source, date, model applicability, exceptions, and approval state for every requirement.

## Scrape coverage and limitations

The collection enumerated **176 public sitemap URLs** and retrieved **all 92 linked English help articles**; 165 sitemap pages exposed substantial text, while 10 form pages exposed loading shells and one battery-agreement page exposed a PDF wrapper ([Base sitemap](https://www.basepowercompany.com/sitemap.xml), [Base help center](https://help.basepowercompany.com/en/)). A separate source inventory records each collected URL, retrieval status, and available content hash, alongside supplementary utility, city, state, and code-reference sources.

This is a broad public-site snapshot, not a claim that private installer documentation, every signup branch, video content, and every diagram have been interpreted. An obsolete help-collection URL returned 404, but the current linked articles were collected; the directly fetched ICC section returned interface text rather than usable code text ([obsolete collection](https://help.basepowercompany.com/en/collections/11386041-agreements-and-policies), [ICC section interface](https://codes.iccsafe.org/s/IRC2024P1/chapter-3-building-planning/IRC2024P1-Pt03-Ch03-SecR330.4)).

The linked “current hardware” manual is a Growatt February 2024 document whose contents include APX equipment, so it must not silently become the installation manual for the newer Base Core model ([Base manual page](https://www.basepowercompany.com/usermanual), [linked Growatt manual](https://www.basepowercompany.com/_bpc/files/YSju1zp8DXgjh6U_-p55pw-growatt-user-manual-feb-2024.pdf)). The SDK could not retrieve that large PDF; a direct public-file download and local text extraction succeeded.

The deliverables are an interpreted research brief, a machine-readable rule catalog, and a source inventory. They intentionally do not republish the entire website as a customer-facing knowledge base.

## Connection arrangements: the Austin distinction is real, but not universal

### Utility and program matrix

“Front of the meter” and “behind the meter” describe electrical connection relative to the billing meter, not where the battery appears visually in a photograph. Base explicitly describes its Austin Energy program as front-of-meter, while its general utility-partnership page describes behind-the-meter installations and front-of-meter deployments where a program requires them ([Austin Energy program](https://www.basepowercompany.com/austinenergy), [Base utility partnerships](https://www.basepowercompany.com/utilities)).

| Program or utility | Verified public information | App behavior |
|---|---|---|
| Austin Energy + Base | Base states that the battery is in front of the customer's billing meter and the customer retains Austin Energy service ([program FAQ](https://www.basepowercompany.com/austinenergy)). | Select a dedicated Austin Energy program profile; require the approved design before any topology-specific installation conclusion. |
| Farmers Electric Cooperative + Base | Base explicitly describes front-of-meter battery installation and unchanged utility service ([Farmers FAQ](https://help.basepowercompany.com/en/articles/11390529)). | Separate Farmers profile; do not reuse Austin-specific amperage or meter geometry rules without confirmation. |
| CoServ + Base | Customer retains CoServ; battery energy not consumed by the home is credited through the Reliability Plus Participation Credit ([CoServ FAQ](https://help.basepowercompany.com/en/articles/11390465)). | Record the credit-based program; the reviewed FAQ does not establish an exact electrical one-line. |
| GVEC + Base | Base describes net-metered battery activity and a Renewable Energy Credit ([GVEC FAQ](https://help.basepowercompany.com/en/articles/11390721)). | Use a GVEC profile; billing language alone is not permission to infer the complete wiring arrangement. |
| El Paso Electric + Base | Base says the program battery has a separate meter and does not change the customer's existing utility billing arrangement ([El Paso Electric FAQ](https://help.basepowercompany.com/en/articles/11390785)). | Collect all relevant meters and their roles; do not force a single-meter data model. |
| Oncor territory | Oncor's February 2025 service guide requires a customer generator transfer switch on the load side of the meter base and prohibits that generator switch between meter and base; Base separately requires Oncor members to sign tariff and interconnection agreements ([Oncor guide, §100.01.18](https://www.oncor.com/content/dam/oncorwww/documents/new-construction/construction-guidelines/Electric%20Service%20Guidelines%20Book.pdf), [Base agreement FAQ](https://help.basepowercompany.com/en/articles/10283841)). | Treat the generator-switch clause as its named equipment scope, not a complete Base battery design or blanket statement about every approved adapter. |
| CenterPoint territory | CenterPoint's DER documentation calls for a one-line, site layout, and battery mode of operation; it distinguishes generator ATS approval from grid-parallel DER gateway approval ([CenterPoint DER guide](https://www.centerpointenergy.com/en-us/Documents/DistributedGenerationDocs/SmallScale-DER-Project-Documentation.pdf)). | Capture the meter, panel, disconnect, solar/gateway context, and configuration evidence. Do not treat every transfer device alike. |

Austin Energy's general customer-owned DER guide actually starts from behind-the-meter interconnection and permits special ahead-of-meter cases ([Austin Energy interconnection guide, Revision 14](https://austinenergy.com/-/media/Project/Websites/AustinEnergy/Contractors/AE_DG_Interconnection_Guide.pdf?rev=e5d375562efb4515bae892387b29e4d9&hash=A9043CEE17BBF4514E6503A1E786423E)). Therefore, “Austin Energy requires all batteries before the meter” would be incorrect; the supported statement is about **Base's specific Austin Energy program**.

Recommended data contract:

```text
Property
  confirmed address + unit
  location + uncertainty
  utility territory + confirmation source
  permitting jurisdiction + confirmation source

Installation profile
  Base program
  battery model + count
  connection arrangement
  approved one-line reference, when available
  rule-set revision + effective/project dates
```

Never select topology from `regulated = true` or from a ZIP code alone. Keep utility, city jurisdiction, equipment profile, and program as independent fields.

## Placement rules: what can be screened and what needs review

### Base's published operational requirements

These are Base's public guidance, not a substitute for the applicable code, utility standards, equipment listing, or approved site design. The app can use them to request evidence and flag apparent conflicts, while preserving uncertainty.

| Subject | Published requirement | Recommended survey behavior |
|---|---|---|
| Indoor versus outdoor | Batteries are installed outside; Base's photo guide excludes garages and indoor locations ([photo instructions](https://help.basepowercompany.com/en/articles/10280641)). | Ask the user to identify the candidate location and capture a wide scene. |
| Main breaker | Generally 100–200 A depending on solar/configuration; “in Austin” 150–200 A ([spacing and electrical FAQ](https://help.basepowercompany.com/en/articles/10280705)). | Read the actual main disconnect and confirm whether “Austin” means utility-program scope or another geographic scope with Base. |
| Solar or two batteries | Electrical panel must be rated 200 A ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Capture the panel nameplate and main disconnect separately; do not substitute one field for the other. |
| Gas meter | At least 3 ft from the battery ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Mark the gas meter and measure nearest relevant surfaces; preserve measurement uncertainty. |
| Windows | Battery cannot be in front of windows ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Capture every nearby window and proposed placement; do not suggest closing the window as a fix. |
| Electrical equipment | Battery cannot be in front of electrical meters, breaker boxes, or solar equipment ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Collect access-space geometry and equipment context, not just battery-to-meter distance. |
| Meter proximity and cable route | Within 20 ft of the meter; no trenching or attic conduit runs ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Capture the plausible route around corners and obstacles. Straight-line distance is not enough. |
| Wall offset | Within 1 ft of the wall ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Identify the intended wall rather than using whichever detected plane is nearest. |
| Planning footprint | Approximately 3 ft × 3 ft for each battery ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Keep planning envelope, physical body, and clearance envelope distinct. |
| Other obstacles | Photo instructions describe 3 ft clearance from AC units, fences, other batteries, and other obstructions ([photo instructions](https://help.basepowercompany.com/en/articles/10280641)). | Collect typed obstacles and distances; model/directional exceptions require confirmation. |
| Meter and panel relationship | Same wall, either beside each other or on opposite sides ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Ask for paired context views; a single exterior scan cannot establish the unseen interior relationship. |
| Panel location and count | Main breaker box cannot be in a closet; only one main breaker box ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Distinguish main panels from subpanels, and multi-unit service from a single household. |
| Meter height | No higher than 6 ft ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Capture finished-grade reference and the measurement point; do not invent a universal lower limit. |
| Equipment condition | Meter and conduit must be secure and undamaged ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Flag visible concerns for a professional; do not claim hidden equipment is sound because the exterior looks normal. |
| Transfer equipment | FAQ describes approximately 13 in switch width, 30 in clearance, and approximately 3 ft wall allocation ([requirements](https://help.basepowercompany.com/en/articles/10280705)). | Confirm the actual transfer equipment and applicable program before drawing its envelope. |

### Windows: fixed, operable, open, and closed are different questions

The 2024 IRC model language reproduced in an official state review worksheet specifies 3 ft from doors and windows directly entering the dwelling, with possible smaller separation under the UL 9540 listing and manufacturer's instructions ([official worksheet, R330.4](http://www.dli.mn.gov/sites/default/files/pdf/TAG-residential-070125-worksheet.pdf)). This is a model-code reference, not proof of the enforceable requirement or an approved exception for every Texas property.

Recommended capture fields:

- **Opening type:** Window, door, vent, air intake, or unknown.
- **Window construction:** Fixed, operable, or unknown.
- **Current position:** Open or closed, recorded separately from construction.
- **Room/egress context:** What the opening serves and whether its emergency-egress role is known.
- **Geometry:** Opening boundary, battery boundary, and measured separation with uncertainty.
- **Exception evidence:** Exact installed model, applicable listing, installation instructions, and professional approval.

Do not auto-pass a closed window, infer that fixed glazing is exempt, or promise that a three-foot move always resolves the issue. Base's “not in front of windows” instruction and an applicable numeric separation requirement may both need to be satisfied.

### Gas water heaters and vents

No verified universal Base battery-to-gas-water-heater distance was located in the reviewed public sources. Base's explicit 3 ft rule names gas meters, while Austin Energy's meter-location guidance separately names gas meters, regulators, and relief valves ([Base requirements](https://help.basepowercompany.com/en/articles/10280705), [Austin Energy design criteria, §1.9](https://austinenergy.com/-/media/project/websites/austinenergy/contractors/designcriteriamanual.pdf)).

Recommendation: do not reuse “3 ft from gas meter” as a universal rule for a furnace, heater, flue, regulator vent, or combustion-air intake. Ask for the appliance label, vent termination, surrounding scene, and relevant distances, then route to review under the applicable appliance and battery instructions.

### Three ambiguities that should block automatic green approval

- **Clearance directions:** The requirements page says within 1 ft of a wall, yet also includes 3 ft from walls or fixed features in its tight-space language; the photo guide separately describes side clearances ([requirements](https://help.basepowercompany.com/en/articles/10280705), [photo guide](https://help.basepowercompany.com/en/articles/10280641)). Treat the mounting wall, side exposures, and passageway as distinct geometries pending clarification.
- **Working-space dimensions:** Base's FAQ literally describes “30 in high x 36 inches wide,” while the retrieved Austin Energy manual specifies width of at least 30 in or equipment width, 36 in front depth, and 6 ft 6 in headroom ([Base FAQ](https://help.basepowercompany.com/en/articles/10280705), [Austin Energy design criteria](https://austinenergy.com/-/media/project/websites/austinenergy/contractors/designcriteriamanual.pdf)). Use typed width/depth/headroom fields and verify the applicable standard rather than copying the FAQ's dimensional wording.
- **Product generations:** Core's published body is 30.68 in wide × 35.9 in high × 22 in deep, while the legacy ground-mounted page lists 38 in wide × 36.25 in high × 24 in deep ([Core specs](https://www.basepowercompany.com/specs/core), [legacy specs](https://www.basepowercompany.com/specs/ground-mounted)). A universal 36-inch square cannot be treated as an exact bounding box for both models.

## City and state regulation: versioning is mandatory

### State change affecting every Texas city profile

Texas SB 1252 took effect September 1, 2025 and defines the covered residential backup category using no more than 50 kW **or** no more than 100 kWh; TDLR explains the limits on municipal installation/inspection regulation and the exception preserving municipally owned utilities' authority ([enrolled statute](https://capitol.texas.gov/tlodocs/89R/billtext/html/SB01252F.HTM), [TDLR implementation guidance](https://www.tdlr.texas.gov/news/2025/08/14/sb-1252-changes-to-residential-energy-backup-system-regulations/)). TDLR also states that non-exempt electrical work still requires applicable NEC compliance and licensed contractors/electricians ([TDLR guidance](https://www.tdlr.texas.gov/news/2025/08/14/sb-1252-changes-to-residential-energy-backup-system-regulations/)).

Product implication: the rules engine needs an **applicability decision**, not merely a pile of city ordinances. A numeric requirement may belong to Base policy, utility design, manufacturer instructions, a model code, or a particular city's remaining review scope; those categories must not be collapsed into one “legal requirement.”

### Initial city coverage

| Jurisdiction | Verified current or recent information | Implementation consequence |
|---|---|---|
| Austin | Austin lists 2024 technical codes effective July 10, 2025 and a 2026 NEC effective September 1, 2026; its fire page confirms the 2024 IFC adoption ([technical codes](https://www.austintexas.gov/development-services/building-technical-codes), [fire-code resources](https://www.austintexas.gov/fire/fire-building-code)). | Track city and Austin Energy scopes separately; obtain project-specific applicability and current utility design revision. |
| Dallas | Service First Bulletin 204 explains SB 1202/1252, continued zoning/building processes, and separate electrical permits for premise-wiring alterations, including service rebuilds, transfer switches, and panel changes ([Dallas bulletin](https://dallascityhall.com/departments/sustainabledevelopment/DCH%20documents/SFB%20%23204.pdf)). | Ask whether the proposal changes service/premise wiring. “Small battery” does not justify a “no permitting work” message. |
| Houston | Houston's updated process states that city inspections remain for service connections and gas piping, while the city does not inspect the covered generator, inverter, or batteries themselves; floodplain cases require additional contact ([Houston backup-power process](https://www.houstonpermittingcenter.org/news-events/notice-process-updates-residential-backup-power-systems)). | Separate battery-program review, electrical reconnect/service work, gas work, and floodplain review. |
| Round Rock | The current building-inspection page lists 2024 I-codes and 2023 NEC, while a June 2025 residential guide still discusses 2020 NEC ([current city page](https://www.roundrocktexas.gov/city-departments/planning-and-development-services/building-inspection/), [older residential guide](https://www.roundrocktexas.gov/wp-content/uploads/2025/06/Residential-Guide.pdf)). | Flag edition conflict; do not silently choose the first downloadable checklist. |

Houston's recent notice says state enforcement of the 2026 NEC begins September 1, 2026, consistent with Austin's updated page, while the retrieved TDLR general compliance FAQ still names the 2023 NEC ([Houston code notice](https://www.houstonpermittingcenter.org/news-events/request-public-comment-administrative-provisions-local-amendments-2026-national), [Austin technical codes](https://www.austintexas.gov/development-services/building-technical-codes), [TDLR general FAQ](https://www.tdlr.texas.gov/electricians/compliance-guide.htm)). Preserve this source-version conflict and confirm the operative rule and project date; a successful scrape does not mean every official webpage has been synchronized.

No city-specific automatic window exemption or universal gas-heater clearance was verified for these four jurisdictions. Outside the initial city set, retain a useful evidence-capture flow but label jurisdiction-specific evaluation unavailable rather than borrowing Austin rules.

### Model-code capacity limits require a separate applicability check

The reproduced 2024 IRC text includes a 20 kWh individual-unit limit and 80 kWh outdoor-ground aggregate provision, with installations beyond those limits directed to another compliance path ([official worksheet, R330.5](http://www.dli.mn.gov/sites/default/files/pdf/TAG-residential-070125-worksheet.pdf)). Base markets a 39.2 kWh Core system, so copying the model-code individual-unit number into a universal rejection rule would be inappropriate without confirming system/listing definitions and the applicable approval path ([Core specifications](https://www.basepowercompany.com/specs/core)).

Recommendation: request the exact system listing, current installation manual, approved configuration drawings, and any accepted testing-based exceptions from Base. Do not equate “UL 9540A testing mentioned on a webpage” with a project-specific permission to reduce clearances.

## Can a meter photo determine replacement?

**Usually it can determine the next evidence request, not the final replacement decision.** CenterPoint explicitly says most of its meters are bidirectional and can be programmed remotely, so a DER installation does not ordinarily require replacing the meter under that documented process ([CenterPoint DER guidance](https://www.centerpointenergy.com/en-us/Documents/DistributedGenerationDocs/SmallScale-DER-Project-Documentation.pdf)).

Use separate outcomes:

| Observation | Appropriate response | Inappropriate response |
|---|---|---|
| Meter label is unreadable | Ask for a focused close-up with less glare. | Guess from the largest digit string. |
| Meter number is readable but socket model is not | Save identity and request enclosure/context photos. | Infer socket compatibility from the meter serial. |
| Main breaker is outside the published program range | Flag configuration review, then collect panel and service evidence. | “Replace your utility meter.” |
| Meter class reads 200 but main rating is unknown | Keep meter class separate; ask for the main disconnect. | “Your main breaker is 200 A.” |
| Multiple meters or main panels | Ask which unit is served and capture an overview. | Assign the nearest meter based on GPS alone. |
| Visible damage, loose enclosure, or suspicious conduit | Advise safe distance and professional review. | Ask the homeowner to open the socket or remove covers. |
| Utility typically reprograms existing meters | Request utility/project confirmation where relevant. | Automatically require new hardware. |
| Socket or service arrangement is unfamiliar | Mark compatibility unknown and collect model/context evidence. | Treat lack of a catalog match as proof of incompatibility. |

Recommended underlying entities:

```text
MeterDevice
MeterSocketOrEnclosure
ServiceConductors
MainDisconnect
Panelboard
SolarInverterAndDisconnect
ExistingTransferEquipment
BatterySystem
```

A required equipment change should eventually carry a professional decision, reason, supporting photos, exact equipment identity, and an approved alternative. The user-facing wording should be “possible equipment change; Base review required” until that decision exists.

## End-to-end adaptive survey

### Property and program context

Start with confirmed address and unit, utility confirmation, homeownership, solar, generators, existing batteries, and the proposed Base hardware. Reuse geolocation to suggest territory and property records, but let the homeowner correct it.

Austin's public permit dataset provides parcel/address identifiers, electrical-work descriptions, status, and dates that can supply historical hints ([Austin permit schema](https://data.austintexas.gov/api/views/3syk-w9eu.json)). Keep a historical permit assertion separate from current camera evidence, and turn conflicts into targeted follow-up questions.

### Electrical capture

Use the existing meter and breaker tiles, but expand them into typed photo slots. The Base kit includes meter identity, wide meter-wall views, left/right/adjacent-wall context, conditional fence views, main panel, main disconnect, and panel-location context ([Base photo instructions](https://help.basepowercompany.com/en/articles/10280641)).

Recommended live coaching:

- **Framing:** “Include the full printed meter label.”
- **Legibility:** “The number is not stable yet. Hold still or change angle to reduce glare.”
- **Semantic ambiguity:** “This looks like a meter class. Now photograph the main disconnect.”
- **Missing context:** “Step back so we can see the meter, panel, and nearby wall.”
- **Panel ambiguity:** “Is this the main disconnect or a subpanel? Add a wider photo.”
- **Conflicting evidence:** “The permit history and this label differ. Keep both photos for review.”

Proposed architecture: Vision proposes observations; a deterministic evidence checklist selects the next prompt; the user confirms the identified field. A language model, if later introduced, should not invent a clearance or override the structured rule source.

### Placement and obstacles

Extend the current AR screen with typed markers for windows, doors, gas meter/regulator, AC units, heater vents, fences, existing electrical equipment, and the proposed route. Let the user mark objects manually first; do not depend on a general camera model recognizing every hazard.

Show three separate overlays: physical battery body, installation/planning envelope, and required access or exposure zones. Uncertain tracking or unobserved obstacles must produce “needs evidence,” not “clear.”

For a minimum distance rule with an uncertainty interval, only label the measurement as preliminarily within range when the entire interval exceeds the threshold. If the uncertainty overlaps the threshold, request a better measurement; this is a recommended conservative screening policy, not a claim about the phone's achieved accuracy.

### Conditional expansion

- **Solar:** Ask for inverter/disconnect context and, where Base requests it, the complete existing interconnection agreement rather than just a PTO letter ([Base solar-document FAQ](https://help.basepowercompany.com/en/articles/10283777)).
- **Legacy battery with A/C:** Base's soft-start article applies its greater-than-100-LRA screen to 25/50 kWh systems, not Core ([soft-start FAQ](https://help.basepowercompany.com/en/articles/10280897)). Add a photograph of each condenser nameplate only when relevant.
- **Core with A/C:** Base excludes Core from the legacy provided-soft-start program, while another article discusses combined LRA above 160 without explicitly naming the model or resolving the equality boundary ([soft-start FAQ](https://help.basepowercompany.com/en/articles/10280897), [whole-home A/C FAQ](https://help.basepowercompany.com/en/articles/12867073)). Capture the data, but confirm applicability before automating a prescription.
- **Existing third-party battery:** Base now documents an eligible retail-choice energy-plan route without installing or taking over that battery ([existing-battery FAQ](https://help.basepowercompany.com/en/articles/13806657)). Offer an alternative pathway instead of labeling the household universally ineligible.
- **Generator:** Distinguish portable generator/interlock/recharge-port cases from whole-home standby generators ([Base generator FAQ](https://help.basepowercompany.com/en/articles/10282049)). Capture the transfer-equipment context and route compatibility to review.
- **Obstructed preferred location:** Ask for adjacent-wall or behind-fence views and create a second placement candidate rather than forcing a single location ([Base photo guidance](https://help.basepowercompany.com/en/articles/10280641)).

### Review and handoff

The final packet should include confirmed property/program context, typed equipment observations, original photographs, measurements and uncertainty, matched rules with sources, contradictions, and unanswered questions. Present “ready for Base review,” not “installation approved.”

Keep agreement status, utility design approval, and engineering follow-up as future workflow fields. Do not simulate a Base submission, signature, permit filing, or utility authorization that the app has not actually performed.

## Fit to the existing repository

The reviewed remote snapshot is substantially ahead of the earlier snapshot: it includes live label scanning, a broader electrical-label parser, explicit measurement endpoints, and expanded review logic. This research does not replace that implementation, and no app source files or remote branches were changed.

| Existing area | Recommended extension |
|---|---|
| `SurveySession.swift` | Add optional `PropertyContext`, `InstallationProfile`, `PhotoEvidence[]`, and typed `EquipmentObservation[]`; preserve decoding compatibility. |
| `LiveLabelScanner.swift` | Keep the live camera interaction, but expose the target component and reason for recapture. |
| `VisionElectricalRecognizer.swift` | Return candidates with text, bounding boxes, component type, and provenance rather than only a scalar string or amperage. |
| `BaseRuleSet.swift` | Replace unconditional Austin rules with explicitly scoped profiles; preserve `unknown` when utility/model/applicability is unresolved. |
| `PlacementARView.swift` | Add typed obstacle markers and alternative candidates; keep the same world-tracking and measurement approach. |
| `SurveyEvaluating.swift` | Separate completeness, preliminary compatibility, and professional-review state. |
| `ReviewView.swift` / exporter | Export source-backed reasons, unresolved questions, full photo slots, and which values were measured versus attested. |

### Specific issues to fix before broader geographic rollout

- **Unconditional Austin range:** The current rule array applies the Austin main-breaker check without a utility/program resolver. Broader rollout needs explicit scope selection.
- **Panel/main substitution:** The solar/two-battery rule currently reads `mainBreakerAmperage` while describing panel rating. Add the separate nameplate evidence before claiming that requirement passed.
- **OCR selection risks:** The parser can prefer the largest recognized rating and can join short numeric fragments for a meter number. Require same-label spatial association and confirmation rather than concatenating unrelated numbers.
- **Meter-height minimum:** The repo uses a 3 ft minimum, while Base's FAQ supplies only a 6 ft maximum; the retrieved Austin Energy table varies its minimum by socket type, including 30 in and 48 in categories ([Base requirement](https://help.basepowercompany.com/en/articles/10280705), [Austin Energy table 1.9.2.C](https://austinenergy.com/-/media/project/websites/austinenergy/contractors/designcriteriamanual.pdf)). Do not use the 3 ft floor as a universal rejection rule.
- **Evidence classification:** Explicitly confirming an AR working-space overlay is not the same as instrumentally verifying every required dimension. Preserve attestation separately from measured evidence.
- **Green status semantics:** Even complete preliminary checks must not imply utility, code, or installation approval.

The repo's current guidance prohibits introducing a backend or external datasets unless later scope requests them. This expansion does request external research/data, but a practical first implementation can still bundle a reviewed, versioned catalog locally and add live property enrichment as a separate, explicitly designed workstream.

## Recommended implementation order

### First release: better evidence, no new backend dependency

Implement typed photo slots, explicit utility/program selection, separate main-breaker and panel-nameplate evidence, model-aware geometry, and a source-backed missing-evidence list. Bundle the research catalog as data after Base reviews the applicable rules; do not load raw scraped prose directly into an approval engine.

### Second release: adaptive capture and property enrichment

Connect confirmed address/utility to public permit history, add recapture prompts, and expand the AR obstacle inventory. Prioritize a complete reviewer packet over automatic equipment recognition or automatic replacement recommendations.

### Later release: authorized operational workflow

Add utility-authorized metadata, a verified equipment compatibility catalog, Base reviewer decisions, and approved document handoff only when those integrations and permissions exist. This is the point at which a human-approved “equipment change required” decision can become a reliable downstream action.

## Review checklist before enabling production rules

Request these specific items from Base:

- **Current Core installation manual:** Exact revision, allowed configurations, physical and service clearances.
- **Program one-lines:** Austin Energy, Farmers, CoServ, GVEC, El Paso Electric, Oncor, and CenterPoint, including approved transfer hardware.
- **Compatibility table:** Accepted meter/socket/service types, exclusions, and which cases require replacement, reprogramming, or a custom design.
- **Window policy:** Fixed versus operable, egress/opening interpretation, numeric separation, and documented exceptions.
- **Gas/appliance policy:** Meter/regulator, water-heater/furnace vent, intake, and other relevant exposure criteria.
- **Model-specific panel rules:** Whether the “200 A panel” wording refers to an approved service configuration, main rating, bus rating, or multiple constraints.
- **Code and permit applicability:** Current city/utility workflows, state-law treatment, project-date selection, and accepted testing/listing exceptions.
- **Geometry definitions:** Whether distances are measured from enclosure edges, meter socket center, walls, route length, or another reference.

Manual acceptance scenarios should include an Austin candidate with a 125 A main, a 225 A bus with a 200 A main, a CenterPoint meter needing programming rather than replacement, a closed operable window, an unknown gas vent, a multi-meter property, an older permit that conflicts with current labels, and a poor-tracking AR session. The success criterion is the correct next prompt or review route, not forcing every household to pass.

## Bottom line

The strongest expansion is **“Base setup assistant that knows what evidence this property and configuration require.”** A utility-aware profile, semantic equipment capture, obstacle-aware placement, and an auditable handoff build directly on the repo while addressing the real enrollment gap.

Automatic meter-replacement decisions are not yet supported by a verified public compatibility matrix. The researched rules should first make the homeowner's capture session more complete and the engineer's decision easier, while keeping final design and safety approval with the responsible professionals.
