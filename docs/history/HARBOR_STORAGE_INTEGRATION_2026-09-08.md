# Harbor Art Pack: first gameplay integration

The storage depot composition replaces the three legacy drawn containers and
their rectangular solids in the Port Authority yard at (2600, 1700). The freight
warehouse loading access remains clear. Cargo and maintenance compositions are
still available in the art pack for subsequent placement.

`HarborStorageArt.gd` uses the existing ground-calibrated static model renderer,
at 22 pixels per metre. Each cargo AABB is projected onto the gameplay ground
plane as a separate StaticBody2D. The total envelope is never a solid. The
composition uses material batching and a single UPDATE_ONCE viewport.

Validation: Godot 4.7.2, Vulkan Forward+, RTX 4060. Run from the game directory:

```powershell
& 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/test_harbor_storage_integration.gd
```

Passed: projected envelope clears all district buildings, access strips and road
reservations; real Dante walks from x=2460 to x=2720 along y=1770; his actual
collision shape is blocked by a pallet stack; batched model and static viewport
contracts hold. Gameplay screenshot: `D:/geteco/harbor-storage-integrated.png`.
Log: `D:/geteco/harbor-storage-test.log`. No script errors or failed assertions.
Godot reports one ObjectDB instance at shutdown; this check does not establish
whole-world memory stability or FPS improvement.

The integration keeps the art pack unchanged. This is the storage composition
only, with exterior 2D gameplay physics; it does not introduce 3D player physics.
