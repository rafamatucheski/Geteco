class_name HarborFireStationInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Fire station interior for Northgate Fire / 03.
## Connects to 3 vehicle bay doors: Entrance0, Entrance1, Entrance2.
## Features Captain Rocha, rotating amber emergency beacon,
## and interactive alarm siren test / protective fire gear locker.

const NPC_SCRIPT := preload("res://world/harbor/interiors/HarborConversationalNPC.gd")
const TRAFFIC_VEHICLE_SCRIPT := preload("res://city_demo/scripts/TrafficVehicle.gd")
const FIRETRUCK_TEXTURE := preload("res://city_demo/art/firetruck.png")
var captain_npc: CharacterBody2D
var alarm_area: Area2D
var alarm_badge: Label
var alarm_dialog: PanelContainer
var alarm_text: Label
var is_near_alarm: bool = false

var beacon_light: PointLight2D
var anim_clock: float = 0.0

var bay_spawns: Array[Marker2D] = []
var bay_exits: Array[BuildingEntrance] = []
var bay_trucks: Array[Node2D] = []

# Life-recovery station (first-aid/oxygen point) — authorized functional
# recovery, no armor/weapon/other reward attached.
var heal_area: Area2D
var heal_badge: Label
var heal_bar_bg: Polygon2D
var heal_bar_fill: Polygon2D
var heal_cross_light: PointLight2D
var is_near_heal: bool = false
var _heal_accum: float = 0.0
const HEAL_RATE_PER_SEC := 9.0
const HEAL_BAR_WIDTH := 100.0

func _init() -> void:
	interior_id = &"fire_station"
	display_name = "NORTHGATE FIRE / 03 — CORPO DE BOMBEIROS"
	room_size = Vector2(880, 560)
	wall_color = Color("#1e1b18")
	floor_color = Color("#292524")
	accent_color = Color("#d97958")

func _get_south_wall_gaps() -> Array:
	var gaps: Array = []
	for bay_idx in 3:
		gaps.append(Vector2(float(bay_idx - 1) * 220.0, 140.0))
	return gaps

func _setup_interior_content() -> void:
	_build_bay_lanes()
	_build_captain()
	_build_ambient_beacons()
	_build_alarm_and_lockers()
	_build_heal_station()
	_build_three_bay_doors()
	_build_trucks()
	call_deferred("_connect_to_interior_manager")

func _build_bay_lanes() -> void:
	for bay_idx in 3:
		var x := float(bay_idx - 1) * 220.0
		var lane := Polygon2D.new()
		lane.color = Color("#1c1917")
		lane.polygon = PackedVector2Array([
			Vector2(x - 80, -250), Vector2(x + 80, -250),
			Vector2(x + 80, 250), Vector2(x - 80, 250)
		])
		lane.z_index = 1
		add_child(lane)

		# Short paved apron through the wall gap so the truck's brief moment
		# crossing the threshold reads as pavement, not the blackout void, in
		# the instant before the automatic exterior transfer completes.
		var apron := Polygon2D.new()
		apron.color = Color("#161412")
		apron.polygon = PackedVector2Array([
			Vector2(x - 70, 250), Vector2(x + 70, 250),
			Vector2(x + 70, 340), Vector2(x - 70, 340)
		])
		apron.z_index = 1
		add_child(apron)

		for side in [-1, 1]:
			var stripe := Line2D.new()
			stripe.points = PackedVector2Array([Vector2(x + side * 75, -240), Vector2(x + side * 75, 240)])
			stripe.width = 3.0
			stripe.default_color = Color("#f59e0b")
			stripe.z_index = 2
			add_child(stripe)

		var bay_lbl := Label.new()
		bay_lbl.text = "BAIA 0%d" % (bay_idx + 1)
		bay_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bay_lbl.position = Vector2(x - 50, -220)
		bay_lbl.size = Vector2(100, 20)
		bay_lbl.add_theme_font_size_override("font_size", 12)
		bay_lbl.add_theme_color_override("font_color", Color("#d97958"))
		bay_lbl.z_index = 3
		add_child(bay_lbl)

func _build_captain() -> void:
	captain_npc = NPC_SCRIPT.new()
	captain_npc.name = "CaptainRocha"
	captain_npc.character_name = "Capitão Rocha"
	captain_npc.title_color = Color("#d97958")
	captain_npc.shirt_color = Color("#b91c1c")
	captain_npc.pants_color = Color("#1c1917")
	captain_npc.has_hat = true
	captain_npc.hat_color = Color("#fbbf24")
	captain_npc.dialogues = [
		"Quartel 03 em alerta constante. O porto tem risco químico e contêineres inflamáveis 24 horas por dia.",
		"Nossas três viaturas precisam de saída livre nas baias. Nunca obstrua o pátio externo de manobra.",
		"Se soar o alarme, todo mundo se afasta dos portões e abre caminho pro caminhão.",
		"Temos trajes de combate a incêndio nos armários à esquerda se você quiser verificar o equipamento."
	]
	captain_npc.position = Vector2(0, -100)
	add_child(captain_npc)

func _build_ambient_beacons() -> void:
	# Giroflex de emergência no teto/parede
	beacon_light = PointLight2D.new()
	beacon_light.color = Color(1.0, 0.5, 0.1)
	beacon_light.energy = 0.9
	beacon_light.position = Vector2(0, -200)
	beacon_light.z_index = 7

	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	beacon_light.texture = tex
	add_child(beacon_light)

func _build_alarm_and_lockers() -> void:
	var alarm_pos := Vector2(-320, -120)

	# Armário de equipamentos
	var locker := Polygon2D.new()
	locker.color = Color("#7f1d1d")
	locker.polygon = PackedVector2Array([
		Vector2(-45, -30), Vector2(45, -30),
		Vector2(45, 30), Vector2(-45, 30)
	])
	locker.position = alarm_pos
	locker.z_index = 3
	add_child(locker)

	alarm_area = Area2D.new()
	alarm_area.collision_layer = 0
	alarm_area.collision_mask = 4
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120, 100)
	col.shape = rect
	alarm_area.add_child(col)
	alarm_area.position = alarm_pos
	add_child(alarm_area)

	alarm_area.body_entered.connect(func(b):
		if b.is_in_group("player"):
			is_near_alarm = true
			alarm_badge.visible = true
	)
	alarm_area.body_exited.connect(func(b):
		if b.is_in_group("player"):
			is_near_alarm = false
			alarm_badge.visible = false
			if alarm_dialog.visible:
				alarm_dialog.visible = false
				modal_closed.emit()
	)

	alarm_badge = Label.new()
	alarm_badge.text = "[ E ] TESTE DE SIRENE & PRONTIDÃO DE RESGATE"
	alarm_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alarm_badge.position = alarm_pos + Vector2(-160, -60)
	alarm_badge.size = Vector2(320, 20)
	alarm_badge.add_theme_font_size_override("font_size", 10)
	alarm_badge.add_theme_color_override("font_color", Color("#d97958"))
	alarm_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	alarm_badge.z_index = 10
	alarm_badge.visible = false
	add_child(alarm_badge)

	# UI do Alarme
	var canvas := CanvasLayer.new()
	canvas.layer = 26
	add_child(canvas)

	alarm_dialog = PanelContainer.new()
	alarm_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	alarm_dialog.offset_left = 140.0
	alarm_dialog.offset_right = -140.0
	alarm_dialog.offset_bottom = -28.0
	alarm_dialog.offset_top = -200.0
	alarm_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(alarm_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.06, 0.05, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#d97958")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	alarm_dialog.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	alarm_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "🚨 CENTRAL DE ALARME — NORTHGATE FIRE / 03"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d97958"))
	vbox.add_child(title)

	alarm_text = Label.new()
	alarm_text.text = "Sistema de sirene testado. Traje ignífugo pronto para uso."
	alarm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alarm_text.add_theme_font_size_override("font_size", 20)
	alarm_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(alarm_text)

	var hint := Label.new()
	var is_en := TranslationServer.get_locale().begins_with("en")
	hint.text = "[ E / ESC ] Close alarm" if is_en else "[ E / ESC ] Fechar alarme"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(hint)

	alarm_dialog.visible = false

func _build_three_bay_doors() -> void:
	for bay_idx in 3:
		var x := float(bay_idx - 1) * 220.0

		var spawn := Marker2D.new()
		spawn.name = "SpawnPoint%d" % bay_idx
		spawn.position = Vector2(x, 150)
		add_child(spawn)
		bay_spawns.append(spawn)

		var exit := ENTRANCE_SCENE.instantiate() as BuildingEntrance
		exit.name = "InteriorExit%d" % bay_idx
		exit.position = Vector2(x, 240)
		exit.destination_id = StringName("harbor/NorthDistrict/NorthFireStation/Entrance%d/exit" % bay_idx)
		exit.display_name = "SAIR PELA BAIA %d" % (bay_idx + 1)
		exit.entrance_kind = BuildingEntrance.EntranceKind.GARAGE
		exit.panel_slide_distance = 24.0
		exit.add_to_group("harbor_interior_exit")

		var sensor := exit.get_node_or_null("InteractionArea") as Area2D
		if sensor:
			sensor.position = Vector2(0, -20)
			sensor.collision_mask = 7
			sensor.body_entered.connect(func(body: Node2D):
				if body.is_in_group("vehicle") and body.get("is_driven_by_player") == true:
					if not body in exit._nearby_actors:
						exit._nearby_actors.append(body)
						exit.actor_approached.emit(exit, body)
						exit._refresh_prompt()
					# "Abrir o portão e dirigir até a saída": the gate opens as
					# soon as a driven vehicle approaches it from inside, no
					# keypress required.
					if exit.enabled and not exit.get("_busy"):
						exit.open_door()
			)
			sensor.body_exited.connect(func(body: Node2D):
				# Automatic no-keypress transfer: only for a still player-driven
				# vehicle actually crossing the gate outward (never a pedestrian —
				# only driven vehicles are ever tracked above — and never a
				# vehicle idling/reversing back inward past the sensor edge).
				# request_interaction() requires is_actor_in_range(), which reads
				# _nearby_actors — it must run before that entry is erased below.
				if body.is_in_group("vehicle") and body.get("is_driven_by_player") == true:
					var moving_outward := false
					if "velocity" in body:
						moving_outward = (body.velocity as Vector2).dot(exit.global_transform.y) > 20.0
					if moving_outward and exit.enabled and not exit.get("_busy"):
						if body.has_meta("home_bay"):
							# Area2D signals fire mid physics-query-flush; changing a
							# physics body's parent synchronously here is unsafe
							# ("Can't change this state while flushing queries").
							body.call_deferred("reparent", get_tree().current_scene, true)
						exit.request_interaction(body)
				if body in exit._nearby_actors:
					exit._nearby_actors.erase(body)
					exit.actor_departed.emit(exit, body)
					exit._refresh_prompt()
			)

		var prompt := exit.get_node_or_null("Prompt") as Label
		if prompt:
			prompt.position = Vector2(-90, -44)

		add_child(exit)
		bay_exits.append(exit)

	# Primary spawn defaults to center bay (bay 1)
	spawn_point = bay_spawns[1]
	exit_door = bay_exits[1]

func get_spawn_for_bay(bay_idx: int) -> Marker2D:
	if bay_idx >= 0 and bay_idx < bay_spawns.size():
		return bay_spawns[bay_idx]
	return spawn_point

func _build_trucks() -> void:
	## Reuses DemoTrafficVehicle — the same drivable class HarborLife already
	## spawns for ambient traffic, with a proven enter/exit + configure_as_parked
	## contract — rather than retrofitting player-driving onto the AI-only
	## EmergencyVehicle.gd. Only its art is swapped to the actual firetruck
	## asset (also used by EmergencyVehicle type=2) so the truck is visually
	## authentic. This never touches EmergencyVehicle.gd/EmergencyPool.gd/the
	## city's existing ambient/dispatched fire trucks.
	for bay_idx in 3:
		var x := float(bay_idx - 1) * 220.0
		var truck := TRAFFIC_VEHICLE_SCRIPT.new()
		truck.name = "FireTruck%d" % bay_idx
		add_child(truck)
		truck.apply_archetype("rescue_pumper", Color("#b02020"))
		truck.vehicle_id = "harbor_fire_truck_%d" % bay_idx
		truck.display_name = "Rescue Pumper"
		truck.characteristic = "Northgate Fire / 03"
		truck.position = Vector2(x, 30.0)
		truck.rotation = PI * 0.5 # Nose toward +Y, facing the bay's south exit.
		# Keep the camera inside this room while boarding/driving in place;
		# the normal exterior-return flow resets this once it actually exits.
		if truck.camera:
			var rect_bounds := get_camera_rect()
			truck.camera.limit_left = int(rect_bounds.position.x - 20)
			truck.camera.limit_top = int(rect_bounds.position.y - 20)
			truck.camera.limit_right = int(rect_bounds.position.x + rect_bounds.size.x + 20)
			truck.camera.limit_bottom = int(rect_bounds.position.y + rect_bounds.size.y + 20)
		truck.configure_as_parked()
		truck.set_meta("home_bay", bay_idx)
		bay_trucks.append(truck)

func _connect_to_interior_manager() -> void:
	var manager := get_parent().get_parent() if get_parent() else null
	if manager and manager.has_signal("actor_entered_interior"):
		if not manager.actor_entered_interior.is_connected(_on_actor_entered_interior):
			manager.actor_entered_interior.connect(_on_actor_entered_interior)

func _on_actor_entered_interior(actor: Node2D, entered_interior_id: StringName) -> void:
	# A truck that drove out earlier is reparented to the exterior scene (see
	# the exit sensor below) so it keeps simulating/driving normally out
	# there. Bring the SAME node back under this interior once it re-enters
	# its own bay — never instantiate a second truck.
	if entered_interior_id != interior_id:
		return
	if is_instance_valid(actor) and actor.has_meta("home_bay") and actor.get_parent() != self:
		var bay_idx: int = actor.get_meta("home_bay")
		actor.reparent(self, true)
		actor.global_position = get_spawn_for_bay(bay_idx).global_position
		if "velocity" in actor:
			actor.velocity = Vector2.ZERO

func _build_heal_station() -> void:
	var heal_pos := Vector2(320, -120)

	var cabinet := Polygon2D.new()
	cabinet.color = Color("#f1f5f9")
	cabinet.polygon = PackedVector2Array([
		Vector2(-45, -32), Vector2(45, -32), Vector2(45, 32), Vector2(-45, 32)
	])
	cabinet.position = heal_pos
	cabinet.z_index = 3
	add_child(cabinet)

	var cabinet_trim := Line2D.new()
	cabinet_trim.points = PackedVector2Array([
		Vector2(-45, -32), Vector2(45, -32), Vector2(45, 32), Vector2(-45, 32), Vector2(-45, -32)
	])
	cabinet_trim.default_color = Color("#22c55e")
	cabinet_trim.width = 2.0
	cabinet_trim.position = heal_pos
	cabinet_trim.z_index = 4
	add_child(cabinet_trim)

	for cross_poly in [
		PackedVector2Array([Vector2(-6, -20), Vector2(6, -20), Vector2(6, 20), Vector2(-6, 20)]),
		PackedVector2Array([Vector2(-20, -6), Vector2(20, -6), Vector2(20, 6), Vector2(-20, 6)]),
	]:
		var cross := Polygon2D.new()
		cross.color = Color("#dc2626")
		cross.polygon = cross_poly
		cross.position = heal_pos
		cross.z_index = 5
		add_child(cross)

	heal_cross_light = PointLight2D.new()
	heal_cross_light.color = Color(0.25, 0.9, 0.5)
	heal_cross_light.energy = 0.6
	heal_cross_light.position = heal_pos
	heal_cross_light.z_index = 6
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	heal_cross_light.texture = tex
	add_child(heal_cross_light)

	var label := Label.new()
	label.text = "PONTO DE PRIMEIROS SOCORROS"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = heal_pos + Vector2(-140, -60)
	label.size = Vector2(280, 20)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("#22c55e"))
	label.z_index = 7
	add_child(label)

	heal_area = Area2D.new()
	heal_area.collision_layer = 0
	heal_area.collision_mask = 4
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(130, 110)
	col.shape = rect
	heal_area.add_child(col)
	heal_area.position = heal_pos
	add_child(heal_area)
	heal_area.body_entered.connect(_on_heal_entered)
	heal_area.body_exited.connect(_on_heal_exited)

	heal_badge = Label.new()
	heal_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heal_badge.position = heal_pos + Vector2(-150, -92)
	heal_badge.size = Vector2(300, 20)
	heal_badge.add_theme_font_size_override("font_size", 11)
	heal_badge.add_theme_color_override("font_color", Color("#4ade80"))
	heal_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	heal_badge.z_index = 10
	heal_badge.visible = false
	add_child(heal_badge)

	heal_bar_bg = Polygon2D.new()
	heal_bar_bg.color = Color("#1c1917")
	heal_bar_bg.polygon = PackedVector2Array([
		Vector2(-HEAL_BAR_WIDTH * 0.5, -5), Vector2(HEAL_BAR_WIDTH * 0.5, -5),
		Vector2(HEAL_BAR_WIDTH * 0.5, 5), Vector2(-HEAL_BAR_WIDTH * 0.5, 5)
	])
	heal_bar_bg.position = heal_pos + Vector2(0, -74)
	heal_bar_bg.z_index = 10
	heal_bar_bg.visible = false
	add_child(heal_bar_bg)

	heal_bar_fill = Polygon2D.new()
	heal_bar_fill.color = Color("#22c55e")
	heal_bar_fill.polygon = PackedVector2Array([
		Vector2(0, -4), Vector2(HEAL_BAR_WIDTH, -4), Vector2(HEAL_BAR_WIDTH, 4), Vector2(0, 4)
	])
	heal_bar_fill.position = heal_bar_bg.position - Vector2(HEAL_BAR_WIDTH * 0.5, 0)
	heal_bar_fill.scale.x = 0.0
	heal_bar_fill.z_index = 11
	heal_bar_fill.visible = false
	add_child(heal_bar_fill)

func _on_heal_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		is_near_heal = true
		heal_badge.visible = true
		heal_bar_bg.visible = true
		heal_bar_fill.visible = true
		_refresh_heal_badge(body)

func _on_heal_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		is_near_heal = false
		heal_badge.visible = false
		heal_bar_bg.visible = false
		heal_bar_fill.visible = false
		_heal_accum = 0.0

func _refresh_heal_badge(player: Node) -> void:
	var cur: int = int(player.get("health")) if player.get("health") != null else 0
	var mx: int = int(player.get("max_health")) if player.get("max_health") != null else 100
	heal_badge.text = "🩹 RECUPERANDO: %d / %d HP" % [cur, mx]
	heal_bar_fill.scale.x = clampf(float(cur) / float(maxi(1, mx)), 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if not is_near_alarm:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if not alarm_dialog.visible:
				_sound_alarm_and_equip()
			else:
				alarm_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and alarm_dialog.visible:
			alarm_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _sound_alarm_and_equip() -> void:
	alarm_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_siren_stream()
	p.volume_db = -8.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

	alarm_text.text = "TESTE DE SIRENE E PRONTIDÃO DE RESGATE:\n• Sirene de teste acionada e sinalizadores operacionais.\n• Pressão da rede de hidrantes: 15 bar (Nominal).\n• Equipamentos de combate a incêndio e macas inspecionados."

func _physics_process(delta: float) -> void:
	anim_clock += delta
	if beacon_light:
		beacon_light.energy = 0.5 + sin(anim_clock * 6.0) * 0.4
	if heal_cross_light:
		heal_cross_light.energy = 0.45 + sin(anim_clock * 3.2) * 0.25
	if is_near_heal:
		var player := get_tree().get_first_node_in_group("player")
		if player and is_instance_valid(player) and "health" in player and "max_health" in player:
			var cur: int = player.health
			var mx: int = player.max_health
			if cur < mx:
				_heal_accum += HEAL_RATE_PER_SEC * delta
				var whole := int(_heal_accum)
				if whole > 0:
					_heal_accum -= whole
					player.health = mini(mx, cur + whole)
			else:
				_heal_accum = 0.0
			_refresh_heal_badge(player)
