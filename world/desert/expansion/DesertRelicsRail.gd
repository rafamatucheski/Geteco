extends RefCounted
const BATCH := preload("res://world/desert/expansion/DesertRelicsBatch.gd")
const BALLAST := preload("res://world/desert/expansion/DesertRelicsBallast.gd")
const START_X := -1370.0
const END_X := -430.0
const STEP := 4.0
const GAUGE := 1.435

static func center(x: float) -> Vector2:
	return Vector2(x, -550.0 + sin((x-START_X)/(END_X-START_X)*TAU)*5.0)

static func reservation_clear(point: Vector2, radius: float = 0.0) -> bool:
	if point.x < START_X-8.0-radius or point.x > END_X+8.0+radius: return true
	return absf(point.y-center(clampf(point.x,START_X,END_X)).y) > 6.0+maxf(radius,0.0)

static func build_chunk(parent: Node3D, rect: Rect2, world_seed: int, height: Callable) -> int:
	if not rect.intersects(Rect2(START_X-9.0,-572.0,END_X-START_X+18.0,44.0)): return 0
	var ballast_count := BALLAST.build_chunk(parent,rect,height,center,START_X,END_X)
	var start := maxi(0, floori((rect.position.x-START_X)/STEP)-1)
	var end := mini(ceili((END_X-START_X)/STEP), ceili((rect.end.x-START_X)/STEP)+1)
	var batch = BATCH.new(parent,"AbandonedRailway",Vector3.ZERO)
	var count := 0
	for i in range(start,end):
		var x := START_X+(float(i)+.5)*STEP
		var point := center(x)
		if not rect.has_point(point): continue
		var a := center(x-STEP*.5)
		var b := center(x+STEP*.5)
		var h := float(height.call(point))
		var yaw := -atan2(b.y-a.y,b.x-a.x)
		var rotation := Vector3(0,yaw,0)
		# The continuous ballast owns a gentle approach to both railheads; these
		# narrow iron solids retain their own exact support and collision volumes.
		for j in 4:
			var index := i*4+j
			if (index+world_seed)%23 == 0: continue
			var tie := center(x-1.5+float(j))
			var tie_height := float(height.call(tie))
			var twist := .085*sin(float(index)*7.1)
			batch.box("Sleeper",Vector3(tie.x,tie_height+.025,tie.y),Vector3(.21,.05,2.35),"wood",false,rotation+Vector3(0,twist,0))
			if index%7 != 0:
				for side in [-1.0,1.0]:
					batch.box("TiePlate",Vector3(tie.x,tie_height+.054,tie.y+side*GAUGE*.5),Vector3(.29,.017,.22),"rust",false,rotation)
		for side in [-1.0,1.0]:
			# Deliberate lifted sections and stolen rail lengths break the perfect
			# silhouette without leaving collision where the track is absent.
			if (i+int(side)*3)%37 in [0,1] or i > 227 and i%3 == 0: continue
			var rail := Vector3(point.x,h+.089,point.y+side*GAUGE*.5)
			batch.box("Rail",rail,Vector3(STEP-.035,.076,.075),"rust",false,rotation)
			batch.box("RailHead",rail+Vector3(0,.044,0),Vector3(STEP-.035,.018,.105),"steel",false,rotation)
			# The support reaches the head's real visible top, h+.142, and its
			# full width. Preserve collision while allowing the normal authored step.
			batch.rail_collision("Rail",rail+Vector3(0,.0075,0),Vector3(STEP-.035,.091,.105),rotation)
		if i%24 == 7:
			batch.box("DiscardedRail",Vector3(point.x,h+.06,point.y+3.2),Vector3(3.4,.12,.11),"rust",false,Vector3(0,.23,0))
			batch.rail_collision("DiscardedRail",Vector3(point.x,h+.06,point.y+3.2),Vector3(3.4,.12,.11),Vector3(0,.23,0))
		if i%36 == 11:
			# Broken telegraph poles punctuate the line; no new runtime lights.
			batch.cylinder("TelegraphStump",Vector3(point.x,h+1.25,point.y-7.0),.15,2.5,"wood")
			batch.beam("FallenPole",Vector3(point.x+1,h+.16,point.y-7),Vector3(point.x+5,h+.2,point.y-5),.22,"wood")
		count += 1
	if count == 0:
		batch.root.free()
		return ballast_count
	batch.root.set_meta("abandoned_rail_segments",count)
	batch.finish()
	return count+ballast_count
