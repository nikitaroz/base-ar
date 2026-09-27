# Two intakes leave a photo-kit gap
**Base Power Company does not collect installation eligibility on one form.** The public **Get Started / join** questionnaire is a zip-gated lead: ownership, solar and generators, street address, and contact. After that lead is saved, engineers judge the site from a **separate nine-shot photo kit**, not from typed breaker or meter fields. The hackathon **Base Site Survey** iPhone app is aimed at that second surface, plus local pass / conflict / unknown checks from published Austin guidance. It already captures the two electrical stills, typed meter number and amperage, solar, name, email, phone, a property identifier, a one-shot GPS **property** fix, and AR distances Base never asks a homeowner to type. It does **not** have most of the photo kit’s wide meter-area shots, and three evidence slots on the session model stay stubbed, so a green placement preview cannot appear. The app writes a local `survey.json` packet. **It is not a submission to Base.**

## Base splits intake into join, then engineer photos
Homeowners who tap **Get started** land on a zip box, not a site survey. `/get-started` asks only for a zip and promises that pricing and availability vary by area; `/signup` and `/eligibility` return 404. Austin zip `78704` routes to a six-step Austin Energy join flow; Dallas zip `75201` routes to a ten-step Oncor flow. Both start with **own or rent**, then energy setup or motive, then address and contact. Neither flow uploads photos, and the join JavaScript has **zero** matches for ESIID, HOA, Wi-Fi, breaker amperage, or a photo widget (`([Get Started](https://www.basepowercompany.com/get-started))`, `([homepage](https://www.basepowercompany.com/))`, `([join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js))`).

The photo work is explicit and later. Help copy says **after you sign up we will send you a link** so engineers can check electrical and spacing rules. Homepage “How it works” already advertises **01 Snap a few pictures**, and reserve-market FAQ copy unlocks the same packet from the member dashboard after a **$50** refundable deposit. Base does not title that packet “site survey.” It is remote photo review: engineering decides configuration, then electricians finalize the pad on install day within NEC and Base SOP. A homeowner cannot self-certify a pass (`([Why does Base request home photos?](https://help.basepowercompany.com/en/articles/10280641))`, `([electrical and spacing requirements](https://help.basepowercompany.com/en/articles/10280705))`).

That split is the right frame for the iPhone app. Copying Get Started would recreate a lead form the prototype does not submit. Matching the **photo kit plus Austin published checks** is the job the app actually took. Partner Typeforms at `/install-partners/interest` and `/partnerships` are a third surface for electricians and utilities, not homeowner eligibility, and `join.basepowercompany.com/auth` is labeled **Internal only**.

## Join-form fields overlap on contact, not on ownership
Austin Energy’s walked join flow collects **own/rent**, a multi-select energy setup (**solar, portable generator, whole-home standby, whole-home battery, or none**), Google-validated **home address** (plus a conditional unit/subpremise screen that is **not** a utility meter number), then **first name, last name, phone, email**, optional marketing SMS, and a **heard from** step documented in the join bundle. Oncor adds **main reason for considering Base**, and later screens can ask **how you get electricity** and **energy + battery vs energy plan**. Utility is inferred from zip, not typed as an account number (`([austinenergy/join-zip](https://join.basepowercompany.com/austinenergy/join-zip))`, `([join-now-zip](https://join.basepowercompany.com/join-now-zip))`, `([join bundle](https://join.basepowercompany.com/assets/index-8AL1yDtp.js))`).

The app’s **Home and personal info** screen now takes a single **Name**, **Email**, **Phone**, a free-text **property address or identifier** with suggestions, and solar as unanswered / no / yes. That is the same contact cluster Base asks at join, compressed: one name instead of first/last, no SMS consent, no attribution, no zip-gated utility routing (`([ContentView.swift](../BaseAR/ContentView.swift))`, `([SurveySession.swift](../BaseAR/Survey/SurveySession.swift))`). Ownership and generators are the join questions that actually gate Base’s product (rent waitlist; standby ATS and third-party whole-home batteries are called incompatible in join copy). Those answers are **missing from the app**.

| Base join field | App status |
| --- | --- |
| Zip / inferred utility | **Missing from app** (no zip or utility field; address is one string) |
| Own or rent | **Missing from app** |
| Solar panels | **Captured in app** (unanswered / no / yes) |
| Portable generator | **Missing from app** |
| Whole-home standby generator | **Missing from app** |
| Existing whole-home battery | **Missing from app** |
| Street address | **Captured in app** as `propertyIdentifier`, not structured street / city / ZIP |
| Apartment, unit, or structure | **Missing from app** (Base’s “meter detail” confirm is a **unit** field, not a meter badge) |
| First and last name | **Captured in app** as one `contactName` |
| Phone and email | **Captured in app** |
| Marketing SMS opt-in | **Missing from app** |
| How did you hear about us | **Missing from app** |
| Main reason / plan choice / how you buy power (Oncor) | **Missing from app** |
| ESIID / utility account | **Missing from app** (absent from the public join form as well) |
| HOA, roof, Wi-Fi | **Missing from app** (Help topics, not signup fields; Wi-Fi is post-install) |

For a prototype aimed at **site evidence**, those join-only gaps are mostly the wrong surface to close. Rent, standby generators, and an existing third-party battery are the exceptions: Base already uses them as hard product filters before photos, and the app never asks.

## Engineers want nine photos; the app keeps few
The published **Required Photos** list is the real eligibility packet. Base wants (1) a zoomed **electric meter** with a **legible meter number**, (2) the **area surrounding the meter** from at least **10 steps** back, (3) the area to the **right**, (4) the area to the **left**, (5) the **adjacent wall** corner to corner, (6) **behind the fence** if applicable, (7) the **main breaker box**, (8) the **main disconnect** showing amperage (usually 125, 150, or 200), and (9) the **area surrounding the breaker box** if that is not already in frame. Gas meters are a **3 ft spacing rule**, not a named upload slot. There is no “proposed battery location” photo: engineers infer a legal pad from the wide shots, and the crew may still move it on install day (`([Why does Base request home photos?](https://help.basepowercompany.com/en/articles/10280641))`, `([electrical and spacing requirements](https://help.basepowercompany.com/en/articles/10280705))`).

The app writes photo JPEGs (`meter.jpg`, `breaker.jpg`) and no longer saves an AR `placement.jpg` screenshot; placement evidence is the AR scan (`scene.ply` and keyframes). Meter number and breaker amperage are **typed** confirmations, which is stricter than Base’s public kit (Base wants those values **readable in the photo**, not entered as fields). OCR exists as `MeterNumberRecognizing` but always returns nil, so the number stays manual. The breaker tile is one photo that can stand in for both the box and the disconnect close-up; the app does not force a lid-lifted amperage crop the way Help troubleshooting does (`([SurveyStore.swift](../BaseAR/Survey/SurveyStore.swift))`, `([MeterNumberRecognizing.swift](../BaseAR/Electrical/MeterNumberRecognizing.swift))`).

| Photo-kit item | App status |
| --- | --- |
| Electric meter, number legible | **Captured in app** (one still) plus typed `meterNumber` |
| Surrounding meter, ≥10 steps | **Missing from app** |
| Area to the right of the meter | **Missing from app** |
| Area to the left of the meter | **Missing from app** |
| Adjacent wall, corner to corner | **Missing from app** |
| Behind the fence (if applicable) | **Missing from app** |
| Main breaker box | **Captured in app** (one still, shared with disconnect) |
| Main disconnect amperage visible | **Captured in app** as the same breaker photo, plus typed `mainBreakerAmperage` |
| Area surrounding the breaker box | **Missing from app** |
| Gas-meter photograph | **Missing from app** (Base also does not name this slot) |

That is the photo-kit gap. If this prototype is meant to stand in for the packet engineers actually review, **six of nine required compositions are absent**: the wide left / right / surrounding / adjacent / behind-fence / panel-context shots that exist so someone can see a **3 ft × 3 ft** pad, **3 ft** side clearance, and a legal wall for the transfer switch. One close meter photo plus an AR scan does not replace that set. The dashboard uploader itself was not opened (it sits behind `account.basepowercompany.com` after signup or deposit), so required flags and file limits on Base’s real form remain unknown; the **composition list** is the published contract.

## Austin checks add measurements Base never asks homeowners to type
Published Austin / ground-mount guidance matches the app’s seven required rules almost verbatim: main breaker **150–200A** in Austin (the national Help band is **100–200A**, with **200A panel** if solar or two batteries), **3 ft × 3 ft** footprint, **within 20 ft** of the meter, **within 1 ft** of the wall, **at least 3 ft** from a gas meter, and wall space for a transfer switch about **13 in** wide with **30 in** NEC working clearance beside the meter. Core’s published box is **30.68 in W × 35.9 in H × 22 in D**, which is the AR placeholder. Official extras the app does **not** encode include meter height **≤ 6 ft**, **30 × 36 in** working space in front of meter and panel, meter and panel on the **same wall**, **one** main breaker box **not in a closet**, alley walk-by **32–38 in**, no indoor or garage install, and no customer-poured pad (`([electrical and spacing requirements](https://help.basepowercompany.com/en/articles/10280705))`, `([Base Core specs](https://www.basepowercompany.com/specs/core))`).

The app **measures** three of those siting rules in AR when the user places a battery and marks the meter (and optionally a gas meter), and it **draws** the 3 ft pad. `footprintIsClear` and `transferSwitchClearanceObserved` exist on `PlacementEvidence` so those checks can stay **unknown** until someone actually measures them; nothing in the UI or measurer writes either field. `plannedBatteryCount` is the same pattern: the solar-or-two-batteries rule needs it, Review shows **Not captured**, and no control sets it. Green (`PlacementTone.clear`) therefore cannot appear in this build (`([SurveySession.swift](../BaseAR/Survey/SurveySession.swift))`, `([BaseRuleSet.swift](../BaseAR/Rules/BaseRuleSet.swift))`, `([PlacementMeasuring.swift](../BaseAR/Placement/PlacementMeasuring.swift))`).

| Evidence / output | App status vs Base forms |
| --- | --- |
| Typed meter number and breaker amperage | **Captured in app**; **missing from Base’s public forms** (photo evidence only) |
| `plannedBatteryCount` | **On app model but stubbed** |
| `footprintIsClear` | **On app model but stubbed** (pad is visual only) |
| `transferSwitchClearanceObserved` | **On app model but stubbed** |
| Meter / wall / gas distances, AR anchors, yaw | **App-only extras** (Base does not collect homeowner tape-measure fields) |
| Gas meter marked in AR | **App-only extra** (optional mark; unmarked stays unknown, not “no gas”) |
| LiDAR mesh flag | **App-only extra** |
| Phone GPS (`GeoFix`) | **App-only extra**: latitude, longitude, timestamp, horizontal accuracy. **Property fix, not a battery coordinate.** AR `PlacementAnchor` is local tracking space, not lat/long |
| Local rule results and placement tone | **App-only extras**; Base reserves the verdict for engineers |
| `survey.json` + photos and AR scan, share sheet | **App-only extra**. **No network. Not a Base submission.** |

GPS and approval copy are consistent on intro, home, placement, review, and the location permission string: the fix is the phone’s property location, and the packet is a **preliminary survey**, not an inspection, code review, or installation approval (`([SurveySession.swift](../BaseAR/Survey/SurveySession.swift))`). Treating that pin as the Core’s install coordinate would invent a precision Base itself does not claim from photos.

## Conclusion
The useful comparison is not “does the app clone Get Started.” Get Started is a **lead router**. The app already overlaps that router on name, email, phone, address, and solar, and it outruns it on the identifiers engineers later need (typed meter number and amperage, plus measured meter/wall/gas distances). The useful comparison is the **photo kit**: Base’s eligibility decision is still a **wide, multi-angle meter-yard packet**, and the prototype stores a **close meter, a close breaker, and one AR frame**. Closing left / right / adjacent / behind-fence context — or treating the AR scene as a guided substitute for those compositions — is the capture work that would make the local packet look like what Base’s engineers already ask for. Until `footprintIsClear`, transfer-switch space, and planned battery count are actually measured, the app can flag conflicts but cannot honestly turn the preview green, which is the correct prototype stance: evidence in, verdict reserved, nothing uploaded to Base.
