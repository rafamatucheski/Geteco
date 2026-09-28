extends "res://gameplay/urban_v1/PortWorker.gd"
var points := PackedVector3Array()
var point_index := 0
var fishing := false
var fishing_clock := 0.0
var rod: Node3D
var fishing_line: MeshInstance3D

func _build_model() -> void:
	model = preload("res://assets/CivilianModel.gd").new()
	model.appearance_locked = true
	model.appearance_variant = int(definition.get("worker_index",0))+380
	model.coat_color = definition.get("coat_color",Color("7d8474"))
	model.pants_color = Color("34434a")
	model.wardrobe_overrides = {"top":1,"bottom":0,"shoe":1,"hat":1 if fishing else 0,"backpack":not fishing,"bag":0}
	add_child(model)
	if fishing:
		rod = Node3D.new()
		rod.position = Vector3(.12,1.02,.38)
		model.add_child(rod)
		var art := preload("res://world/regions/PortLifeArt.gd").new()
		rod.add_child(art)
		art.box(Vector3(0,.55,1),Vector3(.025,.025,2.3),"34494c",false,Basis(Vector3.RIGHT,-.5))
		art.box(Vector3(0,-.08,.12),Vector3(.11,.14,.11),"607c82")
		art.flush()
		fishing_line=MeshInstance3D.new()
		var thread:=BoxMesh.new()
		thread.size=Vector3(.009,.009,1)
		fishing_line.mesh=thread
		fishing_line.material_override=art.mat("b2b3a0")
		fishing_line.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fishing_line)
		model.hand_provider = _fishing_hands

func _ready() -> void:
	super._ready()
	if gameplay != null:
		var reaction = preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(self,model,gameplay)
		if reaction != null: reaction.react_to_aim = true
		if reaction!=null and fishing:
			reaction.threat_started.connect(func(_actor): fishing_line.hide())

func receive_damage(amount: float, source: Node = null) -> void:
	super.receive_damage(amount,source)
	if dead and is_instance_valid(fishing_line): fishing_line.hide()

func _tick_mountain_routine(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	if fishing:
		model.rotation.y=PI if int(definition.get("worker_index",0))==0 else 0.0
		fishing_line.show()
		fishing_clock = fposmod(fishing_clock+delta,26.0)
		activity = "fish"
		# Cast, wait, reel, inspect; each post starts at a different phase.
		rod.rotation.x = -.45*sin(fishing_clock*PI/3.0) if fishing_clock<3 else (.08*sin(fishing_clock*3.0) if fishing_clock>20 else .015*sin(fishing_clock))
		var tip:=rod.to_global(Vector3(0,1.10,2.0))
		var water: Vector3=model.to_global(Vector3(.12,0,3.4))
		water.y=.025
		var span:=water-tip
		fishing_line.global_transform=Transform3D(Basis.looking_at(span.normalized()).scaled_local(Vector3(1,1,span.length())),(water+tip)*.5)
		return
	if point_index >= points.size(): activity = "idle"; return
	var offset := points[point_index]-global_position
	offset.y = 0
	if offset.length()<.22: point_index += 1; return
	var direction := offset.normalized()*1.55
	velocity.x = direction.x
	velocity.z = direction.z
	activity = "walk"

func _fishing_hands() -> Array:
	if dead or get_meta("workplace_threatened",false): return [null,null]
	return [model.to_global(Vector3(-.12,1.0,.42)),model.to_global(Vector3(.14,1.03,.55))]
