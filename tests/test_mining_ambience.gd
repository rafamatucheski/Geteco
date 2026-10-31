extends SceneTree
## Contrato de ciclo de vida do áudio; não certifica a mistura audível nem o FPS renderizado.
const AMBIENCE := preload("res://audio/mining/MiningAmbience.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	print("MINING_AMBIENCE ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func _run() -> void:
	var site := Node3D.new()
	root.add_child(site)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 10, 8)
	site.add_child(camera)
	camera.make_current()
	for cavern in [true, false]:
		var sound := AMBIENCE.new()
		sound.cavern = cavern
		site.add_child(sound)
		var kind := "gallery" if cavern else "crusher"
		_check(sound._bed.stream != null and sound._bed.stream.get_length() > 0, kind + " recorded bed loaded")
		_check(sound._details.size() == 3 and not sound._details.has(null), kind + " structural cues loaded")
		_check(sound._bed.playing and sound.get_child_count() == 2, kind + " starts with only two positional voices")
		# Exercita um detalhe vivo exatamente no momento da suspensão, não só um
		# canal já ocioso. Isso pega sons vazando de uma sala vazia.
		sound._detail_clock = 0
		sound._process(.3)
		_check(sound._detail.playing, kind + " structural cue actually started")
		sound.set_active(false)
		_check(not sound._bed.playing and not sound._detail.playing and not sound.is_processing(), kind + " explicit room suspension stops both voices and updates")
		sound.set_active(true)
		_check(sound._bed.playing, kind + " reentry resumes existing bed")
		site.hide()
		_check(not sound._bed.playing and not sound._detail.playing, kind + " inherited world visibility stops audio immediately")
		site.show()
		_check(sound._bed.playing, kind + " exterior return resumes bed")
		camera.position.x = 200
		sound._process(.3)
		_check(not sound._bed.playing and not sound._detail.playing, kind + " distant site is silent")
		camera.position.x = 0
		sound._process(.3)
		_check(sound._bed.playing, kind + " nearby return reuses channels")
		var bed_ref: WeakRef = weakref(sound._bed)
		var detail_ref: WeakRef = weakref(sound._detail)
		sound.free()
		_check(bed_ref.get_ref() == null and detail_ref.get_ref() == null, kind + " unloading frees both audio channels")
	site.free()
	print("MINING_AMBIENCE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
