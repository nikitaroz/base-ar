# Base Power Company customer / homeowner submission form inventory

Research date: 2026-09-26. Primary method: live walk of public pages in a browser, plus the public `join.basepowercompany.com` JavaScript bundle and public Typeform definitions. No customer lead was submitted. Dummy/public address `205 E Riverside Dr, Austin, TX 78704` was used only to reveal address-validation substeps. Contact fields were recorded but not filled.

## What is the exact public flow to request a Base battery (URL path: signup, get started, check eligibility, reserve, apply)?

### Takeaway
The public homeowner path is zip-gated **Get started**, not `/signup`, `/eligibility`, `/reserve`, or `/apply`. Zip + detected utility routes the browser to a `join.basepowercompany.com/{flow}` questionnaire (6 steps for Austin Energy, 10 steps for Oncor), then contact capture. Photos and reservation/deposit happen after that lead is saved.

### Cited Findings
- Homepage primary CTA is **Get started**, linking to `https://www.basepowercompany.com/get-started`. Sign-in goes to `https://account.basepowercompany.com/sign-in`. — [Base Power homepage](https://www.basepowercompany.com/)
- `/get-started` heading is **Affordable, reliable power starts here**. The only input is a textbox labeled **Enter your zip code** and a button **See available plans**. Copy says “Takes about two minutes” and “Pricing and availability varies by area — see which Base offering you qualify for.” — [Get Started](https://www.basepowercompany.com/get-started)
- `/signup` and `/eligibility` return HTTP 404. `/reserve` and `/apply` were not present as marketing routes. — live HTTP probes of those paths on `www.basepowercompany.com`
- Austin zip `78704` redirected to `https://join.basepowercompany.com/austinenergy/join-zip?postal_code=78704&utility=AUSTIN_ENERGY&…` and showed **Step 1 of 6**. — live walk
- Dallas zip `75201` redirected to `https://join.basepowercompany.com/join-now-zip?postal_code=75201&utility=ONCOR&…` and showed **Step 1 of 10**. — live walk
- `https://join.basepowercompany.com/` redirects to `/auth?next=%2F` and renders **Internal only** with a password field. This is not the public signup. — [join.basepowercompany.com/auth](https://join.basepowercompany.com/auth?next=%2F)
- The join app’s published slugs include `austinenergy/join`, `austinenergy/join-zip`, `join-now`, `join-now-zip`, `join-soon-zip`, `join-waitlist`, `join-waitlist-zip`, `dallas`, `illinois/join-zip`, `illinois/join-waitlist-zip`, `connecticut/join-zip`, `epelectric/join-zip`, `coserv/join-zip`, `farmers/join-zip`, `gvec/join-zip`, plus energy-only `join-energy-calculator` / `join-energy-plan`. — [join bundle `index-8AL1yDtp.js`](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- After Austin Energy contact + “heard from” submit, the bundle redirects to `https://basepowercompany.com/austinenergy/schedule` (also mapped for COSERV / FARMERS / GVEC schedule URLs; ONCOR / CENTERPOINT / TNMP / AEP use a shared schedule URL constant). — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Homepage “How it works” step 01 already advertises photos: **“01 Snap a few pictures — Send a few photos of your home. Our engineers will determine which Base battery configuration is best for you.”** That is marketing copy on the homepage, not a field on `/get-started`. — [Base Power homepage](https://www.basepowercompany.com/)

### Inferences
- “Check eligibility” is implemented as a zip → utility-routed join questionnaire, not a standalone eligibility URL.
- “Reserve” / deposit / schedule are post-lead screens (and in some markets a $50 refundable deposit), not the first public form.
- Existing members use `account.basepowercompany.com`, which is also where post-deposit photo upload is described.

### Gaps
- The live Austin Energy **heard_from** screen and the post-submit `/austinenergy/schedule` page were not opened, because that requires submitting contact info (a lead). Those screens are documented from the join JS only.
- Illinois, Connecticut, El Paso Electric, CoServ, Farmers, and GVEC join slugs were not walked in the browser.

## What information does the form collect: name, email, phone, address, utility, ESIID, meter number, breaker size, solar, roof, HOA, ownership, photos, etc.?

### Takeaway
Public signup collects **zip, homeownership, current energy setup (solar / generators / existing battery), street address, name, phone, email, optional marketing SMS, and “how did you hear about us.”** Deregulated (Oncor) adds **main reason for considering Base** and can add **plan choice** and **how you get electricity**. It does **not** collect ESIID, meter number, breaker amperage, roof details, HOA, Wi-Fi, or photos.

### Cited Findings

#### Field-by-field: marketing gate (`/` and `/get-started`)
| Label (exact) | Type | Required | Step |
| --- | --- | --- | --- |
| Enter your zip code | text / zip | Functionally required to continue (button is **See available plans**) | Homepage hero and `/get-started` |
| Who is your utility provider? | combobox | Optional on homepage pricing block; not on `/get-started` | Homepage “See pricing for your home” |
— [homepage](https://www.basepowercompany.com/); [Get Started](https://www.basepowercompany.com/get-started)

Homepage utility picker values in the join bundle (used for rate tables): **HTX (CenterPoint)**, **ATX/DFW (Oncor)**, **AEP Central**, **AEP North**, **TNMP**. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)

#### Field-by-field: Austin Energy join (`/austinenergy/join-zip`) — walked live through step 5 of 6
Query params after zip: `postal_code=78704`, `utility=AUSTIN_ENERGY`. Progress label: **Step N of 6**. Banner: **We're in your area**.

| Step | Label / copy (exact where seen) | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| 1 | Heading: **Great news. Base is partnering with Austin Energy to bring you affordable backup!** Body: **We’ve got a few questions to make sure your home is a great fit for Base—no commitments.** Question: **First off, do you own or rent your home?** | exclusive choice | Yes | Buttons: **I own my home**, **I rent**. Rent branches to a waitlist (JS). |
| 2 | **What does your home energy setup look like?** Helper: **Choose all that are applicable.** | multi-select | Yes (Continue disabled until a choice) | **I have solar panels installed**; **I have a portable generator**; **I have a whole-home standby generator**; **I have a whole-home battery**; **None of the above** |
| 3 | **Perfect, Base is the place to start.** (shown after **None of the above**) | interstitial, no data | CTA **Sounds great** | Solar / portable-generator variants have different headlines in JS |
| 4 | **What's your address?** Field **Home address**, placeholder **Enter your home address** | address autocomplete combobox (`name="address"`, `autocomplete="street-address"`) | Yes | Google Places |
| 4b (conditional) | **Confirm your unit number**. Banner: **This looks like it might be a multi-unit building. If you have an apartment or unit number, add it to continue.** | structured address | Street / city / state / ZIP prefilled; unit optional | Fields: **Street address**, **Apartment or unit number (optional)**, **City**, **State**, **ZIP** |
| 5 | **Last step - save your progress** | contact | First / last / phone / email required (`required` in DOM) | See names below |
| 6 | Not walked live. JS screen `heard_from`, CTA **Submit**, then `updateLead` + redirect to Austin Energy schedule | single select | Yes to finish | Options listed below |

Step 5 inputs (live DOM + labels):

| Label | `name` / type | Required | Extra |
| --- | --- | --- | --- |
| First name | `first_name`, text, `autocomplete="given-name"` | Yes | Placeholder **First name** |
| Last name | `last_name`, text, `autocomplete="family-name"` | Yes | Placeholder **Last name** |
| Phone number | visible tel + hidden `phone` | Yes | Placeholder **(201) 555-0123**. Consent: **By providing your phone number and clicking Continue, you agree to receive service-related texts and calls from Base Power.** Links: SMS Terms, Privacy Policy |
| Email | `email`, email, `autocomplete="email"` | Yes | Placeholder **name@example.com** |
| I agree to receive marketing text messages from Base Power, including new product announcements, member-only offers, and promotional updates. Reply STOP to opt out or reply HELP for help. Message frequency varies. Msg & data rates may apply. See our SMS Terms and Privacy Policy. | checkbox, optional (`required=false`) | No | Unchecked by default |

Austin Energy step 6 **heard_from** options from JS (Austin-branded utility items): **Word of mouth**, **Mail**, **News**, **Google / search**, **Facebook / Instagram**, **Referral from an existing Base member**, **TV ad**, **Yard signs**, **Youtube**, **Community Event**, **Austin Energy Website**, **Austin Energy Email**, **Other**. A broader option list in the same bundle also includes **Nextdoor**, **Billboard**, **Twitter / X**, **Radio**, **HEB**, **Capital One Shopping**. — live steps 1–5: [austinenergy/join-zip](https://join.basepowercompany.com/austinenergy/join-zip); step 6: [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)

Austin Energy branch copy (JS, not all walked):
- Rent: **We can’t serve renters just yet…** then 3-step waitlist (address + contact). — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Standby generator: incompatibility with existing ATS; contact `team@basepowercompany.com`. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Whole-home third-party battery: cannot install alongside; same contact. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Solar education: **Great—solar and Base are a perfect match.** — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)

#### Field-by-field: Oncor / deregulated join (`/join-now-zip`) — walked live through step 2 of 10
| Step | Label (exact) | Type | Required |
| --- | --- | --- | --- |
| 1 | **Base is available in your area.** Same ownership question: **First off, do you own or rent your home?** | exclusive choice: **I own my home** / **I rent** | Yes |
| 2 | **What’s your main reason for considering Base?** | exclusive choice | Yes |
| 2 options (exact) | **Having reliable backup power at an affordable price**; **Paying a low, fixed energy rate**; **Both — saving on energy and staying backed up** | | |

Later deregulated screens in the same zip-first flow (JS; not all shown live because utility was already `ONCOR`):
- **How do you get your electricity today?** Options: **I pick my own electricity plan — I can choose my electricity provider**; **My electricity provider is assigned — I get electricity from my city or electric co-op and can't switch**; **I'm not sure**.
- **You have two options to power your home with Base.** / **Select which plan you would prefer:** **Base energy + battery** vs **Base energy plan**.
- Same energy-setup multi-select as Austin.
- Same address + contact + heard_from pattern.
- Optional booking screen copy: **We’ll send a calendar invite to your email.** CTA language includes **Confirm booking**.
— live: [join-now-zip ONCOR](https://join.basepowercompany.com/join-now-zip); JS: [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)

#### Address validation variants (JS, not all triggered)
- **Confirm your unit or meter detail** — only if Google address validation cannot verify address + unit. Placeholder: **Apartment, unit, or structure (e.g., guest house, barn)**. This is **not** a utility meter-number field. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Other confirm titles: **Confirm your address**; **Apartment, unit, or structure (optional)**.

#### Illinois-specific extras in the same bundle (not walked)
- Provider list: **ComEd**, **MidAmerican**, **Ameren**, **The City of Naperville**, **The City of St. Charles**. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Self-serve reserve FAQ: **Deposit: $50, fully refundable, and it goes toward your $95 install.** Question **How do I know if my home qualifies?** (see photos section). — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)

#### Explicitly absent from the public join form
Searches of the join JS found **0** matches for `ESIID`, `esiid`, `HOA`, `Wi-Fi`/`wifi`, `200A`, `breaker`, and no photo-upload widgets. Field keys present include `first_name`, `last_name`, `email`, `phone`, `postal_code`, `has_solar`, `has_portable_generator`, `has_standby_generator`, `has_whole_home_battery`, `optin_marketing_sms`, `interest`, `utility` — not meter number or amperage. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)

### Inferences
- Utility is inferred from zip (and sometimes a homepage dropdown), not typed as ESIID or account number.
- Solar is a yes/multi-select on signup; breaker size and meter number are deferred to photos after signup.
- Roof is never asked. HOA is a help-center topic, not a form field.
- “Meter detail” in address confirmation means unit/subpremise, not the electric meter badge.

### Gaps
- Exact live widgets for Illinois plan reserve / $50 checkout were not opened.
- El Paso Electric flow asks that **contact information must match the El Paso Electric account holder** (JS copy) but that screen was not walked, so the exact extra fields (if any) are unknown.
- Whether Oncor step count 10 includes education interstitials as numbered steps was only confirmed for steps 1–2 live.

## Does Base ask homeowners to upload photos of the meter, breaker panel, proposed battery location, gas meter, or yard?

### Takeaway
Not on the public Get Started / join questionnaire. After signup (and, in the reserve FAQ, after placing a deposit), Base sends a link / unlocks the member dashboard and asks for a specific outdoor photo set: electric meter (with **legible meter number**), surrounding yard/walls, optional behind-fence shot, main breaker box, main disconnect amperage, and surrounding panel area. Gas meters are a **spacing rule**, not a dedicated upload slot.

### Cited Findings
- Help article opening line: **“after you sign up we will send you a link to submit a few key photos to understand your ho[me]…”** — [Why does Base request home photos?](https://help.basepowercompany.com/en/articles/10280641)
- Exact **Required Photos:** list from that article:
  1. **Electric meter** — “The gray box with a circular device protruding from it, located on the exterior of your home. Ensure the photo is zoomed in enough for the meter number in the red box to be legible.”
  2. **Area surrounding your meter** — “From as far back as possible (at least 10 steps)… The more zoomed out the better.”
  3. **Area to the right of your meter** — “Each battery is 3 feet wide, and needs 3 feet of clearance on both sides.”
  4. **Area to the left of your meter** — same clearance language (article text says “area to the right” again in the left-side bullet).
  5. **Wall adjacent to the wall with the meter** — “entire side of the house from corner to corner.”
  6. **Area behind the fence (if applicable)**.
  7. **Main breaker box** — “Usually located outside next to your meter or in your garage.”
  8. **Main disconnect switch** — “We need to see the amperage number - usually 125, 150, or 200.”
  9. **Area surrounding the main breaker box (if not already captured)**.
— [photo review article](https://help.basepowercompany.com/en/articles/10280641)
- Troubleshooting asks homeowners to lift the lid on an external disconnect so the main breaker switch is visible. Engineering “will review your photos and reach out within 2 days if any additional information is needed.” — [photo review article](https://help.basepowercompany.com/en/articles/10280641)
- Join-app reserve FAQ (Illinois/self-serve copy): **“After you reserve your spot, you’ll send a few photos from your Base dashboard, unlocked after placing the deposit… Upload photos of your meter, main panel and the space around it.”** Follow-up: **“If anything needs attention, we’ll reach out within about 5-10 business days.”** Refund: **“If you don’t qualify for any reason, we’ll refund your $50.”** — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Homepage already promises “Send a few photos of your home” as step 01 of getting started. — [homepage](https://www.basepowercompany.com/)
- Gas-meter photos are **not** named as a required upload. Gas appears as a clearance rule: batteries “Must be at least 3 feet apart from gas meters” and each battery “needs 3 feet of clearance from gas meters, AC units, fences, other batteries, or other obstructions.” — [electrical/spacing article](https://help.basepowercompany.com/en/articles/10280705); [photo review article](https://help.basepowercompany.com/en/articles/10280641)
- No dedicated “proposed battery location” upload label. The wide yard/wall shots are how engineers pick a code-compliant spot. Preferred spot is discussed on install day if the homeowner is present. — [photo review article](https://help.basepowercompany.com/en/articles/10280641)

### Inferences
- Photo capture is a **post-lead site-qualification packet**, not part of the 2-minute zip form.
- Meter **number** and breaker **amperage** are collected as **photo evidence**, not typed fields.
- Timing language conflicts slightly: photo article says review outreach “within 2 days”; reserve FAQ says “about 5-10 business days.”

### Gaps
- The actual dashboard / emailed photo-upload form (field names, required flags, file types, max count) is behind `account.basepowercompany.com` after signup/deposit and was not opened.
- No public screenshot of a “gas meter” upload slot was found.

## Is there a separate "site survey" or "send us photos" step after initial signup?

### Takeaway
Yes. Base does not use the phrase “site survey” as a public form title. After signup (homepage + help + reserve FAQ), homeowners send photos via a **link** and/or **Base dashboard**, engineers review them, then permitting and install are scheduled. That is a distinct step from Get Started.

### Cited Findings
- Photo article: photos are requested **after you sign up**, via a link. — [photo review article](https://help.basepowercompany.com/en/articles/10280641)
- Reserve FAQ: photos come from the **Base dashboard, unlocked after placing the deposit**. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- Member reviews on the homepage mention “a long vetting process to ensure their battery systems are a good fit for your location next to your electrical panel.” — [homepage](https://www.basepowercompany.com/)
- Install-day article: installations typically occur “within a few weeks after signing up”; members can “log on to account.basepowercompany.com to track updates about your installation status.” — [What do I need to know on the day of installation?](https://help.basepowercompany.com/en/articles/10280833)
- Austin Energy join step 5 heading **Last step - save your progress** is contact capture only; it does not include photo upload. — live walk of [austinenergy/join-zip](https://join.basepowercompany.com/austinenergy/join-zip)
- No public page titled “site survey” was found on `www` or `help` during this pass. Help collection **Backup battery service** includes installation/hardware articles, not a form named site survey. — [Help Center](https://help.basepowercompany.com/en/)

### Inferences
- “Site survey” in Base’s public language is **remote photo review by engineers**, not a homeowner-facing AR/survey form and not (in the public docs) a pre-signup upload.
- Deposit-gated dashboard upload and “we will send you a link” may be the same packet reached two ways (reserve markets vs. Austin Energy partnership).

### Gaps
- Could not confirm whether Austin Energy customers skip the $50 deposit and still get the same dashboard uploader.
- No public “site survey” partner/installer checklist form for homeowners was found.

## Are there help articles that list "what we need from you" or a checklist for installation?

### Takeaway
Yes. The closest checklists are **Why does Base request home photos?** (required photo list) and **What are the electrical and spacing requirements?** (150–200A Austin, 200A if solar or two batteries, 3×3 ft footprint, 20 ft of meter, 1 ft of wall, 3 ft from gas). Install-day and HOA articles add access, Wi-Fi, and permitting notes. None of those are signup-form fields.

### Cited Findings
- Photo checklist article (required photos + daytime / wide-angle / clear-obstructions tips). Review SLA: “within 2 days.” Batteries “can't be installed indoors or in garages.” — [photo review](https://help.basepowercompany.com/en/articles/10280641)
- Electrical/spacing article: main breaker **100–200A** generally; **In Austin, it must be 150–200A**; **200A** if dual battery or solar; meter and main breaker on the same wall; breaker box not in a closet; meter ≤ 6 ft high; 30 in × 36 in working space; transfer switch ~13 in wide with 30 in clearance beside the meter; one main breaker box. — [electrical and spacing requirements](https://help.basepowercompany.com/en/articles/10280705)
- Install day: someone must be home for Visit 1 (access to main breaker; power off 1–3 hours); hold sprinklers 48 hours; after install, download the app and **input your Wi-Fi network name and password**; track status at `account.basepowercompany.com`. — [install day](https://help.basepowercompany.com/en/articles/10280833)
- HOA: **Will I need HOA approval? Does Base have information I can share with my HOA?** Base “manages all permitting creation, submission, and inspection with local cities and utilities.” Hardware is “near the electric meter along an exterior wall. No changes are made to the roof or front face of the home.” This is **not** asked on signup. — [HOA article](https://help.basepowercompany.com/en/articles/10195137)
- Wi-Fi: **How do I connect my battery to my home WiFi network?** Battery works without Wi-Fi (built-in 4G); connecting is recommended post-install in the app. Not a signup question. — [Wi-Fi article](https://help.basepowercompany.com/en/articles/10281409)
- Help Center collections visible on the index: **Backup battery service** (62 articles, includes installation protocol), **General Information** (4), **Energy service: Texas** (17), **Energy service: Illinois** (9). — [Help Center](https://help.basepowercompany.com/en/)
- Related install/hardware article titles also listed on that index include **What do I need to know on the day of installation?** (`10280833`), **What does a typical Base system installation look like?** (`10281281`), **When does Base deliver the installation equipment?** (`10281153`). — [Help Center](https://help.basepowercompany.com/en/)

### Inferences
- “What we need from you” for qualification = photo packet + (implicit) ownership and a qualifying electrical setup, not a typed ESIID/breaker form.
- Wi-Fi credentials are requested **after install in the app**, not during Get Started.

### Gaps
- Intercom search HTML is client-rendered; a full-text search for “ESIID” / “site survey” inside Help could not be completed via curl. No ESIID article URL was discovered from the homepage article list.
- Did not open every one of the 62 backup-battery articles.

## Is there an installer/partner portal form that is publicly documented?

### Takeaway
There is no public installer **portal login** on the marketing site. There are public **interest Typeforms**: installer/electrician at `/install-partners/interest`, and a general partnerships form (utility / homebuilder / other) at `/partnerships`. `join.basepowercompany.com/auth` is labeled Internal only.

### Cited Findings
- Footer **Installer partners** → `https://www.basepowercompany.com/install-partners`. CTAs **Partner with Base** / **Get started** go to `/install-partners/interest`. — [install-partners](https://www.basepowercompany.com/install-partners)
- `/install-partners/interest` embeds Typeform `https://form.typeform.com/to/na5wl9JN`, title **[LIVE] Installer/ECs Partnerships Interest Form**. Page title: **Base Install Partnerships Interest Form | Base Power**. — live page + [Typeform](https://form.typeform.com/to/na5wl9JN)
- Installer Typeform fields (public API definition):

**Group: Hello! We are excited to partner with you** (intro: “If there's a fit, someone on our Partnerships team will be in touch as soon as possible.”)

| Label | Type | Required |
| --- | --- | --- |
| What is your first and last name? | short text | Yes |
| What is your email? | email | Yes |
| What is the legal name of the organization you represent? | short text | Yes |
| What is your full business address (Street, City, State, ZIP)? | short text | Yes |
| What is your current position? | short text | Yes |
| Optional: any additional context that would be helpful | long text | No |

**What best describes your organization?** (multiple choice; installer-additional group only if Installer/electrician)

| Choice | Notes |
| --- | --- |
| Installer/electrician | Unlocks additional questions |
| Other commercial partnership (This form is strictly for installers & electricians, please reach out to us at basepowercompany.com/partnerships for other partnerships) | Redirects other partners |
| I'm a homeowner (This form is strictly for partnerships, please reach out to us at support@basepowercompany.com) | Not a homeowner intake |

**Additional questions for installers**

| Label | Type | Required |
| --- | --- | --- |
| What regions do you operate in? Please list all. (e.g, Austin, TX) | short text | Yes |
| How many installs do you perform per year? | short text | Yes |
| What type of installs do you do? | multi-select: Battery; Solar; EV charger; Generator; Other residential work | Yes |
| Total number of employees | number | Yes |
| Total years in business | number | Yes |
| Total years performing Battery/Energy Storage Installations | number | Yes |
| Number of Service Vans / Work Vehicles | number | Yes |
| Warehouse Capacity: How many pallet spaces could you dedicate to consigned Base hardware? | short text | Yes |
| Are all electricians company employees? | yes/no | Yes |
| Company website (URL) | short text | No |
| Licensed Electrician (Number) | long text | No |
| Non-licensed Electricians: Apprentices/General Labor (Number) | short text | No |
| Other Staff (e.g., Project Managers, Office Support) (Number) | long text | No |
| OSHA citations / safety incidents last 5 years? If yes, please explain below. | short text | No |

— [Typeform na5wl9JN](https://form.typeform.com/to/na5wl9JN); [api.typeform.com/forms/na5wl9JN](https://api.typeform.com/forms/na5wl9JN)

- `/partnerships` (also the homebuilders CTA) embeds Typeform `GOZxUocQ`. Iframe title in the page was **[DRAFT] Utility Partnerships Interest Form**; API title is **[LIVE] Partnerships Interest Form**. — [partnerships](https://www.basepowercompany.com/partnerships)
- Partnerships Typeform: same name/email/org/address/position/optional context block. Organization types: **Utility**; **Homebuilder**; **Other commercial partnership**; **Installer/electrician partners (Please go to basepowercompany.com/install-partners)**; **I'm a homeowner** (support email). Homebuilder extras: regions; homes per year; homes built to date (optional); website (optional); yes/no **Is your community served by any of the following utilities: CenterPoint, Oncor, AEP, Texas–New Mexico Power, Guadalupe Valley EC, CoServ, Farmers, Austin Energy, El Paso Electric, ComEd (Chicago)?** Other-partnership extras: regions; how many customers. — [api.typeform.com/forms/GOZxUocQ](https://api.typeform.com/forms/GOZxUocQ)
- Homebuilders marketing page CTAs go to `/partnerships`, not a separate builder portal. — [homebuilders](https://www.basepowercompany.com/homebuilders)
- `join.basepowercompany.com/auth` = **Internal only** + password. Not a partner application. — [join auth](https://join.basepowercompany.com/auth?next=%2F)

### Inferences
- Partner intake is lead-gen Typeforms, not a documented installer work-order / site-survey portal.
- Homeowners who land on partner forms are explicitly told to email support instead.

### Gaps
- No public URL for an authenticated installer job portal, photo QA tool, or “partner login” was found.
- Utility-specific additional questions on `GOZxUocQ` (if any beyond the homebuilder/other groups) were not fully expanded if hidden by Typeform logic.

## Any mention of ESIID, utility account, Oncor/Austin Energy/CenterPoint, internet, Wi-Fi, 200A service, etc.?

### Takeaway
**Oncor, Austin Energy, and CenterPoint** appear throughout routing and pricing. **200A / 150–200A** appear in help-center electrical rules, not the signup form. **Wi-Fi** is post-install. **ESIID** and **utility account number** do not appear in the public join JS or the walked forms.

### Cited Findings
- Austin Energy: live join headline **Base is partnering with Austin Energy**; URL param `utility=AUSTIN_ENERGY`; heard-from labels **Austin Energy Website** / **Austin Energy Email**. — [austinenergy/join-zip](https://join.basepowercompany.com/austinenergy/join-zip)
- Oncor: live join URL `utility=ONCOR`; homepage rate copy “all-in rate around 13.9¢/kWh in Oncor territory.” — [join-now-zip](https://join.basepowercompany.com/join-now-zip); [homepage](https://www.basepowercompany.com/)
- CenterPoint / Oncor / AEP / TNMP appear as homepage TDU rate-table keys and as homebuilder-form utilities. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js); [partnerships Typeform](https://api.typeform.com/forms/GOZxUocQ)
- Join JS `I2` map also includes `COMMONWEALTH_EDISON`, `COSERV`, `FARMERS`, `GVEC`, `DEREG`. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- **ESIID / esiid**: 0 hits in the join bundle. Not present on walked screens. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- **Utility account**: El Paso Electric education copy says contact info “must match the El Paso Electric account holder”; no account-number field was found in the walked Texas forms. — [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)
- **200A / breaker**: help article, not signup. “The main breaker in the electrical panel must be 100-200A… In Austin, it must be 150-200A.” Dual battery or solar → 200A. Photo article asks for a zoomed disconnect shot showing 125 / 150 / 200. — [electrical requirements](https://help.basepowercompany.com/en/articles/10280705); [photos](https://help.basepowercompany.com/en/articles/10280641)
- **Internet / Wi-Fi**: not on signup. Install-day and Wi-Fi help articles ask members to enter Wi-Fi in the Base app after install; battery has 4G fallback. — [install day](https://help.basepowercompany.com/en/articles/10280833); [Wi-Fi](https://help.basepowercompany.com/en/articles/10281409)
- **HOA**: help article only; signup does not ask. — [HOA](https://help.basepowercompany.com/en/articles/10195137)
- **Solar**: asked on signup as **I have solar panels installed** / **Do you have solar installed at {street}?** (some flows). Help: **Can I join Base if I have solar?** — yes in Texas. Some JS branches say solar is incompatible in specific programs (e.g. a solar_incompatible message). — live Austin step 2; [solar help](https://help.basepowercompany.com/en/articles/10281665); [join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js)

### Inferences
- Qualification that depends on ESIID, 200A service, or meter number is handled **after** lead capture (photos + engineering), while zip/utility routing happens **before**.
- A future app that mirrors Base’s **public signup** should not expect ESIID/breaker/photo fields; an app that mirrors **site qualification** should.

### Gaps
- No public enrollment form asking for ESIID (common on Texas REP switch sites) was found; it may exist later in `account.` energy-switch paperwork, which was not opened.
- Reddit / social were not used (none needed once the live form and official help articles were available).
