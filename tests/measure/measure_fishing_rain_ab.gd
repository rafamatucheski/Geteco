extends "res://tests/measure/measure_fishing_life.gd"
## Só diagnóstico: linha de base reconstruída em memória, NÃO um build histórico.
## Rode com Godot 4.7.2 .NET depois de compilar Harbor.csproj. Sem capturas.
## O arremesso nativo chega à espera; só esta fixture segura o timer da fisgada.
const COVERAGE := preload("res://runtime/atmosphere/PrecipitationCoverage.gd")
const DYNAMICS := preload("res://world/places/fishing/FishingWaterDynamics.gd")
const ORIGINAL_SHADER := """shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled, depth_draw_never;
varying vec2 pond;
void vertex() { pond = VERTEX.xz; }
void fragment() {
 vec2 q = pond - vec2(0.0,-4.0);
 float angle = atan(q.y / 18.0, q.x / 27.0);
 float lobe = 1.0 + .045*sin(angle*3.0+.6) + .025*cos(angle*5.0);
 float edge = length(q / vec2(27.0,18.0)) / lobe;
 float depth = smoothstep(0.0,.42,1.0-edge);
 float a = pond.x*.95 + pond.y*.62 + TIME*.48;
 float b = pond.x*-.71 + pond.y*1.27 - TIME*.37;
 vec2 slope = vec2(cos(a)*.028-cos(b)*.021,cos(a)*.019+cos(b)*.031);
 NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x,1.0,-slope.y)),0.0)).xyz);
 float sheen = sin(a)*sin(b)*.006;
 ALBEDO = mix(vec3(.04,.12,.09),vec3(.009,.065,.057),depth) + sheen;
 ROUGHNESS = .38;
 SPECULAR = .42;
 ALPHA = mix(.36,.63,depth);
}
"""
var cases: Dictionary = {}
var process_inventory: Array = []
var source_start: Dictionary = {}
var weather_locked := false
var site: Node3D
var water: MeshInstance3D
var current_mesh: Mesh
var current_material: ShaderMaterial
var baseline_mesh: ArrayMesh
var baseline_material: ShaderMaterial
var unfocused_frames := 0
var unexpected_phase_frames := 0
var camera_origin := Transform3D.IDENTITY
var camera_max_drift := 0.0
var finished := false

func _process(delta: float) -> bool:
	if is_instance_valid(fishing_driver) and fishing_driver.active:
		match str(fishing_driver.phase):
			"ready": fishing_input(true)
			"charging":
				if fishing_driver._charge > .7: fishing_input(false)
			"waiting": fishing_driver._phase_time = -999.0
	if weather_locked and is_instance_valid(world):
		var weather = world.session.weather
		var camera: Camera3D = world.get_viewport().get_camera_3d()
		COVERAGE.follow(weather.precipitation, camera, world.player.global_position)
		weather.drag_rain.apply(weather.precipitation, camera, delta, weather.weather_state == 2)
		weather.drag_sky.update_lightning(weather.storm.envelope(weather.storm.flash_age) if weather.weather_state == 2 else 0.0, weather.storm.flashes)
		if tracing:
			camera_max_drift = maxf(camera_max_drift, camera.global_position.distance_to(camera_origin.origin))
	if tracing:
		var now := Time.get_ticks_usec()
		intervals[phase].append(float(now - last_tick) / 1000.0)
		last_tick = now
		if not DisplayServer.window_is_focused(): unfocused_frames += 1
		if str(fishing_driver.phase) != "waiting": unexpected_phase_frames += 1
	return false

func run() -> void:
	folder = FIXTURE.output_dir("fishing-rain-ab")
	# Actual Main startup takes about 110 s, followed by four 35 s windows.
	create_timer(420.0, true, false, true).timeout.connect(_timeout)
	if DisplayServer.get_name() == "headless": _abort("blocked_headless", 2); return
	if not _exclusive_render_process(): _abort("blocked_concurrent_renderer", 7); return
	seed(71026)
	Engine.set_meta("fishing_baseline", false)
	source_start = _sources()
	var snapshot := FIXTURE.full_snapshot(ENTRY, false)
	snapshot.campaign.active_id = ""
	snapshot.campaign.step = 0
	snapshot.economy.balance = 500
	var save_path := FIXTURE.write_fixture(folder, "isolated-save.json", snapshot)
	if save_path.is_empty(): _abort("blocked_fixture", 2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.production.no_save = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.state.campaign.cancel("fishing_rain_ab")
	for line in 12:
		if not world.session.dialogue_open: break
		fishing_input(true)
		fishing_input(false)
		await physics_frame
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: _abort("blocked_native", 5); return
	world.production.region.set_focus(ENTRY)
	world.production.region.prepare_collision_at(ENTRY)
	world.player.teleport(ENTRY)
	world.session.fishing_runtime.refresh()
	site = world.session.fishing_runtime.site
	if not is_instance_valid(site): _abort("blocked_site", 6); return
	water = site.get_node("LagoSereno_water")
	current_mesh = water.mesh
	current_material = water.material_override
	_build_baseline()
	var station: Vector3 = site.fishing_spots()[0].position + Vector3.UP * .03
	world.player.teleport(station)
	site.set_focus(station)
	world.camera.initialized = false
	_set_weather(0, 0.0)
	await create_timer(2.0).timeout
	fishing_driver = world.session.fishing
	fishing_driver._rng.seed = 71026
	if not fishing_driver.start(-1): _abort("blocked_fishing", 6); return
	while str(fishing_driver.phase) != "waiting": await physics_frame
	fishing_driver._phase_time = -999.0
	await create_timer(2.0).timeout
	var camera: Camera3D = world.get_viewport().get_camera_3d()
	if not is_equal_approx(camera.size, 10.4): _abort("blocked_camera_size", 6); return
	camera_origin = camera.global_transform
	for condition in [{"id":"light_rain", "state":1, "level":.22}, {"id":"storm", "state":2, "level":1.0}]:
		for baseline in [true, false]:
			if not _exclusive_render_process(): _abort("blocked_concurrent_renderer", 7); return
			_set_weather(0, 0.0)
			_swap_water(baseline)
			world.session.weather.rain_ground._rng.seed = 71026
			_set_weather(int(condition.state), float(condition.level))
			# O RainGround atualiza a lista de superfícies a cada .1 s enquanto ativo. Deixa
			# esse cache largar o local removido antes de instalar o campo vazio.
			await create_timer(.2, true, false, true).timeout
			if baseline: site.water_dynamics = DYNAMICS.new(site.pond_polygon)
			await create_timer(5.0, true, false, true).timeout
			var title: String = str(condition.id) + ("_baseline_reconstructed" if baseline else "_current")
			var impacts: int = site.water_dynamics.impact_count
			var contacts: int = world.session.weather.rain_ground.water_impact_count
			unfocused_frames = 0
			unexpected_phase_frames = 0
			camera_max_drift = 0.0
			var wall_start := Time.get_ticks_usec()
			await sample(title, 30.0)
			var elapsed := float(Time.get_ticks_usec() - wall_start) / 1000000.0
			var values: Array[float] = []
			values.assign(intervals[title])
			cases[title] = {"baseline_reconstructed":baseline, "timing":stats(values), "wall_seconds":elapsed, "warmup_seconds":5.0, "weather_state":condition.state, "rain_level":condition.level, "water_impacts":site.water_dynamics.impact_count - impacts, "water_contacts":world.session.weather.rain_ground.water_impact_count - contacts, "field_active":site.water_dynamics.active, "max_abs_height_at_end":_height_peak(), "unfocused_frames":unfocused_frames, "unexpected_phase_frames":unexpected_phase_frames, "camera_max_drift":camera_max_drift, "camera_size":camera.size, "camera_transform":str(camera.global_transform), "people":world.people.size(), "vehicles":world.production.vehicles.size()}
			if unexpected_phase_frames > 0 or camera_max_drift > .01: _abort("invalid_waiting_fixture", 6); return
			if baseline and (site.water_dynamics.active or site.water_dynamics.impact_count != 0): _abort("invalid_reconstructed_field", 6); return
			if not baseline and site.water_dynamics.impact_count <= impacts: _abort("invalid_current_rain_contacts", 6); return
			_write_report("running")
	_set_weather(0, 0.0)
	_swap_water(false)
	fishing_input(false)
	world.session.fishing.cancel_attempt("rain_ab_complete")
	fishing_driver = null
	finished = true
	_write_report("completed_diagnostic")
	print("FISHING_RAIN_AB_RESULT ", folder, " ", JSON.stringify(cases))
	quit()

func _build_baseline() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 72:
		var a: Vector3 = site._shore(float(index) * TAU / 72.0) + Vector3.UP * .055
		var b: Vector3 = site._shore(float(index + 1) * TAU / 72.0) + Vector3.UP * .055
		for point in [Vector3(0, .055, -4), b, a]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(point.x, point.z))
			surface.add_vertex(point)
	baseline_mesh = surface.commit()
	baseline_material = ShaderMaterial.new()
	baseline_material.shader = Shader.new()
	baseline_material.shader.code = ORIGINAL_SHADER

func _swap_water(baseline: bool) -> void:
	# Substitui só as referências vivas desta fixture. Sem API de produção de limpar/reiniciar.
	site.remove_from_group("native_water_surface")
	site.water_dynamics = DYNAMICS.new(site.pond_polygon)
	water.mesh = baseline_mesh if baseline else current_mesh
	water.material_override = baseline_material if baseline else current_material
	if not baseline:
		current_material.set_shader_parameter("rain_height", site.water_dynamics.texture)
		site.add_to_group("native_water_surface")

func _set_weather(state: int, level: float) -> void:
	var weather = world.session.weather
	weather.set_process(false)
	weather.time_of_day = .45
	weather.weather_state = state
	weather.weather_timer = 9999.0
	weather.rain_intensity = .22
	weather.rain_level = level
	weather._update()
	weather_locked = true

func _height_peak() -> float:
	var peak := 0.0
	for value in site.water_dynamics.heights: peak = maxf(peak, absf(value))
	return peak

func _exclusive_render_process() -> bool:
	if OS.get_name() != "Windows": return false
	var command := "$ErrorActionPreference='Stop'; @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot' -and $_.Name -notmatch '_console' -and $_.ProcessId -ne %d -and $_.CommandLine -notmatch '--headless' } | Select-Object ProcessId,Name,CommandLine) | ConvertTo-Json -Compress" % OS.get_process_id()
	var output: Array = []
	if OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", command]), output, true) != 0: return false
	process_inventory = []
	var raw := "".join(output).strip_edges()
	if not raw.is_empty():
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary: process_inventory.append(parsed)
		elif parsed is Array: process_inventory = parsed
		else: return false
	return process_inventory.is_empty()

func _sources() -> Dictionary:
	var result := fingerprint()
	result["rain_ground"] = FileAccess.get_sha256("res://runtime/atmosphere/RainGroundPresentation.gd")
	return result

func _write_report(status: String) -> void:
	var report := {"status":status, "complete":finished, "baseline_kind":"RECONSTRUCTED_IN_MEMORY", "baseline_limit":"No historical before measurement was available because another renderer occupied the machine. This diagnostic restores the former 72-triangle fan and exact two-sine shader in memory; current production code elsewhere remains loaded. It is not a historical build comparison or automatic performance approval.", "fixture_limit":"Fishing waits indefinitely with its fixture-only negative bite timer. No landing/reeling or image readbacks. Sequential baseline/current intervals retain normal Main population and traffic; transient scene differences remain possible.", "baseline_shader":ORIGINAL_SHADER, "cases":cases, "frames_ms":intervals, "engine":Engine.get_version_info(), "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "process_id":OS.get_process_id(), "other_renderers":process_inventory, "source_before":source_start, "source_after":_sources(), "source_unchanged":source_start == _sources()}
	var output := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(report, "\t"))

func _abort(reason: String, code: int) -> void:
	tracing = false
	_write_report(reason)
	push_error("FISHING_RAIN_AB " + reason)
	quit(code)

func _timeout() -> void:
	_abort("timeout_420_seconds", 3)
