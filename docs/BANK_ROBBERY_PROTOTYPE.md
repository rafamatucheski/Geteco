# Bank and convenience-store prototype

Bank: Harbor NorthFrontage0. Convenience store: NorthFrontage4. Both use existing interior entrance/exit management and minimap icons.

The bank uses the cabin perspective camera, projected floor collision polygons and MountainInteriorActorScale. Its current geometry is procedural. `art/bank-meshy-reference.png` is generated concept art, not a game capture or an imported model.

Unarmed entry is neutral. A visible firearm alerts security; aiming, firing or interacting with the vault starts the alarm. Civilians flee, crouch or call for help. After 30 seconds police dispatch is requested; travel time still depends on the exterior simulation.

Hold E briefly at the vault to start the three-pin timing dial. Space or left click locks a pin in the green band. Three errors cancel; Escape exits. The alarm continues. Opening the door removes its blocking collision. Hold E at each cash pile to collect once, tracked by campaign flags.

At the convenience store, aim a firearm at the clerk with right mouse. A compliant clerk pays after three seconds. A resisting clerk refuses and calls for help. Armed clerk retaliation is not implemented.

`tests/test_bank_robbery.gd` exercises state transitions, collision passage, lockpick cancellation/success, alarm timing, rewards and clerk outcomes in the real Harbor scene. It disables guard physics for controlled assertions; it does not validate a complete natural firefight.

Meshy handoff: use the reference for a roofless stylized bank with a clear central route. Export GLB; request separate floor, walls, counters, props and vault door, with the vault door pivot at its hinge. Keep lighting out of textures. Mesh segmentation and collision suitability must be inspected after export.
