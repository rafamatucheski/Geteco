extends Node3D
## A direção assistida mantém os controles do arrancadão. Os corpos ainda são donos de cada metro e
## portão: um carro bloqueado não pode avançar a rota nem receber tempo de chegada.
const TURN_AT := 760.0
const RADIUS := 3.4
const ARC := PI*RADIUS
const LENGTH := TURN_AT*2.0+ARC
const PROGRESS=preload("res://activities/desert_drag/DesertDragProgress.gd")
var start := Vector3.ZERO
var forward := Vector3.RIGHT
var side := Vector3.BACK

func configure(at: Vector3, heading: Vector3) -> void:
	start=at
	forward=heading
	side=forward.cross(Vector3.UP).normalized()
	var barrel := StaticBody3D.new()
	barrel.name="TurnBarrel"
	barrel.position=start+forward*TURN_AT-Vector3.UP*.08
	barrel.collision_layer=1
	barrel.collision_mask=0
	add_child(barrel)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius=.34
	cylinder.height=.92
	shape.shape=cylinder
	shape.position.y=.46
	barrel.add_child(shape)
	for item in [[.46,.92,.34,Color("d95a29")],[.22,.07,.35,Color("eee1b4")],[.70,.07,.35,Color("eee1b4")],[.94,.035,.35,Color("45403a")]]:
		var mesh := MeshInstance3D.new()
		var drum := CylinderMesh.new()
		drum.top_radius=item[2]
		drum.bottom_radius=item[2]
		drum.height=item[1]
		drum.radial_segments=20
		mesh.mesh=drum
		mesh.position.y=item[0]
		var paint := StandardMaterial3D.new()
		paint.albedo_color=item[3]
		paint.roughness=.82
		mesh.material_override=paint
		barrel.add_child(mesh)

func prepare(entry: Dictionary, lane: int) -> void:
	entry.return_lane=2.0 if lane==0 else -2.0
	entry.return_progress=0.0
	entry.return_gate=0
	entry.return_angle=0.0

func point_at(metres: float, lane: float) -> Vector3:
	if metres<TURN_AT:
		return start+forward*metres+side*lerpf(lane,-RADIUS,smoothstep(TURN_AT-100.0,TURN_AT,metres))
	if metres<TURN_AT+ARC:
		var angle := (metres-TURN_AT)/RADIUS
		return start+forward*(TURN_AT+sin(angle)*RADIUS)-side*cos(angle)*RADIUS
	var along := LENGTH-metres
	return start+forward*along+side*lerpf(RADIUS,-lane,smoothstep(0.0,100.0,TURN_AT-along))

func heading(entry: Dictionary, delta: float) -> Vector3:
	var metres: float=entry.return_progress
	var step := maxf(.02,float(entry.drive.speed_mps)*delta)
	var next := point_at(metres+step,float(entry.return_lane))
	var error: Vector3=next-entry.car.global_position
	error.y=0
	return error.normalized() if error.length_squared()>.000001 else -forward

func observe(entry: Dictionary) -> float:
	var local: Vector3=entry.car.global_position-start
	var along := local.dot(forward)
	var across := local.dot(side)
	var gate: int=entry.return_gate
	if gate==0:
		entry.return_progress=clampf(along,0.0,TURN_AT)
		if along>=TURN_AT-.08 and absf(across+RADIUS)<.7: entry.return_gate=1
	elif gate==1:
		var angle := atan2(along-TURN_AT,-across)
		# Portões ordenados do lado de lá e de retorno impedem cortar pelo tambor.
		var radius := Vector2(along-TURN_AT,across).length()
		if radius>RADIUS-1.0 and radius<RADIUS+1.0 and angle>=0.0 and angle<float(entry.return_angle)+.5:
			entry.return_angle=maxf(float(entry.return_angle),angle)
		entry.return_progress=TURN_AT+float(entry.return_angle)*RADIUS
		if float(entry.return_angle)>PI*.85 and across>RADIUS-.7 and along<=TURN_AT+.08:
			entry.return_gate=2
			entry.return_progress=TURN_AT+ARC
	else:
		entry.return_progress=maxf(TURN_AT+ARC,LENGTH-along)
		if absf(across)>5.0: entry.return_progress=minf(float(entry.return_progress),LENGTH-.01)
	return float(entry.return_progress)

func brake(entry: Dictionary) -> float:
	var progress: float=entry.return_progress
	var speed: float=entry.drive.speed_mps
	var remaining := TURN_AT-progress if entry.return_gate==0 else LENGTH-progress
	var target := 5.5 if entry.return_gate<2 else 17.0
	if entry.return_gate==1: return 1.0 if speed>target else 0.0
	# Frenagem física de serviço, incluindo espaço para parar depois da linha de retorno.
	return 1.0 if remaining<(speed*speed-target*target)/18.0+8.0 and speed>target else 0.0

func runoff(entry: Dictionary, delta: float) -> void:
	var speed: float=entry.drive.speed_mps
	entry.drive.step(delta,0.0,false,1.0)
	entry.drive.speed_mps=minf(float(entry.drive.speed_mps),maxf(0.0,speed-10.5*delta))

func camera_frame(entry: Dictionary, opponent: Vector3) -> Dictionary:
	var car=entry.car
	var gap: float=(opponent-car.global_position).dot(forward)
	var center: Vector3=car.global_position+forward*clampf(gap*.5,-10.0,10.0)+side*((opponent-car.global_position).dot(side)*.5)+Vector3.UP*.75
	var setback := clampf(16.5+maxf(0,absf(gap)-12.0)*.28,16.5,25.5)
	var progress: float=entry.return_progress
	var turn_view := smoothstep(TURN_AT-70.0,TURN_AT,progress)*(1.0-smoothstep(TURN_AT+ARC,TURN_AT+ARC+70.0,progress))
	# A varredura da largada encontra exatamente o referencial lateral comum. Sobe suave em volta
	# do tambor e mantém o mesmo lado do mundo enquanto os carros invertem o sentido.
	return {"target":center,"position":center+side*setback-forward*4.0+Vector3.UP*(4.4+4.0*turn_view)}

static func record_finish(world: Dictionary, identity: String, seconds: float, other: float) -> Dictionary:
	if identity not in PROGRESS.RIVALS or not is_finite(seconds) or seconds<=0.0 or seconds>120.0: return {}
	var value: Variant=world.get("desert_drag_return",{"finishes":0,"best":{}})
	if not validate_snapshot(value) or value.finishes>=1000000: return {}
	var data: Dictionary=value.duplicate(true)
	var best: Dictionary=data.get("best",{}).duplicate()
	best[identity]=minf(float(best.get(identity,seconds)),seconds)
	data.best=best
	data.finishes=int(data.get("finishes",0))+1
	world.desert_drag_return=data
	return {"finished":true,"return_mode":true,"first_win":false,"rival_id":identity,"won":seconds<other,"seconds":seconds,"best_seconds":best[identity],"distance":LENGTH}

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary or not value.get("best") is Dictionary: return false
	var finishes: Variant=value.get("finishes")
	if typeof(finishes) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(finishes)) or float(finishes)!=floorf(float(finishes)) or finishes<0 or finishes>1000000: return false
	if value.best.size()>PROGRESS.RIVALS.size() or finishes<value.best.size(): return false
	for identity in value.best:
		var seconds: Variant=value.best[identity]
		if identity not in PROGRESS.RIVALS or typeof(seconds) not in [TYPE_INT,TYPE_FLOAT]: return false
		if not is_finite(float(seconds)) or seconds<=0 or seconds>120: return false
	return true
