extends SceneTree
## Offline service fleet redesign. Original resources remain untouched.
const KIT=preload("res://tools/fleet_fixups/ServiceMeshKit.gd")
const BATCH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const FLEET=preload("res://runtime/FleetCatalog.gd")
const REDESIGNED=preload("res://runtime/RedesignedFleet.gd")
const IDS=["american_dump_truck","american_tanker_truck","boxrunner","cargo_flatbed_truck","medic_box","police_cruiser","police_suv","rescue_pumper","snow_plow_truck","towmaster","police_transport","armored_truck"]
const DARK=Color("172126")
const STEEL=Color("a9b8be")
const RUBBER=Color("232c31")
const ORANGE=Color("d5983e")
var model: Node3D
var id: String
var kit: RefCounted
var paint: StandardMaterial3D
var wheels: Dictionary
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var report: Dictionary={"scope":"Offline authored assets and geometry counts only. Functional, rendered temporal and frame-time evidence is recorded separately under validation and temporal.","vehicles":{}}
	var previous_report_path: String="res://evidence/fleet-redesign-20261011/service/report.json"
	if FileAccess.file_exists(previous_report_path):
		var previous: Variant=JSON.parse_string(FileAccess.get_file_as_string(previous_report_path))
		if previous is Dictionary: report.vehicles=previous.get("vehicles",{})
	for next_id in IDS:
		id=next_id
		var selected: String=""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--id="): selected=arg.trim_prefix("--id=")
		if selected!="" and selected!=id: continue
		var baseline_path: String="res://evidence/fleet-redesign-20261011/service/before/"+id+".scn"
		if ResourceLoader.exists(baseline_path):
			model=(load(baseline_path) as PackedScene).instantiate()
		else:
			# A fresh checkout may lack the evidence snapshot. Build the original
			# without reusing catalog entries cached for the integrated redesign.
			var redesigned_enabled: bool=REDESIGNED.enabled
			var saved_catalog: Dictionary=FLEET._data
			REDESIGNED.enabled=false
			FLEET._data={}
			model=FLEET.create(id)
			FLEET._data=saved_catalog
			REDESIGNED.enabled=redesigned_enabled
		var before: Dictionary=BATCH.counts(model)
		if not ResourceLoader.exists(baseline_path): BATCH.save_model(model,baseline_path)
		prepare()
		kit=KIT.new()
		match id:
			"police_cruiser","police_suv": police_body()
			"american_dump_truck","american_tanker_truck","cargo_flatbed_truck": american_cab()
			"medic_box": medic()
			"boxrunner": box_truck()
			"rescue_pumper": rescue()
			"towmaster": tow()
			"snow_plow_truck": snow()
			"police_transport": tactical()
			"armored_truck": armor()
		model.add_child(kit.finish("ServiceAuthoredDetails"))
		var baked: Node3D=BATCH.bake(model,.28,id)
		for center: Vector3 in wheels:
			var entry: Dictionary=wheels[center]
			var wheelkit:=KIT.new()
			wheelkit.wheel(center,entry.radius,entry.width,"police" if id in ["police_cruiser","police_suv"] else "utility")
			var part: MeshInstance3D=wheelkit.finish("ServiceWheel_"+str(baked.get_child_count()))
			part.set_meta("wheel_center",center)
			part.set_meta("wheel_radius",entry.radius)
			part.set_meta("wheel_spins",true)
			part.set_meta("wheel_style","steel")
			baked.add_child(part)
		baked.set_meta("service_redesign_version",1)
		preload("res://tools/fleet_fixups/CabinMetadataFix.gd").apply(baked,id)
		var after: Dictionary=BATCH.counts(baked)
		var path: String="res://assets/fleet/redesigned/"+id+".scn"
		var status: Error=BATCH.save_model(baked,path)
		report.vehicles[id]={"before":before,"after":after,"scene":path,"save_status":status,"wheel_pivots":wheels.size()}
		print("SERVICE_BAKED ",id," ",JSON.stringify(report.vehicles[id]))
		model.free(); baked.free()
	var report_path: String="res://evidence/fleet-redesign-20261011/service/report.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()

func prepare() -> void:
	wheels={}
	paint=null
	for p: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if p.get_parent()!=model: continue
		# The cab and vault paint already contain only 252 triangles. Simplifying
		# their disconnected boxes erases the cab door sheets when they open.
		if id=="armored_truck" and p.name=="Armor_paint": p.set_meta("batch_ratio",1.0)
		if not p.visible:
			p.free(); continue
		if p.has_meta("wheel_center"):
			var center: Vector3=p.get_meta("wheel_center")
			var box: AABB=p.transform*p.get_aabb()
			if p.get_meta("wheel_spins",true):
				if not wheels.has(center): wheels[center]={"radius":0.0,"width":0.0}
				wheels[center].radius=maxf(wheels[center].radius,float(p.get_meta("wheel_radius",box.size.y*.5)))
				wheels[center].width=maxf(wheels[center].width,box.size.x)
				p.free(); continue
			# Calipers remain stationary in the same location, grouped with trim.
			p.remove_meta("wheel_center")
			p.remove_meta("wheel_spins")
		for s in p.mesh.get_surface_count():
			var mat: StandardMaterial3D=p.get_active_material(s) as StandardMaterial3D
			if mat==null: continue
			var role: String=BATCH.role(p,s,id)
			if role=="paint" and paint==null: paint=mat.duplicate()
			if mat.emission_enabled and id=="rescue_pumper":
				if mat.albedo_color.is_equal_approx(Color("e74c3c")): p.set_meta("vehicle_material_key","bar_left")
				elif mat.albedo_color.is_equal_approx(Color("f39c12")) and (p.transform*p.get_aabb()).get_center().y>2.0: p.set_meta("vehicle_material_key","bar_right")
	if paint==null:
		paint=StandardMaterial3D.new(); paint.resource_name="paint"; paint.albedo_color=Color("e1e3df")
	paint.vertex_color_use_as_albedo=true
	paint.vertex_color_is_srgb=true
	paint.roughness=.48
	paint.metallic=.3
	for center: Vector3 in wheels:
		wheels[center].width=clampf(wheels[center].width,.20,.38)

func add_paint(k: RefCounted,label: String) -> void:
	var p: MeshInstance3D=k.finish(label,paint)
	p.set_meta("vehicle_material_key","paint")
	model.add_child(p)
func grille(z: float,y: float,width: float,height: float,vertical:=false) -> void:
	kit.box(Vector3(0,y,z),Vector3(width,height,.06),DARK)
	kit.box(Vector3(0,y-height*.5,z-.025),Vector3(width+.06,.035,.06),STEEL)
	kit.box(Vector3(0,y+height*.5,z-.025),Vector3(width+.06,.035,.06),STEEL)
	for side in [-1,1]: kit.box(Vector3(side*width*.5,y,z-.025),Vector3(.035,height,.06),STEEL)
	if vertical:
		for i in 9: kit.box(Vector3(lerpf(-width*.44,width*.44,i/8.0),y,z-.05),Vector3(.022,height*.87,.018),Color("6c7e85"))
	else:
		for i in 6: kit.box(Vector3(0,lerpf(y-height*.41,y+height*.41,i/5.0),z-.05),Vector3(width*.92,.018,.018),Color("617078"))
func plate_frame(z: float,y: float,width:=.38) -> void:
	kit.box(Vector3(0,y,z),Vector3(width+.06,.16,.03),DARK)
	kit.box(Vector3(0,y,z-.019),Vector3(width,.12,.012),Color("c4c8c2"))
func compartment(x: float,y: float,z: float,w: float,h: float,color: Color) -> void:
	var side:=signf(x)
	kit.box(Vector3(x,y,z),Vector3(.026,h,w),DARK)
	kit.box(Vector3(x+side*.015,y,z),Vector3(.014,h-.04,w-.04),color)
	kit.box(Vector3(x+side*.027,y-h*.32,z),Vector3(.025,.035,minf(.22,w*.6)),STEEL)
func chevrons(x: float,y: float,z: float,length: float,color: Color) -> void:
	for j in int(length/.32):
		var z0:=z-length*.5+j*.32
		kit.quad(Vector3(x,y-.07,z0),Vector3(x,y-.07,z0+.13),Vector3(x,y+.07,z0+.27),Vector3(x,y+.07,z0+.14),Vector3(signf(x),0,0),color)
func hood(k: RefCounted,width: float,z0: float,z1: float,y0: float,y1: float) -> void:
	var cuts: Array[float]=[-1,-.92,-.68,0,.68,.92,1]
	for i in cuts.size()-1:
		var a: float=cuts[i]; var b: float=cuts[i+1]
		var da:=.065*pow(absf(a),4); var db:=.065*pow(absf(b),4)
		k.quad(Vector3(a*width*.46,y0-da,z0),Vector3(b*width*.46,y0-db,z0),Vector3(b*width*.5,y1-db,z1),Vector3(a*width*.5,y1-da,z1),Vector3.UP,Color.WHITE)
	for s in [-1,1]: k.quad(Vector3(s*width*.46,y0-.45,z0),Vector3(s*width*.5,y1-.45,z1),Vector3(s*width*.5,y1-.065,z1),Vector3(s*width*.46,y0-.065,z0),Vector3(s,0,0),Color.WHITE)
	k.quad(Vector3(-width*.46,y0-.45,z0),Vector3(width*.46,y0-.45,z0),Vector3(width*.46,y0,z0),Vector3(-width*.46,y0,z0),Vector3.FORWARD,Color.WHITE)

func police_body() -> void:
	var suv:=id=="police_suv"
	var half:=1.05 if suv else .9
	var front:=-2.52 if suv else -2.22
	var rear:=2.52 if suv else 2.28
	var belt:=1.14 if suv else .80
	var roof:=1.82 if suv else 1.40
	# Replace the original rectangular lower body with a faceted, open-arch shell.
	for p: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if p.get_parent()!=model: continue
		var b: AABB=p.transform*p.get_aabb()
		if BATCH.role(p,0,id)=="paint" and b.size.x>1.6 and b.get_center().y<1.1: p.free()
	var shell:=KIT.new()
	var samples: Array[float]=[]
	for i in 61: samples.append(lerpf(front,rear,i/60.0))
	for s in [-1,1]:
		for i in samples.size()-1:
			var za:=samples[i]; var zb:=samples[i+1]
			var ba:=.31; var bb:=.31
			for c: Vector3 in wheels:
				var radius: float=wheels[c].radius+.065
				if absf(za-c.z)<radius: ba=maxf(ba,c.y+sqrt(radius*radius-pow(za-c.z,2)))
				if absf(zb-c.z)<radius: bb=maxf(bb,c.y+sqrt(radius*radius-pow(zb-c.z,2)))
			var wa:=half-.12*pow(absf(za)/maxf(absf(front),rear),8)
			var wb:=half-.12*pow(absf(zb)/maxf(absf(front),rear),8)
			var shoulder_a:=maxf(ba,belt-.075)
			var shoulder_b:=maxf(bb,belt-.075)
			shell.quad(Vector3(s*(wa-.045),ba,za),Vector3(s*(wb-.045),bb,zb),Vector3(s*wb,shoulder_b,zb),Vector3(s*wa,shoulder_a,za),Vector3(s,0,0),Color.WHITE)
			shell.quad(Vector3(s*wa,shoulder_a,za),Vector3(s*wb,shoulder_b,zb),Vector3(s*(wb-.045),belt,zb),Vector3(s*(wa-.045),belt,za),Vector3(s,.7,0),Color.WHITE)
		kit.box(Vector3(s*(half-.034),.36,0),Vector3(.055,.085,1.6),DARK)
		# Dark door panel and narrow brushed metal belt: purposeful interceptor identity.
		kit.box(Vector3(s*(half+.006),belt-.19,.15),Vector3(.014,.19,1.92 if suv else 1.56),Color("24343d"))
		kit.box(Vector3(s*(half+.015),belt-.105,.15),Vector3(.01,.018,1.93 if suv else 1.57),STEEL)
		for z in [-.48,.64]: kit.box(Vector3(s*(half+.018),belt-.02,z),Vector3(.026,.026,.13),STEEL)
		for c: Vector3 in wheels:
			if signf(c.x)!=s: continue
			for j in 18:
				var aa:=PI*j/18.0; var bb:=PI*(j+1)/18.0
				var r: float=wheels[c].radius+.07
				kit.beam(Vector3(s*(half-.01),c.y+sin(aa)*r,c.z+cos(aa)*r),Vector3(s*(half-.01),c.y+sin(bb)*r,c.z+cos(bb)*r),.028,DARK)
	hood(shell,half*2,front,-1.10 if suv else -.89,belt-.03,belt)
	# Rear deck and front/rear valance close the shell.
	shell.box(Vector3(0,belt-.04,2.13 if suv else 1.73),Vector3(half*1.75,.08,.72 if suv else 1.08),Color.WHITE)
	for z in [front,rear]: shell.box(Vector3(0,.43,z),Vector3(half*1.78,.23,.08),Color.WHITE)
	shell.box(Vector3(0,belt-.22,front+.006),Vector3(half*1.75,.42,.04),Color.WHITE)
	shell.box(Vector3(0,(belt+.51)*.5,rear-.014),Vector3(half*1.79,belt-.51,.06),Color.WHITE)
	kit.box(Vector3(0,belt-.065,rear+.022),Vector3(1.17,.028,.027),STEEL)
	kit.box(Vector3(0,belt-.16,rear+.035),Vector3(.23,.05,.03),DARK)
	if not suv:
		for s in [-1,1]:
			# Closed A/C pillar cheeks bridge the rectangular side glass and the
			# inclined windshields, whose endpoints were disjoint in the old asset.
			shell.quad(Vector3(s*.705,.808,.883),Vector3(s*.675,.808,1.15),Vector3(s*.675,1.32,.858),Vector3(s*.705,1.32,.884),Vector3(s,0,0),Color.WHITE)
			shell.quad(Vector3(s*.675,.808,-.892),Vector3(s*.705,.808,-.642),Vector3(s*.705,1.32,-.642),Vector3(s*.675,1.32,-.58),Vector3(s,0,0),Color.WHITE)
			shell.quad(Vector3(s*.855,.80,-.895),Vector3(s*.855,.80,1.15),Vector3(s*.699,.821,1.15),Vector3(s*.699,.821,-.895),Vector3.UP,Color.WHITE)
			kit.beam(Vector3(s*.698,1.305,-.66),Vector3(s*.698,1.305,.91),.027,DARK)
	add_paint(shell,"InterceptorSculptedBody")
	var gz:=front-.05
	grille(gz,belt-.21,1.18,.25,suv)
	plate_frame(gz-.08,.46)
	kit.box(Vector3(0,.31,front+.03),Vector3(half*1.85,.06,.22),DARK)
	kit.box(Vector3(0,.35,rear),Vector3(half*1.8,.09,.16),DARK)
	# Roof rails on SUV; restrained deck spoiler on sedan.
	if suv:
		for s in [-1,1]:
			kit.beam(Vector3(s*.71,roof+.025,-.7),Vector3(s*.71,roof+.025,1.86),.055,DARK)
			for z in [-.6,1.7]: kit.box(Vector3(s*.71,roof-.005,z),Vector3(.1,.07,.15),DARK)
	else:
		kit.box(Vector3(0,belt+.08,2.13),Vector3(1.5,.045,.15),DARK)
		for s in [-1,1]: kit.box(Vector3(s*.54,belt+.03,2.13),Vector3(.09,.1,.10),DARK)
	kit.beam(Vector3(.5,roof,-.1),Vector3(.5,roof+.2,-.1),.017,DARK)

func american_cab() -> void:
	# A tapered bonnet replaces the old broad cube. The cab and all lamp mounts stay.
	for p: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if p.get_parent()!=model: continue
		var b: AABB=p.transform*p.get_aabb()
		if BATCH.role(p,0,id)=="paint" and b.size.x>1.3 and b.get_center().z< -2.7: p.free()
	var shell:=KIT.new()
	hood(shell,1.50,-3.90,-2.05,1.65,1.76)
	add_paint(shell,"LongBonnet")
	grille(-3.94,1.18,1.18,1.03,true)
	kit.box(Vector3(0,.60,-4.11),Vector3(2.52,.23,.11),Color("657781"))
	plate_frame(-4.18,.61)
	# Fine hood seam, raised centre spine, side vent louvers and bolted steps.
	kit.beam(Vector3(0,1.657,-3.78),Vector3(0,1.766,-2.16),.023,STEEL)
	for s in [-1,1]:
		for j in 7: kit.box(Vector3(s*.745,1.43,-2.78+j*.085),Vector3(.023,.19,.035),DARK)
		kit.box(Vector3(s*1.052,1.51,-1.39),Vector3(.018,.23,.95),Color("dfd3b6"))
		kit.box(Vector3(s*1.064,1.49,-1.39),Vector3(.013,.16,.93),Color("40545b"))
		for y in [.60,.78]:
			kit.box(Vector3(s*1.13,y,-1.38),Vector3(.36,.06,.93),Color("586971"))
			for z in [-1.73,-1.56,-1.39,-1.22,-1.05]: kit.box(Vector3(s*1.14,y+.035,z),Vector3(.31,.012,.027),STEEL)
		kit.box(Vector3(s*1.075,2.20,-1.1),Vector3(.024,.13,.27),DARK)
		kit.box(Vector3(s*1.098,2.20,-1.1),Vector3(.01,.075,.21),Color("405963"))
	if id=="american_dump_truck":
		for s in [-1,1]:
			for z in [.15,.91,1.67,2.43,3.19]:
				kit.box(Vector3(s*1.289,1.75,z),Vector3(.055,1.27,.07),Color("5d6b68"))
				kit.box(Vector3(s*1.321,1.35,z),Vector3(.011,.06,.12),STEEL)
			kit.box(Vector3(s*1.30,2.46,1.72),Vector3(.10,.08,4.51),Color("55615d"))
			chevrons(s*1.322,1.18,1.7,3.9,Color("d6b665"))
	elif id=="american_tanker_truck":
		# Separate broad steel bands and a narrow catwalk distinguish the cylindrical tank.
		for z in [.15,1.62,3.1]:
			for j in 24:
				var aa:=TAU*j/24.0; var bb:=TAU*(j+1)/24.0
				kit.quad(Vector3(cos(aa)*1.145,1.70+sin(aa)*1.145,z-.04),Vector3(cos(bb)*1.145,1.70+sin(bb)*1.145,z-.04),Vector3(cos(bb)*1.145,1.70+sin(bb)*1.145,z+.04),Vector3(cos(aa)*1.145,1.70+sin(aa)*1.145,z+.04),Vector3(cos(aa),sin(aa),0),Color("5d747e"))
		kit.box(Vector3(0,2.86,1.55),Vector3(.49,.055,4.17),DARK)
		for z in [.12,1.42,2.72]: kit.cylinder(Vector3(0,2.91,z),.20,.10,STEEL)
		for s in [-1,1]: kit.beam(Vector3(s*.33,3.05,-.25),Vector3(s*.33,3.05,3.5),.034,STEEL)
		for s in [-1,1]:
			for z in [-.25,1.62,3.5]: kit.beam(Vector3(s*.33,2.78,z),Vector3(s*.33,3.05,z),.032,STEEL)
			# The inherited yellow rail lost tiny posts in the old detail reduction.
			# Restore continuous supports as authored geometry, kept at full detail.
			for z in [.3,1.2,2.2,3.1]: kit.box(Vector3(s*.3,3.165,z),Vector3(.034,.30,.034),Color("c69c30"))
	else:
		for s in [-1,1]:
			kit.box(Vector3(s*1.19,1.03,1.7),Vector3(.10,.13,4.45),Color("556974"))
			for z in [.1,.9,1.7,2.5,3.3]:
				kit.box(Vector3(s*1.235,1.0,z),Vector3(.045,.19,.12),STEEL)
				kit.box(Vector3(s*1.245,.85,z),Vector3(.05,.07,.20),ORANGE)
		for z in [.15,1.7,3.25]: kit.box(Vector3(0,1.093,z),Vector3(2.14,.02,.052),Color("485a61"))

func medic() -> void:
	van_nose(1.035,-2.65,-1.64,.97,1.03,1.74,-.49)
	for s in [-1,1]:
		# The beacon keeps its authored mounting height, now visibly carried by
		# two feet anchored into the newly closed cabin roof.
		kit.box(Vector3(s*.62,1.902,-1.25),Vector3(.075,.275,.12),DARK)
		kit.box(Vector3(s*.62,1.77,-1.25),Vector3(.16,.025,.23),STEEL)
	grille(-2.70,.84,1.12,.35)
	plate_frame(-2.756,.48)
	for s in [-1,1]:
		# Recessed lockers, rails and a strong red shoulder band.
		kit.box(Vector3(s*1.084,1.20,1.1),Vector3(.024,.18,2.85),Color("b92937"))
		kit.box(Vector3(s*1.088,1.32,1.1),Vector3(.021,.027,2.85),STEEL)
		for z in [.13,1.01,1.89]: compartment(s*1.081,.71,z,.70,.32,Color("bec9cc"))
		compartment(s*1.077,1.71,1.69,.66,.58,Color("eee9df"))
		kit.box(Vector3(s*1.10,1.69,1.69),Vector3(.02,.34,.09),Color("b92937"))
		kit.box(Vector3(s*1.10,1.69,1.69),Vector3(.02,.09,.34),Color("b92937"))
		kit.box(Vector3(s*.83,2.31,1.1),Vector3(.045,.06,2.36),Color("727f86"))
		for z in [.2,2.0]: kit.box(Vector3(s*.83,2.27,z),Vector3(.09,.09,.13),STEEL)
		kit.box(Vector3(s*.50,1.22,2.626),Vector3(.85,.12,.02),Color("b92937"))
		kit.box(Vector3(s*.88,.50,2.73),Vector3(.25,.06,.22),RUBBER)

func box_truck() -> void:
	open_flat_cab(1.075,-3.275,-1.625,.525,1.11,1.975)
	grille(-3.30,.83,1.32,.35)
	plate_frame(-3.47,.48)
	for s in [-1,1]:
		kit.box(Vector3(s*1.124,1.04,.88),Vector3(.025,.23,4.68),Color("2e6871"))
		kit.box(Vector3(s*1.14,1.18,.88),Vector3(.012,.025,4.68),Color("d7ad66"))
		for z in [-1.38,-.2,.98,2.16,3.1]: kit.box(Vector3(s*1.135,1.98,z),Vector3(.034,1.42,.033),Color("8e9c9f"))
		kit.box(Vector3(s*1.128,2.73,.86),Vector3(.042,.038,4.78),STEEL)
		kit.box(Vector3(s*1.10,.77,-2.24),Vector3(.13,.045,.87),Color("7d8c93"))
	for y in [1.01,1.23,1.45,1.67,1.89,2.11,2.33,2.55]: kit.box(Vector3(0,y,3.306),Vector3(1.88,.015,.016),Color("4f6169"))
	kit.box(Vector3(0,.73,3.326),Vector3(1.90,.055,.035),STEEL)
	for s in [-1,1]: kit.box(Vector3(s*.83,.66,3.41),Vector3(.20,.05,.20),RUBBER)

func rescue() -> void:
	grille(-4.227,.87,1.08,.39,true)
	kit.box(Vector3(0,.49,-4.46),Vector3(2.30,.17,.12),Color("657d86"))
	plate_frame(-4.53,.49)
	for s in [-1,1]:
		for z in [-.87,.65,2.17]:
			compartment(s*1.215,1.43,z,1.27,1.18,Color("788e97"))
			for y in [1.02,1.18,1.34,1.50,1.66,1.82]: kit.box(Vector3(s*1.247,y,z),Vector3(.01,.012,1.16),Color("4b6470"))
		kit.box(Vector3(s*1.247,.80,.7),Vector3(.034,.095,4.12),Color("d6c782"))
		for z in [-.9,.0,.9,1.8,2.7]: kit.box(Vector3(s*1.267,.79,z),Vector3(.01,.09,.22),Color("ece9d4"))
		# Compact pump-panel gauges with machined surrounds.
		for z in [-.32,.05,.42]:
			kit.disc(Vector3(s*1.285,1.64,z),.082,Vector3(s,0,0),STEEL,12)
			kit.disc(Vector3(s*1.29,1.64,z),.063,Vector3(s,0,0),Color("25323a"),12)
			kit.beam(Vector3(s*1.30,1.64,z),Vector3(s*1.30,1.68,z+.026),.012,Color("e3d9b5"))
		kit.beam(Vector3(s*1.02,2.36,-1.0),Vector3(s*1.02,2.36,2.8),.035,STEEL)
	kit.box(Vector3(0,2.34,1.1),Vector3(.85,.16,2.44),Color("695a42"))
	for z in [.0,.28,.56,.84,1.12,1.4,1.68,1.96,2.24]: kit.box(Vector3(0,2.43,z),Vector3(.80,.021,.07),Color("aa956b"))

func tow() -> void:
	open_flat_cab(1.10,-3.375,-1.525,.555,1.166,2.005)
	grille(-3.482,.96,1.25,.34,true)
	plate_frame(-3.56,.49)
	for s in [-1,1]:
		kit.box(Vector3(s*1.09,1.02,-2.30),Vector3(.025,.21,1.03),Color("353e40"))
		chevrons(s*1.106,1.03,-2.30,.95,Color("cdb77b"))
		compartment(s*1.132,.91,.78,1.37,.38,Color("70818b"))
		kit.box(Vector3(s*1.15,1.18,.76),Vector3(.075,.065,2.0),Color("d1b46c"))
		for z in [.15,.6,1.05,1.5]: kit.box(Vector3(s*1.164,1.19,z),Vector3(.02,.054,.13),RUBBER)
		kit.beam(Vector3(s*.48,1.22,-.15),Vector3(s*.48,1.72,.65),.08,Color("9c7641"))
	kit.cylinder(Vector3(0,1.38,.09),.18,.85,Color("646d6f"),Basis(Vector3.FORWARD,PI*.5),16)
	for x in [-.31,-.20,-.09,.02,.13,.24,.35]: kit.cylinder(Vector3(x,1.38,.09),.187,.027,Color("29383f"),Basis(Vector3.FORWARD,PI*.5),12)

func snow() -> void:
	grille(-3.313,1.07,1.20,.31,true)
	for s in [-1,1]:
		# A real reverse face and rolled edges keep the V blade visible from the
		# rear. The original front-only sheet exposed isolated marker poles.
		var edge0:=Vector3(0,.14,-4.1)
		var edge1:=Vector3(s*1.72,.14,-3.72)
		var top0:=Vector3(0,1.05,-4.1)
		var top1:=Vector3(s*1.72,.94,-3.72)
		var back:=Vector3(0,0,.045)
		kit.quad(edge0+back,edge1+back,top1+back,top0+back,Vector3(0,0,1),Color("876722"))
		kit.quad(top0,top1,top1+back,top0+back,Vector3.UP,STEEL)
		kit.quad(edge0,edge1,edge1+back,edge0+back,Vector3.DOWN,Color("4d5351"))
		kit.quad(edge1,edge1+back,top1+back,top1,Vector3(s,0,0),STEEL)
		kit.beam(Vector3(s*1.63,.65,-3.74),Vector3(s*1.63,.65,-3.59),.035,STEEL)
	for s in [-1,1]:
		kit.box(Vector3(s*1.15,1.36,.8),Vector3(.028,.28,3.9),Color("ded0a0"))
		kit.box(Vector3(s*1.17,1.36,.8),Vector3(.015,.13,3.9),Color("303e45"))
		for z in [-.7,.5,1.7,2.6]: kit.box(Vector3(s*1.18,1.65,z),Vector3(.08,.72,.065),Color("8b9ba1"))
		kit.beam(Vector3(s*1.63,.65,-3.59),Vector3(s*1.63,1.23,-3.59),.027,Color("d69336"))
		kit.box(Vector3(s*1.63,1.20,-3.59),Vector3(.045,.14,.045),Color("ece0b7"))
		compartment(s*1.16,.88,.3,.93,.27,Color("677980"))
	# Top-screen grid on the grit hopper: purposeful, low polygon detail.
	kit.box(Vector3(0,2.087,1.2),Vector3(1.62,.022,2.63),DARK)
	for x in [-.66,-.44,-.22,0,.22,.44,.66]: kit.box(Vector3(x,2.11,1.2),Vector3(.022,.025,2.6),STEEL)
	for z in [.1,.55,1.0,1.45,1.90,2.30]: kit.box(Vector3(0,2.126,z),Vector3(1.6,.02,.022),STEEL)

func tactical() -> void:
	van_nose(.94,-2.375,-1.72,.93,.99,2.0,-.46)
	grille(-2.409,.89,1.22,.39,true)
	plate_frame(-2.45,.47)
	for s in [-1,1]:
		kit.box(Vector3(s*.963,1.44,.96),Vector3(.03,.80,2.53),Color("273942"))
		for z in [.05,.87,1.69]:
			compartment(s*.981,1.48,z,.64,.64,Color("3c515a"))
			for y in [1.22,1.71]:
				kit.disc(Vector3(s*1.012,y,z-.24),.020,Vector3(s,0,0),STEEL,6)
				kit.disc(Vector3(s*1.012,y,z+.24),.020,Vector3(s,0,0),STEEL,6)
		kit.box(Vector3(s*1.04,.57,.55),Vector3(.13,.085,2.24),DARK)
		kit.box(Vector3(s*.86,2.10,.74),Vector3(.06,.07,2.62),STEEL)
		for z in [-.4,.55,1.5]: kit.box(Vector3(s*.86,2.055,z),Vector3(.10,.09,.16),DARK)
		kit.box(Vector3(s*.45,1.7,2.428),Vector3(.64,.45,.025),DARK)
		for y in [1.56,1.7,1.84]: kit.box(Vector3(s*.45,y,2.45),Vector3(.63,.021,.022),STEEL)

func armor() -> void:
	grille(-2.873,1.36,1.08,.36,true)
	for s in [-1,1]:
		# Slanted reinforced brow and replaceable corner armor emphasize the safe body.
		kit.box(Vector3(s*1.15,2.03,-2.047),Vector3(.08,.73,.12),Color("344744"),Basis(Vector3.RIGHT,-.12))
		kit.box(Vector3(s*1.245,2.02,2.46),Vector3(.09,1.39,.24),Color("344744"))
		kit.box(Vector3(s*1.248,2.68,.70),Vector3(.06,.11,3.75),Color("465d58"))
		for z in [-.72,.02,.76,1.50,2.24]:
			kit.disc(Vector3(s*1.28,2.68,z),.022,Vector3(s,0,0),STEEL,6)
			kit.disc(Vector3(s*1.29,1.22,z),.022,Vector3(s,0,0),STEEL,6)
		compartment(s*1.238,1.89,.27,.63,.60,Color("455b54"))
		kit.box(Vector3(s*1.272,1.89,.27),Vector3(.014,.32,.04),Color("bdab78"))
		kit.box(Vector3(s*1.272,1.89,.27),Vector3(.014,.04,.24),Color("bdab78"))
		for z in [-.80,-.65,-.50,-.35]: kit.box(Vector3(s*1.255,2.49,z),Vector3(.028,.05,.066),DARK)
	kit.box(Vector3(0,2.684,-1.63),Vector3(1.92,.055,.80),Color("344744"))
	kit.box(Vector3(0,.48,-2.91),Vector3(2.06,.13,.23),Color("697d79"))

func open_flat_cab(half: float,front: float,rear: float,floor_y: float,belt_y: float,roof_y: float) -> void:
	for p: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if p.get_parent()!=model: continue
		var b: AABB=p.transform*p.get_aabb()
		if BATCH.role(p,0,id)=="paint" and b.size.x>1.8 and b.get_center().z< -1.8 and b.size.y>1.0: p.free()
	var shell:=KIT.new()
	var centerz: float=(front+rear)*.5
	shell.box(Vector3(0,(floor_y+belt_y)*.5,centerz),Vector3(half*2,belt_y-floor_y,rear-front),Color.WHITE)
	shell.box(Vector3(0,roof_y-.04,centerz),Vector3(half*2,.08,rear-front),Color.WHITE)
	shell.box(Vector3(0,(roof_y+belt_y)*.5,rear-.025),Vector3(half*2,roof_y-belt_y,.05),Color.WHITE)
	for s in [-1,1]:
		# The tapered screen has space behind it; no opaque cuboid fills the cabin.
		shell.box(Vector3(s*(half-.025),(roof_y+belt_y)*.5,rear-.09),Vector3(.06,roof_y-belt_y,.13),Color.WHITE)
		shell.beam(Vector3(s*(half-.04),belt_y,front+.035),Vector3(s*(half-.04),roof_y,front+.20),.055,Color.WHITE)
		kit.box(Vector3(s*(half+.015),belt_y+.015,centerz+.16),Vector3(.026,.04,.91),DARK)
	add_paint(shell,"OpenFramedCab")

func van_nose(half: float,front: float,screen: float,front_y: float,belt_y: float,roof_y: float,rear: float) -> void:
	var shell:=KIT.new()
	hood(shell,half*2,front,screen,front_y,belt_y)
	shell.box(Vector3(0,.57,front+.026),Vector3(half*1.84,.40,.06),Color.WHITE)
	for s in [-1,1]:
		# Close the fender shoulder above the original front wheel cutout.
		shell.box(Vector3(s*(half-.045),belt_y-.095,(front+rear)*.5),Vector3(.09,.18,rear-front),Color.WHITE)
		shell.box(Vector3(s*(half-.10),belt_y-.33,(screen+rear)*.5),Vector3(.13,.47,rear-screen),Color.WHITE)
		shell.beam(Vector3(s*(half-.105),belt_y,screen),Vector3(s*(half-.12),roof_y,screen+.24),.054,Color.WHITE)
		kit.box(Vector3(s*(half-.015),belt_y-.08,screen+.52),Vector3(.03,.045,.15),STEEL)
	shell.box(Vector3(0,roof_y+.026,(screen+.24+rear)*.5),Vector3(half*1.80,.065,rear-screen-.20),Color.WHITE)
	add_paint(shell,"ClosedVanBonnet")
