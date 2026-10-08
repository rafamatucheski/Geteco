extends Node
## Harbor owns this exterior; the fishing controller owns its attempt and ledger.
const SITE := preload("res://world/places/fishing/FishingSite.gd")
var session
var site: Node3D
var _clock := 0.0

func _ready() -> void:
	name = "FishingRuntime"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	refresh()

func _process(delta: float) -> void:
	_clock += delta
	if _clock < .35: return
	_clock = 0.0
	refresh()

func refresh() -> void:
	if session == null or not is_instance_valid(session.world.player): return
	var point: Vector3 = session.world.player.global_position
	var distance := Vector2(point.x-SITE.ANCHOR.x,point.z-SITE.ANCHOR.z).length()
	var outdoors: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	if not outdoors or distance > 250.0:
		_release()
		return
	if not is_instance_valid(site) and distance < 185.0:
		var began := Time.get_ticks_usec()
		site = SITE.new()
		session.world.add_child(site)
		site.bind_gameplay(session.world.gameplay)
		session.fishing.site = site
		set_meta("last_install_ms",float(Time.get_ticks_usec()-began)/1000.0)
	if is_instance_valid(site): site.set_focus(point)

func _release() -> void:
	if session != null and is_instance_valid(session.fishing):
		session.fishing.cancel_attempt("Pesca encerrada ao sair do lago.")
		session.fishing.site = null
	if is_instance_valid(site): site.queue_free()
	site = null

func _exit_tree() -> void:
	_release()
