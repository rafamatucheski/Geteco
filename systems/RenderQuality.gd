extends Node
## Configure streamed viewports and one shadow-casting key light per 3D world.

func _ready() -> void:
	get_tree().root.msaa_2d = Viewport.MSAA_DISABLED
	get_tree().node_added.connect(_configure_node)
	get_parent().display_settings_changed.connect(_refresh_quality)

func _configure_node(node: Node) -> void:
	if node is SubViewport:
		_configure_viewport(node)
	elif node is Sprite2D:
		_configure_display.call_deferred(node)
	elif node is DirectionalLight3D:
		_configure_light.call_deferred(node)

func _configure_viewport(viewport: SubViewport) -> void:
	if not viewport.has_meta("authored_msaa"):
		viewport.set_meta("authored_msaa", int(viewport.msaa_3d))
	viewport.add_to_group("quality_viewports")
	if viewport.disable_3d:
		if viewport.msaa_2d == Viewport.MSAA_DISABLED:
			viewport.msaa_2d = Viewport.MSAA_2X
	else:
		viewport.msaa_3d = maxi(int(viewport.get_meta("authored_msaa")), get_parent().msaa_3d) as Viewport.MSAA

func _refresh_quality() -> void:
	get_tree().root.msaa_3d = get_parent().msaa_3d as Viewport.MSAA
	for viewport in get_tree().get_nodes_in_group("quality_viewports"):
		_configure_viewport(viewport)
		# Cached props need a single new render after a quality change.
		if viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _configure_light(light) -> void:
	if not is_instance_valid(light) or not light.is_inside_tree(): return
	var viewport := light.get_viewport() as SubViewport
	if viewport == null: return
	var key: WeakRef = viewport.get_meta("shadow_key") if viewport.has_meta("shadow_key") else null
	if key != null and is_instance_valid(key.get_ref()): return
	viewport.set_meta("shadow_key", weakref(light))
	# Animated humans use the live silhouette; reserve shadow maps for props/rooms.
	if viewport.get_parent() is CharacterBody2D: return
	if viewport.render_target_update_mode not in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED]: return
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL

	var camera := viewport.get_camera_3d()
	if camera:
		light.directional_shadow_max_distance = camera.position.length() + (camera.size * 2.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 6.0)
		light.shadow_bias = 0.02
		light.shadow_normal_bias = 0.1

func _configure_display(display) -> void:
	if not is_instance_valid(display) or not display.is_inside_tree(): return
	if display.name == "PoseShadow" or display.name == "VehicleShadow": return
	var host: Node = display.get_parent()
	var viewport: SubViewport
	# Explicit production display contracts; never flatten a whole interior/UI.
	if host.get("sprite_3d_display") == display or host.get("presentation_sprite") == display or (host is CharacterBody2D and host.get("display") == display):
		viewport = host.get("viewport_3d") as SubViewport
		if viewport == null: viewport = host.get("viewport") as SubViewport
	elif (host.get("sprite") == display or host.get("visual") == display) and (host.get("body_viewport") is SubViewport or host.get("viewport_3d") is SubViewport or host.get("viewport") is SubViewport):
		viewport = host.get("body_viewport") as SubViewport
		if viewport == null: viewport = host.get("viewport_3d") as SubViewport
		if viewport == null: viewport = host.get("viewport") as SubViewport
		if viewport != null and viewport.transparent_bg:
			var footprint: Vector2 = host.get("footprint") if host.get("footprint") is Vector2 else Vector2.ZERO
			preload("res://systems/ContactShadow.gd").add_vehicle_silhouette(display, viewport, footprint)
		return
	elif host.get("lamp_sprite") == display:
		return
	elif host.get("sprite_3d") == display and host.has_method("project_floor"):
		viewport = host.get("viewport_3d") as SubViewport
		if viewport != null and host.get("model") is Node3D:
			preload("res://systems/StaticGroundShadow.gd").build(host,host.model,viewport)
		return
	if viewport == null or not viewport.transparent_bg: return
	preload("res://systems/ContactShadow.gd").add_silhouette(display,viewport)
