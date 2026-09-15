# Road boundary audit precision

The eight reported Harbor road edge failures were false positives in the audit,
not gaps or internal seams introduced by the traffic signals. The original map
produced the same eight messages with all signal objects removed.

Three checks misclassified points near distant polygon vertices through the
native float32 point-in-polygon predicate. Five checks used a fixed 0.12-pixel
normal offset that crossed the narrow void and entered a second road surface.
Scalar ray casting at smaller offsets confirmed that each reported segment is
an actual union boundary. Diagnostic inputs and probe results are retained in
`D:/geteco/artifacts/road-edge-seams.var` and `probe-seams-precise.log`.

The audit now classifies points using scalar float64 differences and chooses
normal offsets from the precision of the stored float32 coordinates. It checks
three positions per segment, rather than only the midpoint. Road geometry,
contours, access masks, and runtime rendering are unchanged.

`test_road_boundary_audit_precision.gd` includes positive and negative controls
at the origin and at distant positive/negative coordinates. It accepts real
boundaries next to a 0.06-pixel gap and short 0.02-pixel segments, while rejecting
internal seams (including one only 0.01 pixels inside a surface), detached
contours, and degenerate edges. These controls ensure the fix does not merely
silence legitimate boundary errors.

Validation: the full Harbor audit now reports `failures=0`, checking 10,179
boundary segments, 48 closed contours, and 150 access masks. All 18 precision
regression checks pass. Results are in `D:/geteco/artifacts/road-boundary-final.log`
and `D:/geteco/artifacts/road-boundary-precision.log`.
