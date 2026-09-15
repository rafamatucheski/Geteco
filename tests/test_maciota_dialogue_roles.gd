extends SceneTree
class Visitor extends Node2D:
	var is_in_dialogue := false
	var is_control_disabled := false
var failures: Array[String] = []
var completed := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var npc := preload("res://characters/JagerNPC.gd").new()
	root.add_child(npc)
	var visitor := Visitor.new()
	root.add_child(visitor)
	npc.configure_conversation(["Dante, né?", "Cadê meu irmão?", "Calma, cara."], [], [], ["maciota", "dante", "maciota"])
	npc.conversation_completed.connect(func(): completed += 1)
	npc._try_greeting(visitor)
	check(npc.greeting_label.visible and npc.greeting_index == 1, "Arrival gets a discreet greeting")
	npc._try_greeting(visitor)
	check(npc.greeting_index == 1, "Cooldown suppresses repeated greetings")
	npc._open_dialogue()
	check(not npc.greeting_label.visible, "Dialogue suppresses arrival caption")
	npc._advance_dialogue()
	check(npc.name_label.text == "DANTE" and npc.active_speaker == "dante", "Reply belongs to Dante")
	npc._close_dialogue()
	check(completed == 0, "Interrupted dialogue does not complete contact")
	npc._open_dialogue()
	npc._advance_dialogue()
	check(npc.active_speaker == "maciota", "Maciota resumes his own lines")
	npc._advance_dialogue()
	check(completed == 1 and not npc.is_talking, "Only final advance completes the contact")
	npc.queue_free()
	visitor.queue_free()
	await process_frame
	print("MACIOTA_DIALOGUE_ROLES failures=", failures)
	quit(0 if failures.is_empty() else 1)
