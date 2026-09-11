extends SceneTree
const GRID := preload("res://world/harbor/CrossingNeighborhood.gd")
class Crossing:
	extends Node2D
	var road_width := 96.0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var crossings: Array = []
	for i in 150:
		var crossing := Crossing.new()
		crossing.position = Vector2(rng.randf_range(-3000,3000),rng.randf_range(-3000,3000))
		crossing.rotation = rng.randf_range(-PI,PI)
		crossing.scale = Vector2(rng.randf_range(0.5,2),rng.randf_range(0.5,2))
		root.add_child(crossing)
		crossing.add_to_group("road_crossing_area")
		crossings.append(crossing)
	var actor := Node2D.new()
	root.add_child(actor)
	var checked := 0
	for crossing in crossings:
		for point in [Vector2(-18,-88),Vector2(18,88),Vector2.ZERO,Vector2(0,87.9),Vector2(-17.9,-87.9)]:
			actor.global_position = crossing.to_global(point)
			var actual: Array = GRID.near(actor)
			if not actual.has(crossing): failures += 1
			# Toda faixa exata precisa estar presente, e a ordem deve continuar a da árvore.
			var last := -1
			for candidate in actual:
				var index := crossings.find(candidate)
				if index <= last: failures += 1
				last = index
			checked += 1
	var removed: Node = crossings.pop_back()
	removed.free()
	await physics_frame
	await process_frame
	for candidate in GRID.near(actor):
		if not is_instance_valid(candidate): failures += 1
	for crossing in crossings: crossing.free()
	actor.free()
	print("CROSSING_NEIGHBORHOOD_RESULT probes=%d failures=%d" % [checked,failures])
	quit(0 if failures == 0 else 1)
