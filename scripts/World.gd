extends Node3D
## Cena principal. O ProductionWorld monta o mundo e preenche os campos abaixo (jogador, câmera,
## região em `street`, direção, HUD). O protótipo antigo (--sandbox/--slice: Street, Traffic,
## RouteActivity, V2Session) saiu em 18/10/2026; nenhum runner ou teste ainda o usava.
const GAMEPLAY_HUD := preload("res://ui/ClassicGameplayHUD.gd")
var player: CharacterBody3D
var camera: Camera3D
var street: Node3D
var people: Array[CharacterBody3D] = []
var population := 100
var diagnostic_label: Label
var pause_panel: CanvasLayer
var hud: CanvasLayer
var stats_clock := 0.0
var driving: Node
var traffic: Node3D
var maciota_place: Node3D
var session: Node
var gameplay: Node3D
var production: Node
var dispatch: Node3D
var traffic_yield: Node

func _ready() -> void:
	# Absolute aiming, confined so an invisible cursor cannot click another window.
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	seed(21092026)
	production = preload("res://runtime/ProductionWorld.gd").new()
	production.world = self
	add_child(production)
	production.build.call_deferred()

func set_population(count: int) -> void:
	if production != null: production.set_population(count)

func _build_hud() -> void:
	hud = GAMEPLAY_HUD.new()
	hud.world = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	diagnostic_label = Label.new()
	diagnostic_label.position = Vector2(26,160)
	diagnostic_label.visible = false
	hud.add_child(diagnostic_label)
	pause_panel = preload("res://ui/PauseMenu.tscn").instantiate()
	pause_panel.world = self
	add_child(pause_panel)
	# Only this small UI handler processes while paused.
	var handler := Node.new()
	handler.set_script(preload("res://scripts/PauseInput.gd"))
	handler.world = self
	handler.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(handler)
	# The loaded world is promoted in place by SkyMenu. Its touch layer must
	# exist before the handoff; SkyMenu hides and suspends it with the HUD.
	if OS.has_feature("android") or "--touch-controls" in OS.get_cmdline_user_args():
		var touch_layer := CanvasLayer.new()
		touch_layer.layer = 90
		add_child(touch_layer)
		var touch := preload("res://ui/AndroidControls.gd").new()
		touch.world = self
		touch_layer.add_child(touch)

func _toggle_pause() -> void:
	if session != null and session.get("modal") == true: return
	pause_panel.toggle()

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.world.process", span, 3000)

func _process_traced(delta: float) -> void:
	if diagnostic_label == null: return
	stats_clock += delta
	if stats_clock < 0.5: return
	stats_clock = 0
	if diagnostic_label.visible:
		diagnostic_label.text = "%d FPS · %d pessoas\n[ / ]  diminuir / aumentar pessoas" % [Engine.get_frames_per_second(),population]
