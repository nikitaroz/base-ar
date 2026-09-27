# ARKit LiDAR mesh coverage and quality metrics

Scope: signals an on-device app can compute from ARKit alone (`ARMeshAnchor` / `ARMeshGeometry`, scene depth and `ARConfidenceLevel`, `trackingState`, `worldMappingStatus`, `rawFeaturePoints`, camera pose) to decide whether a small outdoor site (ground, one wall, meter area, a few meters of working space) is complete enough for foot-scale clearances. Inch-level means about 2.5 cm. Millimeter metrology is out of scope. Sources were read on 26 September 2026. Apple’s documentation JSON for these APIs still describes the same contracts (legal notice copyright 2026). Numeric raw values that Apple states only by enum order are marked as such.

Two products are easy to conflate. **Scene depth** is a per-frame depth image from the LiDAR scanner. **Scene reconstruction** is a fused triangle mesh delivered as updating `ARMeshAnchor`s. Studies that export “iPhone LiDAR” through an app may be either, and at least one widely used app samples points from ARKit’s mesh rather than exporting the raw returns.

---

## How do people quantify mesh completeness and accuracy from ARMeshAnchor?

### Takeaway

ARKit exposes a triangle mesh with per-vertex positions and normals and an optional per-face class, and it updates that mesh continuously, but it does not publish density, hole, completeness, or accuracy scores. Completeness has to be computed from the buffers. Published centimeter errors mostly describe app-exported clouds compared with a laser or photogrammetric reference, and several of those clouds are mesh-sampled rather than raw LiDAR.

### Cited Findings

- Enabling `sceneReconstruction` makes ARKit add a polygonal mesh that estimates the physical environment, delivered as `ARMeshAnchor` objects. Support must be checked first. With plane detection also on, ARKit smooths the mesh where it detects a plane, because the LiDAR mesh on a real surface can be slightly uneven. If people occlusion is on, ARKit removes mesh that overlaps people (`personSegmentation` or `personSegmentationWithDepth`). — [sceneReconstruction](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction)
- `supportsSceneReconstruction` is true only on a device with a LiDAR scanner. Apple’s example is the fourth-generation iPad Pro. — [supportsSceneReconstruction(_:)](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:))
- ARKit subdivides the surroundings into mesh anchors. Anchors constantly update as the model is refined. A mesh will eventually reflect a physical change such as a chair being pulled out, but that update is not meant to track the change in real time. — [ARMeshAnchor](https://developer.apple.com/documentation/arkit/armeshanchor)
- Each vertex is a connection point (`SIMD3<Float>`, three components). Every three indices form one triangle (a face). Faces carry an outside direction via the normals buffer. The SDK header states normals are per vertex (`ARMeshGeometry.normals`). Classification, when present, is one value per face. — [ARMeshGeometry](https://developer.apple.com/documentation/arkit/armeshgeometry); [vertices](https://developer.apple.com/documentation/arkit/armeshgeometry/vertices); [faces](https://developer.apple.com/documentation/arkit/armeshgeometry/faces); [normals](https://developer.apple.com/documentation/arkit/armeshgeometry/normals)
- If a face cannot be classified, the value is `0`, the raw value for `none`. The default at each index is `0`. Classes are `none`, `wall`, `floor`, `ceiling`, `table`, `seat`, `window`, and `door`. `wall` means a real-world wall. `floor` means a real-world floor. `none` means a face ARKit cannot classify. There is no ground, terrain, or equipment class. — [classification](https://developer.apple.com/documentation/arkit/armeshgeometry/classification); [ARMeshClassification](https://developer.apple.com/documentation/arkit/armeshclassification); [wall](https://developer.apple.com/documentation/arkit/armeshclassification/wall); [floor](https://developer.apple.com/documentation/arkit/armeshclassification/floor); [none](https://developer.apple.com/documentation/arkit/armeshclassification/none)
- Reconstruction modes are `mesh` and `meshWithClassification` (the latter includes the former). The header names them `ARSceneReconstructionMesh` and `ARSceneReconstructionMeshWithClassification` (iOS 13.4). — [ARConfiguration.h in the iOS SDK](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction)
- Luetzenburg, Kroon, and Bjørk (Scientific Reports, 2021) scanned with an iPhone 12 Pro and iPad Pro. They report the sensor’s maximum range as up to 5 m. Potential point density was 7,225 points/m² at 25 cm and 150 points/m² at 250 cm. The emitter is an 8×8 array diffracted into 3×3 grids, 576 points. No iPad-versus-iPhone difference in emitted points, density, or focal length. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Same paper, small objects measured with a stick: absolute accuracy of ±1 cm for objects with side length greater than 10 cm (abstract). The body says scanned objects were measured with an absolute accuracy of one centimeter and a precision error of one centimeter, that precision decreases under 10 cm side length, and that the limit of detection is around 5 cm. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Same paper, a coastal cliff about 130 × 15 × 10 m, 3d Scanner App versus a UAV photogrammetry reference, M3C2 after fine registration (registration RMS 0.052 m): mean distance −0.11 m, standard deviation 0.68, RMS 0.69. For 80% of points the distance was under 15 cm, and for 92% under 30 cm. Differences were smaller on the horizontal beach than on the sloped face, smaller on plane areas than on rough surfaces, and larger where the laser-to-target distance increased. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- The abstract of that paper also says cliff models of that size were compiled with an absolute accuracy of ±10 cm. That summary is not the same number as the M3C2 RMS of 0.69 m reported in the results. Both statements are in the paper. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Same paper, six scans of a smaller cliff patch (about 10 × 15 × 10 m): mean M3C2 between one scan and the other five was 0.02 m. The distance to the reference LiDAR model was smaller than 5 cm for 92% of points (they print “std. dev. = 4.50” next to that percentage). — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Same paper, methods: in 3d Scanner App, exported points are sampled from the mesh surface and are not the raw LiDAR returns. SiteScape and EveryPoint’s “ARKit LiDAR Points” mode can record the direct cloud but were limited to 12 million points. 3d Scanner App 2.5 in “ARKit LiDAR Mesh” mode builds a mesh of the close surroundings (under 5 m). The discussion says Apple’s internal mesh triangulation partly overcomes the raw-point count limit “at the cost of the 3D models accuracy.” — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Treccani, Adami, and Fregonese (ISPRS Archives, 2024) compared five iOS LiDAR apps with a terrestrial laser scanner on a university corridor and a narrow urban street. They report errors on the order of 10 cm in some areas and on the order of 1 cm in others. Results depended on how each app handled the raw data. Apps that used loop closure to reduce trajectory drift did better on these medium-sized indoor and outdoor sites. The full per-app tables were not in the HTML landing text retrieved here; the figures above are the paper’s own abstract. — [doi:10.5194/isprs-archives-xlviii-2-w8-2024-431-2024](https://doi.org/10.5194/isprs-archives-xlviii-2-w8-2024-431-2024)
- Costantino and colleagues (Applied System Innovation, 2022), from the abstract: when scanning problems were absent, accuracies from smartphone depth sensors (including iPhone 12 Pro and iPad Pro 2021) were about 1–3 cm. They also report surface splitting, loss of planarity, and inertial-navigation drift. The PDF body was not retrieved (MDPI returned 403), so the 1–3 cm figure is the authors’ abstract conclusion, not a table copied from the results section. — [doi:10.3390/asi5040063](https://doi.org/10.3390/asi5040063)
- Apple’s ARKitScenes paper (Baruch et al., arXiv:2111.08897, 2022, Apple) captured 2020 iPad Pro data with the ARKit SDK, including world tracking, scene reconstruction, and the LiDAR depth map, and registered it to a Faro Focus S70. Table 1 lists ARKit depth resolution as 256×192, against laser-scanner frames of 1920×1440. The scenes are indoor homes, not exteriors. — [arXiv:2111.08897](https://arxiv.org/abs/2111.08897)
- In that paper’s depth-upsampling protocol, frames were dropped when RMSE between the low-resolution ARKit depth and a downscaled laser depth exceeded 7 cm, or when more than 20% of pixels differed by more than 5 cm. Those cuts remove registration failures. They are not a stated accuracy of the mesh. Validation frames with specular or transparent “depth aggressors” were also removed by hand. — [arXiv:2111.08897](https://arxiv.org/abs/2111.08897)

### Inferences

- Vertex density and mean triangle area in a region of interest are computable directly: transform `vertices` by the anchor’s transform, keep faces whose centroid lies in the region, then use vertex count, face count, and triangle area. Apple does not define a “dense” cutoff.
- Hole detection is computable as boundary edges: an edge owned by only one triangle, then the length of boundary loops inside the region. That is ordinary mesh topology. It is not an ARKit API, and no cited paper gives an `ARMeshAnchor` hole-size threshold.
- Classification coverage is the fraction of face area labeled `wall`, `floor`, or `none` inside the region. For this survey, `wall` is evidence of a wall surface. `floor` is only evidence of whatever ARKit calls a floor. A meter, a gas meter, and much outdoor clutter should be expected to stay `none`, because those classes do not exist.
- Normal consistency (variance of vertex normals, or angle between neighboring normals) is computable from `normals`. On a surface where plane detection has smoothed the mesh, consistency is partly ARKit’s plane fit, not an independent measurement of flatness. Apple says the unsmoothed LiDAR mesh can be slightly uneven and that planes are used to smooth it.
- Anchor stability is computable because anchors keep an identity while `geometry` is replaced. Compare vertex positions for the same anchor across updates. Apple’s chair example means a moving object will not show up immediately, so a short-term “stable” mesh can still be stale.
- Studies that quote ~1 cm or ~1–3 cm are the right order of magnitude for a small, nearby, mostly rigid scene. The 130 m cliff (RMS 0.69 m versus photogrammetry) is a different problem: long trajectory, range limits, and rough terrain. A few meters of working space is closer to the small-object and small-patch experiments than to that cliff.
- Because 3d Scanner App’s export is sampled from the mesh, Luetzenburg’s cliff and patch numbers are evidence about an ARKit-mesh product, not about raw flash returns. The authors separately say meshing spends accuracy to cover more area. Direct-point apps can look different. Treat “iPhone LiDAR accuracy” papers as mesh-accurate only when the method says so.

### Gaps

- No Apple document found that states `ARMeshAnchor` vertex spacing, triangle edge length, update rate in hertz, or a completeness percentage.
- No peer-reviewed hole-detection or voxel-coverage threshold specific to `ARMeshAnchor` was retrieved.
- Whether outdoor concrete or soil is labeled `floor` was not measured in the sources opened here.
- Vogt et al. (Technologies, 2021, doi:10.3390/technologies9020025) compare iPad Pro LiDAR and TrueDepth with an industrial scanner on Lego bricks and conclude the industrial scanner is more accurate while the phone “may already be sufficient, depending on the application.” The PDF was blocked, so their tolerance numbers are not in these notes.
- Teppati Losè et al. (Remote Sensing, 2022, doi:10.3390/rs14174157) tested SiteScape, EveryPoint, and 3D Scanner App for cultural-heritage accuracy. Only the abstract was retrieved; it does not contain the centimeter results.
- The 2026 EGU abstract “Comparative accuracy analysis of iPhone LiDAR applications” (doi:10.5194/egusphere-egu26-2752) was only a truncated Crossref abstract, with no results copied.

---

## How should ARConfidenceLevel and scene-depth confidence maps be used?

### Takeaway

Confidence is a per-pixel label on the current depth image, stored as the raw value of `low`, `medium`, or `high`. Apple defines those words qualitatively and says to drop lower-accuracy depths when an algorithm needs it. Apple does not attach a centimeter error to each level. The mesh itself has no confidence channel.

### Cited Findings

- `ARDepthData` holds LiDAR depth. Each `depthMap` pixel is the distance, in meters, from the plane of the camera to a region of the captured image. The header calls the same buffer per-pixel depth in meters. — [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata); [depthMap](https://developer.apple.com/documentation/arkit/ardepthdata/depthmap)
- `confidenceMap` measures accuracy of that depth map by storing an `ARConfidenceLevel` raw value for every depth component. It is useful for filtering out lower-accuracy depths. Natural light makes ARKit less confident on surfaces that are highly reflective or that absorb a lot of light. — [confidenceMap](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap)
- The three levels, in documentation order: `low` is depth-value accuracy the framework is less confident about; `medium` is moderately confident; `high` is fairly confident. The type is `Comparable` and `RawRepresentable`. — [ARConfidenceLevel](https://developer.apple.com/documentation/arkit/arconfidencelevel); [low](https://developer.apple.com/documentation/arkit/arconfidencelevel/low); [medium](https://developer.apple.com/documentation/arkit/arconfidencelevel/medium); [high](https://developer.apple.com/documentation/arkit/arconfidencelevel/high)
- The iOS SDK header `ARDepthData.h` (copyright 2020, still the public header in the iOS 27 SDK on this machine) declares `ARConfidenceLevelLow`, `ARConfidenceLevelMedium`, `ARConfidenceLevelHigh` as an `NS_ENUM` with no explicit integers. In that form the raw values are 0, 1, and 2 in declaration order. Apple’s confidence-map discussion says the buffer stores those raw values, and gives `kCVPixelFormatType_OneComponent8` (`L008`) as an example format to be read at runtime, with Metal `r8Uint` as the matching texture. The format is an example, not a promise; the docs say to query the pixel format at runtime. — [confidenceMap](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap); [ARConfidenceLevel](https://developer.apple.com/documentation/arkit/arconfidencelevel)
- `sceneDepth` is nil unless the `sceneDepth` frame semantic is enabled, and the device and configuration must support it (`supportsFrameSemantics`). `smoothedSceneDepth` is the same depth, averaged over time to reduce the frame-to-frame change. Both include confidence. — [sceneDepth](https://developer.apple.com/documentation/arkit/arframe/scenedepth); [smoothedSceneDepth](https://developer.apple.com/documentation/arkit/arframe/smoothedscenedepth)
- The frame-semantic comments: scene depth associates depth with each captured image; smoothed scene depth is temporally smoothed (iOS 14). — [ARFrame.sceneDepth](https://developer.apple.com/documentation/arkit/arframe/scenedepth)
- ARKitScenes Table 1 records that ARKit depth, captured through the official SDK on a 2020 iPad Pro, was 256×192. That is a reported capture resolution, not an API constant. — [arXiv:2111.08897](https://arxiv.org/abs/2111.08897)
- Specular and transparent surfaces are treated in that paper as depth aggressors that are hard to reject automatically. Apple’s confidence text separately names highly reflective surfaces and high absorption as low-confidence cases. — [arXiv:2111.08897](https://arxiv.org/abs/2111.08897); [confidenceMap](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap)

### Inferences

- Use the map as a mask, not as a variance. A practical reading of Apple’s “filter lower-accuracy” sentence is: ignore `low` (raw 0) when accepting a depth sample; treat `medium` as usable but not the best; prefer `high` when choosing among samples of the same surface. That ranking follows `Comparable` and the case order. It is not a calibrated probability.
- Because depth is distance from the camera plane, it is a z value in camera space, not the slant range along the ray. At the edge of a wide view the two differ. For a meter-scale site the difference is a few percent of range toward the image edge; it matters if code compares depth to a Euclidean mesh distance without projecting into the same z.
- Scene depth is whatever the camera sees this frame. It does not fill in the back of the wall or a surface the user has not looked at. Confidence coverage of a battery pad requires projecting the region into recent views, which means using the camera transform and intrinsics, not only the latest frame.
- `smoothedSceneDepth` is the better stream for a stable distance reading. `sceneDepth` is the better stream for noticing that the surface just changed. Smoothing lags, which matches the mesh anchor’s non-real-time behavior.
- The fused mesh does not inherit this map. A green mesh triangle can sit where the last depth sample was `low`. A coverage test that cares about measurement quality should require both a mesh face and a recent medium-or-high depth sample that agrees with that face.
- The closest published “disagreement” numbers are ARKitScenes’ indoor filters (more than 5 cm on more than 20% of pixels, or RMSE over 7 cm versus a laser). Using 5 cm as an on-device depth-versus-mesh agreement band is a heuristic borrowed from that filter, not an Apple threshold, and it was measured indoors against a Faro scan after registration.

### Gaps

- Apple does not publish millimeter or centimeter error bars for `low`, `medium`, or `high`.
- No source found that states the confidence pixel values in prose as “0, 1, 2.” That mapping is the unannotated `NS_ENUM` order plus the documented “raw value” buffer. An app should still read the pixel format at runtime.
- No source found that guarantees 256×192 on every current iPhone video format. Read `CVPixelBuffer` width and height at runtime.
- No outdoor confidence-versus-lux study was retrieved.

---

## How do trackingState, world-mapping status, and feature-point counts relate to whether the cloud is trustworthy?

### Takeaway

`trackingState` is a gate on the world coordinate system the mesh lives in. `worldMappingStatus` says whether the visible area is mapped well enough to relocalize, not whether distances are accurate to an inch. Feature-point count is explicitly unstable and is a weak quality signal; the supported feature signal is the tracking reason `insufficientFeatures`.

### Cited Findings

- `trackingState` is not available, limited, or normal. Limited reasons are initializing, excessive motion, insufficient features, and relocalizing. — [trackingState](https://developer.apple.com/documentation/arkit/arcamera/trackingstate-swift.enum). Wording is the SDK comments in `ARTrackingStatusTypes.h`, which the documentation page is generated from.
- `worldMappingStatus` describes mapping for the area visible in the frame, and whether more scanning should be done before saving a world map. `notAvailable`: mapping is not available. `limited`: mapping exists but has limited features, and the map is not recommended for relocalization at the current position. `extending`: the map is being extended; previously visited areas can relocalize, and the current space is still updating. `mapped`: the visible area is adequately mapped and can relocalize the current position. — [worldMappingStatus](https://developer.apple.com/documentation/arkit/arframe/worldmappingstatus). Same source pattern: comments in `ARFrame.h`.
- `rawFeaturePoints` are notable image features whose 3D positions are extrapolated as part of world tracking. Together they loosely correlate with object contours. Apple does not guarantee that the number or arrangement stays stable across software releases or even across subsequent frames. The cloud can help debug placement of virtual objects. Feature points require a world-tracking session. — [rawFeaturePoints](https://developer.apple.com/documentation/arkit/arframe/rawfeaturepoints)
- `ARPointCloud` also exposes a `uint64` identifier per point (SDK header `ARPointCloud.h`), so a point that keeps its identifier can be followed. That does not override the stability disclaimer above. — [rawFeaturePoints](https://developer.apple.com/documentation/arkit/arframe/rawfeaturepoints)
- Mesh anchors and scene depth are expressed in the tracked world. Plane anchors are a separate stream: if `planeDetection` is set, planes are added as `ARPlaneAnchor` objects and keep updating; merged planes drop the newer anchor. Plane detection is not the same flag as scene reconstruction. — header comments summarized at [ARWorldTrackingConfiguration](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration); reconstruction’s LiDAR requirement is [supportsSceneReconstruction(_:)](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:))
- Medium-area app scans lose accuracy to trajectory drift unless the app closes the loop (Treccani et al., 2024). That is a tracking-integration error, not a single-pixel depth error. — [doi:10.5194/isprs-archives-xlviii-2-w8-2024-431-2024](https://doi.org/10.5194/isprs-archives-xlviii-2-w8-2024-431-2024)

### Inferences

- If `trackingState` is not `.normal`, distances between mesh points are not trustworthy, even if the triangles look dense. Excessive motion and insufficient features mean the camera pose is the weak link. Initializing and relocalizing mean the world origin may still jump.
- `.normal` is necessary and not sufficient. A normally tracked session can still have a hole in the mesh, a low-confidence depth image, or a surface past the LiDAR range.
- `worldMappingStatus == .mapped` means “this view is good enough to relocalize later.” It does not mean the mesh matches a tape measure. `.limited` is a reason to keep scanning if the user will leave and come back. For a single-session survey that never relocalizes, mapping status is a weak proxy for feature richness in the current view, secondary to `trackingState`.
- Do not threshold `rawFeaturePoints.count`. Apple says the count is not stable frame to frame. A collapse into `insufficientFeatures` is the supported binary signal. Persistent identifiers can show whether the same corners are still tracked, which is a better debug signal than the integer count, and still not a centimeter accuracy estimate.
- Drift on a walked baseline (meter to battery, on the order of 20 ft) will not show up as `trackingState != .normal` if motion stays smooth. Treccani’s loop-closure result is the relevant warning: medium-area error is path-dependent. A coverage metric should record whether the region was seen from overlapping views, not only whether tracking stayed normal.

### Gaps

- No Apple formula ties feature-point count, mapping status, or tracking state to mesh error in centimeters.
- No retrieved study measures `worldMappingStatus` against tape-measured outdoor distances.

---

## What spatial structures are practical on device?

### Takeaway

The practical structures are a small occupancy grid around the battery pad, a boundary-edge hole test on the mesh inside that box, a count of camera views that saw each cell with medium-or-high confidence, and a depth-versus-mesh residual along those views. All of the inputs exist on a LiDAR phone. None of them is an ARKit query. Without LiDAR the mesh, the depth image, and the confidence map are absent, and the remaining structure is plane anchors plus tracking state.

### Cited Findings

- Inputs that exist on a LiDAR device: mesh vertices, faces, per-vertex normals, per-face classification, anchor transforms that update in place; per-frame `depthMap` in meters from the camera plane; per-pixel confidence; camera pose and parameters on `ARFrame.camera`; `trackingState`; `worldMappingStatus`. — [ARMeshGeometry](https://developer.apple.com/documentation/arkit/armeshgeometry); [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata); [sceneDepth](https://developer.apple.com/documentation/arkit/arframe/scenedepth); [ARFrame](https://developer.apple.com/documentation/arkit/arframe)
- Plane detection remains a separate configuration. Detected planes become `ARPlaneAnchor`s. Scene reconstruction is the API that requires LiDAR. — [supportsSceneReconstruction(_:)](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:)); plane-detection property comments are on [ARWorldTrackingConfiguration](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration)
- Raw sensor density falls from 7,225 points/m² at 25 cm to 150 points/m² at 250 cm, and the stated maximum range is 5 m. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9); range also in Apple’s March 2020 iPad Pro release: the LiDAR scanner measures distance to surrounding objects up to 5 meters away and works indoors and outdoors. — [Apple Newsroom, 18 March 2020](https://www.apple.com/newsroom/2020/03/apple-unveils-new-ipad-pro-with-lidar-scanner-and-trackpad-support-in-ipados/)
- People occlusion deletes mesh over people. Plane detection flattens the mesh on detected planes. — [sceneReconstruction](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction)

### Inferences

- A voxel (or surfel) grid is practical because the region is small: a pad plus a few meters of working space, not a whole lot. Transform mesh vertices into world space once per anchor update and bin them. Surfel-style storage (position, normal, class, last-seen time) matches the buffers ARKit already provides and avoids inventing a second reconstruction.
- Cell size is a heuristic. Deriving a spacing from Luetzenburg’s densities as `1/sqrt(density)`, which assumes a uniform spread, gives about 1.2 cm at 25 cm range (7,225 points/m²) and about 8.2 cm at 250 cm (150 points/m²). Those figures are raw-return densities, not measured `ARMeshAnchor` edge lengths. A grid finer than that far-range spacing will show empty cells even when the sensor is doing what that study measured. A 5–10 cm cell is in the same range as the 5 cm object-detection limit and the 5 cm ARKitScenes pixel-difference filter. Label any chosen cell size as a heuristic.
- View coverage: for each occupied cell, count frames where the cell projects inside the image, the camera is within a few meters, `trackingState` is normal, and the confidence sample is medium or high. One glancing view is weaker than several overlapping views. This is the on-device analogue of the loop-closure finding, without building a pose graph.
- Distance-to-surface: sample `depthMap` at that projection and compare with the mesh point’s camera-plane z, not with Euclidean range, unless the ray is converted. A residual larger than the 5 cm band ARKitScenes used as a “pixels differ” cutoff is a reasonable “present but disagreeing” flag. Heuristic, indoor-laser origin, stated above.
- Occupancy answers “was this volume given a surface.” It does not by itself answer “is the surface the true wall.” Pair occupancy with classification (`wall` / `floor` / `none`), normal agreement with an expected vertical or horizontal, and the depth residual.
- Non-LiDAR phones: do not invent mesh metrics. `supportsSceneReconstruction` is false, so there are no mesh anchors and no face classes. Scene depth and confidence stay unavailable unless `supportsFrameSemantics` says otherwise, which for these semantics means a LiDAR device. What remains is plane anchors (extent, alignment, transform), hit-tests or raycasts against those planes, `trackingState`, mapping status, and feature points. Placement can proceed from planes. A graded “mesh is dense enough” answer should be reported as unavailable, not as a failing mesh.

### Gaps

- No cited implementation note or paper gives a tested voxel size for `ARMeshAnchor` coverage on device.
- `ARMeshAnchor` vertex spacing was not found as a measured number, so the 1.2 cm and 8.2 cm figures must not be described as mesh resolution. They are converted raw-cloud densities.
- Plane-anchor extent accuracy without LiDAR was not part of the studies retrieved here.

---

## What thresholds separate a thin or missing patch, a present but uncertain surface, and a mesh dense enough for inch-level site measurements?

### Takeaway

Apple publishes no such thresholds. The measurement studies support a graded reading for this survey: missing if the local surface was never reconstructed or tracking is not normal; uncertain if the only evidence is a thin or single-view mesh, low confidence, or a baseline longer than the 5 m LiDAR range; locally usable for foot-scale checks when the surface sits inside a few meters, has been seen more than once, and depth confidence is not low. Inch-level (about 2.5 cm) is at the optimistic end of close-range results (about 1 cm on small objects, about 1–3 cm when scans behave, about 5 cm repeatability on a small outdoor patch) and is not what the large-scene errors show.

### Cited Findings

- Close range, object dimensions, iPhone 12 Pro LiDAR via scanning apps: ±1 cm absolute accuracy for side lengths above 10 cm; precision worsens below 10 cm; detection limit around 5 cm. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Repeatability on a ~10 × 15 × 10 m outdoor rock patch: mean inter-scan M3C2 0.02 m, and 92% of points within 5 cm of the reference LiDAR scan. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Same sensor family against photogrammetry on a 130 m cliff: RMS 0.69 m, 80% of points within 15 cm, 92% within 30 cm. Abstract states ±10 cm for that product. The two summaries disagree; the RMS is the statistic with a stated method (M3C2). — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Medium indoor corridor and outdoor street versus a terrestrial laser scanner: on the order of 1 cm in some areas and 10 cm in others, with trajectory drift as the main app-level limiter. — [doi:10.5194/isprs-archives-xlviii-2-w8-2024-431-2024](https://doi.org/10.5194/isprs-archives-xlviii-2-w8-2024-431-2024)
- Abstract claim of about 1–3 cm when smartphone scans had no scanning problems, with drift and loss of planarity called out as failure modes. Body tables not retrieved. — [doi:10.3390/asi5040063](https://doi.org/10.3390/asi5040063)
- Indoor ARKit depth versus a Faro scanner, after Apple’s authors discarded bad registrations: the discard rules were RMSE greater than 7 cm, or more than 20% of pixels off by more than 5 cm. Specular and transparent surfaces were removed from the reported validation. — [arXiv:2111.08897](https://arxiv.org/abs/2111.08897)
- Stated LiDAR range up to 5 m (Apple newsroom and Luetzenburg). Mesh mode in 3d Scanner App is described as the surroundings under 5 m. Density at 2.5 m is already down to 150 points/m². — [Apple Newsroom, 18 March 2020](https://www.apple.com/newsroom/2020/03/apple-unveils-new-ipad-pro-with-lidar-scanner-and-trackpad-support-in-ipados/); [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Meshing “at the cost of” accuracy relative to staying on raw points. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Confidence levels have no centimeter definition. Tracking must be normal for the coordinate frame to be the one ARKit considers tracked. See the previous sections.

### Inferences

These bands are a synthesis for foot-scale site checks (1 ft wall clearance, 3 ft gas clearance, a 3 ft footprint, a 20 ft meter distance). They are not Apple pass/fail values. The 20 ft check is about 6.1 m, which is beyond a single 5 m depth sample, so it is called out separately.

**Thin or missing**

- No triangles in the region, or an open boundary loop whose span is a large fraction of the pad or the wall patch the user needs. “Large” is not published; a hole on the order of the footprint (3 ft) is obviously missing, and a hole near the 5 cm detection limit may be the sensor’s floor rather than a real gap.
- The surface was never inside a camera view closer than the 5 m specification.
- `trackingState` is not normal while the only samples were taken.
- Non-LiDAR device: mesh completeness is unavailable. Do not grade it as thin. Grade it as not measurable from a mesh.

**Present but uncertain**

- Triangles exist, but only one view, or confidence on the rays that hit the surface is mostly `low`, or successive anchor updates still move the surface by more than the tolerance of the check.
- Depth and mesh disagree by more than about 5 cm (heuristic taken from ARKitScenes’ per-pixel filter, not a field calibration).
- Classification is `none` on a surface the survey needs to call wall or ground. The surface can still be geometrically usable; the class is just not evidence.
- Any distance that depends on walking a baseline near or beyond 5 m (the 20 ft meter distance). Treccani’s 10 cm-class regions and the cliff RMS say this is where drift, not local LiDAR noise, dominates. Loop-like overlap of views reduces that, but ARKit does not report a drift estimate.

**Dense enough for local, inch-scale site measurements**

- The wall, the ground under the pad, and nearby objects used for a clearance sit well inside 5 m, ideally in the range where the cited small-object work saw ±1 cm (objects larger than about 10 cm) or the small-patch repeatability of a few centimeters (92% of points within 5 cm between LiDAR scans).
- More than one normal-tracking view, with confidence at least medium on the samples used for the number.
- The check itself is a foot or a few feet, so a 1–5 cm error still answers “about 1 ft” or “about 3 ft.” It does not answer a millimeter call, and it does not by itself certify the 20 ft meter distance.
- Calling the preview “inch-accurate” across the whole cloud overclaims the literature. The defensible grade is: local clearances can be inch-class when the conditions above hold; the long meter baseline should stay at “about a tenth of a meter unless the path was reobserved.”

### Gaps

- No study retrieved measures `ARMeshAnchor` edge lengths, so “thin mesh” cannot be quoted as a vertex spacing from Apple or from a paper.
- No outdoor tape-measure study of ARKit scene reconstruction for a house wall and a meter, at 1–6 m, was found. The numbers above are cliffs, streets, rooms, boxes, and indoor laser comparisons.
- The abstract-versus-RMS conflict in Luetzenburg (±10 cm versus 0.69 m RMS) is unresolved here. Prefer the M3C2 figures when stating large-scene error.

---

## Outdoor-specific degradation: range, sunlight, specular or dark surfaces, moving objects, mesh flicker

### Takeaway

The published hard limit is about 5 m, with density and error both worse as range grows. Reflective and strongly absorbing surfaces are the cases Apple links to low depth confidence; specular and transparent surfaces are the cases an Apple dataset paper calls depth aggressors. Moving objects update late, and people can be cut out of the mesh if occlusion is on. Sunlight and mesh flicker do not have a published numeric error model in the sources opened here.

### Cited Findings

- Range: the LiDAR scanner measures objects up to 5 meters away, indoors and outdoors (Apple, 18 March 2020). Luetzenburg independently states a maximum range up to 5 m and describes ARKit LiDAR mesh mode as the close surroundings under 5 m. Potential density drops from 7,225 points/m² at 25 cm to 150 points/m² at 250 cm. M3C2 differences were higher where sensor-to-target distance increased. Their density series stopped at 250 cm, not at 5 m. — [Apple Newsroom, 18 March 2020](https://www.apple.com/newsroom/2020/03/apple-unveils-new-ipad-pro-with-lidar-scanner-and-trackpad-support-in-ipados/); [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Surface type: rough surfaces showed higher M3C2 differences than plane areas; the sloped cliff face was worse than the horizontal beach. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Reflective and dark: natural light makes confidence lower for highly reflective surfaces and for surfaces with high light absorption. — [confidenceMap](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap)
- Specular and transparent: ARKitScenes removed those frames from validation because they are depth aggressors that are hard to detect automatically. The dataset itself is indoor. — [arXiv:2111.08897](https://arxiv.org/abs/2111.08897)
- Outdoor medium-area surveys still show about 1 cm in some regions and about 10 cm in others versus a terrestrial laser scanner, largely from how the app integrates the trajectory. — [doi:10.5194/isprs-archives-xlviii-2-w8-2024-431-2024](https://doi.org/10.5194/isprs-archives-xlviii-2-w8-2024-431-2024)
- Moving objects: mesh anchors do update for a real change, and Apple’s example is a person pulling out a chair, but the change is not intended to appear in real time. If people occlusion is enabled, mesh overlapping a person is removed. — [ARMeshAnchor](https://developer.apple.com/documentation/arkit/armeshanchor); [sceneReconstruction](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction)
- Flicker, as a behavior Apple does document: anchors constantly update their geometry as understanding changes. There is no documented amplitude or rate. — [ARMeshAnchor](https://developer.apple.com/documentation/arkit/armeshanchor)
- Plane smoothing can hide outdoor unevenness on any surface ARKit accepts as a plane, because the framework deliberately flattens the LiDAR mesh there. — [sceneReconstruction](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction)
- Sunlight is mentioned by Luetzenburg as an acquisition problem for the photogrammetry photos (overlap, viewing angle, sunlight exposure), not as a measured LiDAR error versus lux. — [doi:10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)

### Inferences

- Treat 5 m as a hard “do not trust a single depth sample” limit, and treat the outer part of that range (around 2.5 m and beyond) as already density-limited: about 8 cm mean raw spacing if the 150 points/m² figure is spread uniformly. A wall clearance measured with the phone standing close to the wall is in the favorable regime. A 20 ft meter-to-pad distance is not.
- Glass on an electrical meter, glossy paint, wet surfaces, and very dark siding should be expected to produce `low` confidence and holes or flying triangles. That expectation is the combination of Apple’s reflective/absorption note and ARKitScenes’ specular/transparent note. It is not a field trial of meters.
- A person walking through the meter area can either lag in the mesh (chair example) or punch a hole (if person segmentation is on). For a survey, freeze the measurement when the relevant cells are stable across updates and not labeled as a transient hole. Stability threshold: heuristic.
- Mesh flicker is the visible result of constant anchor updates plus pose noise. A practical filter is temporal: accept a surface only after its vertices move less than the check tolerance for a short interval while tracking stays normal. Apple does not specify the interval.
- Outdoor ground may fail a `floor` coverage test and still be a usable plane-smoothed mesh. Prefer geometric evidence (horizontal normal, occupied voxels, depth agreement) over the class label for the ground, and use `wall` as supporting evidence for the house wall rather than as the only evidence.

### Gaps

- No controlled study of direct sun versus ARKit mesh or confidence was retrieved. Apple’s sentence about natural light is qualitative and tied to reflective and absorbing materials.
- No retrieved number for mesh flicker amplitude, update hertz, or how long a moving person remains in the mesh.
- No retrieved outdoor test of mesh classification on siding, concrete, or a glass meter cover.
- Density between 2.5 m and the 5 m specification was not in Luetzenburg’s reported series.
