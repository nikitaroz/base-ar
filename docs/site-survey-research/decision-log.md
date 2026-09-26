# Product decision log

This is a task-relevant summary of the conversation, not a verbatim transcript. It preserves the current direction and the reasoning needed to avoid restarting the strategy discussion.

## Evolution of the idea

- **Initial comparison:** The discussion considered enrollment/photo capture, physical battery design optimization, a Base home-software OS, and battery-aware competition with Arbor in retail-choice markets. The original comparison and supplied reviewed input are retained in `archive/`.
- **Competitive concern:** The user reported two other teams doing similar work. Their names, implementations, and exact overlap were not established; this is a reason to focus the product, not a verified competitor analysis.
- **Native app focus:** The team is developing the iPhone app in Swift/ARKit through Xcode. Research shifted toward meter/main-disconnect images, on-device readings, and address-linked public electrical records.
- **Explicit direction:** The user chose to stay with the existing repository and expand the setup experience end to end. Base OS and physical-design alternatives are not the active roadmap.
- **Latest research request:** Broadly collect Base's website/FAQ and relevant utility/city guidance, then use location, equipment identity, and Base configuration to guide better photos, possible siting changes, and review of equipment compatibility.
- **Repository save request:** Preserve this context and its links on a sensible branch structure. This documentation branch satisfies that request without modifying or merging application code.

## Product intent

The intended flow is:

```text
Confirmed property and utility
  -> Base program and equipment profile
  -> optional public property/permit context
  -> guided meter, disconnect, and panel capture
  -> typed observations plus user confirmation
  -> AR placement and obstacle evidence
  -> targeted follow-up photos or alternate placement
  -> reviewer-ready export
```

The goal is to reduce incomplete submissions and repeated photo requests. Conversion impact, review-time savings, and install-visit reductions remain hypotheses to validate rather than measured outcomes.

## Decisions to preserve

- **Use the current native app:** Extend the existing interfaces rather than replacing the repo with a web demo or an unrelated platform.
- **Utility and program first:** Do not route solely by “regulated/deregulated” or by city/ZIP.
- **Semantic equipment fields:** Meter device, socket/enclosure, main disconnect, panelboard, solar equipment, and transfer equipment are separate entities.
- **Historical evidence stays historical:** A permit can suggest an expected configuration but cannot establish the current installed condition.
- **Photos drive the next question:** Unreadable labels, missing context, multiple meters, unknown panel identity, and observed obstacles should trigger specific follow-up requests.
- **Safety-critical conclusions need review:** The app can flag possible issues but cannot approve an installation or require a meter/service replacement from imagery alone.
- **Hardware versions matter:** Core and legacy batteries must not inherit each other's physical dimensions or operational rules indiscriminately.
- **Missing or conflicting sources stay visible:** Do not turn a stale FAQ, code-edition conflict, or missing compatibility table into a silent default.
- **Public versus authorized data:** Public permit/GIS enrichment is separate from customer-authorized consumption and utility account data.

## Important corrections from the research

- **Austin topology:** Base's Austin Energy program is explicitly front-of-meter, but Austin Energy's general DER guide does not mandate that topology for every battery ([Base program](https://www.basepowercompany.com/austinenergy), [Austin Energy DER guide](https://austinenergy.com/-/media/Project/Websites/AustinEnergy/Contractors/AE_DG_Interconnection_Guide.pdf?rev=e5d375562efb4515bae892387b29e4d9&hash=A9043CEE17BBF4514E6503A1E786423E)).
- **Meter replacement:** CenterPoint documents remote programming of most existing bidirectional meters, so replacement cannot be the generic outcome of adding a battery ([CenterPoint guidance](https://www.centerpointenergy.com/en-us/Documents/DistributedGenerationDocs/SmallScale-DER-Project-Documentation.pdf)).
- **Gas equipment:** Base names a gas-meter distance; no universal battery-to-gas-water-heater distance was verified in the reviewed public material ([Base requirements](https://help.basepowercompany.com/en/articles/10280705)).
- **Closed windows:** Base prohibits placement in front of windows; a closed window is not a documented workaround ([Base requirements](https://help.basepowercompany.com/en/articles/10280705)).
- **Texas process:** SB 1252 changes municipal treatment of qualifying residential backup systems while preserving municipally owned utility authority ([TDLR guidance](https://www.tdlr.texas.gov/news/2025/08/14/sb-1252-changes-to-residential-energy-backup-system-regulations/)).

## Still unknown

No test service address, unit, or exact iPhone model was provided for the property-data investigation. No Base-approved meter/socket compatibility matrix, current Core installation manual, or complete set of program-specific one-lines was supplied.

The source-backed documents retain their own research dates and repository baselines. In particular, older claims about code that was missing may have been overtaken by the team's ongoing commits and should not be treated as a fresh audit of `main`.
