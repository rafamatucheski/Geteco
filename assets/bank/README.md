# Bank finish

The shipped scene is a clean, simplified reconstruction inspired by the supplied Meshy bank/reference, not the original Meshy mesh with a new texture. It replaces the distorted geometry with authored floor tiles, wall panels, teller counters, benches and a separate vault door. Uses solid PBR materials rather than baked image textures. Original user files are preserved.

bank-finished.glb: editable source, 2928 triangles. bank-finished.tscn: self-contained Godot scene used by RobberyRoom3D. Door parts are reparented to the existing vault hinge while loot and collision logic remain independent. Built to match existing projected collision footprints.

Validation: test_bank_robbery.gd passed in Vulkan, including door parts attached to hinge, movement route, closed/open collision, lockpick, rewards and alarm dispatch. Exit still reports one ObjectDB leak; natural full combat/performance profiling not covered by this test.
