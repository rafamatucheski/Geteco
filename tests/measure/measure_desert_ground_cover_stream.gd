extends SceneTree
## Quantos quadros um trecho novo do deserto leva para terminar de se vestir (fila de 1 ms por quadro),
## com e sem o chão povoado. Rodar duas vezes: GETECO_DESERT_GROUND_COVER=0 e =1.
##   tools/run_godot_locked.sh --path . --script res://tests/measure/measure_desert_ground_cover_stream.gd
## Editor/debug: o número de quadros compara as duas variantes, não é tempo de release.
const REGION := preload("res://world/desert/DesertRegion.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var results := {}
	for spot in [["truck_stop", LAYOUT.TRUCK_STOP], ["rota66_norte", Vector3(347, 0, -1150)], ["aberto", Vector3(80, 0, -1180)]]:
		var region := REGION.new()
		region.initial_focus = spot[1]
		root.add_child(region)
		var frames := 0
		var began := Time.get_ticks_msec()
		while not region.is_streaming_idle() and frames < 5000:
			await process_frame
			frames += 1
		var instances := 0
		for node in region.find_children("DesertGroundCover_*", "MultiMeshInstance3D", true, false):
			instances += (node as MultiMeshInstance3D).multimesh.instance_count
		results[spot[0]] = {"frames_to_idle": frames, "ms": Time.get_ticks_msec() - began, "chunks": region.chunks.size(), "cover_instances": instances}
		region.free()
		await process_frame
	print("DESERT_GROUND_COVER_STREAM ", OS.get_environment("GETECO_DESERT_GROUND_COVER"), " ", JSON.stringify(results))
	quit(0)
