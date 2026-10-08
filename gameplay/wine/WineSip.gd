extends Node3D
## Small finite presentation, world-owned so death/transitions cannot leave a prop.
var player: Node3D
var session
var tint:=Color("7c213b")
var elapsed:=0.0
var glass: Node3D
var start_health:=100.0
var start_place:=""
func _ready() -> void:
	name="WineSip"
	if session!=null:
		start_health=session.world.gameplay.health
		start_place=session.state.place_id
	glass=Node3D.new(); add_child(glass)
	_cylinder(0.025,0.025,0.17,Vector3(0,0.105,0),Color("c7cec8"))
	_cylinder(0.075,0.075,0.015,Vector3(0,0.018,0),Color("c7cec8"))
	_cylinder(0.075,0.045,0.13,Vector3(0,0.245,0),Color("adb7b3"))
	_cylinder(0.069,0.048,0.07,Vector3(0,0.25,0),tint)
	set_process(true)
func _process(delta: float) -> void:
	if not is_instance_valid(player) or not player.visible or elapsed>2.0 or player.get_meta("wine_cancel_sip",false): queue_free(); return
	if session!=null and (session.world.gameplay.health<start_health or session.is_transition_blocked() or session.world.driving.occupied or session.state.place_id!=start_place or session.state.equipped_weapon!="fists"):
		queue_free(); return
	elapsed+=delta
	var visual: Node3D=player.get("visual")
	global_transform=Transform3D(visual.global_basis.orthonormalized(),player.global_position) if is_instance_valid(visual) else player.global_transform
	var lift:=sin(clampf(elapsed/2.0,0,1)*PI)
	glass.position=Vector3(0.2-0.1*lift,0.85+0.45*lift,-0.24)
	glass.rotation.z=-0.35*lift
	if player.has_method("pose_seated_limbs"):
		var grip_global:=glass.to_global(Vector3(0,0.12,0))
		var grip:=Transform3D(player.global_basis.inverse()*glass.global_basis,player.to_local(grip_global))
		player.pose_seated_limbs({}, {"Right":grip})
func _cylinder(top: float, bottom: float, height: float, point: Vector3, color: Color) -> void:
	var mesh:=CylinderMesh.new(); mesh.top_radius=top; mesh.bottom_radius=bottom; mesh.height=height; mesh.radial_segments=10
	var node:=MeshInstance3D.new(); node.mesh=mesh; node.position=point; node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=0.28; mat.metallic=0.2
	node.material_override=mat; glass.add_child(node)
