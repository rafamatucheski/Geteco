extends SceneTree
## Crash de 29/10 (runtime/NonFiniteGuard.gd): sangue com posição NaN entrava na lista alfa com profundidade NaN e o
## release crashava na ordenação. Confere que mancha, respingo, gota e marca de rastro com NaN não nascem, que a
## posição finita continua nascendo e que o registro NON_FINITE sai.
const BLOOD := preload("res://gameplay/street_physics/GroundBlood3D.gd")
const TRACKS := preload("res://gameplay/street_physics/BloodTracks3D.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	print(("CASE PASS " if ok else "CASE FAIL ") + label + " | " + detail)
	if not ok: failures.append(label)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var blood := BLOOD.new()
	stage.add_child(blood)
	var nan := Vector3(NAN, 0, 0)
	var pool: Dictionary = blood.spawn_pool(nan, true)
	check(pool.is_empty() and blood.stains.is_empty(), "poça em NaN não nasce", "stains=%d" % blood.stains.size())
	blood.spawn_drip(Vector3(0, INF, 0), .5)
	blood.spawn_splatter(nan, Vector3.FORWARD, .5)
	blood.spawn_pool(Vector3.ZERO, false, null, Vector3(NAN, 0, 1))
	check(blood.stains.is_empty(), "gota, respingo e direção NaN não nascem", "stains=%d" % blood.stains.size())
	var good: Dictionary = blood.spawn_pool(Vector3(1, 0, 2), false)
	check(not good.is_empty() and blood.stains.size() == 1, "poça finita continua nascendo", "stains=%d" % blood.stains.size())
	var tracks := TRACKS.new()
	stage.add_child(tracks)
	# Sem StreetPhysics (director) aqui: só o _emit é exercitado.
	tracks.set_physics_process(false)
	tracks._emit(nan, 0.0, Vector2(.2, .5), .5)
	tracks._emit(Vector3.ZERO, NAN, Vector2(.2, .5), .5)
	check(tracks._multimesh.visible_instance_count == 0, "marca de rastro NaN não entra no MultiMesh", "visible=%d" % tracks._multimesh.visible_instance_count)
	tracks._emit(Vector3(1, 0, 1), 0.0, Vector2(.2, .5), .5)
	check(tracks._multimesh.visible_instance_count == 1, "marca finita entra", "visible=%d" % tracks._multimesh.visible_instance_count)
	print("BLOOD_NON_FINITE failures=%d %s" % [failures.size(), str(failures)])
	quit(0 if failures.is_empty() else 1)
