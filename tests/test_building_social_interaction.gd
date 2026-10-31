extends SceneTree
## Linha de visão física e posse da conversa. A entrada pela FullSession, as reações
## vivas dos NPCs e a apresentação renderizada são cobertas pela rodada de sessão separada.
const SOCIAL := preload("res://runtime/BuildingSocialInteraction.gd")

class Player extends CharacterBody3D:
	var input_locked := false

class Gameplay extends Node:
	signal player_wounded(lethal: bool)
	signal police_warning_issued
	signal npc_gunfire(origin: Vector3, direction: Vector3, shooter: Node3D)
	signal explosion_occurred(origin: Vector3, radius: float, source: Node)
	var health := 100.0
	var stars := 0
	var surrendered := false
	func police_surrendering() -> bool: return surrendered

class Driving extends Node:
	var occupied := false

class Entrance extends Node:
	var inside := true
	func in_building() -> bool: return inside

class Room extends Node3D:
	var occupants: Node
	var floor_index := 0

class Occupants extends Node3D:
	var residents: Array[Node3D] = []

class Reaction extends Node:
	signal threat_started(actor: Node3D)

class Resident extends CharacterBody3D:
	var dead := false
	var available := true
	var talking := false
	var action_count := 0
	var end_count := 0
	var physics_ticks := 0
	func _ready() -> void:
		add_to_group("building_resident")
		var reaction := Reaction.new()
		reaction.name = "WorkplaceThreatReaction"
		add_child(reaction)
	func _physics_process(_delta: float) -> void:
		physics_ticks += 1
	func social_snapshot() -> Dictionary:
		return {"name":"Lia", "state":"happy" if action_count > 0 else "neutral", "mood_label":"Feliz" if action_count > 0 else "Tranquila", "can_interact":available and not dead}
	func social_options() -> Array:
		var result: Array = []
		for id in ["greet", "chat", "joke", "reassure", "intimidate"]: result.append({"id":id,"enabled":true})
		return result
	func begin_social(_player: Node3D) -> bool:
		talking = available
		return talking
	func end_social() -> void:
		talking = false
		end_count += 1
	func social_interact(action: String, _player: Node3D) -> Dictionary:
		action_count += 1
		if action == "intimidate":
			available = false
			get_node("WorkplaceThreatReaction").threat_started.emit(self)
		return {"ok":true, "line":"Bom te ver." if action != "intimidate" else "Sai de perto!"}

class World extends Node3D:
	var player: Player
	var gameplay: Gameplay
	var driving: Driving
	var hud: CanvasLayer

class Session extends Node:
	var world: World
	var room: Room
	var building_entrance: Entrance
	var building_social: Node
	var ready_for_play := true
	var modal := false
	var rescue_pending := false
	var arrest_pending := false
	var transition_generation := 0
	var blocked := false
	var state := {"place_id":"harbor_building_test"}
	var panel := PanelContainer.new()
	var menu_closed := Callable()
	var last_message := ""
	func is_transition_blocked() -> bool: return blocked
	func _menu(_title: String) -> void:
		if building_social.active: building_social.close()
		modal = true
		world.player.input_locked = true
		panel.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	func close_menu() -> void:
		if menu_closed.is_valid(): menu_closed.call()
		menu_closed = Callable()
		modal = false
		panel.hide()
		world.player.input_locked = world.gameplay.health <= 0 or blocked or rescue_pending or arrest_pending
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	func show_message(value: String) -> void: last_message = value
	func show_speech(_speaker: String, value: String, _duration := 5.0, _play_voice := true, _persona := "", _canonical := "", _character_id := "", _section := "") -> void: last_message = value

var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("BUILDING_SOCIAL_UI ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func event(action: String) -> InputEventAction:
	var result := InputEventAction.new()
	result.action = action
	result.pressed = true
	return result

func run() -> void:
	var world := World.new()
	root.add_child(world)
	world.player = Player.new()
	world.gameplay = Gameplay.new()
	world.driving = Driving.new()
	world.hud = CanvasLayer.new()
	for child in [world.player, world.gameplay, world.driving, world.hud]: world.add_child(child)
	var session := Session.new()
	session.world = world
	world.add_child(session)
	world.hud.add_child(session.panel)
	session.room = Room.new()
	world.add_child(session.room)
	session.room.occupants = Occupants.new()
	session.room.add_child(session.room.occupants)
	session.building_entrance = Entrance.new()
	session.add_child(session.building_entrance)
	var resident := Resident.new()
	resident.position = Vector3(1.5, 0, 0)
	session.room.occupants.add_child(resident)
	session.room.occupants.residents.append(resident)
	var controller = SOCIAL.new()
	controller.session = session
	session.building_social = controller
	session.add_child(controller)
	await physics_frame
	check(controller.nearest_action().get("target") == resident, "Nearby same-floor resident publishes a conversation")
	world.player.position.y = -3
	check(not controller.open(resident) and controller.nearest_action().is_empty(), "A resident on another floor cannot be reached")
	world.player.position = Vector3.ZERO
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(.75, 1, 0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.2, 2, 2)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	check(not controller.open(resident) and controller.nearest_action().is_empty(), "The actual solid wall prevents conversation through a cutaway")
	wall.queue_free()
	await physics_frame
	await physics_frame
	world.player.input_locked = true
	check(not controller.open(resident), "Another owner of player control is preserved")
	world.player.input_locked = false
	world.gameplay.stars = 1
	check(not controller.open(resident), "Pursuit cannot be suspended by opening conversation")
	world.gameplay.stars = 0
	world.gameplay.surrendered = true
	check(not controller.open(resident), "Surrender retains input ownership")
	world.gameplay.surrendered = false
	session.state.place_id = "maciota"
	check(not controller.open(resident), "Garage residents are outside social enrollment")
	session.state.place_id = "harbor_building_test"
	check(controller.open(resident), "Valid approach opens the real conversation panel")
	check(controller.active and session.modal and world.player.input_locked and resident.talking, "Conversation owns input and resident attention")
	var screen := root.get_visible_rect().size
	controller.panel.set_conversation_anchor(Vector2(screen.x * .75, screen.y * .5))
	check(controller.panel.card.get_rect().end.x < screen.x * .75 and controller.panel.card.position.x < screen.x * .5, "Conversation docks left when both people stand on the right")
	controller.panel.set_conversation_anchor(Vector2(screen.x * .25, screen.y * .5))
	check(controller.panel.card.position.x > screen.x * .5, "Conversation docks right when both people stand on the left")
	var ticks_before := resident.physics_ticks
	await physics_frame
	await physics_frame
	check(not paused and resident.physics_ticks > ticks_before, "Conversation never pauses resident physics or the world")
	check(controller.handle_input(event("fire")) and controller.blocks_gameplay_input(), "Combat presses are consumed while talking")
	check(not controller.handle_input(event("ui_accept")), "Keyboard and gamepad accept reach focused buttons")
	controller.panel.buttons.greet.pressed.emit()
	check(resident.action_count == 1 and controller.panel.reply_label.text == "Bom te ver." and controller.panel.mood_label.text == "Feliz", "Choosing a greeting presents the NPC response and mood")
	await process_frame
	controller.panel.buttons.chat.grab_focus()
	controller.panel.present(resident.social_snapshot(), resident.social_options())
	check(root.gui_get_focus_owner() == controller.panel.buttons.chat, "Routine mood refresh preserves the selected keyboard/controller action")
	var waiting: Array = resident.social_options()
	for option: Dictionary in waiting: option.enabled = false
	controller.panel.present(resident.social_snapshot(), waiting)
	check(root.gui_get_focus_owner() == controller.panel.close_button, "Cooldown keeps a usable close action focused")
	controller.panel.present(resident.social_snapshot(), resident.social_options())
	var old_events := InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var remapped := InputEventKey.new()
	remapped.physical_keycode = KEY_P
	InputMap.action_add_event("interact", remapped)
	controller.panel.buttons.chat.grab_focus()
	remapped.pressed = true
	controller.handle_input(remapped)
	check(resident.action_count == 2, "The remapped interaction key activates the focused choice")
	remapped.echo = true
	controller.handle_input(remapped)
	check(resident.action_count == 2, "Key repeat cannot spam conversation choices")
	InputMap.action_erase_events("interact")
	for binding in old_events: InputMap.action_add_event("interact", binding)
	check(controller.handle_input(event("ui_cancel")) and not controller.active and not session.modal and not world.player.input_locked and not resident.talking, "Cancel releases the panel, input, and resident attention")
	check(controller.open(resident), "Reentry is possible after cancellation")
	check(not controller.handle_input(event("pause_game")) and not controller.active, "Pause dismisses conversation and reaches the normal pause handler")
	check(controller.open(resident), "Conversation resumes after pause cancellation")
	paused = true
	controller._process(.2)
	check(not controller.active and not world.player.input_locked and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "External pause also releases ownership and preserves its pointer")
	paused = false
	controller.open(resident)
	world.gameplay.npc_gunfire.emit(Vector3(2, 0, 0), Vector3.RIGHT, null)
	check(not controller.active and not world.player.input_locked, "Nearby external gunfire interrupts immediately")
	controller.open(resident)
	world.gameplay.player_wounded.emit(false)
	check(not controller.active, "Incoming wounds interrupt immediately")
	controller.open(resident)
	world.gameplay.explosion_occurred.emit(Vector3(2, 0, 0), 3.0, null)
	check(not controller.active, "Nearby explosions interrupt immediately")
	controller.open(resident)
	controller.choose("intimidate")
	check(not controller.active and session.last_message == "Sai de perto!", "A synchronous threat closes safely and preserves the NPC response")
	resident.available = true
	controller.open(resident)
	world.player.position.x = 8
	controller._process(.2)
	check(not controller.active and not world.player.input_locked, "Moving outside conversation range restores control")
	world.player.position = Vector3.ZERO
	controller.open(resident)
	session.room.floor_index = 1
	controller._process(.2)
	check(not controller.active, "A floor replacement invalidates the conversation")
	session.room.floor_index = 0
	controller.open(resident)
	session.transition_generation += 1
	session.blocked = true
	controller._process(.2)
	check(not controller.active and world.player.input_locked, "A transition retains its own lock when conversation ends")
	session.blocked = false
	world.player.input_locked = false
	controller.open(resident)
	session.menu_closed = Callable()
	controller._process(.2)
	check(not controller.active and session.modal and world.player.input_locked, "A replacement modal retains ownership")
	session.close_menu()
	controller.open(resident)
	Input.action_press("fire")
	controller.panel.close_button.pressed.emit()
	check(not controller.active and controller.blocks_gameplay_input(), "Holding a mouse click across close cannot fire a weapon")
	Input.action_release("fire")
	controller._process(.01)
	check(not controller.blocks_gameplay_input() and not controller.is_processing(), "Releasing the held fire input restores play and stops idle processing")
	controller.open(resident)
	world.gameplay.health = 0
	controller._process(.2)
	check(not controller.active and world.player.input_locked, "Death preserves the rescue lock")
	world.gameplay.health = 100
	world.player.input_locked = false
	controller.open(resident)
	resident.queue_free()
	await process_frame
	controller._process(.2)
	check(not controller.active and not world.player.input_locked, "Removed residents leave no stale interaction or input lock")
	check(world.gameplay.npc_gunfire.get_connections().is_empty() and world.gameplay.player_wounded.get_connections().is_empty(), "Cancellation disconnects temporary danger listeners")
	world.queue_free()
	await process_frame
	print("BUILDING_SOCIAL_UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
