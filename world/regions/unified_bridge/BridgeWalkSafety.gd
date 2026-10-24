extends RefCounted
## Follows the deck profile, independently of the narrower traffic graph.
const KIT := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")

static func protected_segment(a: Dictionary, b: Dictionary, side: float) -> bool:
	var middle: Vector3 = (a.point+b.point)*.5
	if middle.x >= 578.125 or (is_equal_approx(middle.x,375.0) and middle.z > -136.0): return false
	var mouth := KIT.east_mouth_limits()
	return not (side < 0 and is_equal_approx(middle.x,375.0) and middle.z >= mouth.x-2.0 and middle.z <= mouth.y+2.0)

static func add_geometry(kit) -> void:
	var rows := KIT.east_sections()
	for i in range(rows.size()-1):
		var a: Dictionary = rows[i]
		var b: Dictionary = rows[i+1]
		kit.section_at(a.distance)
		for side in [-1.0,1.0]:
			if not protected_segment(a,b,side): continue
			var start: Vector3 = a.point+a.side*(a.road+.32)*side
			var end: Vector3 = b.point+b.side*(b.road+.32)*side
			kit._beam("concrete",start+Vector3.UP*.22,end+Vector3.UP*.22,.22,.30,false)
			kit._beam("steel",start+Vector3.UP*1.08,end+Vector3.UP*1.08,.12,.10,false)
			kit._beam("steel",start+Vector3.UP*.67,end+Vector3.UP*.67,.08,.08,false)
			kit._beam("",start+Vector3.UP*.60,end+Vector3.UP*.60,.22,1.10,true)
			kit.add_box("steel",start+Vector3.UP*.72,Vector3(.10,.80,.10))
		# Wide approaches carry two lanes per direction. Preserve the double
		# yellow centre and mark the boundary within each direction in white.
		if minf(a.road,b.road) < 8.0: continue
		var length: float = b.distance-a.distance
		var cursor := 0.0
		while cursor < length-.001:
			var phase := fposmod(float(a.distance)+cursor,6.0)
			var run := minf(length-cursor,(3.0 if phase<3.0 else 6.0)-phase)
			if phase < 3.0:
				for side in [-1.0,1.0]:
					var p: Vector3 = a.point+a.side*a.road*.5*side+Vector3.UP*.041
					var q: Vector3 = b.point+b.side*b.road*.5*side+Vector3.UP*.041
					kit._beam("white",p.lerp(q,cursor/length),p.lerp(q,(cursor+run)/length),.10,.006,false)
			cursor += maxf(run,.001)

static func walk_point(row: Dictionary, side: float) -> Vector3:
	return row.point+row.side*(row.road+1.45)*side

static func population_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if not KIT.enabled(): return slots
	var rows := KIT.east_sections()
	for side in [-1.0,1.0]:
		var first := 0
		for i in range(1,rows.size()):
			if not protected_segment(rows[i-1],rows[i],side): first=i; continue
			if rows[i].distance-rows[first].distance < 6.0: continue
			var a := walk_point(rows[first],side)
			var b := walk_point(rows[i],side)
			slots.append({"a":a,"b":b,"point":(a+b)*.5,"width":2.0,"bridge_walk":true,"road":{"id":"bridge_sidewalk","width":2.0}})
			first=i
	return slots

static func add_lamps(owner_node: Node3D) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("e7dbb8")
	glass.emission_enabled = true
	glass.emission = Color("ffe4b5")
	glass.emission_energy_multiplier = .55
	var next_distance := 12.0
	for row in KIT.east_sections():
		if row.distance < next_distance or row.point.x >= 450.0: continue
		next_distance = row.distance+22.0
		for side in [-1.0,1.0]:
			var next: Dictionary = row.duplicate()
			next.point += Vector3.FORWARD*.01
			if not protected_segment(row,next,side): continue
			var foot: Vector3 = row.point+row.side*(row.deck-.23)*side
			var head: Vector3 = foot-row.side*side*.9+Vector3.UP*5.0
			owner_node._box("BridgeCurveLampPole",foot+Vector3.UP*2.5,Vector3(.13,5.0,.13),KIT.material("steel"))
			owner_node._beam_between("BridgeCurveLampArm",foot+Vector3.UP*5.0,head,.12,.12,KIT.material("steel"),false)
			owner_node._box("BridgeCurveLampHead",head,Vector3(.50,.14,.60),glass)
			# Mesmo padrão dos postes do tronco (WorldConnection3D): sem sombra, energia 0 de dia e
			# acesas por set_night_lights. Custo à noite a medir na bancada (3ª rodada, 24/10).
			var lamp := OmniLight3D.new()
			lamp.name = "BridgeCurveNightLight"
			lamp.set_meta("bridge_night_lamp",true)
			lamp.position = head-Vector3.UP*.15
			lamp.light_color = Color("ffe4b5")
			lamp.omni_range = 19.0
			lamp.omni_attenuation = 1.45
			lamp.shadow_enabled = false
			lamp.light_energy = 0.0
			owner_node.add_child(lamp)
			owner_node.bridge_lamps.append(lamp)
