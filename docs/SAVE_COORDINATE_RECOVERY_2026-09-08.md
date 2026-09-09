# Legacy coordinate recovery

SaveManager validates copies before writing, after loading, and before applying a pending save. RegionTravel also validates its vehicle snapshot and direct restoration path. Existing save files are never rewritten by loading.

Only malformed coordinate arrays, nonnumeric components, NaN/infinity, or coordinates outside +/-200000 units trigger recovery. Legitimate interiors around 20000-30000 units remain unchanged.

- Harbor player recovery uses HarborGame/ArrivalSpawn (1700,1130).
- Mountain recovery uses the existing travel entry (3240,430), adding ContinuousWorld.MOUNTAIN_OFFSET only for coordinates_version >= 2. Version 1 retains the normal one-time migration.
- Unknown legacy scenes keep their own authored spawn instead of guessing a region.
- An invalid parked Monaliza position is removed from its state so PersonalCarManager uses its existing garage bay. Health, paint, ownership, inventory and mission progress remain intact.
- Invalid driven-vehicle snapshots are omitted; no unsafe body is spawned and no duplicate personal car is created.
- An invalid mountain exterior return is replaced by the same regional entry. Recovering an invalid player to outdoors removes stale interior metadata.

Warnings are emitted only when invalid data is repaired; load_game also returns them in its warnings array. Nonfinite vehicle rotations and numeric controller values are sanitized.

Validation: tests/test_saved_coordinate_recovery.gd uses copied dictionaries and an isolated temporary save, verifies valid interiors are unchanged and confirms the original legacy file remains byte-for-byte identical after loading.
