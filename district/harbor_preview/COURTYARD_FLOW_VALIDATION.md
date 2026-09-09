# Harbor local-street circulation — 2026-09-05

## Reproduced causes and minimal correction

1. `TrafficVehicle` permits a 14px movement step after a render hitch, while
   `JunctionTrafficController` rejects connector entry overshoot above 12px.
   A real Courtyard lane fixture, starting 0.25px before either authored turn,
   advanced 13.884px and lost the plan despite owning the reservation. Both
   turns failed before the fix. The controller now caps the motion contract at
   the authored connector entry before movement; ordinary reserved handoff does
   the turn. No increased tolerance, teleport or route replacement.
2. The full life test then exposed a close-block reservation lock on Exchange:
   a car near (5580,1181) held junction (5550,1000) while waiting at the next
   connector. Release previously required a full vehicle length beyond the
   conflict radius, retaining a junction already cleared by the car's rear.
   Release now uses the larger of half the supplied vehicle length and the
   actual rectangle's farthest transformed corner, plus the unchanged stop-line
   margin. This includes rotation, lateral corners, collision offset and scale.
   The regression verifies retaining the reservation 1px before clearance and
   releasing 1px after it, not early release based only on the vehicle centre.

The existing Harbor queue-head arbitration remains unchanged.

## Files changed in this subtask

- `district/roads/traffic/JunctionTrafficController.gd`: motion entry clamp and
  conservative body-envelope reservation release only. Preserved earlier edits.
- `tests/test_harbor_connector_hitch.gd`: new deterministic production-lane
  overshoot/clearance regression; initial placement is a fixture, the turn runs
  production `advance_on_lane()`.
- This report. No commits or changes to missions, terminal, prototypes or art.

## Results (sequential headless Compatibility runs)

All six final tests exit 0:

- `test_harbor_connector_hitch.gd`: both Courtyard turns enter their connectors;
  0.252px entry displacement; rotated rectangle retained/released at boundaries.
- `test_harbor_life.gd`: **0 failures**, 25/28 cars made over 100px net progress,
  39 pedestrians, 42 connector handoffs in the initial population snapshot,
  zero invalid lane contracts and zero deadlock-limit events in that snapshot.
  Exchange forward/reverse travelled 1174.4/1357.7px; Courtyard forward/reverse
  travelled 1278.9/1359.8px. All entered/exited, all `obstacles=[]`.
  Train completed 13738.8px with partial entry, underground disappearance and
  emergence verified. Existing life test and its assertions were not weakened.
- `junction_traffic_contract_test.gd`: exclusive reservations, red stop,
  connector handoff and safety-zone clamp PASS.
- `test_junction_revision_cache.gd`: 0 failures.
- `test_junction_stage_publication.gd`: 0 failures.
- `district_one_traffic_integration_test.gd`: PASS, maximum observed frame
  movement 1.033px, maximum wait 1.360s in its bounded fixture.

The first full run after the entry clamp alone failed four assertions due to
the separate Exchange clearance lock; that run is not represented as a pass.

## Limits

No whole-suite or FPS benchmark claim. These are bounded regression runs,
not a guarantee of unlimited-session traffic behavior. The life test still
reports two ObjectDB instances retained at shutdown. Sandbox user-log and
certificate-store errors remain; the legacy integration also reports existing
UID path fallbacks and unsafe infill lots skipped. No script/parse failure in
the final six runs. Parent task validates terminal/campaign separately.
