extends RefCounted
## Read compatibility only: preserve IDs, inventory, receipts and progression.
## Validation still runs on the private migrated snapshot before live state changes.
const COMPACT := preload("res://world/desert/DesertCompactLayout.gd")
const HEIST := preload("res://gameplay/desert_heist/DesertHeistState.gd")
const KEY := "desert_layout_version"
const OLD_HEIST_LENGTH := 1340.0

static func valid_version(world: Dictionary) -> bool:
    if not world.has(KEY): return true
    var version: Variant = world[KEY]
    return typeof(version) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(version)) and float(version) in [1.0,float(COMPACT.VERSION)]

static func migrate_snapshot(data: Dictionary) -> Dictionary:
    var result := data.duplicate(true)
    var world: Variant = result.get("world")
    if not world is Dictionary or not valid_version(world) or world.get(KEY,1) == COMPACT.VERSION: return result
    var pedestrian: Variant = world.get("pedestrian")
    var indoor_pedestrian: Variant = null
    if not str(result.get("place_id","")).is_empty() and pedestrian is Dictionary:
        indoor_pedestrian = pedestrian.duplicate(true)
    _records(world)
    if indoor_pedestrian != null: world.pedestrian = indoor_pedestrian
    _cargo(world)
    _yard_job(world)
    world[KEY] = COMPACT.VERSION
    return result

static func _point(value: Variant) -> Vector3:
    if not value is Array or value.size()!=3: return Vector3.INF
    for coordinate in value:
        if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)): return Vector3.INF
    return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _array(point: Vector3) -> Array: return [point.x,point.y,point.z]

static func _records(value: Variant) -> void:
    if value is Array:
        for entry in value: _records(entry)
    elif value is Dictionary:
        var region: Variant = value.get("region",value.get("region_id",""))
        if region == "desert" and value.get("place_id","") == "" and value.has("position"):
            var old := _point(value.position)
            if old.is_finite(): value.position = _array(COMPACT.map_legacy_point(old))
        for key in value:
            if str(key) != HEIST.KEY: _records(value[key])

static func _cargo(world: Dictionary) -> void:
    var saved: Variant = world.get(HEIST.KEY)
    if not saved is Dictionary: return
    var old := _point(saved.get("position"))
    var region: Variant = saved.get("region","desert")
    var distance: Variant = saved.get("distance")
    if typeof(distance) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(distance)) or distance<0 or distance>OLD_HEIST_LENGTH: return
    saved.distance = float(distance)/OLD_HEIST_LENGTH*HEIST.START.distance_to(HEIST.END)
    if region != "desert" or not old.is_finite(): return
    var moved := COMPACT.map_legacy_point(old)
    if saved.get("phase","") == "driving": moved = HEIST.START.lerp(HEIST.END,float(distance)/OLD_HEIST_LENGTH)
    saved.position = _array(moved)
    var guards: Variant = saved.get("guards",[])
    if guards is Array:
        for guard in guards:
            if not guard is Dictionary or not guard.has("position"): continue
            var guard_point := _point(guard.position)
            if guard_point.is_finite(): guard.position = _array(moved+guard_point-old)
    # The same stolen truck can also be owned by the ordinary fleet. Both copies
    # must restore the same body pose after shortening its authored road.
    var identity := "desert_cargo_%d_%d"%[int(saved.get("day",0)),int(saved.get("slot",0))]
    var vehicles: Variant = world.get("vehicles",[])
    if vehicles is Array:
        for record in vehicles:
            if record is Dictionary and record.get("vehicle_id","")==identity and record.get("region","")=="desert": record.position = saved.position.duplicate()

static func _yard_job(world: Dictionary) -> void:
    # Delivered quarry rocks are world-space poses without a region field.
    # Their rotations, IDs, delivery count and one-time reward stay unchanged.
    var job: Variant = world.get("mining_yard_job")
    if not job is Dictionary or not job.get("delivered") is Dictionary: return
    for row in job.delivered.values():
        if not row is Dictionary: continue
        var old := _point(row.get("position"))
        if not old.is_finite(): continue
        if old.x>= -196.25 and old.x<= -189.75 and old.z>= -1753.75 and old.z<= -1749.25:
            row.position = _array(old+COMPACT.MINING)
