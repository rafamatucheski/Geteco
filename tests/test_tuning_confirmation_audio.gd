extends SceneTree
## Drive the real authoritative workshop handler: refused purchases are silent,
## successful paid/free installation gets one routed, reusable confirmation.
const WORKSHOP := preload("res://runtime/MaciotaWorkshop.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const AUDIO := preload("res://gameplay/desert_cars/TuningConfirmationAudio.gd")
var failures: Array[String] = []
var checks := 0

class CampaignFixture extends RefCounted:
	func snapshot() -> Dictionary: return {}

class SessionFixture extends RefCounted:
	var state: Dictionary
	var world: Dictionary
	var panel := Control.new()
	var menu_closed := Callable()
	var saves := 0
	func save_game() -> bool:
		saves += 1
		return true

class PanelFixture extends CanvasLayer:
	var confirmations := 0
	var messages := 0
	func confirm_application() -> void:
		confirmations += 1
		AUDIO.play(self)
	func show_vehicle(_id, _parts, _owned, _wins, _balance, _appearance = {}) -> void: pass
	func set_message(_message) -> void: messages += 1

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var car := VEHICLE.new()
	car.archetype = "desert_coyote"
	car.vehicle_id = "tuning_confirmation_fixture"
	root.add_child(car)
	car.set_physics_process(false)
	car.set_meta("garage_place","maciota")
	var session := SessionFixture.new()
	var economy := ECONOMY.new()
	economy.grant_reward("confirmation_fixture",2000)
	session.state = {"place_id":"maciota","region_id":"harbor","world_state":{},"economy":economy,"campaign":CampaignFixture.new()}
	session.world = {"driving":{"occupied":false,"car":car},"maciota_place":{"entry_position":Vector3.ZERO},"gameplay":{"health":100}}
	root.add_child(session.panel)
	var panel := PanelFixture.new()
	root.add_child(panel)
	var workshop := WORKSHOP.new()
	workshop.session = session
	workshop.panel = panel
	workshop.tuning_car = car
	workshop.set_process(false)
	root.add_child(workshop)
	workshop._open_tuning()
	check(panel.confirmations==0 and not panel.has_node(AUDIO.PLAYER),"Initial authoritative display is silent")
	workshop._buy_part("street_cam")
	check(panel.confirmations==0 and panel.messages==1,"Locked purchase has no installation cue")
	workshop._apply_loadout({"paint":"paint_ocean"})
	check(panel.confirmations==1 and economy.balance==800,"Paid loadout emits one cue after a real successful charge")
	var voice := panel.get_node_or_null(AUDIO.PLAYER) as AudioStreamPlayer
	check(voice != null and voice.stream != null and voice.stream.get_length()>0 and voice.stream.get_length()<1.5,"Successful application uses a short playable existing cue")
	check(voice.bus==preload("res://ui/MenuAudio.gd").get_sfx_bus_name(),"Installation follows the configured menu effects bus")
	workshop._apply_loadout({"sunroof":"sunroof_glass"})
	check(panel.confirmations==1,"Insufficient balance cannot play an installation cue")
	workshop._apply_loadout({})
	var before_refit: int = economy.balance
	workshop._apply_loadout({"paint":"paint_ocean"})
	check(panel.confirmations==3 and economy.balance==before_refit,"Free owned-part refit receives exactly one confirmation too")
	workshop._buy_part("paint_pearl")
	check(panel.confirmations==3,"Rejected individual purchase stays silent")
	workshop._buy_part("paint_ocean")
	check(panel.confirmations==4,"Successful individual owned-part installation confirms")
	check(panel.get_node(AUDIO.PLAYER)==voice and panel.find_children(AUDIO.PLAYER,"AudioStreamPlayer",false,false).size()==1 and voice.max_polyphony==1,"Repeated success reuses one bounded audio voice")
	workshop.free(); panel.free(); session.panel.free(); car.free()
	print("TUNING_CONFIRMATION_AUDIO checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
