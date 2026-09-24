extends Node3D

const ACTOR := preload("res://scripts/Actor.gd")
const STREET := preload("res://scripts/Street.gd")
const CAMERA := preload("res://scripts/CameraRig.gd")
const DRIVING := preload("res://scripts/Driving.gd")
const TRAFFIC := preload("res://scripts/Traffic.gd")
const ACTIVITY := preload("res://scripts/RouteActivity.gd")
const GAMEPLAY_HUD := preload("res://ui/ClassicGameplayHUD.gd")
var player: CharacterBody3D
var camera: Camera3D
var street: Node3D
var people: Array[CharacterBody3D] = []
var population := 100
var diagnostic_label: Label
var pause_panel: CanvasLayer
var hud: CanvasLayer
var stats_clock := 0.0
var driving: Node
var traffic: Node3D
var activity: Node3D
var traffic_enabled := true
var maciota_place: Node3D
var session: Node
var gameplay: Node3D
var production: Node
var dispatch: Node3D
var traffic_yield: Node

func _ready() -> void:
	seed(21092026)
	if not "--sandbox" in OS.get_cmdline_user_args() and not "--slice" in OS.get_cmdline_user_args():
		production = preload("res://runtime/ProductionWorld.gd").new()
		production.world = self
		add_child(production)
		production.build.call_deferred()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--population="): population = clampi(arg.split("=")[1].to_int(),0,100)
		if arg == "--no-traffic": traffic_enabled = false
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("829da6")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4d4de")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	add_child(sun)
	street = STREET.new()
	street.name = "Street"
	add_child(street)
	player = ACTOR.new()
	player.name = "Dante"
	player.is_player = true
	player.position = Vector3(-8.3,0.04,3)
	add_child(player)
	camera = CAMERA.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)
	player.camera = camera
	set_population(population)
	_build_hud()
	driving = DRIVING.new()
	driving.world = self
	add_child(driving)
	traffic = TRAFFIC.new()
	traffic.name = "Traffic"
	traffic.enabled = traffic_enabled
	add_child(traffic)
	activity = ACTIVITY.new()
	activity.world = self
	add_child(activity)
	if not "--sandbox" in OS.get_cmdline_user_args():
		activity.process_mode = Node.PROCESS_MODE_DISABLED
		activity.label.hide()
		activity.arrow.hide()
		maciota_place = preload("res://world/maciota/MaciotaPlace.gd").new()
		add_child(maciota_place)
		session = preload("res://scripts/V2Session.gd").new()
		session.world = self
		add_child(session)
	for item in hud.get_children():
		if item is Label:
			item.add_theme_color_override("font_shadow_color",Color(0,0,0,0.8))
			item.add_theme_constant_override("shadow_offset_x",1)
			item.add_theme_constant_override("shadow_offset_y",2)

func set_population(count: int) -> void:
	if production != null:
		production.set_population(count)
		return
	count = clampi(count,0,100)
	while people.size() > count:
		var person: CharacterBody3D = people.pop_back()
		remove_child(person)
		person.queue_free()
	while people.size() < count:
		var index := people.size()
		var block := index % 4
		var slot := index / 4
		var xsign := -1.0 if block % 2 == 0 else 1.0
		var zsign := -1.0 if block < 2 else 1.0
		var route := PackedVector3Array([Vector3(xsign*8.2,0,zsign*8.2),Vector3(xsign*31.4,0,zsign*8.2),Vector3(xsign*31.4,0,zsign*31.4),Vector3(xsign*8.2,0,zsign*31.4)])
		var distance := fposmod(float(slot)*0.61803398875,1.0)*92.8
		var segment := int(distance / 23.2) % 4
		var fraction := fmod(distance,23.2) / 23.2
		var spawn := route[segment].lerp(route[(segment+1)%4],fraction)
		var found := false
		for attempt in 104:
			found = player.position.distance_to(spawn) >= 0.9
			for resident in people:
				if resident.position.distance_to(spawn) < 0.9:
					found = false
					break
			if found: break
			distance += 0.9
			segment = int(distance / 23.2) % 4
			fraction = fmod(distance,23.2) / 23.2
			spawn = route[segment].lerp(route[(segment+1)%4],fraction)
		if not found: break
		var person := ACTOR.new()
		person.name = "Citizen_%02d" % index
		person.identity = index
		person.speed = 1.55
		person.route = route
		person.position = spawn + Vector3.UP*0.04
		person.waypoint = (segment+1)%4
		add_child(person)
		people.append(person)
	population = people.size()

func _build_hud() -> void:
	hud = GAMEPLAY_HUD.new()
	hud.world = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	diagnostic_label = Label.new()
	diagnostic_label.position = Vector2(26,160)
	diagnostic_label.visible = false
	hud.add_child(diagnostic_label)
	pause_panel = preload("res://ui/PauseMenu.tscn").instantiate()
	pause_panel.world = self
	add_child(pause_panel)
	# Only this small UI handler processes while paused.
	var handler := Node.new()
	handler.set_script(preload("res://scripts/PauseInput.gd"))
	handler.world = self
	handler.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(handler)

func _toggle_pause() -> void:
	if session != null and session.get("modal") == true: return
	pause_panel.toggle()

func _process(delta: float) -> void:
	if diagnostic_label == null: return
	stats_clock += delta
	if stats_clock < 0.5: return
	stats_clock = 0
	if diagnostic_label.visible:
		diagnostic_label.text = "%d FPS · %d pessoas\n[ / ]  diminuir / aumentar pessoas" % [Engine.get_frames_per_second(),population]
