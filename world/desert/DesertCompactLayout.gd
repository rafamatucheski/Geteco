extends RefCounted
## Compact desert revision. Only distances between authored places change; actors,
## buildings, interiors and the 800 m strip retain their original dimensions.
const CANYON_DIMENSIONS := preload("res://world/desert/canyon/CanyonDimensions.gd")
const VERSION := 2
const ORIGINAL_BOUNDS := Rect2(-1500, -1950, 1940, 1576.5)
const BOUNDS := Rect2(-1340, -1230, 1780, 856.5)
const TOWN := Vector3(0, 0, 340)
const DRAG := Vector3(140, 0, 520)
const SOUTH := Vector3(140, 0, 640)
const MINING := Vector3(0, 0, 680)
const RELIEF := Vector3(140, 0, 680)
const WEST := Vector3(140, 0, 0)
const TRUCK_STOP := Vector3(0, 0, 260)
const NORTH_PASS := Vector3(0, 0, 640)
const NORTH_RELICS := Vector3(140, 0, 120)
## Explicit rigid moves for the small places whose new position cannot follow
## a whole district. Also used when loading an old save next to those places.
const SITE_MOVES := [
    [Vector2(-640,-1527),Vector2(-500,-887),18.0],
    [Vector2(-470,-800),Vector2(-470,-460),15.0],
    [Vector2(-322,-934),Vector2(-322,-594),18.0],
    [Vector2(-350,-1700),Vector2(-350,-1020),18.0],
    [Vector2(-212,-1572),Vector2(-212,-932),20.0],
    [Vector2(-1250,-1640),Vector2(-1110,-1000),30.0],
    [Vector2(-1300,-1720),Vector2(-1160,-1080),60.0],
    [Vector2(-650,-1510),Vector2(-510,-870),18.0],
    [Vector2(-360,-650),Vector2(-360,-485),28.0],
    [Vector2(-1040,-770),Vector2(-900,-485),28.0],
    [Vector2(40,-1050),Vector2(0,-710),28.0],
    [Vector2(-1360,-1210),Vector2(-1240,-850),28.0],
    [Vector2(-1320,-1810),Vector2(-1180,-1130),36.0],
    [Vector2(40,-1890),Vector2(12,-1180),20.0],
    [Vector2(-880,-1130),Vector2(-600,-470),28.0],
    [Vector2(200,-1410),Vector2(-370,-1170),28.0],
    [Vector2(-1120,-1410),Vector2(-1210,-940),35.0],
    [Vector2(-600,-1410),Vector2(-480,-865),30.0],
    [Vector2(-360,-1690),Vector2(-360,-1010),32.0],
    [Vector2(-280,-810),Vector2(-280,-470),28.0],
    [Vector2(-1170,-1730),Vector2(-1030,-1050),30.0],
    [Vector2(366,-1200),Vector2(366,-680),32.0],
    [Vector2(-790,-858),Vector2(-790,-518),28.0],
    [Vector2(-1176,-1090),Vector2(-1036,-650),28.0],
    [Vector2(-480,-1290),Vector2(-340,-770),28.0],
    [Vector2(100,-1600),Vector2(240,-960),68.0],
    [Vector2(-750,-1512),Vector2(-610,-872),27.0],
    [Vector2(-1100,-1567),Vector2(-960,-927),32.0],
    [Vector2(-350,-1516),Vector2(-210,-876),24.0],
    [Vector2(-300,-1282),Vector2(-160,-762),28.0],
    [Vector2(-1100,-585),Vector2(-960,-465),70.0],
    [Vector2(-872,-550),Vector2(-732,-430),38.0],
    [Vector2(-650,-580),Vector2(-510,-460),30.0],
    [Vector2(-1400,-1080),Vector2(-1260,-1080),60.0],
]
const LANDFORM_MOVES := [
    [Vector2(-790,-690),Vector2(-650,-690),65.0],
    [Vector2(-25,-622),Vector2(-25,-460),80.0],
    [Vector2(-790,-1420),Vector2(150,-680),110.0],
    [Vector2(-650,-1080),Vector2(149,-1090),125.0],
]
const ORIGINAL_MINE_ACCESS := [Vector2(-180,-1540),Vector2(-180,-1574),Vector2(-167,-1598),Vector2(-167,-1611),Vector2(-180,-1630)]
const COMPACT_MINE_ACCESS := [Vector2(-180,-900),Vector2(-180,-914),Vector2(-180,-928),Vector2(-180,-939),Vector2(-180,-950)]

static func world_point(old: Vector3, zone: String) -> Vector3:
    match zone:
        "town": return old + TOWN
        "drag": return old + DRAG
        "south": return old + SOUTH
        "mining": return old + MINING
        "relief": return old + RELIEF
        "west": return old + WEST
        "truck_stop": return old + TRUCK_STOP
        "north_pass": return old + NORTH_PASS
        "north_relics": return old + NORTH_RELICS
    return old

static func map_legacy_xz(old: Vector2) -> Vector2:
    var mapped := map_legacy_point(Vector3(old.x,0,old.y))
    return Vector2(mapped.x,mapped.z)

static func map_legacy_point(old: Vector3) -> Vector3:
    var p := Vector2(old.x,old.z)
    # Interiors are instantiated beyond this envelope; their local/global poses
    # must never be mistaken for outdoor coordinates.
    if not ORIGINAL_BOUNDS.grow(.1).has_point(p): return old
    var canyon := _legacy_canyon(old)
    if canyon.is_finite(): return canyon
    for move in SITE_MOVES:
        if p.distance_to(move[0]) <= float(move[2]):
            var shift: Vector2 = move[1]-move[0]
            return old+Vector3(shift.x,0,shift.y)
    var access := _legacy_access(p)
    if access.is_finite(): return Vector3(access.x,old.y,access.y)
    if Rect2(-1070,-1385,1210,185).has_point(p): return old+DRAG
    if Rect2(-326,-1910,300,310).has_point(p): return old+MINING
    if Rect2(-1140,-1936,580,368).has_point(p):
        var moved := old+RELIEF
        moved.z = maxf(BOUNDS.position.y+8,moved.z)
        return moved
    if Rect2(-1480,-790,270,360).has_point(p): return old+WEST
    # Keep saves beside relocated natural activities. The strip above takes
    # precedence over the old salt-flat footprint, which bordered its return.
    for move in LANDFORM_MOVES:
        if p.distance_to(move[0]) <= float(move[2]):
            var shift: Vector2 = move[1]-move[0]
            return old+Vector3(shift.x,0,shift.y)
    if Rect2(-665,-1110,805,360).has_point(p): return old+TOWN
    if Rect2(215,-815,115,115).has_point(p): return old+TRUCK_STOP
    if p.x >= 308 and p.y <= -1500:
        var moved := old+NORTH_PASS
        if p.y < -1810: moved.z = lerpf(-1170,-1220,clampf((-p.y-1810)/135.0,0,1))
        return moved
    # Empty distances were removed. Restore an outdoor save onto the corresponding
    # road, keeping its signed lane/shoulder offset instead of leaving it in a pit.
    var mapped := _road_point(p)
    return Vector3(mapped.x,old.y,mapped.y)

static func legacy_point(old: Vector3) -> Vector3: return map_legacy_point(old)

static func _legacy_canyon(old: Vector3) -> Vector3:
    var source := old+WEST
    var source_xz := Vector2(source.x,source.z)
    if not CANYON_DIMENSIONS.SOURCE_BOUNDS.has_point(source_xz): return Vector3.INF
    var lateral := source.x-CANYON_DIMENSIONS.CENTER_X
    # The full-size pedestrian deck has a shorter span, not a narrower lane.
    if absf(lateral)<=2.8 and source.z>= -775.0 and source.z<=CANYON_DIMENSIONS.FIXED_END_Z and old.y>= -.5:
        var bridge_z := CANYON_DIMENSIONS.source_to_field(source_xz).y
        var gate_z := CANYON_DIMENSIONS.FIXED_END_Z-10.0
        # Fixed bollards keep their human-scale spacing. Do not restore a point
        # inside one when compression maps a formerly clear part of the deck there.
        if source.z<=gate_z:
            for barrier_z in [gate_z,gate_z+3.0]:
                if absf(bridge_z-float(barrier_z))>=.8: continue
                for across in [-1.45,0.0,1.45]:
                    if absf(lateral-float(across))<.685: bridge_z=gate_z-.8
        return Vector3(source.x,old.y,bridge_z)
    # The inhabited mesa, its armory and their immediate circulation do not scale.
    if Rect2(CANYON_DIMENSIONS.CENTER_X-36.0,-524,72,64).grow(3.0).has_point(source_xz): return source
    var field := CANYON_DIMENSIONS.source_to_field(source_xz)
    var height := old.y*CANYON_DIMENSIONS.DEPTH_FACTOR if old.y<0.0 else old.y
    # Load only while restoring an old outdoor gorge pose. Keeping this deferred
    # avoids a preload cycle between terrain, layout and migration resources.
    var terrain = load("res://world/desert/canyon/DesertSmugglerTerrain.gd")
    var surface: float = terrain.surface_height(field)
    if is_finite(surface): height=maxf(height,surface+.1)
    return Vector3(field.x,height,field.y)

static func _legacy_access(p: Vector2) -> Vector2:
    # The quarry itself moved rigidly, but its public approach was shortened and
    # straightened. Preserve lane/shoulder offsets along corresponding segments.
    var best := 81.000001
    var result := Vector2.INF
    for index in ORIGINAL_MINE_ACCESS.size()-1:
        var a: Vector2 = ORIGINAL_MINE_ACCESS[index]
        var b: Vector2 = ORIGINAL_MINE_ACCESS[index+1]
        var nearest := Geometry2D.get_closest_point_to_segment(p,a,b)
        var distance := p.distance_squared_to(nearest)
        if distance >= best: continue
        best = distance
        var along := clampf((nearest-a).dot(b-a)/(b-a).length_squared(),0,1)
        var direction := (b-a).normalized()
        var side := (p-nearest).dot(Vector2(-direction.y,direction.x))
        var target_a: Vector2 = COMPACT_MINE_ACCESS[index]
        var target_b: Vector2 = COMPACT_MINE_ACCESS[index+1]
        var target_direction := (target_b-target_a).normalized()
        result = target_a.lerp(target_b,along)+Vector2(-target_direction.y,target_direction.x)*side
    return result

static func _road_point(p: Vector2) -> Vector2:
    var roads := [
        [Vector2(342.5,-373.5),Vector2(342.5,-445),Vector2(342.5,-373.5),Vector2(342.5,-445)],
        [Vector2(342.5,-445),Vector2(342.5,-750),Vector2(342.5,-445),Vector2(342.5,-490)],
        [Vector2(342.5,-750),Vector2(342.5,-880),Vector2(342.5,-490),Vector2(342.5,-540)],
        [Vector2(342.5,-880),Vector2(342.5,-1500),Vector2(342.5,-540),Vector2(342.5,-860)],
        [Vector2(342.5,-880),Vector2(-370,-880),Vector2(342.5,-540),Vector2(-370,-540)],
        [Vector2(-370,-880),Vector2(-1160,-880),Vector2(-370,-540),Vector2(-1020,-540)],
        [Vector2(-1160,-880),Vector2(-1200,-920),Vector2(-1020,-540),Vector2(-1060,-580)],
        [Vector2(-1200,-920),Vector2(-1200,-1500),Vector2(-1060,-580),Vector2(-1060,-860)],
        [Vector2(-1200,-1500),Vector2(-1160,-1540),Vector2(-1060,-860),Vector2(-1020,-900)],
        [Vector2(-1160,-1540),Vector2(302.5,-1540),Vector2(-1020,-900),Vector2(302.5,-900)],
        [Vector2(302.5,-1540),Vector2(342.5,-1500),Vector2(302.5,-900),Vector2(342.5,-860)],
    ]
    var best := INF
    var result := Vector2(342.5,-445)
    for road in roads:
        var a: Vector2 = road[0]
        var b: Vector2 = road[1]
        var nearest := Geometry2D.get_closest_point_to_segment(p,a,b)
        var distance := p.distance_squared_to(nearest)
        if distance >= best: continue
        best = distance
        var direction := (b-a).normalized()
        var t := clampf((nearest-a).dot(b-a)/(b-a).length_squared(),0,1)
        var next_direction: Vector2 = (road[3]-road[2]).normalized()
        var across := clampf((p-nearest).dot(Vector2(-direction.y,direction.x)),-12,12)
        result = (road[2] as Vector2).lerp(road[3],t)+Vector2(-next_direction.y,next_direction.x)*across
    return result
