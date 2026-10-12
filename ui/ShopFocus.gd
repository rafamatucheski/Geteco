extends RefCounted
## Explicit, cyclic order; disabled and hidden actions never trap the controller.
static func rebuild(container: Control) -> void:
	var buttons: Array[Button] = []
	for node in container.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and not node.disabled:
			buttons.append(node)
	if buttons.is_empty(): return
	for i in buttons.size():
		var button := buttons[i]
		var previous := button.get_path_to(buttons[posmod(i - 1, buttons.size())])
		var next := button.get_path_to(buttons[(i + 1) % buttons.size()])
		button.focus_neighbor_top = previous
		button.focus_neighbor_bottom = next
		button.focus_neighbor_left = previous
		button.focus_neighbor_right = next
		button.focus_previous = previous
		button.focus_next = next
	var focused := container.get_viewport().gui_get_focus_owner()
	if focused not in buttons: buttons[0].grab_focus()
