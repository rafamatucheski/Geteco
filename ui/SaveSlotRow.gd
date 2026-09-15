extends RefCounted
## A mesma ação de exclusão nos menus principal e de pausa.
static func install(owner: Node, container: VBoxContainer, button: Button, info: Dictionary, refreshed: Callable, status: Label) -> void:
	var row := HBoxContainer.new()
	container.add_child(row)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	if not info.get("exists", false): return
	var english := TranslationServer.get_locale().begins_with("en")
	var remove := Button.new()
	remove.text = "Delete" if english else "Apagar"
	remove.set_meta("delete_slot", info.slot_id)
	row.add_child(remove)
	preload("res://ui/GameStyle.gd").apply(remove)
	preload("res://ui/MenuAudio.gd").hook_button(remove, owner)
	remove.pressed.connect(func():
		var dialog := ConfirmationDialog.new()
		dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		dialog.title = "Delete save" if english else "Apagar save"
		var slot_name: String = preload("res://ui/SavePresentation.gd").slot_name(info.slot_id)
		dialog.dialog_text = ("Delete %s? This cannot be undone." if english else "Apagar %s? Esta ação não pode ser desfeita.") % slot_name
		dialog.ok_button_text = "Delete" if english else "Apagar"
		dialog.cancel_button_text = "Cancel" if english else "Cancelar"
		owner.add_child(dialog)
		dialog.canceled.connect(func():
			dialog.queue_free()
			remove.grab_focus())
		dialog.confirmed.connect(func():
			var result: Dictionary = owner.get_node("/root/SaveManager").delete_save(info.slot_id)
			dialog.queue_free()
			if result.success:
				refreshed.call()
				status.text = "Save deleted." if english else "Save apagado."
				preload("res://ui/GameStyle.gd").trap_focus.call_deferred(container.get_parent())
			else:
				status.text = ("Could not delete save: " if english else "Não foi possível apagar o save: ") + str(result.error)
				remove.grab_focus())
		dialog.popup_centered()
		dialog.get_cancel_button().grab_focus())
