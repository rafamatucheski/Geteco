extends SceneTree
## MovieWriter grava reprodução natural, sem seek. Duração máxima evita travamento.
var started:=0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720); root.content_scale_size=root.size
	var opening: Control=load("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.allow_skip=false
	opening.finished.connect(func(_destination):
		print("OPENING_V3_MOVIE_COMPLETE")
		quit())
	root.add_child(opening)
	started=Time.get_ticks_msec()
