extends Node2D
## Static, road-aligned escarpments used only as visual terrain.
var road: Node2D
var patches: Array[Dictionary] = []

func build(sections: Array[PackedVector2Array]) -> void:
	z_index = -1
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").grain(self)
	# The lake occupies the valley below this road bend. Cliff faces may end at
	# its shore, but must never form a solid-looking wedge across the water.
	var lake_shore := PackedVector2Array([
		Vector2(6720, 350), Vector2(7200, 270), Vector2(7440, -140),
		Vector2(7220, -300), Vector2(6940, -110), Vector2(6740, 140)
	])
	var lake_clearance := Geometry2D.offset_polygon(lake_shore, 24.0, Geometry2D.JOIN_ROUND)
	for section in sections:
		for i in range(0,section.size()-4,4):
			var a := section[i]
			var b := section[i+4]
			var na: Vector2 = (a-road.curve.get_closest_point(a)).normalized()
			var nb: Vector2 = (b-road.curve.get_closest_point(b)).normalized()
			# Lip lies beyond the rendered gravel shoulder, never inside it.
			a += na*(25.0+3.0*sin(float(i)*1.7))
			b += nb*(25.0+3.0*sin(float(i+4)*1.7))
			var foot_a := a+na*(155.0+22.0*sin(float(i)*.37))+Vector2(0,65)
			var foot_b := b+nb*(155.0+22.0*sin(float(i+4)*.37))+Vector2(0,65)
			var safe := true
			for point in [a,b,foot_a,foot_b,(foot_a+foot_b)*0.5]:
				if road.junctions.contains(point,true) or preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd").is_reserved(point): safe=false
				if point.distance_to(road.curve.get_closest_point(point)) < 80.0: safe=false
			if not safe: continue
			var polygon := PackedVector2Array([a,b,foot_b,foot_a])
			var crosses_lake := false
			for shore in lake_clearance:
				if not Geometry2D.intersect_polygons(polygon, shore).is_empty():
					crosses_lake = true
					break
			if crosses_lake: continue
			# Summit connections are paved ground, including the entire merged junction.
			var overlaps_pavement := false
			for surface in road.pavement:
				if not Geometry2D.intersect_polygons(polygon, surface).is_empty(): overlaps_pavement = true
			if overlaps_pavement: continue
			if Geometry2D.triangulate_polygon(polygon).is_empty(): continue
			patches.append({"lip":PackedVector2Array([a,b]),"foot":PackedVector2Array([foot_a,foot_b]),"polygon":polygon,"normal":(na+nb).normalized()})
	queue_redraw()

func _draw() -> void:
	for patch in patches:
		var a: Vector2 = patch.lip[0]
		var b: Vector2 = patch.lip[1]
		var fa: Vector2 = patch.foot[0]
		var fb: Vector2 = patch.foot[1]
		# Continuous strata share their endpoints with adjacent sections. The
		# valley fades within the face; no repeated triangle fans or fog wedges.
		for layer in 7:
			var top := PackedVector2Array()
			var bottom := PackedVector2Array()
			for j in 5:
				var u := float(j)/4.0
				var lip := a.lerp(b,u)
				var foot := fa.lerp(fb,u)
				for edge in 2:
					var depth := float(layer+edge)/7.0
					var ripple := sin(lip.x*.045+lip.y*.033+depth*11.0)*sin(depth*PI)*.055
					var point := lip.lerp(foot,clampf(depth+ripple,0.0,1.0))
					if edge == 0: top.append(point)
					else: bottom.append(point)
			var polygon := top.duplicate()
			bottom.reverse()
			polygon.append_array(bottom)
			var shade := Color("72695a").lerp(Color("394f59"),float(layer)/6.0)
			shade = shade.darkened(.08 if layer%3==1 else 0.0)
			var colors := PackedColorArray()
			for j in polygon.size():
				var color := shade
				color.a = 1.0-smoothstep(.68,1.0,float(layer+(1 if j>=5 else 0))/7.0)*.82
				colors.append(color)
			draw_polygon(polygon,colors)
			if layer in [1,3,5]: draw_polyline(top,Color(.15,.19,.19,.38-float(layer)*.04),1.2,true)
		draw_line(a,b,Color("a99d86"),3.0,true)
		draw_line(a+patch.normal*3,b+patch.normal*3,Color("42443b"),2.0,true)
