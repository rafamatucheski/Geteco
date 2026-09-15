extends Node2D
## Static, road-aligned escarpments. The same lip defines visible and physical void.
var road: Node2D
var patches: Array[Dictionary] = []
var hazard: Area2D

func build(sections: Array[PackedVector2Array]) -> void:
	z_index = -1
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").grain(self)
	hazard = Area2D.new()
	hazard.collision_layer = 0
	hazard.collision_mask = 1 | 2 | 4 | 8
	add_child(hazard)
	hazard.body_entered.connect(func(_body): set_physics_process(true))
	set_physics_process(false)
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
			# Summit connections are paved ground, including the entire merged junction.
			var overlaps_pavement := false
			for surface in road.pavement:
				if not Geometry2D.intersect_polygons(polygon, surface).is_empty(): overlaps_pavement = true
			if overlaps_pavement: continue
			if Geometry2D.triangulate_polygon(polygon).is_empty(): continue
			patches.append({"lip":PackedVector2Array([a,b]),"foot":PackedVector2Array([foot_a,foot_b]),"polygon":polygon,"normal":(na+nb).normalized()})
			var shape := CollisionPolygon2D.new()
			shape.polygon = polygon
			hazard.add_child(shape)
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

func _physics_process(_delta: float) -> void:
	var bodies := hazard.get_overlapping_bodies().filter(func(body): return body is CharacterBody2D and (body.has_method("take_environment_damage") or body.is_in_group("vehicle")))
	if bodies.is_empty():
		set_physics_process(false)
		return
	for body in bodies:
		if body.has_meta("mountain_falling"): continue
		var point := to_local(body.global_position)
		for patch in patches:
			if Geometry2D.is_point_in_polygon(point,patch.polygon):
				_on_body_entered(body,patch.normal)
				break

func _on_body_entered(body: Node2D, outward: Vector2) -> void:
	if body.has_meta("mountain_falling") or not body is CharacterBody2D: return
	if not body.has_method("take_environment_damage") and not body.is_in_group("vehicle"): return
	if body.get("is_dead") == true or body.get("is_exploded") == true: return
	_fall.call_deferred(body,outward)

func _fall(body: Node2D, outward: Vector2) -> void:
	if not is_instance_valid(body) or not _can_fall(body): return
	if body.is_in_group("vehicle"):
		body.set_meta("cliff_recovery_position", road.to_global(road.curve.get_closest_point(road.to_local(body.global_position))))
	var effect := preload("res://world/mountain_pass/MountainCliffFall.gd").new()
	effect.name = "MountainCliffFall"
	get_tree().root.add_child(effect)
	effect.begin(body, outward)

func _can_fall(body: Node2D) -> bool:
	if not body is CharacterBody2D or body.has_meta("mountain_falling"): return false
	if not body.visible: return false
	if body.get("is_dead") == true or body.get("is_exploded") == true: return false
	if body.get("is_recovering") == true or body.get("is_arrested") == true: return false
	if body.get("_respawn_grace_active") == true or body.has_meta("mountain_interior"): return false
	if body.get("current_vehicle") != null or body.has_meta("mountain_lift_riding"): return false
	return body.has_method("take_environment_damage") or body.is_in_group("vehicle")
