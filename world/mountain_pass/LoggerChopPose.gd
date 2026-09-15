extends Node3D
## Two handed, target-driven chop. The blade edge never travels below the log top.
const DURATION := 3.2
const CONTACT_TIME := 1.65
var elapsed := 0.0
var target := Vector3(0,.695,1.0)
var edge := Vector3.ZERO
var grips: Array[Vector3] = []
var arms: Array[Node3D] = []
var tool: Node3D
var owner_model: Node3D

func configure(model: Node3D) -> void:
	owner_model = model
	var parts = preload("res://characters/pedestrians/CitizenDetails.gd")
	for side in [-1,1]:
		for size in [Vector3(.17,.29,.19),Vector3(.145,.29,.17),Vector3(.13,.13,.145)]:
			arms.append(parts.piece(self,size,Vector3.ZERO,model.coat_color if size.y > .2 else Color("2c3036")))
	tool = Node3D.new()
	add_child(tool)
	# Local +Z points toward the head; the cutting edge is the origin.
	parts.piece(tool,Vector3(.045,.045,.79),Vector3(0,.06,-.37),Color("856040"))
	parts.piece(tool,Vector3(.20,.12,.075),Vector3(0,.06,-.04),Color("919fa6"))
	parts.piece(tool,Vector3(.20,.018,.028),Vector3(0,.009,-.014),Color("d9e1e3"))
	hide()

func sample(time: float) -> void:
	elapsed = time
	var phase := fposmod(time,DURATION)
	var rest := target + Vector3(0,.32,-.06)
	var raised := Vector3(.035,2.08,.24)
	if phase < 1.25:
		edge = rest.lerp(raised,smoothstep(.25,1.25,phase))
	elif phase < CONTACT_TIME:
		var fall := clampf((phase-1.25)/.4,0.0,1.0)
		edge = raised.lerp(target,fall*fall)
	elif phase < 1.86:
		edge = target
	else:
		edge = target.lerp(rest,smoothstep(1.86,2.7,phase))
	# Withdraw upwards along the same cut, with a deliberate pause after impact.
	var lift := clampf((edge.y-target.y)/(raised.y-target.y),0.0,1.0)
	var direction := Vector3(0,-.28,1).normalized().lerp(Vector3(0,1,.18).normalized(),lift).normalized()
	tool.position = edge
	# Keep the blade width horizontal, its lower edge at the requested contact height.
	var across := Vector3.RIGHT
	var up := direction.cross(across).normalized()
	tool.basis = Basis(across,up,direction)
	grips.clear()
	for i in 2:
		var hand := edge + up*.06 - direction*(.73 if i==0 else lerpf(.62,.28,lift))
		grips.append(hand)
		var shoulder: Vector3 = owner_model.limbs[1 if i==0 else 3].position
		var reach := hand-shoulder
		var length := reach.length()
		var axis := reach.normalized()
		var pole := Vector3(-1 if i==0 else 1,-.4,-.3)
		var perpendicular := (pole-axis*pole.dot(axis)).normalized()
		var elbow := shoulder+reach*.5+perpendicular*sqrt(maxf(0.0,.34*.34-length*length*.25))
		_segment(arms[i*3],shoulder,elbow)
		_segment(arms[i*3+1],elbow,hand)
		arms[i*3+2].position = hand
		arms[i*3+2].basis = tool.basis

func _segment(mesh: Node3D, start: Vector3, end: Vector3) -> void:
	var axis := (end-start).normalized()
	var right := axis.cross(Vector3.FORWARD).normalized()
	mesh.position = (start+end)*.5
	mesh.basis = Basis(right,axis,right.cross(axis))
	mesh.scale.y = start.distance_to(end)/.29
