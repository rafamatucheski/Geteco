extends Control
## Gallery only: no writes to state, settings, saves or input bindings.

const PANEL := preload("MenuPanel.gd")
const WEAPONS := preload("../../gameplay/WeaponCatalog.gd")
const MISSIONS := preload("../../data/campaign/HarborMissions.gd")

var menu
var page := ""

func _ready() -> void:
	menu = PANEL.new()
	add_child(menu)
	menu.back_requested.connect(_back)
	menu.set_context("Demonstração · ações sem efeito no jogo")
	_gallery()

func _gallery() -> void:
	page = "gallery"
	menu.begin("Demonstração de apresentação")
	menu.add_action("Inventário", _inventory)
	menu.add_action("Missões", _missions)
	menu.add_action("Configurações", _settings)
	menu.add_action("Controles", _controls)
	menu.finish("Fechar demonstração")

func _inventory() -> void:
	page = "inventory"
	menu.begin("Inventário · R$ 0")
	menu.add_action(str(WEAPONS.WEAPONS.fists.label), _preview_only)
	menu.add_action("Configurações", _settings)
	menu.finish()

func _missions() -> void:
	page = "missions"
	menu.begin("Missões")
	menu.add_action(str(MISSIONS.MISSIONS.primeiro_giro.steps[0].objective), _preview_only)
	menu.add_action("Cancelar missão", _preview_only)
	menu.finish()

func _settings() -> void:
	page = "settings"
	menu.begin("Configurações")
	menu.add_volume(0.8, func(_value): pass)
	menu.add_action("Tela cheia: não", _preview_only)
	menu.add_action("Suavização: 1", _preview_only)
	menu.add_action("Restaurar controles", _preview_only)
	menu.add_action("Configurar teclas", _controls)
	menu.finish()

func _controls() -> void:
	page = "controls"
	menu.begin("Controles")
	var controls := get_node_or_null("/root/GameInput")
	if controls != null:
		for action in controls.KEYS:
			if action in ["pause_game", "inventory"]: continue
			menu.add_action(controls.label(action) + " · " + controls.hint(action, true), _preview_only)
	menu.finish()

func _preview_only() -> void:
	pass

func _back() -> void:
	if page == "gallery":
		get_tree().quit()
	elif page == "controls":
		_settings()
	else:
		_gallery()
