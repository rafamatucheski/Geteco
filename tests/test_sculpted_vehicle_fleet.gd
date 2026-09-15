extends SceneTree

const HARBOR_LIFE := preload("res://world/harbor/HarborLife.gd")
const RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const DOOR := preload("res://prototypes/living_cast/VehicleDoor3D.gd")
const ENGINE_SOUND := preload("res://audio/VehicleEngineSound.gd")

const EXPECTED_MODELS := {
	"dune_buggy": "DuneBuggyModel.gd",
	"beach_buggy": "BeachBuggyModel.gd",
	"surf_woody_wagon": "WoodyWagonModel.gd",
	"snow_plow_truck": "SnowPlowModel.gd",
	"dock_delivery_van": "DockDeliveryVanModel.gd",
	"orbita_micro": "OrbitaMicroModel.gd",
	"aurora_executive": "AuroraExecutiveModel.gd",
	"vale_crossover": "ValeCrossoverModel.gd",
	"nimbus_minivan": "NimbusMinivanModel.gd",
	"vertice_midengine": "VerticeMidEngineModel.gd",
	"bravio_crew": "BravioCrewModel.gd",
}
const NEW_CITY_MODELS := [
	"orbita_micro", "aurora_executive", "vale_crossover",
	"nimbus_minivan", "vertice_midengine", "bravio_crew",
]
const DOOR_MODELS := [
	"surf_woody_wagon", "dock_delivery_van", "orbita_micro",
	"aurora_executive", "vale_crossover", "nimbus_minivan",
	"vertice_midengine", "bravio_crew",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var model_paths: Array[String] = []
	var signatures: Array[String] = []
	var bench := Node3D.new()
	root.add_child(bench)

	for id in EXPECTED_MODELS:
		var spec := VehicleCatalog.get_vehicle_spec(id)
		var model_path := String(spec.get("model_class", ""))
		check(String(spec.get("id", "")) == id, "%s mantém identidade própria no catálogo" % id)
		check(model_path.get_file() == EXPECTED_MODELS[id], "%s usa %s" % [id, EXPECTED_MODELS[id]])
		check(not model_paths.has(model_path), "%s tem script visual exclusivo" % id)
		model_paths.append(model_path)
		for key in ["target_length", "target_width", "mass", "max_speed", "acceleration", "braking", "turn_speed", "drift_factor", "durability"]:
			check(float(spec.get(key, 0.0)) > 0.0, "%s possui %s físico válido" % [id, key])
		check(ENGINE_SOUND.family_for_vehicle(id) == String(spec.engine_family), "%s usa família de motor %s" % [id, spec.engine_family])

		var script := load(model_path)
		check(script != null, "%s carrega o recurso visual" % id)
		if script == null:
			continue
		var model := script.new() as Node3D
		bench.add_child(model)
		var signature := String(model.get_meta("silhouette_signature", ""))
		check(not signature.is_empty() and not signatures.has(signature), "%s declara silhueta exclusiva (%s)" % [id, signature])
		signatures.append(signature)
		check(model.get("paint") is StandardMaterial3D, "%s expõe pintura para oficina" % id)
		check(model.get("originals").size() > 0, "%s registra painéis para dano reparável" % id)
		check(model.get("lamp_sources").size() >= 4, "%s possui faróis e lanternas danificáveis" % id)

		var sculpted_vertices := 0
		var wheel_centers := {}
		for child in model.get_children():
			if child is MeshInstance3D and child.material_override == model.paint and child.mesh is ArrayMesh:
				var vertices: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				sculpted_vertices = maxi(sculpted_vertices, vertices.size())
			if child.has_meta("wheel_center"):
				wheel_centers[child.get_meta("wheel_center")] = true
		check(sculpted_vertices >= 1000, "%s usa lataria contínua de alta resolução (%d vértices)" % [id, sculpted_vertices])
		check(wheel_centers.size() >= 4, "%s possui pelo menos quatro cubos autorais" % id)

		model.apply_impact(Vector3(0.0, 0.80, 0.0), Vector3.LEFT, 12.0)
		check(model.impact_count == 1, "%s aceita dano de carroceria" % id)
		model.repair()
		check(model.impact_count == 0 and model.damaged_vertices.is_empty(), "%s repara sem preservar deformação" % id)

		var rig := RIG.new()
		check(rig.mount(model), "%s monta o rig de rodas" % id)
		check(rig.pivots.size() >= 4, "%s mantém rodas articuladas após montagem" % id)
		BATCHER.batch_model(model)
		if id in DOOR_MODELS:
			var door := DOOR.new()
			model.add_child(door)
			door.configure(model, -1.0)
			check(door.extracted_triangles > 0, "%s gera porta tridimensional funcional" % id)

		bench.remove_child(model)
		model.free()

	for id in NEW_CITY_MODELS:
		check(VehicleCatalog.DISTRICT_VEHICLES.city.has(id), "%s pertence à frota urbana do catálogo" % id)
		check(HARBOR_LIFE.CAR_TYPES.has(id), "%s aparece no tráfego real do Harbor" % id)

	check(VehicleCatalog.VEHICLES.has("dock_delivery_van"), "Dock Delivery Van não depende mais do fallback do sedã")
	check(VehicleCatalog.get_vehicle_spec("dock_delivery_van").mass > 1.5, "Dock Delivery Van tem massa deliberada de utilitário")

	# Exercise the same scene/factory-facing integration used by ambient traffic.
	var traffic_scene := load("res://cars/traffic/TrafficVehicle.tscn") as PackedScene
	for id in EXPECTED_MODELS:
		var spec := VehicleCatalog.get_vehicle_spec(id)
		var vehicle := traffic_scene.instantiate()
		bench.add_child(vehicle)
		vehicle.apply_archetype(id, (spec.colors as Array)[0])
		check(vehicle.active_archetype_id == id and vehicle.is_3d_vehicle, "%s integra como TrafficVehicle 3D" % id)
		check(vehicle.body_model != null and vehicle.body_model.get_script().resource_path == spec.model_class, "%s instancia a carroceria catalogada" % id)
		var shape := vehicle.get_node("Collision").shape as RectangleShape2D
		check(is_equal_approx(shape.size.x, float(spec.target_length) * 0.82), "%s dimensiona o collider pela ficha" % id)
		bench.remove_child(vehicle)
		vehicle.free()
	bench.queue_free()
	await process_frame
	print("SCULPTED_VEHICLE_FLEET failures=%d models=%d signatures=%d" % [failures.size(), model_paths.size(), signatures.size()])
	quit(0 if failures.is_empty() else 1)
