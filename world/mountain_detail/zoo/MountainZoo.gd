extends Node3D
const GEO=preload("res://world/mountain_detail/zoo/ZooGeometry.gd")
const ANIMAL=preload("res://world/mountain_detail/zoo/ZooAnimal.gd")
const CENTER:=Vector3(716,0,-363)
const FOOTPRINT:=Rect2(690,-386,52,49)
const BOUNDARY:= [Vector2(-2,20),Vector2(-10,20),Vector2(-19,17),Vector2(-23,10),Vector2(-23,-8),Vector2(-19,-17),Vector2(-10,-19),Vector2(8,-19),Vector2(19,-17),Vector2(23,-10),Vector2(23,9),Vector2(18,17),Vector2(9,20),Vector2(2,20)]
var animals: Array[Node3D]=[]
var clock:=0.0
var active:=true
var admission: Node
var session
var sounds: Array[AudioStreamPlayer3D]=[]
var sound_clock:=6.0
var sound_index:=0
static func approach() -> Dictionary:
	return {"id":"mountain_zoo_walk","width":3.0,"points":PackedVector3Array([Vector3(716,0,-330),Vector3(716,0,-338),Vector3(716,0,-343)])}
static func pen_outline(center: Vector2) -> PackedVector2Array:
	var points:=PackedVector2Array()
	for p in [Vector2(-5.7,-6.2),Vector2(4.8,-6.2),Vector2(7.4,-4.7),Vector2(8,-1),Vector2(7.6,3.5),Vector2(5.4,6.2),Vector2(-4.6,6.2),Vector2(-7.7,4.1),Vector2(-8,-2.9)]: points.append(p+center)
	return points
func _ready() -> void:
	name="MountainZoo"; add_to_group("mountain_zoo")
	var g:=GEO.new()
	# One organic gravel court: all planting beds and pens have their own curved outline.
	var outer:=PackedVector2Array(BOUNDARY)
	GEO.polygon(self,outer,.035,Color("77775e"))
	for i in range(outer.size()-1): g.fence_segment(self,outer[i],outer[i+1],2.0,"PerimeterFence")
	# Curved promenade forms a loop around the exhibits, with a clear central crossing.
	_path(PackedVector2Array([Vector2(0,20),Vector2(0,14),Vector2(-.2,5),Vector2(0,0),Vector2(.1,-9),Vector2(0,-17)]),3.4)
	_path(PackedVector2Array([Vector2(-20,0),Vector2(-10,.1),Vector2(-2,0),Vector2(2,0),Vector2(11,-.1),Vector2(20,0)]),3.2)
	_path(PackedVector2Array([Vector2(0,17),Vector2(-9,17),Vector2(-17,14.8),Vector2(-20,8),Vector2(-20,-7),Vector2(-17,-14.8),Vector2(-9,-17),Vector2(8,-17),Vector2(17,-14.8),Vector2(20,-8),Vector2(20,8),Vector2(16.5,14.8),Vector2(8,17),Vector2(0,17)]),2.2)
	for x in [-10.5,10.5]:
		for z in [-8.5,8.5]:
			var species: String=("giraffe" if x<0 else "lion") if z<0 else ("zebra" if x<0 else "monkey")
			_pen(g,Vector3(x,0,z),species)
	for x in [-2.05,2.05]:
		g.part("box",Vector3(x,1.7,20),Vector3(.32,3.4,.32),"59452e")
		GEO.solid(self,"EntrancePost",Vector3(x,1.7,20),Vector3(.32,3.4,.32))
	g.part("box",Vector3(0,3.4,20),Vector3(4.6,.7,.30),"355347")
	GEO.solid(self,"EntranceBeam",Vector3(0,3.4,20),Vector3(4.6,.7,.30))
	var name_label:=Label3D.new(); name_label.text="Serra Viva"; name_label.font_size=72; name_label.pixel_size=.008
	name_label.position=Vector3(0,3.41,20.17); name_label.modulate=Color("f0deb0"); name_label.outline_size=0; add_child(name_label)
	preload("res://world/mountain_detail/zoo/ZooTicketBooth.gd").build(self)
	for at in [Vector3(-21.8,0,1.2),Vector3(21.8,0,1.2)]: _bench(g,at)
	# Low planting and boulders soften the perimeter without concealing the visitor route.
	for i in outer.size():
		var p: Vector2=outer[i]
		if absf(p.x)<4: continue
		g.part("round",Vector3(p.x*.96,.22,p.y*.96),Vector3(1.1,.65,.8),"62704b")
	g.flush(self)
	admission=load("res://world/mountain_detail/zoo/ZooAdmission.gd").new()
	admission.zoo=self; add_child(admission)
	_build_audio()
func _path(points: PackedVector2Array, width: float) -> void:
	# Round-capped segment union avoids coplanar overlapping strips at intersections.
	var polygons: Array[PackedVector2Array]=Geometry2D.offset_polyline(points,width*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
	for polygon in polygons: GEO.polygon(self,polygon,.052,Color("9e937a"))
func _pen(g: RefCounted, center: Vector3, species: String) -> void:
	var height:=2.65 if species in ["lion","monkey"] else 1.8
	var outline:=pen_outline(Vector2(center.x,center.z))
	for i in outline.size(): g.fence_segment(self,outline[i],outline[(i+1)%outline.size()],height)
	GEO.polygon(self,outline,.058,Color("8d8a5a") if species in ["monkey","zebra"] else Color("ae9870"))
	for x in [-4.0,0.0,4.0]:
		var animal:=ANIMAL.new(); animal.species=species; animal.phase=float(animals.size())
		animal.home=center+Vector3(x,.06,1.3 if x!=0 else -1.0)
		add_child(animal); animals.append(animal)
	var rear:=center+Vector3(0,0,-4.7)
	var roof_height:=5.1 if species=="giraffe" else 2.5
	for x in [-2.0,2.0]:
		g.part("pole",rear+Vector3(x,roof_height*.5,0),Vector3(.23,roof_height,.23),"695339")
		GEO.solid(self,"ShelterPost",rear+Vector3(x,roof_height*.5,0),Vector3(.23,roof_height,.23))
	g.part("box",rear+Vector3(0,roof_height,0),Vector3(5,.24,2.6),"665947")
	GEO.solid(self,"ShelterRoof",rear+Vector3(0,roof_height,0),Vector3(5,.24,2.6))
	if species=="monkey":
		for x in [-5.0,5.0]:
			g.part("pole",center+Vector3(x,1.1,-3.5),Vector3(.25,2.2,.25),"695339")
			GEO.solid(self,"ClimbingPost",center+Vector3(x,1.1,-3.5),Vector3(.25,2.2,.25))
		for i in 11:
			var at:=center+Vector3(-5+i,2.1-sin(float(i)/10*PI)*.5,-3.5)
			g.part("box",at,Vector3(.8,.10,.8),"766149"); GEO.solid(self,"ClimbingPlank",at,Vector3(.8,.10,.8))
		# Thin wires clipped to the actual polygon; no rectangular roof protrudes at corners.
		for x in range(-7,8):
			var length:=10.0 if absi(x)<6 else 7.0
			g.part("box",center+Vector3(x,height,0),Vector3(.025,.025,length),"444d47")
	for x in [-5.5,5.5]:
		var rock:=center+Vector3(x,.35,-4.3)
		g.part("round",rock,Vector3(1.5,.8,1.1),"77776c"); GEO.solid(self,"HabitatRock",rock,Vector3(1.3,.7,1))
		for i in 5: g.part("round",center+Vector3(x+(i%2)*.25,.22,-5+floori(float(i)/2.0)*.18),Vector3(.65,.6,.6),"62704b")
	var trough:=center+Vector3(3.5,.22,4.9)
	g.part("box",trough,Vector3(2,.44,1.1),"77776c")
	g.part("box",trough+Vector3(0,.23,0),Vector3(1.7,.025,.8),"64898b")
	GEO.solid(self,"Trough",trough,Vector3(2,.44,1.1))
func _bench(g: RefCounted, at: Vector3) -> void:
	g.part("box",at+Vector3(0,.48,0),Vector3(1.8,.15,.55),"806044")
	g.part("box",at+Vector3(0,.85,-.25),Vector3(1.8,.6,.10),"806044")
	for x in [-.65,.65]: g.part("box",at+Vector3(x,.23,0),Vector3(.12,.46,.5),"48584d")
	GEO.solid(self,"Bench",at+Vector3(0,.55,0),Vector3(1.8,1.1,.65))
func _build_audio() -> void:
	for species in ["lion","monkey","giraffe","zebra"]:
		var path: String="res://assets/zoo/audio/"+species+".ogg"
		if not ResourceLoader.exists(path): continue
		var sound:=AudioStreamPlayer3D.new(); sound.name=species+"Call"
		sound.stream=load(path)
		sound.max_distance=65; sound.unit_size=14; sound.volume_db=-9 if species=="lion" else -15
		if AudioServer.get_bus_index("SFX")>=0: sound.bus="SFX"
		for animal in animals:
			if animal.species==species: sound.position=animal.home+Vector3.UP; break
		add_child(sound); sounds.append(sound)
func _process(delta: float) -> void:
	clock+=delta
	if clock>.5:
		clock=0
		if session==null:
			var ancestor:=get_parent()
			while ancestor!=null:
				if ancestor.get("session")!=null: session=ancestor.session; break
				ancestor=ancestor.get_parent()
		var camera:=get_viewport().get_camera_3d()
		active=camera!=null and camera.global_position.distance_to(global_position)<100
	if active:
		for animal in animals: animal.advance(delta)
		if session!=null and session.ready_for_play:
			sound_clock-=delta
			if sound_clock<=0 and not sounds.is_empty():
				var sound:=sounds[sound_index%sounds.size()]; sound_index+=1
				# Giraffe hums were recorded at night; quiet by day.
				if sound.name!="giraffeCall" or session.weather.time_of_day<.25 or session.weather.time_of_day>.78: sound.play()
				sound_clock=18+float(sound_index%4)*4
	else:
		for sound in sounds:
			if sound.playing: sound.stop()
func _exit_tree() -> void:
	for sound in sounds: sound.stop()
