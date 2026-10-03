extends Node
## The investigation begins only after death and a continuous day away.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ABSENCE_DAYS := 1.0
const CLOSED_DAYS := 3.0
const AWAY_DISTANCE := 65.0
var heist
var _last_day := -1.0
var _poll := 0.0
var _definition: Dictionary = {}
var _tape: Node3D
var _facade: Node3D

func reset_clock() -> void:
	_last_day = -1.0
	_poll = 0.0

func update(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0: return
	_poll = .2
	var session = heist.session
	# Fixtures without a world clock do not silently substitute wall time.
	if not "weather" in session or session.weather == null: return
	var today: float = float(session.weather.moon_day()) + float(session.weather.time_of_day)
	var days := maxf(0.0, today - _last_day) if _last_day >= 0.0 else 0.0
	_last_day = today
	if not heist.data.aftermath.is_empty(): advance(days, bank_is_away())
	_sync_tape()

func advance(days: float, away: bool) -> void:
	if not is_finite(days) or days < 0.0: return
	var data: Dictionary = heist.data
	var began_investigation := false
	if data.aftermath == "pending":
		if not away:
			data.elapsed_days = 0.0
			return
		var previous := float(data.elapsed_days)
		data.elapsed_days = minf(ABSENCE_DAYS, previous + days)
		if float(data.elapsed_days) >= ABSENCE_DAYS:
			days = maxf(0.0, previous + days - ABSENCE_DAYS)
			data.aftermath = "closed"
			data.elapsed_days = 0.0
			began_investigation = true
	if data.aftermath == "closed":
		data.elapsed_days = minf(CLOSED_DAYS, float(data.elapsed_days) + days)
		# Both installation and removal happen outside the player's view.
		if float(data.elapsed_days) >= CLOSED_DAYS and away: heist._reopen_bank()
		elif began_investigation: heist._session_save()

func bank_is_away() -> bool:
	var session = heist.session
	if session.state.place_id == "harbor_bank": return false
	if session.state.region_id != "harbor": return true
	if _definition.is_empty(): _definition = PLACES.get_definition("harbor_bank")
	var exterior: Vector3 = _definition.exterior_position
	if session.world.player.global_position.distance_squared_to(exterior) < AWAY_DISTANCE * AWAY_DISTANCE: return false
	if not session.state.place_id.is_empty(): return true
	var camera := session.world.camera as Camera3D
	if not is_instance_valid(camera): return false
	# Project the complete facade bounds, not just its center, so the edge of
	# the building cannot be replaced while still visible at a wide zoom.
	var screen := Rect2(Vector2.ZERO, camera.get_viewport().get_visible_rect().size).grow(40.0)
	var projected := Rect2()
	var first := true
	for x in [-12.0, 12.0]:
		for y in [0.0, 10.0]:
			for z in [-7.0, 7.0]:
				var point := exterior + Vector3(x, y, z)
				if camera.is_position_behind(point): continue
				var pixel := camera.unproject_position(point)
				if first:
					projected = Rect2(pixel, Vector2.ZERO)
					first = false
				else: projected = projected.expand(pixel)
	return first or not screen.intersects(projected, true)

func _sync_tape() -> void:
	var session = heist.session
	var show_tape: bool = heist.data.aftermath == "closed" and session.state.region_id == "harbor" and session.state.place_id.is_empty()
	if show_tape:
		if not is_instance_valid(_facade):
			for candidate in get_tree().get_nodes_in_group("v2_walkin_facade"):
				if str(candidate.get_meta("place_id", "")) == "harbor_bank":
					_facade = candidate
					break
		show_tape = is_instance_valid(_facade) and _facade.is_visible_in_tree()
	if not show_tape:
		if is_instance_valid(_tape):
			_tape.hide()
			_tape.queue_free()
			_tape = null
		return
	if is_instance_valid(_tape):
		_tape.show()
		return
	if _definition.is_empty(): _definition = PLACES.get_definition("harbor_bank")
	var access = session.weapon_shop_entrance
	if not is_instance_valid(access): return
	_tape = Node3D.new()
	_tape.name = "BankInvestigationTape"
	add_child(_tape)
	_tape.global_position = access._door_position("harbor_bank", _definition) - access._inward("harbor_bank") * .42
	_tape.rotation.y = float(_definition.get("editor_rotation", 0.0))
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color("f8c42e")
	yellow.roughness = .83
	var black := StandardMaterial3D.new()
	black.albedo_color = Color("161a1e")
	black.roughness = .83
	for side in [-1.0, 1.0]:
		_piece(_tape, Vector3(.08, 1.5, .08), Vector3(side * 1.65, .75, 0), black)
		_piece(_tape, Vector3(.45, .09, .40), Vector3(side * 1.65, .045, 0), black)
		var post := StaticBody3D.new()
		post.collision_layer = 1
		post.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.45, 1.5, .40)
		collision.shape = shape
		post.add_child(collision)
		_tape.add_child(post)
		post.position = Vector3(side * 1.65, .75, 0)
	for slope in [-.17, .17]:
		var ribbon := Node3D.new()
		_tape.add_child(ribbon)
		ribbon.position.y = 1.04
		ribbon.rotation.z = slope
		_piece(ribbon, Vector3(3.4, .14, .014), Vector3.ZERO, yellow)
		for i in 13:
			var stripe := _piece(ribbon, Vector3(.10, .14, .016), Vector3(-1.56 + i * .26, 0, 0), black)
			stripe.rotation.z = -.25

func _piece(parent: Node3D, size: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.position = point
	return mesh
