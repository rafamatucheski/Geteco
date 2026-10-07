extends SceneTree
## Sondagem de pontos do deserto (altura do chão, reservas, estradas) para escolher locais de entradas subterrâneas.
const LANDFORMS := preload("res://world/desert/expansion/DesertLandforms.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var region = load("res://world/desert/DesertRegion.gd").new()
	region.initial_prewarm_only = true
	root.add_child(region)
	await process_frame
	region.prepare_data()
	# leito seco: amostra e cruzamentos com estradas
	var best := {}
	for i in 201:
		var t := float(i) / 200.0
		var p: Vector2 = LANDFORMS.wash_point(lerpf(0.0, 1.0, t))
		for road in region.roads:
			var pts: PackedVector3Array = road.points
			for k in range(1, pts.size()):
				var d := Geometry2D.get_closest_point_to_segment(p, Vector2(pts[k-1].x, pts[k-1].z), Vector2(pts[k].x, pts[k].z)).distance_to(p)
				if d < 80.0 and (not best.has(road.id) or d < best[road.id].d): best[road.id] = {"d": d, "p": p, "t": t}
	for id in best: print("WASH_ROAD ", id, " d=", snappedf(best[id].d, 0.1), " p=", best[id].p, " t=", best[id].t)
	print("WASH start ", LANDFORMS.wash_point(0.0), " end ", LANDFORMS.wash_point(1.0))
	var candidates := {"mine_e1":Vector2(10,-1700),"mine_e2":Vector2(30,-1760),"mine_e3":Vector2(10,-1820),"mine_w1":Vector2(-340,-1700),"mine_w2":Vector2(-360,-1760),"mine_w3":Vector2(-350,-1650),
		"wash_end":Vector2(-540,-1190),"wash_end2":Vector2(-545,-1170),"wash_start":Vector2(-745,-980),"wash_mid":Vector2(-640,-1075),"wash_side":Vector2(-610,-1060),
		"salt_n":Vector2(-640,-1553),"salt_s":Vector2(-640,-1527),"main_n":Vector2(-700,-893),"main_s":Vector2(-700,-867),"west_e":Vector2(-1188,-1100),"moon_well":Vector2(-470,-800),"moon_well3":Vector2(-500,-760)}
	for name in candidates:
		var p: Vector2 = candidates[name]
		print("PONTO ", name, " ", p, " y=", snappedf(region._ground_height(p), 0.01), " livre3=", region._decoration_clear(p, 3.0), " livre6=", region._decoration_clear(p, 6.0))
	quit()
