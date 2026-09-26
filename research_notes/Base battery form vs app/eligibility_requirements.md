# Base Core eligibility and site requirements

Retrieval window: September 2026. Primary sources are official Base Power Company pages (`basepowercompany.com`) and the Base Help Center (`help.basepowercompany.com`). Help-article last-edited dates below are taken from Front KB `last_edited` / on-page “Edited …” stamps as of 26 September 2026. Marketing site facts are from live HTML fetched the same day.

Product scope: Base Power Company (Austin HQ; residential battery + VPP / retail electricity). Product family includes **Base Core (39.2 kWh)**, plus older **25 kWh single / 50 kWh double** ground-mounted systems and a **20 kWh wall-mounted** SKU mentioned in HOA materials. Not Coinbase “Base.”

## What electrical eligibility does Base require (main breaker amperage, panel type, solar, two-battery rules, service size, meter type)?

### Takeaway
Official Help Center text is the only quantified electrical eligibility source: main breaker **100–200A** generally (stricter **150–200A in Austin**), **200A-rated panel required if the home has solar or a dual-battery system**, a **single main breaker box** that **shares a wall with the meter**, and a **hard 200A system ceiling**. Meter *type* is not an eligibility filter; Base asks for a readable **meter number** on a typical round residential meter.

### Cited Findings
- “The main breaker in the electrical panel must be **100-200A**, depending on whether the home has solar and how many batteries we’re installing. **In Austin, it must be 150-200A.**” — [What are the electrical and spacing requirements for Base equipment?](https://help.basepowercompany.com/en/articles/10280705) (edited 17 August 2026)
- “For a **dual battery system**, your electrical panel must be **rated 200A**.” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “If you have **solar** on your home, your electrical panel must be **rated 200A**.” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “There must only be **1 main breaker box**.” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “The meter and main breaker box need to **share the same wall** (either next to each other on the same exterior wall or on opposite sides of the same wall).” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “The main breaker box **cannot be located in a closet**, as it must be kept away from flammable materials.” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “The meter must be installed **no higher than 6 feet** off the ground.” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “In front of the meter and main breaker box there must be a **clear space of 30 in high x 36 inches wide**.” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “The meter and conduit must be **securely attached and undamaged**.” Same article. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Photo-review article asks for the **amperage number** on the main disconnect, “usually **125, 150, or 200**.” It does not say 125A is always eligible. — [Why does Base request home photos?](https://help.basepowercompany.com/en/articles/10280641) (edited 29 July 2026)
- Specs FAQ: “Base systems **only support up to 200 amps**, so if you plan to upgrade your main panel to exceed 200 amps, please contact us.” — [Base Core System Specifications](https://www.basepowercompany.com/specs/core); same wording on [Ground Mounted Battery System Specs (25/50 kWh)](https://www.basepowercompany.com/specs/ground-mounted)
- After-install upgrade article: “Base systems support a **maximum of 200 amps**. In most cases, Base **cannot support upgrades above 200A**, as they typically require splitting the panel, which would necessitate the **de-installation** of your Base system.” — [Do I need to do anything if I'm installing an EV charger or making other electrical upgrades?](https://help.basepowercompany.com/en/articles/10282241)
- Solar is **not required**. Batteries “store energy directly from the grid.” — [Does Base require Solar?](https://help.basepowercompany.com/en/articles/10281537); also [llms.txt](https://www.basepowercompany.com/llms.txt) (“Solar is not required, and the battery also works with existing solar.”)
- Existing solar is allowed: “Base batteries integrate seamlessly with **most** solar panels.” Not a guarantee of every inverter topology. — [Can I join Base if I have solar?](https://help.basepowercompany.com/en/articles/10281665)
- After solar is added, Base requires **AC-coupled** solar via a **back-fed breaker**. “Base does **not** support DC-coupled systems wired into the Base inverter.” “Do **not** line side tap solar leads into the Hub.” “No back-fed equipment should be installed **upstream of the Base SYN**.” — [What steps do I need to take if I am adding solar panels after my Base system installation?](https://help.basepowercompany.com/en/articles/10282689)
- That same solar-installer article names the Hub as “the white panel that contains our **200A service disconnect**” and references Growatt hardware for 25 kWh installs: “APX HV Battery US [Growatt APX HV, modular 5–30 kWh]” and “Inverter (MIN 8200~11400TL-XH-US).” — [10282689](https://help.basepowercompany.com/en/articles/10282689)
- Whole-home backup is limited by **instantaneous kW**, not just breaker size: **Base Core** must see **< 20 kW** to turn on; **one or two 25 kWh** batteries must see **≤ 11 kW** to turn on (two-battery systems may then go to **22 kW after 5 minutes**). — [Does the battery back up my whole home? How much power can it handle?](https://help.basepowercompany.com/en/articles/10627905) (edited 25 September 2026)
- A/C startup: if **combined LRA > 160**, the home may need to shed A/C for the battery to start (then wait 5 minutes). — [What does whole-home backup mean?](https://help.basepowercompany.com/en/articles/12867073)
- Soft starts apply to **25 kWh and 50 kWh only**, not Base Core. On those systems, **LRA over 100** “need[s] a soft start.” Soft starts are “**not** provided for Base Core (our 39.2 kWh battery).” — [What is a soft start and do I need one?](https://help.basepowercompany.com/en/articles/10280897)
- Hardware lineup (Help): “Base offers a **25 kWh, 39.2 kWh, and 50 kWh** capacity battery system with an **11 kW inverter**.” Surge protector added on install if the older home lacks one (on the main panel for 25/50 kWh; on the **battery disconnect** for 39.2 kWh). — [What hardware does Base use?](https://help.basepowercompany.com/en/articles/10280513) (edited 11 September 2026)
- Electrical service voltage published as **120/240 V** nominal, **60 Hz**. — [specs/core](https://www.basepowercompany.com/specs/core); [specs/ground-mounted](https://www.basepowercompany.com/specs/ground-mounted)
- Meter description for photos: “The gray box with a **circular device** protruding from it, located on the exterior of your home. Ensure the photo is zoomed in enough for the **meter number** in the red box to be legible.” No published eligibility by smart vs analog, form 2S, etc. — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Core specs table (marketing): Total energy **39.2 kWh**; AC voltage **120/240 V**; certifications **UL 1973, UL 9540, UL 991, UL 1998, UL 1741, IEEE 1547-2003**. — [specs/core](https://www.basepowercompany.com/specs/core)

### Inferences
- “Main breaker 100–200A” and “panel rated 200A” are **not the same test**. Solar and dual-battery rules are written as **panel rating = 200A**, while the general band is about the **main breaker**. Official text never maps 100A vs 125A vs 150A for a **no-solar, single-battery** home outside Austin.
- Austin’s **150–200A** floor is the only city-named breaker exception found. It is consistent with the hackathon brief’s “Austin: 150–200A,” but official pages do **not** say 150A is the floor everywhere.
- The 200A ceiling is both an eligibility cap and a **post-install lock-in**: splitting a panel for >200A service is treated as requiring de-installation.

### Gaps
- Official pages do **not** say whether a **100A** or **125A** no-solar single-battery home is accepted outside Austin; they only give the 100–200A band plus the 200A solar/dual rules.
- No published eligibility by **meter type** (smart meter, analog, socket form, CT-rated service).
- No published eligibility by **panel brand/type** (Split-bus, Rule of Six, Zinsco, Federal Pacific, indoor vs outdoor enclosure) beyond: one main breaker box, not in a closet, same wall as the meter, undamaged meter/conduit.
- “Panel rated 200A” vs “main breaker 200A” is not defined (bus rating vs breaker handle rating vs utility service size).
- Wall-mounted **20 kWh** is listed in HOA materials but is **absent** from the three configurations in the electrical/spacing article; its electrical rules are unpublished on the pages fetched.

## What siting / placement rules does Base publish (footprint, wall distance, meter distance, gas meter clearance, transfer switch space, indoor/outdoor, flood, HOA, etc.)?

### Takeaway
Ground-mounted batteries are **outdoor-only, near the meter**: **3 ft × 3 ft** footprint per battery, **within 1 ft of the wall**, **within 20 ft of the meter**, **≥ 3 ft from gas meters**, **not in front of meters / breaker boxes / solar equipment / windows**, plus wall space for an **automatic transfer switch (~13 in wide, 30 in NEC working clearance, 3 ft of wall allocated)**. Indoor, garage, underground, and attic conduit are explicitly disallowed. Flood is a **product rating** (Core IP67 / 3 ft submersion), not a published site-eligibility rule. HOA treatment differs by state.

### Cited Findings

**Product dimensions (planning envelope)**
- Base Core published dimensions: **Width 30.68 in**, **Height 35.9 in**, **Depth 22 in**. — [specs/core](https://www.basepowercompany.com/specs/core)
- Ground-mounted 25/50 kWh published dimensions: **Width 38"**, **Height 36.25"**, **Depth 24"**. Operating temperature **14 to 122 °F**. — [specs/ground-mounted](https://www.basepowercompany.com/specs/ground-mounted)
- Help spacing article (applies to ground-mounted): “Each battery occupies a **3ft x 3ft area** and is about **36 inches tall**.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Photo article: “Each battery is roughly the size of an AC unit” and “Each battery is **3 feet wide**, and needs **3 feet of clearance on both sides**.” — [10280641](https://help.basepowercompany.com/en/articles/10280641)

**Distance / clearance rules (Help electrical & spacing article)**
- Typical layout: “installed near the electric meter, with **3ft of space allocated on the wall for mounting the automatic transfer switch**, followed by a **3ft x 3ft ground footprint** for the first battery, and **another 3ft of space for the second battery** when applicable.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “Must be **at least 3 feet apart from gas meters**, and **cannot be placed in front of electrical equipment** (electrical meters, breaker boxes, or solar equipment, etc.) **or windows**.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “Should be installed **within 20 feet of the electrical meter**. A wiring harness runs from the battery to the meter, and Base **cannot perform any trenching or attic conduit runs**.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “Should be placed **within 1 foot of the wall**.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Alley / tight space: “ensure a **clear walk-by space of 32-38 inches** is maintained while maintaining a **minimum clearance of 3 feet from walls or other fixed features**.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Integrated pad only: “There is an **integrated base** at the bottom of the battery. We do **not** offer any other type of base… **Please do not pour your own concrete pad**.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Transfer switch: “approximately **13 inches wide** and requires a **total clearance of 30 inches** to accommodate National Electrical Code working space requirements. The transfer switch **must be installed on the wall next to the electrical meter**. Ensure to measure the distance between obstacles like fences or solar equipment to properly accommodate the switch.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- “all Base hardware is installed on the **exterior** of your home.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Final location is **not guaranteed** from photos: “The Base Power team is **unable to guarantee exactly where** your battery system will be installed. On your installation day, you can work with the electricians… so long as it remains within standard operating procedures and meets National Electric Code.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Sprinkler heads: install crew “will work with you on the best solution.” Not a published numeric setback. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Bushes / obstructions may be asked to be removed. — [10280705](https://help.basepowercompany.com/en/articles/10280705)

**Broader clearance language (photo-review article — overlaps but is not identical)**
- “Each battery … needs **3 feet of clearance from gas meters, AC units, fences, other batteries, or other obstructions**.” — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- “The battery system is **always installed outside near the electric meter**. Batteries **can't be installed indoors or in garages**, and we **can't run conduit underground or through attics**.” — [10280641](https://help.basepowercompany.com/en/articles/10280641)

**Indoor / outdoor / configurations**
- Three published ground-mounted configs: **25 kWh Single**, **39.2 kWh Single (limited beta in select areas)**, **50 kWh Double** (“great for homes with a lot of outdoor space and high energy needs”). — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- HOA article also lists a **“20 kWh single wall-mounted”** spec sheet among the SKUs. — [Will I need HOA approval?](https://help.basepowercompany.com/en/articles/10195137)
- llms.txt: specs cover “**ground-mounted and wall-mounted** home batteries.” — [llms.txt](https://www.basepowercompany.com/llms.txt)
- Typical-install article is photo-only examples of 39.2 single, 25 single, and double 25 (50 kWh). No measurements in the text. — [What does a typical Base system installation look like?](https://help.basepowercompany.com/en/articles/10281281)

**Flood / environment**
- Marketing (Austin Energy Core page): “Tested for **-22 to 122°F**, **flash flooding**, and **submersion-rated to 3 feet**.” “**IP67** submersion testing (rated to 3 feet), **IPX9K** high-pressure water testing, and internal flash-flood testing.” — [austinenergy/core](https://www.basepowercompany.com/austinenergy/core)
- Core spec table operating temperature: **-22 to 122 °F**. — [specs/core](https://www.basepowercompany.com/specs/core)
- Help temperature article (older/generic): “**−10°C to 50°C (14°F to 122°F)**.” — [What is the temperature range of the battery?](https://help.basepowercompany.com/en/articles/10280577)
- Ground-mounted (25/50) spec table: **14 to 122 °F**. — [specs/ground-mounted](https://www.basepowercompany.com/specs/ground-mounted)
- No Help or marketing page fetched states “homes in a FEMA flood zone are ineligible” or gives a required pad elevation.

**HOA / aesthetics / location on the lot**
- Texas: “Under Texas law, HOAs **cannot ban** Base batteries installed in your **fenced-in yard or patio**. Exact placement depends on your home's layout.” Cites **Property Code §202.010 & Tax Code §171.107**. “Hardware is installed near the electric meter along an exterior wall. **No changes are made to the roof or front face of the home.**” — [10195137](https://help.basepowercompany.com/en/articles/10195137)
- Illinois: “Illinois law protects homeowners' rights to install **solar energy systems, including storage devices that collect and store solar energy**. Whether that protection applies to your installation will **depend on your specific setup**.” Cites **765 ILCS 165**. Homeowners are told to contact the HOA before scheduling. — [10195137](https://help.basepowercompany.com/en/articles/10195137)

**Noise / chemistry (siting-adjacent, not placement geometry)**
- Core noise: **55 dBA at 1 meter**. — [specs/core](https://www.basepowercompany.com/specs/core)
- 25/50 kWh noise: **40 dB (nearly silent)** at 1 meter. — [specs/ground-mounted](https://www.basepowercompany.com/specs/ground-mounted)
- Chemistry: LiFePO₄; “active fire suppressants” / airbags inside the battery (HOA article). — [10195137](https://help.basepowercompany.com/en/articles/10195137)

### Inferences
- The hackathon brief’s placement set (3×3 footprint, ≤20 ft to meter, ≤1 ft to wall, ≥3 ft from gas, transfer-switch space beside the meter, outdoor) **matches the 17 August 2026 Help article almost verbatim**. Official extras the brief does not capture: **meter height ≤6 ft**, **30×36 in working space in front of meter/panel**, **same-wall meter+panel**, **no closet panel**, **one main breaker box**, **32–38 in alley walk-by**, **no customer-poured pad**, **no placement in front of windows / electrical / solar equipment**, and **ATS ~13 in / 30 in clearance**.
- Photo-article “3 ft clearance on **both sides**” plus “3 ft from fences / AC units / other batteries” is **stricter and wider** than the electrical article’s 3×3 footprint + 3 ft from gas. Treat these as **two official but not fully reconciled** clearance models.
- Alley walk-by of 32–38 in **and** “minimum clearance of 3 feet from walls” sit in the same bullet; they can conflict on a narrow lot. Official text does not resolve which wins.

### Gaps
- No official numeric rule for **doors, property lines, HVAC condensing units, or windows** beyond “cannot be placed in front of … windows” and the photo-article’s 3 ft from AC units/fences.
- No published **flood-zone / finished-floor / pad-elevation** eligibility rule, only Core’s IP67 / 3 ft submersion *test*.
- Wall-mounted 20 kWh siting rules (height, wall type, indoor vs outdoor) are unpublished on the pages fetched.
- “Within 20 feet” is “should,” not “must.” Official text does not say what happens if the only viable pad is 21+ ft away.

## What photos, measurements, or evidence does Base say they need to evaluate a site?

### Takeaway
After signup, Base emails a **homeowner photo-upload link**. Engineers use those photos — not a homeowner-completed measurements form — to check electrical and spacing rules. Required shots are **meter (with readable meter number)**, **wide surroundings left/right/adjacent wall/behind fence**, **main breaker box**, and a **zoomed main-disconnect amperage**. The only homeowner-stated measurement in the photo brief is “at least **10 steps** back.” LRA, solar IA, and some clearances are collected later or only if needed.

### Cited Findings
- Purpose: “To help Base ensure your home meets the **electrical and spacing requirements** for a backup system installation, **after you sign up we will send you a link** to submit a few key photos.” — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- “Submitting home photos allows Base to evaluate whether a home meets the electrical and spacing requirements for our equipment.” — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Austin Energy marketing funnel: “**Check eligibility in minutes**” then “**Snap a few pictures**” / “Send a few photos of your home. **Our engineers will determine** which Base Core configuration is best for you.” — [austinenergy](https://www.basepowercompany.com/austinenergy)
- **Required photo list** (field names as published):
  1. **Electric meter** — gray box, circular device; **meter number** must be legible.
  2. **Area surrounding your meter** — from as far back as possible (**at least 10 steps**), zoomed out.
  3. **Area to the right of your meter** — ≥10 steps; looking for battery space; “3 feet wide… 3 feet of clearance on both sides.”
  4. **Area to the left of your meter** — same (the left-side bullet accidentally repeats “area to the right” in the official text).
  5. **Wall adjacent to the wall with the meter** — entire side, corner to corner; space around the closest corner.
  6. **Area behind the fence (if applicable)** — full side behind the fence.
  7. **Main breaker box** — “Usually located outside next to your meter or in your garage.”
  8. **Main disconnect switch** — “amperage number - usually 125, 150, or 200”; “either inside your main breaker box or outside next to your meter.”
  9. **Area surrounding the main breaker box (if not already captured)** — location (outside, garage, or closet).
  — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Troubleshooting evidence: clear wood piles first; if there is “an electrical box connected to your utility meter with a small black/grey box on it, **lift the lid** to show your main breaker switch.” Missing that **delays review**. — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Review SLA: “The **Base engineering team** will review your photos and reach out **within 2 days** if any additional information is needed.” — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Tips: daytime, wide angle, no obstructions. — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Soft-start / A/C: “If you can't locate [LRA], **Base will check this during your photo review**, or our electricians will confirm it **on-site**.” — [10280897](https://help.basepowercompany.com/en/articles/10280897)
- Solar homes: utility may require the existing **Interconnection Agreement** (full 12–15 page IA PDF, not the application or PTO). “**We'll let you know if we need it.** If not, that means it's not required by your utility and/or you don't have solar.” Oncor contact `dg@oncor.com`; CenterPoint `residential.dg@centerpointenergy.com`. — [What is an Interconnection Agreement (IA)?](https://help.basepowercompany.com/en/articles/10283777)
- Homeowner-made site fixes: “if you make changes to your electrical panel or outdoor space … a team member from Base will **review the evidence that you send in** and confirm if the updates meet the requirements.” Evidence type is not specified. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- $50 deposit “reserves our team's time to **review your photos and start your paperwork**.” Refundable until photos are approved / paperwork begins (wording differs slightly across articles). — [Why do you ask for a $50 refundable deposit?](https://help.basepowercompany.com/en/articles/10311169); [How much does the battery cost?](https://help.basepowercompany.com/en/articles/10194945); Austin Energy FAQ on [austinenergy](https://www.basepowercompany.com/austinenergy)

### Inferences
- Official evaluation is **photo-first, measurement-second**. Homeowners are not asked to enter wall-distance, meter-distance, or footprint numbers; engineers infer space from wide photos and then electricians confirm on install day.
- The only structured numeric field implied in the photo kit is **main-disconnect amperage** (and **meter number** as an identifier, not a rule input).
- Closet panels are both a **photo target** (“we need to see … in a closet”) and an **eligibility fail** (“cannot be located in a closet”).

### Gaps
- No official list of **required measurements** (tape-measure fields) for the homeowner. Distances in the spacing article are for **Base/engineers/installers**, not a published homeowner worksheet.
- No published requirement to photograph a **gas meter** even though 3 ft gas clearance is a placement rule.
- No published requirement to photograph **A/C nameplates / LRA** even though LRA is used later.
- Address / utility / occupancy fields used at signup (`/get-started`, `/core-form`) were not fully inventoried here (signup is a JS form). Official marketing says availability “varies by address.”

## Do official pages distinguish homeowner self-check vs installer/engineer evaluation?

### Takeaway
Yes. Homeowners **self-report via photos (and a $50 deposit)** after an address-level eligibility check; **Base engineering** judges electrical/spacing compliance from those photos; **licensed Base electricians** finalize placement on install day; **cities/utilities** do post-install inspections. Homeowners are not told they can self-certify a site as passing.

### Cited Findings
- Homeowner action: submit photos after signup. — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Evaluator named: “**Base Power's engineering and installation teams** require these photos to verify compliance with electrical code standards.” “The **Base engineering team** will review your photos…” — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Austin Energy marketing: “**Our engineers** will determine which Base Core configuration is best for you.” Permits and install: “we take care of all the details. Our **expert crew**…” — [austinenergy](https://www.basepowercompany.com/austinenergy)
- Install-day homeowner presence is **optional unless** “your main breaker box is in your garage or inside, or you want to request a specific battery placement.” — [What do I need to know on the day of installation?](https://help.basepowercompany.com/en/articles/10280833)
- Preferred spot: “you **must be home** during installation to discuss options with the crew. While they must follow electrical and spacing code requirements, they’re usually able to accommodate slight adjustments within code.” — [10280641](https://help.basepowercompany.com/en/articles/10280641)
- Electricians “will **not** be able to perform additional electrical upgrades or modifications—such as outlet removals, **panel changes**, or charger installations—on the day of your battery installation.” Those must be done **before** install by a licensed electrician. — [10280833](https://help.basepowercompany.com/en/articles/10280833)
- Permits: “**Base manages all permitting** creation, submission, and inspection with local cities and utilities.” — [10195137](https://help.basepowercompany.com/en/articles/10195137)
- City inspections: “Some cities require one or two electrical inspections after installation… **Base will handle all coordination**… no additional cost.” — [Do cities require permits for Base battery installations?](https://help.basepowercompany.com/en/articles/10281089)
- Installers are “certified, bonded, insured, and licensed electricians under the supervision of our master electrician (**license #476697**).” — [What safety precautions does Base take?](https://help.basepowercompany.com/en/articles/10280961)
- Installer-partner marketing exists ([install-partners](https://www.basepowercompany.com/install-partners)) but public Help text still describes **Base’s** engineering review + Base/partner crews, not a homeowner DIY install.

### Inferences
- Three official layers: (1) **address / signup eligibility**, (2) **engineering photo review**, (3) **on-site electrician + AHJ inspection**. A homeowner self-check app can only approximate layer 2.
- Base does **not** publish a homeowner pass/fail checklist with all numeric rules on the signup page; the rules live in Help, and the decision is reserved to engineers.

### Gaps
- The “check eligibility in minutes” step (Austin Energy) is not documented as a public rule table — it is almost certainly **address / utility coverage**, not electrical.
- No published rubric for how engineers score a photo set (what is auto-fail vs request-more-photos vs on-site judgment).

## What is explicitly out of scope or "Base will check later"?

### Takeaway
Base is explicit that **final placement, LRA/soft-start, some solar paperwork, city inspections, and some electrical upgrades** are deferred. Several homeowner-relevant items are **out of product scope**: life-critical medical backup, overnight solar self-consumption, DC-coupled solar into the Base inverter, indoor/garage install, customer-poured pads, trenching/attic runs, same-day extra electrical work, and (usually) adding a generator recharge port after signup.

### Cited Findings
- **Placement not guaranteed from photos**; finalized on install day within NEC / SOP. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- **LRA / soft start**: determined “after reviewing your photo submission, **or sometimes when our electricians are on-site**.” — [10280897](https://help.basepowercompany.com/en/articles/10280897)
- **Solar IA**: “**We'll let you know if we need it.**” — [10283777](https://help.basepowercompany.com/en/articles/10283777)
- **City inspections**: scheduled after install; Base coordinates. — [10281089](https://help.basepowercompany.com/en/articles/10281089)
- **39.2 kWh Core two-visit install**: Visit 1 electrical + pad (homeowner must be home; power off 1–3 hours); Visit 2 battery set (no one needs to be home), “within three weeks.” — [10280833](https://help.basepowercompany.com/en/articles/10280833)
- **Post-install diagnostics**: battery may not show as active in the app for **1–2 days**. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- **Life-critical medical devices**: “Backup energy **should not be used for life-critical devices and cannot be guaranteed**.” — [Does Base back up life-critical medical devices?](https://help.basepowercompany.com/en/articles/10283521); restated in the battery agreement FAQ — [10283073](https://help.basepowercompany.com/en/articles/10283073)
- **Not a solar storage / overnight self-consumption battery.** “If overnight self-consumption is your primary goal, Base isn't designed for that use case.” — [Can I use Base as an overnight solar battery?](https://help.basepowercompany.com/en/articles/11270081)
- **DC-coupled solar into the Base inverter** is unsupported. — [10282689](https://help.basepowercompany.com/en/articles/10282689)
- **Indoor / garage install, underground conduit, attic runs** cannot be done. — [10280641](https://help.basepowercompany.com/en/articles/10280641); [10280705](https://help.basepowercompany.com/en/articles/10280705)
- **Customer concrete pad** not offered / not allowed. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- **Same-day extra electrical work** (panel changes, outlets, EV chargers) is out of scope for the install crew. — [10280833](https://help.basepowercompany.com/en/articles/10280833)
- **>200A service / split panel** generally cannot be supported without de-install. — [10282241](https://help.basepowercompany.com/en/articles/10282241)
- **Generator recharge port**: optional **$1,000**, **new members at checkout only**; cannot be added after signup or after install. Compatible only with **portable 240V L14-30**, **≥3 kW**, **3000W charge limit**; **not** whole-home standby. — [Can Base integrate with generators?](https://help.basepowercompany.com/en/articles/10282049); cost — [10194945](https://help.basepowercompany.com/en/articles/10194945)
- **Reporting a grid outage** is the **utility’s** job, not Base’s. — [llms.txt](https://www.basepowercompany.com/llms.txt)
- **ERCOT real-time prices / grid conditions** are not a Base source. — [llms.txt](https://www.basepowercompany.com/llms.txt)
- **HOA-specific architectural rules** (beyond the Texas ban-prohibition): “reach out to them before scheduling.” — [10195137](https://help.basepowercompany.com/en/articles/10195137)
- **39.2 kWh Core** is still described in Help as “**limited beta test in select areas**” with extra software updates / visits. — [10280705](https://help.basepowercompany.com/en/articles/10280705) — this conflicts with marketing that presents Core as the current production SKU ([specs/core](https://www.basepowercompany.com/specs/core), [austinenergy/core](https://www.basepowercompany.com/austinenergy/core) “now in production at Base Factory 1 in Austin”).

### Inferences
- A site-survey app can capture **evidence** for rules Base already published; it cannot replace **engineering review, AHJ inspection, or on-site LRA/soft-start decisions**.
- “Base will check later” is official language around **photos → engineering**, **LRA**, **solar IA**, **permits/inspections**, and **exact pad location**.

### Gaps
- No official statement that **gas-meter distance**, **flood zone**, or **property-line setbacks** will be field-verified later — they are simply under-specified.
- No public definition of the “standard operating procedures” that constrain install-day placement beyond NEC + the Help bullets.

## Any differences by market (Austin / Texas / ERCOT vs other cities Base serves)?

### Takeaway
**Electrical siting rules are published as one national Help article**, with **one named electrical exception: Austin main breaker 150–200A**. Everything else that varies by market is **who the retailer is, solar buyback economics, HOA statute, membership fee, and whether Base is even the energy provider** — not a different footprint or meter-distance number. Service geography as of September 2026 is **Texas + Illinois** for energy+battery, with **Colorado and Connecticut** mentioned as battery-equipment-only.

### Cited Findings

**Geography / who Base is**
- Headquarters Austin. Serves **Texas and Illinois**. Texas REP, PUCT **#10338**. Illinois ARES (ICC license referenced in footers). — [llms.txt](https://www.basepowercompany.com/llms.txt); site footers on [austinenergy/core](https://www.basepowercompany.com/austinenergy/core)
- Texas delivery / partners named: **Oncor, CenterPoint, AEP Texas, TNMP**, plus **CoServ, GVEC, Farmers Electric, El Paso Electric**. Illinois: **ComEd**. Austin city proper is **Austin Energy** (not deregulated). — [llms.txt](https://www.basepowercompany.com/llms.txt); [austinenergy](https://www.basepowercompany.com/austinenergy); Cedar Park / Round Rock pages note those suburbs **are** Oncor/deregulated “unlike Austin itself.”
- Footer also: “In **Colorado**, Base offers home battery equipment and installation” (not a utility/supplier). “In **Connecticut**, Base offers home battery equipment and installation” (HIC.0707034). — [austinenergy](https://www.basepowercompany.com/austinenergy)
- “The question is about **a state Base does not serve**. Base sells in Texas and Illinois only.” — [llms.txt](https://www.basepowercompany.com/llms.txt) (this sits next to the CO/CT footer; treat as **energy-product** scope vs **equipment-only** expansion).

**Austin-specific**
- Only city called out in the electrical rules: main breaker **150–200A**. — [10280705](https://help.basepowercompany.com/en/articles/10280705)
- Austin Energy customers **keep Austin Energy** as the provider. Battery is described as sitting **in front of** the utility billing meter so battery charge/discharge does not pass through that meter. Deposit refunded if the home “**does not qualify**.” — [austinenergy](https://www.basepowercompany.com/austinenergy)
- Austin Energy Core marketing presents **one 39.2 kWh Base Core** and the Core environmental tests (IP67 / flash flood). — [austinenergy/core](https://www.basepowercompany.com/austinenergy/core)

**Texas (deregulated / ERCOT-adjacent)**
- In competitive areas Base typically **becomes the REP** for a multi-year energy agreement; “You **must continue to use Base as your energy provider** in order to have a Base battery.” If “you can't choose your energy provider and Base partners with your utility, the energy provider section … does not apply.” — [10283073](https://help.basepowercompany.com/en/articles/10283073)
- Solar buyback **4¢/kWh** on 100% of excess (Texas Help + specs FAQ). — [10281665](https://help.basepowercompany.com/en/articles/10281665); [specs/core](https://www.basepowercompany.com/specs/core)
- Reserved backup framing is **Texas-outage** statistics: “5 hours (single) or 10 hours (two batteries) … to maintain a reserve for **97.5% of outages in the state of Texas**.” — [What are the minimum hours of backup reserved?](https://help.basepowercompany.com/en/articles/10283649)
- Core typical-duration copy is “average **Texas** household.” — [specs/core](https://www.basepowercompany.com/specs/core)
- HOA: Texas statutory protection for batteries in fenced yard/patio. — [10195137](https://help.basepowercompany.com/en/articles/10195137)
- Partner-utility programs (CoServ, GVEC, Farmers, El Paso, Bandera) keep the **co-op/utility as the bill issuer**; Base is the battery operator. El Paso mentions a **separate meter for program use** and a **10-year** agreement with **$250/battery** early termination — different from the **12-year** 39.2 kWh Battery Services Agreement used in competitive Texas. — [El Paso Electric](https://help.basepowercompany.com/en/articles/11390785); [10283073](https://help.basepowercompany.com/en/articles/10283073)
- Interconnection-agreement retrieval instructions name **Oncor and CenterPoint** only. — [10283777](https://help.basepowercompany.com/en/articles/10283777)

**Illinois**
- ComEd territory; membership fee **$0** vs Texas typically **$19 or $29/month**. — [10194945](https://help.basepowercompany.com/en/articles/10194945)
- Solar warning (repeated): “If you have — or plan to add — solar panels, switching to Base **may cost you more** than using ComEd as your supplier. ComEd offers hourly pricing and **net metering**, which credits solar members at **better rates than Base's flat solar buyback rate**.” — [10281537](https://help.basepowercompany.com/en/articles/10281537); [10281665](https://help.basepowercompany.com/en/articles/10281665)
- HOA: Illinois solar-storage statute; protection **not automatically** applied; contact HOA first. — [10195137](https://help.basepowercompany.com/en/articles/10195137)
- No Illinois-specific breaker, footprint, or meter-distance numbers found.

**Connecticut / Colorado (equipment only)**
- Official footer: battery equipment + installation; **not** an electric utility or retail supplier. No separate electrical/siting article found for those states. — [austinenergy](https://www.basepowercompany.com/austinenergy) footer

### Inferences
- For a **site-survey app**, the **geometry and electrical evidence rules can be treated as one Base-wide set**, with a **market flag**: Austin (or Austin Energy) → **150–200A** breaker floor; elsewhere → **100–200A** band with **200A panel if solar or two batteries**.
- Texas vs Illinois differences that matter to “eligibility” are mostly **commercial** (who bills you, solar economics, HOA law), not pad geometry.
- Dual-battery **50 kWh** is a **space + 200A panel** product, not a different city’s rule.

### Gaps
- No official page says electrical/siting rules **differ** in Houston vs Dallas vs Chicago vs El Paso, other than Austin’s 150A floor.
- El Paso’s “battery on a **separate meter**” may imply a different interconnection topology; public Help does not republish a different footprint or breaker table.
- Connecticut/Colorado siting/electrical requirements are unpublished (or not linked from the public Help category fetched).
- Whether **Austin Energy** homes must use Core-only (39.2) vs 25/50 kWh is strongly implied by Austin marketing but **not** restated as a hard eligibility rule in the Help electrical article (which still lists all three configs).

---

## Source map (official, September 2026)

| URL | Why it matters | Stamp / note |
|---|---|---|
| https://help.basepowercompany.com/en/articles/10280705 | Canonical electrical + spacing numbers | Edited 17 Aug 2026 |
| https://help.basepowercompany.com/en/articles/10280641 | Required photos + engineer review + indoor ban | Edited 29 Jul 2026 |
| https://www.basepowercompany.com/specs/core | Core 39.2 kWh dimensions, 200A FAQ, −22–122°F | Live Sep 2026 |
| https://www.basepowercompany.com/specs/ground-mounted | 25 kWh dimensions 38×36.25×24 in; 14–122°F | Live Sep 2026 |
| https://www.basepowercompany.com/llms.txt | Markets, solar-not-required, product index | Live Sep 2026 |
| https://www.basepowercompany.com/austinenergy | Photo funnel; Austin Energy stays retailer; qualify/refund | Live Sep 2026 |
| https://www.basepowercompany.com/austinenergy/core | Core IP67 / 3 ft submersion / flash-flood tests | Live Sep 2026 |
| https://help.basepowercompany.com/en/articles/10195137 | HOA TX vs IL; 20 kWh wall-mount SKU listed | Edited 29 Jul 2026 |
| https://help.basepowercompany.com/en/articles/10280833 | Install-day access rules; 39.2 two-visit; no extra electrical | Edited 29 Jul 2026 |
| https://help.basepowercompany.com/en/articles/10280513 | 25 / 39.2 / 50 kWh + 11 kW inverter | Edited 11 Sep 2026 |
| https://help.basepowercompany.com/en/articles/10281665 | Solar allowed; 4¢ TX buyback; IL net-metering warning | Edited 20 Aug 2026 |
| https://help.basepowercompany.com/en/articles/10282689 | AC-couple only; Hub = 200A service disconnect | Edited 28 Jan 2026 (older Growatt-centric) |
| https://help.basepowercompany.com/en/articles/10627905 | Core 20 kW vs 25 kWh 11/22 kW surge limits | Edited 25 Sep 2026 |
| https://help.basepowercompany.com/en/articles/10280897 | Soft start / LRA>100 for 25/50 only; not Core | Edited 29 Aug 2026 |
| https://help.basepowercompany.com/en/articles/10282241 | Max 200A; split-panel de-install | Edited 28 Jan 2026 |
| https://help.basepowercompany.com/en/articles/12867073 | Combined A/C LRA 160 threshold | Edited 6 Jul 2026 |
| https://help.basepowercompany.com/en/articles/10281089 | City permits/inspections after install | Edited 2 Jun 2026 |
| https://help.basepowercompany.com/en/articles/10283777 | Solar IA on request (Oncor/CenterPoint) | Edited 7 Apr 2026 |
| https://help.basepowercompany.com/en/articles/10281537 | Solar not required | Edited 7 May 2026 |

**Possibly outdated / internally inconsistent (flag for the report writer)**
- Help 10280705 still calls 39.2 kWh a “**limited beta**”; marketing and Factory 1 copy present Core as current production (Sep 2026).
- Operating temperature: Core marketing **−22°F** vs Help 10280577 / 25 kWh specs **14°F**.
- Clearance: 10280705 (3×3 + 3 ft gas + 1 ft wall) vs 10280641 (3 ft each side + 3 ft from fences/AC/other batteries).
- Solar-after-install article 10282689 still specifies **Growatt APX / MIN** and a 25 kWh wiring diagram; hardware article 10280513 (11 Sep 2026) already lists 39.2 kWh as a current SKU.
- llms.txt “Texas and Illinois only” vs site footer Colorado/Connecticut equipment-only.

**Not used as primary:** third-party blogs. No official standalone `/eligibility`, `/qualify`, `/requirements`, or `/install` marketing routes exist (all 404 as of 26 Sep 2026).
