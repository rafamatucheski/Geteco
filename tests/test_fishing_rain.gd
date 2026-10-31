extends SceneTree
## Contratos isolados de água/chuva. Exige leitura de MultiMesh com renderizador real;
## o renderizador dummy do headless não consegue conferir transformações de contato/dados personalizados.
## Não certifica a aparência integrada nem FPS.
## A API real de superfície do Site roda com um polígono pequeno injetado; a construção de
## cenário/NPCs fica de fora de propósito. O RainGround ainda lança raios reais.
const WATER := preload("res://world/places/fishing/FishingWaterDynamics.gd")
const SITE := preload("res://world/places/fishing/FishingSite.gd")
const RAIN := preload("res://runtime/atmosphere/RainGroundPresentation.gd")
var POLYGON := PackedVector2Array([Vector2(-20,-15), Vector2(20,-15), Vector2(20,12), Vector2(-20,12)])
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("FISHING_RAIN ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func advance(field, seconds: float) -> void:
	for frame in ceili(seconds / WATER.STEP): field.update(WATER.STEP)

func energy(field) -> float:
	var result := 0.0
	for index in field.heights.size():
		result += field.heights[index] * field.heights[index] + field.velocities[index] * field.velocities[index]
	return result

func peak(field) -> float:
	var result := 0.0
	for height in field.heights: result = maxf(result, absf(height))
	return result

func grid_point(cell: Vector2i) -> Vector2:
	return WATER.ORIGIN + Vector2(cell) / Vector2(WATER.SIZE - Vector2i.ONE) * WATER.EXTENT

func test_field() -> void:
	@warning_ignore("integer_division")
	var center := Vector2i(WATER.SIZE.x / 2, WATER.SIZE.y / 2)
	var point := grid_point(center)
	var field = WATER.new(POLYGON)
	check(not field.active and is_zero_approx(energy(field)), "dry field starts asleep and flat")
	field.impact(point, .7, .5)
	advance(field, .2)
	check(field.impact_count == 0 and is_zero_approx(energy(field)), "a falling drop cannot disturb water before its descent delay")
	advance(field, .5)
	check(field.impact_count == 1 and peak(field) > 0.0, "the scheduled landing creates a measurable wave exactly once")
	advance(field, .2)
	check(field.impact_count == 1, "one pending drop is not applied repeatedly")

	var propagation = WATER.new(POLYGON)
	var distant := grid_point(center + Vector2i(3,0))
	propagation.impact(point, .6, 0.0)
	propagation.update(WATER.STEP)
	check(absf(propagation.height_at(distant)) < .00000001, "neighbor beyond the impact footprint starts undisturbed")
	advance(propagation, .8)
	check(absf(propagation.height_at(distant)) > .00000001, "wave propagates to a previously undisturbed neighboring cell")
	var energized := energy(propagation)
	advance(propagation, 3.0)
	check(energized > 0.0 and energy(propagation) < energized, "wave energy dissipates after rain stops")
	advance(propagation, 10.0)
	check(not propagation.active and is_zero_approx(energy(propagation)), "dry field eventually sleeps with no residual displacement or velocity")
	var asleep_count: int = propagation.impact_count
	propagation.update(60.0)
	check(not propagation.active and propagation.impact_count == asleep_count and is_zero_approx(energy(propagation)), "sleeping water remains idle during a long dry frame")

	var light = WATER.new(POLYGON)
	var heavy = WATER.new(POLYGON)
	light.impact(point, .2, 0.0)
	heavy.impact(point, .8, 0.0)
	advance(light, .3)
	advance(heavy, .3)
	check(peak(heavy) > peak(light) and peak(light) > 0.0, "stronger rainfall produces a larger wave under the same conditions")
	var outside = WATER.new(POLYGON)
	outside.impact(Vector2(1000,1000), 1.0, 0.0)
	advance(outside, .3)
	check(is_zero_approx(energy(outside)), "a point outside the water domain cannot deform the lake")

	var bounded = WATER.new(POLYGON)
	var original_cells: int = bounded.heights.size()
	for drop in WATER.MAX_PENDING * 8: bounded.impact(point, .8, .5)
	check(bounded._pending.size() <= WATER.MAX_PENDING, "a rain burst cannot grow the pending queue beyond its fixed budget")
	bounded.update(120.0)
	check(bounded.impact_count == 0, "one long frame does not fast-forward delayed rain through unbounded catch-up steps")
	advance(bounded, 1.0)
	var finite := true
	for value in bounded.heights:
		if not is_finite(value): finite = false
	check(finite and bounded.heights.size() == original_cells and bounded.velocities.size() == original_cells and bounded._next.size() == original_cells, "storm load preserves a finite fixed-size simulation grid")
	check(bounded.impact_count <= WATER.MAX_PENDING and bounded._pending.is_empty(), "bounded rain queue drains without duplicating accepted impacts")

func add_box(stage: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	stage.add_child(body)
	body.global_position = point
	return body

func one_probe(effects, point: Vector3) -> void:
	# Deterministic sample position and one budgeted probe; actual ray/contact code.
	effects._sample_bounds = AABB(point, Vector3.ZERO)
	effects._probe_index = 1
	effects._probe_budget = 1.0
	effects._tick = -1.0
	effects._physics_process(0.0)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rain contact contracts require a renderer for MultiMesh readback; omit --headless.")
		quit(2)
		return
	test_field()
	var stage := Node3D.new()
	root.add_child(stage)
	var site = SITE.new()
	site.complete = true
	site._spawn_index = SITE.NAMES.size()
	site.pond_polygon = POLYGON
	site.water_dynamics = WATER.new(POLYGON)
	stage.add_child(site)
	site.set_process(false)
	var point: Vector3 = site.to_global(Vector3(0, SITE.WATER_Y, 0))
	var initial_height: float = site.rain_surface_height_at(point)
	check(is_equal_approx(initial_height, point.y), "surface API reports the real water height in world coordinates")
	var outside: Vector3 = site.to_global(Vector3(25, SITE.WATER_Y, 0))
	site.receive_rain_impact(outside, .8, 0.0)
	check(site.water_dynamics._pending.is_empty() and not site.water_dynamics.active, "Site rejects a land impact before it enters the water queue")
	site._near = false
	site.receive_rain_impact(point, .8, 0.0)
	check(site.water_dynamics._pending.is_empty(), "nonresident lake does not schedule rainfall work")
	site._near = true
	add_box(stage, point + Vector3.DOWN * 1.5, Vector3(8,1,8))
	var effects = RAIN.new()
	stage.add_child(effects)
	effects.set_conditions(point, .8, 1.0, false)
	effects.set_process(false)
	effects.set_physics_process(false)
	effects._update_bounds()
	await physics_frame
	await physics_frame
	var cursor: int = effects._cursor
	one_probe(effects, point)
	check(effects.water_impact_count == 1 and site.water_dynamics._pending.size() == 1, "real rain ray routes a drop into water instead of the lower solid ground")
	var landing: Transform3D = effects.rings.multimesh.get_instance_transform(cursor)
	check(landing.origin.y >= initial_height and landing.origin.y < initial_height + .1, "visible contact is anchored at the water surface, above lake bottom")
	var custom: Color = effects.rings.multimesh.get_instance_custom_data(cursor)
	check(custom == effects.drops.multimesh.get_instance_custom_data(cursor) and custom.a > .5, "falling drop and splash share one water contact and arrival time")
	if not site.water_dynamics._pending.is_empty():
		check(is_equal_approx(site.water_dynamics._pending[0].w, custom.b), "water simulation receives the same delay used by the falling drop")
	advance(site.water_dynamics, custom.b * .4)
	check(site.water_dynamics.impact_count == 0 and is_zero_approx(energy(site.water_dynamics)), "rain contact remains flat while its visible drop is still falling")
	advance(site.water_dynamics, custom.b + WATER.STEP)
	check(site.water_dynamics.impact_count == 1 and peak(site.water_dynamics) > 0.0, "routed drop eventually changes actual water displacement")
	check(absf(site.rain_surface_height_at(point) - initial_height) > .00000001, "surface height query follows the displaced field used by rain")

	# Um telhado sólido real acima do mesmo ponto de água precisa ganhar o raio do primeiro acerto.
	add_box(stage, point + Vector3.UP * 3.0, Vector3(4,.2,4))
	await physics_frame
	await physics_frame
	var previous_water: int = effects.water_impact_count
	var previous_roof: int = effects.roof_impact_count
	var pending_before: int = site.water_dynamics._pending.size()
	cursor = effects._cursor
	one_probe(effects, point)
	check(effects.roof_impact_count == previous_roof + 1 and effects.water_impact_count == previous_water, "roof above water receives the rain instead of the sheltered lake")
	check(site.water_dynamics._pending.size() == pending_before, "roof hit does not enqueue an underwater rain impact")
	check(effects.rings.multimesh.get_instance_transform(cursor).origin.y > point.y + 2.0, "roof contact stays above the water rather than leaking through")
	check(effects._water_contact(outside, {}).is_empty(), "rain surface selection rejects coordinates on dry land")
	effects.set_conditions(point, 0.0, 1.0, false)
	check(not effects.is_processing() and not effects.is_physics_processing(), "dry weather stops the rain contact producer")
	advance(site.water_dynamics, 12.0)
	check(not site.water_dynamics.active and is_zero_approx(energy(site.water_dynamics)), "existing lake waves dissipate and sleep after the producer stops")
	stage.queue_free()
	for frame in 4: await process_frame
	print("FISHING_RAIN_RESULT checks=", checks, " failures=", failures, " rendered_validation=false")
	quit(0 if failures.is_empty() else 1)
