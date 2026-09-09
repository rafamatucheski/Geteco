# Police stop and parked vehicle contact

Implemented locally after the user's request to fix passive police behavior.

Confirmed code paths: PoliceOfficer explicitly set velocity to zero whenever
the suspect was a vehicle; the cruiser's arrived-waypoint path explicitly
excluded seated suspects from deployment. Officers tracking a car without a
service-vehicle reference could also retain the car after the driver exited.

PoliceVehicleStop now approaches the actual safe side door, issues a warning,
opens the existing animated door, invokes the real vehicle exit/camera handoff,
moves the actual player outward and holds a short arrest pose before invoking
the existing custody flow. No replacement car or character models are used.
One officer reserves the stop; other officers do not extract the same driver.
Flight during opening cancels; clearance, stopped speed, wanted state and
officer health are rechecked. Officer removal restores control/poses.

VehicleMotionSafety skips move_and_slide at zero velocity, preventing parked
cars from applying overlap recovery against pedestrians. Their collision
layer stays enabled. This is not a change to active emergency routing.

Validation executed with Godot 4.7.2:

- tests/test_police_vehicle_stop_live.gd: Vulkan, HarborGame, real player,
  personal car and dispatched crew. Seated arrest without attack, voluntary
  exit arrest, moving-car rejection, cancel on acceleration, wall clearance,
  and pedestrian contact all passed. Safety probes freeze the test car and
  exercise the guard directly; full seated and on-foot arrest run in scene.
- tests/test_police_fair_arrest.gd: passed.
- tests/test_vehicle_physics_regressions.gd: passed.

Logs: D:/geteco/police-stop-live.log, police-stop-regression.log,
police-motion-regression.log. Screenshot: D:/geteco/police-stop-live.png.
Some fixtures report ObjectDB objects at shutdown; no performance claim is
made by these tests. Test setup positions actors at a controlled open location;
it does not validate every city route or dispatch from the precinct.

The extraction is a basic real-actor motion/pose sequence, not the final
hand-to-hand choreography requested from Antigravity. Police/ambulance routing,
parking layout and performance investigation remain separate work. Changes to
EmergencyVehicle are confined to the seated-suspect deployment condition;
preserve this when merging concurrent route fixes.
