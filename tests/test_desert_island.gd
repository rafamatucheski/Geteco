extends SceneTree
## Ilha do deserto (etapa 2 do mundo orgânico, 26/10/2026): as cordilheiras de horizonte cabem dentro da
## ilha. Todo vértice acima da água fica na ilha do deserto, antes da praia e fora da área jogável; a
## crista norte (horizonte da câmera da arrancada) continua alta. Não abre o jogo.
## Uso: "$GODOT" --headless --path . --script res://tests/test_desert_island.gd
const RELIEF := preload("res://world/desert/DesertHorizonRelief.gd")
const SHAPE := preload("res://world/shape/WorldShape.gd")
const L := preload("res://world/desert/DesertLayout.gd")
## A parede das fileiras se desloca alguns metros além do pé calculado; a praia tem 18 m.
const BEACH_TOLERANCE := 10.0
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> bool:
	checks += 1
	print("DESERT_ISLAND ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func _initialize() -> void:
	var relief: Node3D = RELIEF.build()
	var outside := 0
	var on_beach := 0
	var inside_play := 0
	var north_top := 0.0
	var south_top := 0.0
	var worst := Vector2.ZERO
	for mesh: MeshInstance3D in relief.get_children():
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in vertices:
			if v.y < -.5: continue
			var p := Vector2(v.x, v.z)
			if SHAPE.island_at(p) != "desert": outside += 1; worst = p
			elif SHAPE.signed_distance(p) < RELIEF.BEACH - BEACH_TOLERANCE: on_beach += 1
			if L.BOUNDS.grow(-1.0).has_point(p): inside_play += 1
			if p.y < L.BOUNDS.position.y: north_top = maxf(north_top, v.y)
			if p.y > L.BOUNDS.end.y: south_top = maxf(south_top, v.y)
	check(outside == 0, "nenhum vértice das cordilheiras fora da ilha do deserto (%d fora, ex. %s)" % [outside, worst])
	check(on_beach == 0, "cordilheiras param antes da praia (%d vértices a menos de %.0f m da costa)" % [on_beach, RELIEF.BEACH - BEACH_TOLERANCE])
	check(inside_play == 0, "nenhum vértice dentro da área jogável (%d)" % inside_play)
	check(north_top > 80.0, "crista norte segue alta para o horizonte da arrancada (%.0f m)" % north_top)
	print("DESERT_ISLAND crista sul até %.0f m (o canal até Harbor fica livre)" % south_top)
	relief.free()
	print("DESERT_ISLAND checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
