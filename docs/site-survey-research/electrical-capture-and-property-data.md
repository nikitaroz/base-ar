# Base Power AR: Electrical Capture and Property Data

Research and implementation brief | September 26, 2026

## Executive findings

**Public electrical permit data can make an AR enrollment survey meaningfully smarter before the camera opens.** Austin publishes address-linked electrical permits with descriptions, status, dates, and parcel identifiers; live queries returned finalized records explicitly describing panel replacements, main-breaker replacements, and service equipment amperages ([Austin permit dataset](https://data.austintexas.gov/Building-and-Development/Issued-Construction-Permits/3syk-w9eu)). This is historical evidence to compare against a fresh photograph, not an authoritative current inventory of every property's electrical equipment.

The strongest recommended product combines four distinct evidence layers:

- **Public property history:** Resolve the address and utility territory, then retrieve relevant permits and reference equipment information.
- **Current camera evidence:** Read visible equipment labels and preserve photographs, text locations, candidate values, and user confirmation.
- **AR geometry:** Estimate equipment location and surrounding dimensions, while explicitly exposing tracking and measurement uncertainty.
- **Customer-authorized utility data:** Optionally obtain meter metadata and consumption through the appropriate utility route, rather than treating geolocation as permission.

No comprehensive, public, address-to-current-panel-and-meter database was verified in this investigation. Austin explicitly treats customer usage and advanced-meter information as confidential by default, while Smart Meter Texas documents customer authorization for third-party access ([Austin utility confidentiality policy](https://coautilities.com/wps/wcm/connect/occ/coa/util/support/utility-service/confidentiality), [Smart Meter Texas security and access terms](https://www.smartmetertexas.com/?view=security)).

Scope is Austin-first, with a separate route for eligible Texas utility territories. No test property address or iPhone model was supplied, so the results below establish sources and capabilities, not the configuration of a particular home; no native app integration or device accuracy test was performed.

## What Base actually needs photographed

Base's published survey is not simply “meter or breaker box”: it requests a readable meter number, wide and side views around the meter, adjacent-wall context, conditional fence views, the main breaker box, main-disconnect amperage, and additional breaker context when needed ([Base photo instructions](https://help.basepowercompany.com/en/articles/10280641)). Base also describes engineering review of home photos before installation, which makes an evidence packet a better product target than an automated safety approval ([Base installation partners](https://www.basepowercompany.com/install-partners)).

Recommended guided targets are therefore:

- **Meter identity:** Printed utility meter number, manufacturer/model when visible, and a clean identifying image.
- **Main disconnect:** A separate close-up of the actual main-disconnect rating, not an arbitrary branch breaker.
- **Panel nameplate:** Manufacturer, catalog/model, marked voltage, bus rating, and other legible equipment information.
- **Site context:** Wider images showing the relationship between equipment, adjacent walls, obstructions, and proposed battery placement.
- **Optional meter display:** A separate, clearly labeled reading capture. It must not replace the printed meter identity photograph.

Treat eligibility and placement requirements as versioned Base rules, with jurisdiction, battery configuration, and hardware applicability attached. A photo-collection app should not silently turn a partial reading into a permit, engineering decision, or assertion of code compliance.

## What the iPhone can obtain

### Camera, OCR, and AR capabilities

| Data or capability | Available mechanism | Appropriate interpretation |
|---|---|---|
| Camera image and capture timestamp | `ARFrame.capturedImage` and `timestamp` ([Apple ARFrame](https://developer.apple.com/documentation/arkit/arframe)) | Raw visual evidence; retain an unobstructed image rather than only an AR screenshot. |
| Camera calibration | Intrinsic matrix and image resolution ([Apple camera intrinsics](https://developer.apple.com/documentation/arkit/arcamera/intrinsics)) | Inputs for projecting image observations into geometry, not electrical measurements. |
| Printed text and candidate strings | Vision `VNRecognizeTextRequest` ([Apple text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)) | OCR candidates requiring semantic classification and confirmation. |
| Depth and confidence maps | `sceneDepth`, supported on LiDAR-capable devices ([Apple scene-depth example](https://developer.apple.com/documentation/ARKit/displaying-a-point-cloud-using-scene-depth)) | Approximate visible-surface distance, subject to confidence and capture conditions. |
| Scene mesh and raycasting | Scene reconstruction and `ARMeshAnchor` ([Apple reconstruction example](https://developer.apple.com/documentation/ARKit/visualizing-and-interacting-with-a-reconstructed-scene)) | Estimated surfaces and placement geometry. |
| Generic surface classes | Mesh classes include wall, floor, ceiling, table, seat, window, door, and none ([Apple mesh classifications](https://developer.apple.com/documentation/arkit/armeshclassification)) | ARKit does not supply a built-in “electric meter” or “breaker panel” mesh class. |
| Higher-resolution still capture within AR | Supported configurations can use a recommended high-resolution format and `captureHighResolutionFrame` ([Apple AR configuration guidance](https://developer.apple.com/documentation/arkit/configuration-objects)) | Feature-check on the actual phone and retain a normal-frame fallback. |
| Property location and uncertainty | Core Location horizontal accuracy is a radius in meters; negative values indicate invalid accuracy ([Apple horizontal accuracy](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy)) | A property candidate, not proof of the exact parcel, meter, or outdoor equipment location. |

Recommendation: start with user-selected capture modes such as “meter label,” “main disconnect,” and “panel label,” rather than training a detector before validating the workflow. Vision should extract text within the selected target, while ARKit supplies the spatial context; the two should contribute separate observations.

### Electrical fields worth extracting

| Target | Candidate fields | Mandatory distinction |
|---|---|---|
| Meter face/nameplate | Printed meter number, manufacturer/model, class, form, marked voltage, barcode when present | Meter class and nominal voltage are equipment attributes, not measured service load or verified main-breaker size; meter variants have different electrical and communication options ([Landis+Gyr FOCUS AXe specification](https://www.landisgyr.com/content/dam/landisgyr/products/product-sheets/devices/2510%20LG%20Focus%20AXe%20PS%20digital.pdf)). |
| Main disconnect | Visible amperage marking and associated device identity | Keep this separate from panel nameplate capacity; a panel may have a main breaker below its marked panel rating ([UL panelboard guide](https://www.ul.com/thecodeauthority/knowledge/panelboards-guide)). |
| Panel nameplate | Manufacturer/catalog number, bus ampacity, voltage, phase where marked, short-circuit rating | Short-circuit rating is not normal service amperage, and bus capacity is not necessarily main-breaker amperage ([UL panelboard guide](https://www.ul.com/thecodeauthority/knowledge/panelboards-guide)). |
| Digital meter display | Visible number, decimal position, unit, register identifier, timestamp | A changing register value is not the printed meter ID; register meanings depend on the meter/utility configuration ([Oncor meter FAQs](https://www.oncor.com/content/oncorwww/us/en/home/faqs/faqs-details.html)). |
| Surrounding scene | Relative positions and approximate wall/ground distances | Measurements need their own uncertainty and tracking status; reconstructed geometry is an AR output, not a site inspection ([Apple scene reconstruction](https://developer.apple.com/documentation/ARKit/visualizing-and-interacting-with-a-reconstructed-scene)). |

A concrete manufacturer example demonstrates the semantic risk: Schneider lists a Homeline configuration with a **200 A main breaker and 225 A bus rating** ([Schneider Homeline product information](https://productinfo.se.com/nadigest/5c51d645347bdf0001f1f280/Master/17701_MAIN%20(bookmap)_0000056628.xml/$/_17701015_58738)). The app should have separate fields for those numbers, not a single `amps` property.

Recommended prohibited inference: do not present camera-derived values as actual current, measured voltage, available load headroom, verified grounding, hidden conductor size, or safety approval. Capture visible evidence only, and route uncertain or conflicting cases to a qualified reviewer.

### What a meter reading actually provides

Oncor documents register `001` for inflow and `057` for outflow on applicable configured meters; it also explains that the outflow reading is cumulative rather than the current month's exported energy ([Oncor meter FAQs](https://www.oncor.com/content/oncorwww/us/en/home/faqs/faqs-details.html)). These are useful examples of why the app must store register context, but they should not be hardcoded as universal Austin Energy meter rules.

For a known cumulative-energy register with valid timestamps and no reset or rollover, two readings permit a calculation:

\[
\text{energy difference} = (\text{later register} - \text{earlier register}) \times \text{applicable multiplier}
\]

\[
\text{average power in kW} = \frac{\text{energy difference in kWh}}{\text{elapsed hours}}
\]

This calculation does not establish instantaneous load, starting surge, or code-compliant service capacity. If the register, units, scaling, channel, or identity are uncertain, retain the images and mark the reading uninterpreted rather than manufacturing a consumption estimate.

Recommendation: capture a short sequence when the LCD cycles through screens, while keeping printed meter identity and digital readings in separate data objects. Do not assume a documented optical port or AMI radio can be read directly by an ordinary iPhone app; the meter specification describes those interfaces but does not establish an authorized iPhone integration ([Landis+Gyr meter specification](https://www.landisgyr.com/content/dam/landisgyr/products/product-sheets/devices/2510%20LG%20Focus%20AXe%20PS%20digital.pdf)).

## Public records that can prepopulate the survey

### Austin construction permits: verified bulk electrical data

The public Austin construction-permit dataset includes electrical permits and exposes a queryable API plus a bulk-download option ([Austin permit dataset](https://data.austintexas.gov/Building-and-Development/Issued-Construction-Permits/3syk-w9eu), [bulk resource catalog](https://catalog.data.gov/dataset/issued-construction-permits/resource/ea7a948d-5f0c-43fd-a6fd-19fb82e4f2b4)). Its schema includes `permittype`, `permit_number`, `description`, `tcad_id`, address fields, jurisdiction, status, issue/completion dates, coordinates, and a detailed-record link; it does not expose dedicated structured fields for main-breaker amperage, panel model, or meter serial number ([verified dataset schema](https://data.austintexas.gov/api/views/3syk-w9eu.json)).

The useful electrical information is often in the **description**, and a live bounded query returned the following records ([executed electrical-permit query](https://data.austintexas.gov/resource/3syk-w9eu.json?$select=permit_number,description,status_current,issue_date,completed_date&$where=permittype%3D%27EP%27%20AND%20status_current%3D%27Final%27%20AND%20upper(description)%20like%20%27%25200%25%27&$order=issue_date%20DESC&$limit=5)). This was a deliberately targeted sample of finalized records containing “200,” not a prevalence estimate or a result for the user's property.

| Permit | Recorded work | Product implication |
|---|---|---|
| `2026-117621 EP` | Final; description specifies a 400 A riser, two 200 A meter bases, and two 125 A panels for units A and B ([live query](https://data.austintexas.gov/resource/3syk-w9eu.json?$select=permit_number,description,status_current,issue_date,completed_date&$where=permittype%3D%27EP%27%20AND%20status_current%3D%27Final%27%20AND%20upper(description)%20like%20%27%25200%25%27&$order=issue_date%20DESC&$limit=5)). | Extract component-specific assertions and unit associations. “Largest number wins” would produce the wrong residential panel inference. |
| `2026-122365 EP` | Final; “200amp panel replacement. No meter work. AE is the electrical provider.” ([live query](https://data.austintexas.gov/resource/3syk-w9eu.json?$select=permit_number,description,status_current,issue_date,completed_date&$where=permittype%3D%27EP%27%20AND%20status_current%3D%27Final%27%20AND%20upper(description)%20like%20%27%25200%25%27&$order=issue_date%20DESC&$limit=5)). | Suggest a 200 A panel-history hint, but do not claim a replacement meter or infer the current disconnect rating. |
| `2026-120250 EP` | Final; description says a loose/tripping main breaker was replaced with a 200 A main breaker ([live query](https://data.austintexas.gov/resource/3syk-w9eu.json?$select=permit_number,description,status_current,issue_date,completed_date&$where=permittype%3D%27EP%27%20AND%20status_current%3D%27Final%27%20AND%20upper(description)%20like%20%27%25200%25%27&$order=issue_date%20DESC&$limit=5)). | Stronger historical evidence for the main-breaker field, still requiring property matching and current verification. |
| `2026-122293 EP` | Final; emergency like-for-like upgrade of an existing 200 A underground service with new panel and meter ([live query](https://data.austintexas.gov/resource/3syk-w9eu.json?$select=permit_number,description,status_current,issue_date,completed_date&$where=permittype%3D%27EP%27%20AND%20status_current%3D%27Final%27%20AND%20upper(description)%20like%20%27%25200%25%27&$order=issue_date%20DESC&$limit=5)). | Surface a service-history hint and request both panel and meter confirmation. |
| `2026-121087 EP` | Final; “Replacing AE meter can and 200A outdoor panel” ([live query](https://data.austintexas.gov/resource/3syk-w9eu.json?$select=permit_number,description,status_current,issue_date,completed_date&$where=permittype%3D%27EP%27%20AND%20status_current%3D%27Final%27%20AND%20upper(description)%20like%20%27%25200%25%27&$order=issue_date%20DESC&$limit=5)). | Identify outdoor-panel context without equating a meter can with meter identity. |

Recommended production retrieval:

- **Property match:** Confirm address, unit, and parcel before accepting a record as relevant.
- **Projection:** Request descriptions, IDs, dates, status, and record links rather than unnecessary contractor or owner contact fields.
- **History:** Retrieve relevant electrical history, including unresolved work, but distinguish final, active, expired, and other statuses.
- **Extraction:** Preserve exact text spans and associate numbers with equipment, unit, and whether work is proposed or recorded as completed.
- **Reconciliation:** Show historical expectations beside current photographs; never overwrite contradictory OCR merely to make it match a permit.
- **Scale:** Begin with bounded address/parcel queries and caching, not a full-city download on a phone.

Recommended UI language: “A finalized permit describes replacement of a 200 A main breaker. Please photograph the current main-disconnect marking.” Avoid “Your house has verified 200 A service” based on that record alone.

### Geolocation, parcel, utility, and building layers

| Public source | Verified content | Recommended use |
|---|---|---|
| Austin Energy service-area polygon | `SERVICE_AREA`, polygon geometry, query support ([utility boundary schema](https://maps.austintexas.gov/gis/rest/Shared/BoundariesGrids_2/MapServer/1?f=pjson)) | Route utility-specific onboarding; confirm against the bill when uncertain. |
| Travis appraisal-district parcels | `PID_10`, `PROP_ID`, parcel geometry ([parcel schema](https://maps.austintexas.gov/gis/rest/Shared/AppraisalDistricts/MapServer/0?f=pjson)) | Identify parcel candidates; verify identifier mapping to permit `tcad_id` before deploying the join. |
| Address points | House number, street components, `PLACE_ID`, and `PARENT_PLACE_ID` ([address-layer schema](https://maps.austintexas.gov/gis/rest/Shared/Property/MapServer/0)) | Resolve the correct address and distinguish multiple units or structures. |
| Building footprints, 2023 | Building polygons and height/elevation fields ([footprint schema](https://maps.austintexas.gov/gis/rest/Shared/PlanimetricsSurvey_1/MapServer/0?f=pjson)) | Background context and structure disambiguation, not current equipment position or clearance approval. |
| Electrical permit GIS layer | Permit number, location, dates, status, description, and record link; `WORK_DESCRIPTION` has a 250-character field length ([electrical GIS schema](https://maps.austintexas.gov/gis/rest/Shared/Permits/MapServer/4?f=pjson)) | Map discovery; prefer the Socrata description for text extraction to avoid this field's length limit. |

A live point-in-polygon query using the generic demonstration coordinate longitude `-97.7431`, latitude `30.2672` returned `Austin Energy Service Area` ([executed utility query](https://maps.austintexas.gov/gis/rest/Shared/BoundariesGrids_2/MapServer/1/query?f=pjson&geometry=-97.7431,30.2672&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=SERVICE_AREA&returnGeometry=false)). This demonstrates a working lookup, not the user's utility assignment.

Implementation recommendations:

- **Coordinates:** Send longitude before latitude and specify `inSR=4326` for GPS coordinates.
- **Units:** Explicitly transform returned geometry; these Austin layers use a projected coordinate system with feet, not the meters used for AR geometry ([Austin parcel spatial reference](https://maps.austintexas.gov/gis/rest/Shared/AppraisalDistricts/MapServer/0?f=pjson)).
- **Ambiguity:** Retain the GPS uncertainty radius and require confirmation if multiple parcels, units, or buildings are plausible.
- **Identifiers:** Preserve parcel and service IDs as strings, including leading zeros. Validate `PID_10` to `tcad_id` matching on known examples rather than assuming all appraisal identifiers are interchangeable.
- **Coverage:** Outside the Austin Energy polygon means “not matched to this layer,” not automatically “Oncor.” Use a confirmed utility or a second authoritative territory source.

AR's local coordinate system should stay separate from the property's geographic coordinate. Apple's geographic AR tracking relies on supported-location checks and visual localization imagery largely associated with public streets, so it is not an appropriate dependency for a meter behind a private fence ([Apple geographic AR tracking](https://developer.apple.com/documentation/arkit/tracking-geographic-locations-in-ar)).

### Detailed plans, ESPA forms, and permit attachments

Austin's AB+C manual describes public permit search without registration, including record information, processes, and attachments available for public sharing; availability depends on record type and status ([AB+C public-search manual](https://abc.austintexas.gov/citizenportal/custom/AB+C%20Manual.pdf)). Detailed pages for sampled permits were blocked during this investigation by an IP/security challenge, so the existence or contents of electrical drawings for those records remain unverified ([sample detailed permit page](https://abc.austintexas.gov/web/permit/public-search-other?t_detail=1&t_selected_folderrsn=13774065)).

Austin Energy's Electric Service Planning Application, or ESPA, is especially relevant: the reference form includes service address, main disconnect, meter-can size and quantity, calculated load, service voltage, conductors, and overhead/underground service information ([ESPA reference guide](https://austinenergy.com/-/media/project/websites/austinenergy/commercial/PDFs%20and%20Files/ESPA%20Reference%20Guide.pdf)). The blank form is public, but that does not establish a public database of completed applications; Austin Energy describes it as part of the service-planning and approval process ([Austin Energy construction forms](https://austinenergy.com/contractors/Construction-Renovation/Forms)).

Recommendation: accept a homeowner-supplied approved ESPA or electrical plan as optional evidence, and distinguish its design date and approval status from installed equipment. For unavailable city records, Austin provides a records-and-research route, potentially including public-information requests and retrieval costs; no request or fee-bearing action was initiated here ([Austin records and research](https://www.austintexas.gov/development-services/records-and-research)).

## Actual utility metadata and consumption

### Smart Meter Texas: rich data, authorized access

Smart Meter Texas documents meter, premise, interval, daily, and monthly data interfaces and customer authorization for third-party sharing; its guide lists AEP Texas, CenterPoint, Oncor, and TNMP service territories, not Austin Energy ([SMT data-access guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)). Consequently, “the property is in Texas” is not sufficient to route a household into this integration.

| Data group | Documented fields or outputs | Survey value |
|---|---|---|
| Meter metadata | `meterSerialNumber`, `utilityMeterId`, `manufacturerName`, `meterModel`, `meterClass`, `meterPhases`, `installationDate`, `KWHMeterMultiplier`, and other configuration fields ([SMT guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)) | Cross-check meter identity and interpret usage with known metadata. |
| Premise metadata | `ESIID`, `serviceVoltage`, structured service address, `premiseStatus`, `timeZone`, `loadProfile`, and `rateClassCode` ([SMT guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)) | Validate service point and utility context separately from the device serial number. |
| Interval data | 15-minute consumption/generation data with actual/estimated indicators ([SMT guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)) | Historical load-pattern analysis, not guaranteed real-time power. |
| Daily/monthly data | Daily start/end readings and kWh; monthly billing quantities and demand-related fields where applicable ([SMT guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)) | Consumption and billing context beyond a single photo. |
| On-demand reading | Near-real-time request functionality with access and request constraints ([SMT guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)) | Optional authorized reading, not a promise of continuous low-latency telemetry. |

The documented fields do not establish access to a home's breaker-circuit inventory or installed main-breaker rating ([SMT data-access guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)). Even with utility authorization, those still need their own evidence.

SMT's guide describes account credentials, token authentication, third-party integration requirements, and customer-sharing workflows ([SMT data-access guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)). Recommended architecture is a secured backend adapter with explicit customer consent and revocation handling; do not embed integration credentials in the Swift application or assume API enrollment can be completed during a short demo build.

### Austin Energy: different route

Austin's utility confidentiality policy makes individual usage, billed amounts, and advanced-meter data confidential by default, subject to its stated exceptions and customer disclosure choices ([Austin utility privacy policy](https://coautilities.com/wps/wcm/connect/occ/coa/util/support/utility-service/confidentiality)). A public building permit and protected utility consumption are different data categories, even when both refer to the same street address.

Austin Energy's residential guidance documents authenticated energy-usage views and a Green Button download ([Austin Energy residential usage tools](https://savings.austinenergy.com/multifamily/learn/tips-for-residents/multifamily-app)). Commercial guidance also describes Energy Profiler Online, interval information, and data-sharing features, but that is not evidence of an unrestricted public API or identical residential capabilities ([Austin Energy commercial usage tools](https://austinenergy.com/energy-efficiency/monitor-usage/commercial)).

Recommended prototype route: let the homeowner upload their own available Green Button export, while keeping the photo survey usable without it. Preserve timestamps, time zone, channels, units, and provenance; do not claim a public address lookup can retrieve their historical usage.

### Public ESI ID lookup is narrower than meter access

Address-based ESI ID lookup interfaces exist for deregulated Texas service areas, including Energy Ogre's public lookup ([Energy Ogre lookup](https://www.energyogre.com/esid-lookup-tool)). However, SMT separately models the premise `ESIID`, `meterSerialNumber`, and `utilityMeterId`, so the service-point identifier must not be substituted for the printed device number ([SMT field definitions](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf)).

Recommendation: treat a lookup website as a manual fallback unless documented integration rights and an appropriate API are established. A public-facing search form neither authorizes bulk harvesting nor grants access to usage.

## Equipment references and model training data

Austin Energy publishes approved metering-equipment references, including 200 A and class-320 socket categories and manufacturer information ([Austin Energy metering and transformers](https://austinenergy.com/contractors/Construction-Renovation/Metering-Transformers)). These can support a utility-specific vocabulary and equipment-reference catalog, but they are approved-equipment lists, not a property-level installation inventory.

Manufacturer documentation can help interpret a confirmed model's markings and options, such as a panel's distinct main and bus ratings or a meter family's supported forms and communication hardware ([Schneider panel specifications](https://productinfo.se.com/nadigest/5c51d645347bdf0001f1f280/Master/17701_MAIN%20(bookmap)_0000056628.xml/$/_17701015_58738), [Landis+Gyr meter specifications](https://www.landisgyr.com/content/dam/landisgyr/products/product-sheets/devices/2510%20LG%20Focus%20AXe%20PS%20digital.pdf)). Recommended matching order is visible manufacturer plus exact model plus the relevant variant, with unmatched or ambiguous configurations left unresolved.

Public automatic-meter-reading datasets exist, including UFPR-AMR, UFPR-ADMR, and Copel-AMR entries in UFPR's research catalog ([UFPR visual research datasets](https://web.inf.ufpr.br/vri/databases/)). This investigation did not verify their commercial-use licenses or suitability for Texas utility serial labels, so they should not be treated as a ready-to-ship model or a representative accuracy benchmark.

Recommendation: begin with native OCR and a permissioned local evaluation set. Include reflective glass, weathered labels, multiple meters, digit confusions, rotating LCD registers, subpanels, and visibly different bus/main ratings before considering a custom model.

## Proposed Swift and backend architecture

### Capture and recognition

The reviewed repository snapshot already contains a `VisionMeterNumberRecognizer` that selects numeric candidates of 7–12 digits, ranks by text height and confidence, and returns the top result. It also contains Core Location acquisition; these are existing building blocks, not a completed property-data or semantic electrical-recognition pipeline.

Recommended changes:

- **Recognition contract:** Return several typed candidates, original text, bounding boxes, and OCR confidence instead of only a digit string.
- **Identity safeguards:** Do not discard all non-numeric characters before deciding what field a string represents. Preserve leading zeros and distinguish printed meter identity from an LCD register.
- **Camera orientation:** Pass the correct image orientation to Vision and map recognized boxes through the image/display transforms before drawing overlays.
- **Frame scheduling:** Start with a tunable low-frequency OCR loop and one request in flight. Profile thermal load, responsiveness, and accuracy on the actual iPhone rather than assuming a fixed rate is safe.
- **Capture quality:** Request a clear label view, reduce glare by changing the viewing angle, and retain a high-quality raw capture where supported.
- **Confirmation:** Require explicit acceptance of meter ID and main-disconnect rating. OCR confidence is not the probability that the value belongs to the right electrical component.
- **Spatial quality:** Keep image-space OCR, depth geometry, and AR world coordinates separate until their transformations are validated. Reject unreliable depth and tracking instead of silently filling gaps.

Apple provides `VNRecognizeTextRequest` for text recognition, AR image/display transformations, and feature-checked depth/high-resolution capture capabilities ([Vision API](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), [ARFrame API](https://developer.apple.com/documentation/arkit/arframe), [AR configuration guidance](https://developer.apple.com/documentation/arkit/configuration-objects)). Recommended first implementation should reuse these APIs rather than requiring a new trained model or assuming every supported iPhone has LiDAR.

### Property enrichment service

Recommended request:

```json
{
  "confirmedAddress": "user-confirmed service address",
  "unit": "optional unit",
  "coordinate": {
    "latitude": 30.2672,
    "longitude": -97.7431,
    "horizontalAccuracyMeters": 12
  },
  "requestedEvidence": [
    "utilityTerritory",
    "parcelCandidates",
    "electricalPermitHistory"
  ]
}
```

This is a proposed contract, not a deployed endpoint; the coordinate is a generic demonstration point. Recommended response states include `matched`, `ambiguous`, `not_found`, `partial`, `source_unavailable`, and `authorization_required`, so missing records never mean “the property has no electrical equipment.”

Recommended processing order:

1. Confirm service address and unit with the user.
2. Resolve utility and parcel candidates, retaining uncertainty.
3. Query permit history by verified identifiers and normalized address.
4. Extract component-specific historical assertions with exact text spans.
5. Generate a small set of expected labels and next-photo prompts.
6. Compare new camera observations with public history.
7. Offer an optional utility-data connection or customer file import.
8. Export a reviewer-ready packet with original images and contradictions.

### Evidence model

Use separate evidence records rather than merging everything into one “property facts” object. The following is an illustrative schema, not a finding about a real home:

```json
{
  "field": "mainDisconnectAmpRating",
  "componentId": "main-disconnect-1",
  "value": 200,
  "unit": "A",
  "sourceType": "photo_ocr",
  "sourceRef": "photo-123",
  "rawText": "200",
  "capturedAt": "ISO-8601 capture time",
  "effectiveAt": null,
  "ocrConfidence": 0.94,
  "humanConfirmed": false,
  "propertyMatch": "confirmed_address_unverified_meter",
  "status": "needs_confirmation"
}
```

Recommended additional fields include image-region coordinates, permit number/status, exact supporting text, document revision, utility identifier, and the algorithm version that produced an extraction. Store geometry uncertainty separately from OCR confidence and property-matching confidence; none should be treated as an interchangeable quality score.

A permit saying “200 A panel” and a visible main breaker saying “125” should create a conflict or a component-classification question, not an automatic correction. Likewise, a photograph of one meter at a duplex must not inherit a neighbor's permit or utility account merely because the parcel matches.

## Verified query entry points

These are source interfaces verified during the investigation, not deployed app features. They provide an implementation starting point without requiring a broad scrape of residential records.

- **Permit schema:** [Austin dataset metadata](https://data.austintexas.gov/api/views/3syk-w9eu.json).
- **Working electrical sample query:** [Five finalized permits with electrical descriptions containing 200](https://data.austintexas.gov/resource/3syk-w9eu.json?$select=permit_number,description,status_current,issue_date,completed_date&$where=permittype%3D%27EP%27%20AND%20status_current%3D%27Final%27%20AND%20upper(description)%20like%20%27%25200%25%27&$order=issue_date%20DESC&$limit=5).
- **Working utility lookup:** [Point-in-polygon query for the demonstration coordinate](https://maps.austintexas.gov/gis/rest/Shared/BoundariesGrids_2/MapServer/1/query?f=pjson&geometry=-97.7431,30.2672&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=SERVICE_AREA&returnGeometry=false).
- **Parcel query schema:** [Travis appraisal parcels](https://maps.austintexas.gov/gis/rest/Shared/AppraisalDistricts/MapServer/0?f=pjson).
- **Address query schema:** [Austin address points](https://maps.austintexas.gov/gis/rest/Shared/Property/MapServer/0).
- **Authorized utility integration specification:** [SMT data-access guide](https://www.smartmetertexas.com/commonapi/gethelpguide/help-guides/Smart_Meter_Texas_Data_Access_Interface_Guide%20-%20v2.pdf).

Recommendation: construct production URLs with a URL/query builder, escape user inputs appropriately, paginate with bounded requests, and cache responses with retrieval timestamps. Review current source terms and request limits before scaling; an accessible endpoint is not a promise of uptime or an unlimited production service.

## Build sequence and validation gates

### First working slice

Prioritize one end-to-end flow: confirmed Austin address → public electrical history → meter/disconnect capture → explicit confirmation → reviewer packet. Defer utility-account integration until the public-history and photo workflow works reliably.

- **Property context:** Show confirmed address, tentative/confirmed utility, recent relevant permit summaries, and unavailable-data states.
- **Semantic capture:** Separate meter number, main breaker, panel bus rating, and optional display register.
- **Evidence comparison:** Highlight agreement, conflict, and missing evidence without promising automatic eligibility.
- **Export:** Include original images, extracted fields, source links, dates, confirmation state, and unresolved questions.

### Required tests

| Test case | Expected behavior |
|---|---|
| No relevant public permits | Continue capture; display “no matching records found,” not “no electrical work.” |
| Old permit and different current label | Preserve both; flag conflict for review. |
| 225 A bus and 200 A main | Record separate equipment fields. |
| 200 A panel history and 125 A visible breaker | Ask whether this is the main or a subpanel; do not silently choose 200. |
| Duplex or several meters | Require unit and meter association; do not infer from parcel alone. |
| LCD number larger than printed serial | Keep reading and identity candidates separate. |
| Glare, partial label, OCR disagreement | Ask for recapture or manual confirmation. |
| No LiDAR or poor AR tracking | Preserve photo/OCR workflow; disable unsupported spatial claims. |
| Location denied or imprecise | Allow address entry and explicit confirmation. |
| Protected utility data unavailable | Continue the survey; offer optional authorized import later. |
| Permit portal blocked or unavailable | Preserve available public metadata and record the missing attachment state. |

Recommended safety boundary: photograph externally accessible labels only; do not instruct users to remove dead fronts, break meter seals, pull meters, touch wiring, or operate breakers merely to identify equipment. Unreadable or inaccessible information should become a reviewer task rather than a more invasive homeowner instruction.

## Verification limits and next decision

The investigation verified public API schemas, executed bounded electrical-permit and utility-boundary queries, and examined primary utility, manufacturer, Base, and Apple documentation. It did not download the entire permit corpus, establish completeness for every property, verify completed ESPA attachments, authorize a utility account, or measure recognition accuracy on an iPhone.

The next useful test needs a specific service address or coordinates, the unit if applicable, and the iPhone model. The recommended success criterion is not “the app guessed the amperage,” but “the app retrieved relevant evidence, correctly identified the component, captured a legible current label, and clearly exposed anything that still needs review.”
