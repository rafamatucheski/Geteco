extends SceneTree
## O índice espacial de RailwayWorld._guard_inside_corridor (16/10/2026) precisa responder exatamente o
## que a varredura de todos os descritores respondia: guarda omitida só onde entra em outro corredor.
## Compara as duas respostas em todo ponto de guarda testado pela montagem dos trechos, mais uma grade
## densa na área da junção.
const RAILWAY := preload("res://world/railway/RailwayWorld.gd")

func _initialize() -> void: _run.call_deferred()

static func _brute(railway: Node3D, point: Vector3) -> bool:
	if point.x<330.0 or point.x>475.0 or point.z> -184.0 or point.z< -280.0: return false
	for rows in railway._descriptors.values():
		for row in rows:
			if point.x<minf(row.a.x,row.b.x)-3.0 or point.x>maxf(row.a.x,row.b.x)+3.0: continue
			if point.z<minf(row.a.z,row.b.z)-3.0 or point.z>maxf(row.a.z,row.b.z)+3.0: continue
			if point.distance_to(Geometry3D.get_closest_point_to_segment(point,row.a,row.b))<3.0: return true
	return false

func _run() -> void:
	var railway: Node3D = RAILWAY.new()
	railway._prepare_descriptors()
	var points: Array[Vector3] = []
	for rows in railway._descriptors.values():
		for row in rows:
			var a: Vector3 = row.a
			var b: Vector3 = row.b
			var right := (b-a).normalized().cross(Vector3.UP).normalized()
			for side in [-1.0, 1.0]:
				for fraction in [0.0, .25, .5, .75, 1.0]:
					points.append((a+right*3.30*side).lerp(b+right*3.30*side, fraction))
	for x in range(326, 480, 2):
		for z in range(-284, -180, 2):
			for y in [0.0, 12.0]:
				points.append(Vector3(x, y, z))
	var mismatches := 0
	var omitted := 0
	for point in points:
		var expected := _brute(railway, point)
		var actual: bool = railway._guard_inside_corridor(point)
		if expected: omitted += 1
		if expected != actual:
			mismatches += 1
			if mismatches <= 5: print("MISMATCH ", point, " esperado=", expected, " indice=", actual)
	railway.free()
	print("railway corridor index: pontos=%d omitidos=%d divergencias=%d" % [points.size(), omitted, mismatches])
	# A área da junção tem que ter omissões de verdade, senão o teste não exercita nada.
	quit(0 if mismatches == 0 and omitted > 0 else 1)
