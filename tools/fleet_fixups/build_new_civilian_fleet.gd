extends "res://tools/fleet_fixups/build_sport_coupe_gt.gd"
## Deterministic offline authoring. Baked functional leaves, wheels and semantic lenses.
const CATALOG = preload("res://runtime/NewCivilianFleet.gd")
var car_id := ""
var door := {}
var skin := .8
var roof := 1.8
var belt_y := 1.0
var front := -2.1
var rear := 2.1
var axles: Array[Vector3] = []
var paint_color := Color.WHITE
var pale := Color("e5dec6")

func material(key: String) -> StandardMaterial3D:
 if materials.has(key): return materials[key]
 var m := super.material(key)
 m.vertex_color_is_srgb = true
 if key == "paint": m.albedo_color = paint_color
 if key == "cream":
  m.albedo_color = pale
  m.roughness = .48
 if key == "glass":
  m.albedo_color = Color("294551")
  m.roughness = .19
 return m

func glazing(corners: Array, normal: Vector3) -> void:
 if car_id!="mare_microvan":
  super.glazing(corners,normal)
  return
 for rect in [Vector4(0,1,0,.065),Vector4(0,1,.95,1),Vector4(0,.05,.065,.95),Vector4(.95,1,.065,.95)]:
  panel("cream",corners,rect.x,rect.y,rect.z,rect.w,normal)
 tint=DARK
 for rect in [Vector4(.05,.95,.065,.095),Vector4(.05,.95,.92,.95),Vector4(.05,.065,.095,.92),Vector4(.935,.95,.095,.92)]:
  panel("detail",corners,rect.x,rect.y,rect.z,rect.w,normal)
 tint=Color.WHITE
 panel("glass",corners,.065,.935,.095,.92,normal)

func setup(id: String) -> void:
 car_id=id; groups={}; materials={}
 door=CATALOG.door_spec(id)
 skin=float(door.x); belt_y=float(door.belt); roof=float(door.top)
 front=-2.00 if id=="besouro_1300" else (-2.18 if id=="mare_microvan" else -2.09)
 rear=-front
 paint_color=Color.html(CATALOG.spec(id).colors[0])
 var wheel_x:=.75 if id=="besouro_1300" else .74
 var wheel_y:=.325 if id=="besouro_1300" else .34
 var zf:=-1.21 if id=="besouro_1300" else -1.39
 var zr:=1.18 if id=="besouro_1300" else 1.40
 axles.assign([Vector3(-wheel_x,wheel_y,zf),Vector3(-wheel_x,wheel_y,zr),Vector3(wheel_x,wheel_y,zf),Vector3(wheel_x,wheel_y,zr)])
 model=Node3D.new(); model.name=id.to_pascal_case()
 model.set_meta("fleet_finish",true)
 model.set_meta("fleet_redesign_version",2)
 model.set_meta("new_civilian_model",true)
 model.set_meta("usage_open_bed",id=="toco_minitruck")
 var rf:= -.29 if id=="besouro_1300" else -1.57
 var back:= .68 if id=="besouro_1300" else (-.52 if id=="toco_minitruck" else -.68)
 model.set_meta("vehicle_interior_spec",{"kind":"car" if id=="besouro_1300" else "van","floor":.355 if id=="besouro_1300" else .35,"belt":belt_y,"roof":roof,"hw":skin-.09,"wz0":float(door.zf),"wz1":rf,"rear":back,"rear_top":back,"sx":-.36,"sz":float(door.seat_z)})

func side_bottom(z: float) -> float:
 var y:=.25
 for c in axles:
  if c.x>0: continue
  var dz:=absf(z-c.z)
  var r:=c.y+.055
  if dz<r: y=maxf(y,c.y+sqrt(r*r-dz*dz))
 return y

func side_width(z: float) -> float:
 if car_id!="besouro_1300": return skin
 if z>=float(door.zf) and z<=float(door.zr): return skin
 var swell:=0.0
 for c in axles:
  if c.x<0: swell=maxf(swell,.16*exp(-pow((z-c.z)/.56,4)))
 return skin+swell

func lower_body() -> void:
 var zs: Array[float]=[front,rear,float(door.zf),float(door.zr)]
 for i in 41: zs.append(lerpf(front,rear,i/40.0))
 for c in axles:
  if c.x<0:
   for i in 17: zs.append(c.z+(c.y+.055)*cos(PI*i/16.0))
 zs.sort()
 for s in [-1.,1.]:
  for i in zs.size()-1:
   var a:=zs[i]; var b:=zs[i+1]
   if b-a<.00001: continue
   var is_door:=a>=float(door.zf) and b<=float(door.zr)
   active=("DoorL" if s<0 else "DoorR") if is_door else "Body"
   var ya:=side_bottom(a); var yb:=side_bottom(b)
   var top_y:=belt_y
   if car_id=="besouro_1300": top_y=belt_y-.23*clampf((absf((a+b)*.5)-1.3)/.7,0,1)
   if car_id=="toco_minitruck" and a>=-.50:
    ya=maxf(ya,.63); yb=maxf(yb,.63); top_y=.74
   if car_id=="besouro_1300" and not is_door:
    var ta:=belt_y-.23*clampf((absf(a)-1.3)/.7,0,1); var tb:=belt_y-.23*clampf((absf(b)-1.3)/.7,0,1)
    var ma:=maxf(ya,ta-.075); var mb:=maxf(yb,tb-.075)
    quad("paint",Vector3(s*side_width(a),ya,a),Vector3(s*side_width(b),yb,b),Vector3(s*side_width(b),mb,b),Vector3(s*side_width(a),ma,a),Vector3(s,0,0))
    quad("paint",Vector3(s*side_width(a),ma,a),Vector3(s*side_width(b),mb,b),Vector3(s*(side_width(b)-beetle_shoulder(b)),tb,b),Vector3(s*(side_width(a)-beetle_shoulder(a)),ta,a),Vector3(s,1,0))
   else:
    quad("paint",Vector3(s*side_width(a),ya,a),Vector3(s*side_width(b),yb,b),Vector3(s*side_width(b),maxf(top_y,yb),b),Vector3(s*side_width(a),maxf(top_y,ya),a),Vector3(s,0,0))
   if is_door:
    tint=Color("303537")
    quad("detail",Vector3(s*(skin-.045),ya+.02,a),Vector3(s*(skin-.045),belt_y-.02,a),Vector3(s*(skin-.045),belt_y-.02,b),Vector3(s*(skin-.045),yb+.02,b),Vector3(-s,0,0))
    tint=Color.WHITE
  active="DoorL" if s<0 else "DoorR"
  for z in [float(door.zf)+.02,float(door.zr)-.02]:
   var by:=side_bottom(z)
   box("paint",Vector3(s*(skin-.02),(by+belt_y)*.5,z),Vector3(.05,belt_y-by,.025))
  active="Body"
  for z in [float(door.zf),float(door.zr)]: beam("detail",Vector3(s*(skin+.002),.32,z),Vector3(s*(skin+.002),belt_y,z),.010,DARK)
  box("detail",Vector3(s*(skin+.014),.28,.0),Vector3(.07,.06,1.28),DARK)
 active="Body"
 box("detail",Vector3(0,.26,0),Vector3(skin*1.65,.08,rear-front-.15),DARK)
 for c in axles:
  var s:=signf(c.x)
  var rr:=c.y+.055
  if car_id=="besouro_1300":
   var center:=Vector3(s*(absf(c.x)-.13),c.y,c.z)
   tint=DARK
   for j in 16:
    var a:=PI*j/16.; var b:=PI*(j+1)/16.
    triangle("detail",center,center+Vector3(0,sin(a)*rr,cos(a)*rr),center+Vector3(0,sin(b)*rr,cos(b)*rr),Vector3(s,0,0))
   tint=Color.WHITE
  for j in 16:
   var a:=PI*j/16.; var b:=PI*(j+1)/16.
   var za:=c.z+cos(a)*rr; var zb:=c.z+cos(b)*rr
   var label_a:=("DoorL" if s<0 else "DoorR") if za>=float(door.zf) and za<=float(door.zr) else "Body"
   var label_b:=("DoorL" if s<0 else "DoorR") if zb>=float(door.zf) and zb<=float(door.zr) else "Body"
   if label_a!=label_b: continue
   active=label_a
   beam("detail",Vector3(s*(side_width(za)+.006),c.y+sin(a)*rr,za),Vector3(s*(side_width(zb)+.006),c.y+sin(b)*rr,zb),.018,DARK)
 active="Body"
 if car_id!="besouro_1300":
  for z in [front,rear]:
   quad("paint",Vector3(-side_width(z),.26,z),Vector3(side_width(z),.26,z),Vector3(side_width(z),belt_y,z),Vector3(-side_width(z),belt_y,z),Vector3.FORWARD if z<0 else Vector3.BACK)

func cabin_shape() -> void:
 var bes:=car_id=="besouro_1300"
 var truck:=car_id=="toco_minitruck"
 var lx:=skin-.025
 var ux:=skin-.12
 var wz:=float(door.zf)
 var rf:=-.29 if bes else -1.57
 var rb:=.54 if bes else (-.57 if truck else rear-.14)
 var cb:=1.42 if bes else (-.52 if truck else rear-.08)
 active="Body"
 glazing([Vector3(-lx,belt_y,wz),Vector3(lx,belt_y,wz),Vector3(ux,beetle_roof_y(rf) if bes else roof,rf),Vector3(-ux,beetle_roof_y(rf) if bes else roof,rf)],Vector3(0,1,-1))
 if car_id=="mare_microvan": beam("cream",Vector3(0,belt_y+.02,wz-.006),Vector3(0,roof,rf-.006),.035,pale)
 for s in [-1.,1.]:
  active="DoorL" if s<0 else "DoorR"
  glazing([Vector3(s*lx,belt_y,wz),Vector3(s*lx,belt_y,float(door.zr)),Vector3(s*ux,beetle_roof_y(float(door.zr)-.025) if bes else roof,float(door.zr)-.025),Vector3(s*ux,beetle_roof_y(rf) if bes else roof,rf)],Vector3(s,0,0))
  if bes: beetle_header(s,rf,float(door.zr)-.025,ux,ux)
  box("detail",Vector3(s*(skin+.02),belt_y-.14,float(door.zr)-.16),Vector3(.04,.04,.17),METAL if bes else DARK)
  var mz:=wz+.18
  beam("detail",Vector3(s*skin,belt_y+.17,mz),Vector3(s*(skin+.12),belt_y+.22,mz),.027,DARK)
  box("detail",Vector3(s*(skin+.15),belt_y+.27,mz),Vector3(.10,.14,.14),METAL if bes else DARK)
  active="Body"
  if not truck:
   var cuts: Array[float]=[float(door.zr),cb]
   if not bes: cuts=[float(door.zr),.20,1.16,cb]
   for j in cuts.size()-1:
    if bes:
     glazing([Vector3(s*lx,belt_y,cuts[j]),Vector3(s*lx,belt_y,cuts[j+1]),Vector3(s*(ux-.05),beetle_roof_y(1.02),1.02),Vector3(s*ux,beetle_roof_y(cuts[j]),cuts[j])],Vector3(s,0,0))
     beetle_header(s,cuts[j],1.02,ux,ux-.05)
    else:
     glazing([Vector3(s*lx,belt_y,cuts[j]),Vector3(s*lx,belt_y,cuts[j+1]),Vector3(s*ux,roof,rb if j==cuts.size()-2 else cuts[j+1]),Vector3(s*ux,roof,cuts[j])],Vector3(s,0,0))
 if bes:
  beetle_roof(rf,ux)
  glazing([Vector3(-lx,belt_y,cb),Vector3(lx,belt_y,cb),Vector3(ux-.05,beetle_roof_y(1.02),1.02),Vector3(-ux+.05,beetle_roof_y(1.02),1.02)],Vector3(0,1,1))
 else:
  for i in 10:
   var xa:=lerpf(-ux,ux,i/10.0); var xb:=lerpf(-ux,ux,(i+1)/10.0)
   var ya:=roof+.05*(1-pow(xa/ux,2)); var yb:=roof+.05*(1-pow(xb/ux,2))
   var roof_key:="paint" if car_id!="mare_microvan" else "cream"
   quad(roof_key,Vector3(xa,ya,rf),Vector3(xb,yb,rf),Vector3(xb,yb,rb),Vector3(xa,ya,rb),Vector3.UP)
   quad(roof_key,Vector3(xa,roof,rf),Vector3(xb,roof,rf),Vector3(xb,yb,rf),Vector3(xa,ya,rf),Vector3.FORWARD)
   quad(roof_key,Vector3(xa,roof,rb),Vector3(xb,roof,rb),Vector3(xb,yb,rb),Vector3(xa,ya,rb),Vector3.BACK)
  glazing([Vector3(-lx,belt_y,cb),Vector3(lx,belt_y,cb),Vector3(ux,roof,rb),Vector3(-ux,roof,rb)],Vector3(0,1,1))
 for s in [-1.,1.]:
  beam("detail",Vector3(s*.10,belt_y+.04,wz-.01),Vector3(s*.49,belt_y+.14,wz+.05),.013,DARK)
 if not bes:
  quad("paint",Vector3(-skin,belt_y,front),Vector3(skin,belt_y,front),Vector3(lx,belt_y,wz),Vector3(-lx,belt_y,wz),Vector3.UP)
 if bes: beetle_decks(wz,cb)
 elif truck: truck_bed()
 else:
  for z in [.35,1.30]:
   box("detail",Vector3(0,.67,z),Vector3(1.34,.16,.40),Color("897a5f"))
   box("detail",Vector3(0,.98,z+.16),Vector3(1.34,.54,.12),Color("8f8066"))
   for s in [-1.,1.]: box("detail",Vector3(s*.51,.45,z),Vector3(.035,.30,.24),DARK)
  for s in [-1.,1.]:
   box("cream",Vector3(s*(skin+.004),belt_y+.025,0),Vector3(.013,.095,rear-front-.10))
   for j in 5: box("detail",Vector3(s*(skin+.008),.87+j*.055,rear-.32),Vector3(.018,.023,.34),DARK)

func beetle_shoulder(z: float) -> float:
 return .055*clampf(maxf(float(door.zf)-z,z-float(door.zr))/.30,0,1)

func beetle_roof_y(z: float) -> float:
 return roof-.19*pow((z-.10)/.92,2)

func beetle_header(side: float, za: float, zb: float, wa: float, wb: float) -> void:
 for j in 6:
  var u:=j/6.0; var v:=(j+1)/6.0
  var z0:=lerpf(za,zb,u); var z1:=lerpf(za,zb,v)
  var x0:=side*lerpf(wa,wb,u); var x1:=side*lerpf(wa,wb,v)
  quad("paint",Vector3(x0,lerpf(beetle_roof_y(za),beetle_roof_y(zb),u),z0),Vector3(x1,lerpf(beetle_roof_y(za),beetle_roof_y(zb),v),z1),Vector3(x1,beetle_roof_y(z1),z1),Vector3(x0,beetle_roof_y(z0),z0),Vector3(side,0,0))

func beetle_roof(rf: float, width_at_front: float) -> void:
 for j in 10:
  var za:=lerpf(rf,1.02,j/10.0); var zb:=lerpf(rf,1.02,(j+1)/10.0)
  var wa:=width_at_front-.05*clampf((za-.57)/.45,0,1)
  var wb:=width_at_front-.05*clampf((zb-.57)/.45,0,1)
  for i in 10:
   var u:=lerpf(-1,1,i/10.0); var v:=lerpf(-1,1,(i+1)/10.0)
   quad("paint",Vector3(u*wa,beetle_roof_y(za)+.09*(1-u*u),za),Vector3(v*wa,beetle_roof_y(za)+.09*(1-v*v),za),Vector3(v*wb,beetle_roof_y(zb)+.09*(1-v*v),zb),Vector3(u*wb,beetle_roof_y(zb)+.09*(1-u*u),zb),Vector3.UP)
 for z in [rf,1.02]:
  var w:=width_at_front if z<0 else width_at_front-.05
  for i in 10:
   var u:=lerpf(-1,1,i/10.0); var v:=lerpf(-1,1,(i+1)/10.0)
   quad("paint",Vector3(u*w,beetle_roof_y(z),z),Vector3(v*w,beetle_roof_y(z),z),Vector3(v*w,beetle_roof_y(z)+.09*(1-v*v),z),Vector3(u*w,beetle_roof_y(z)+.09*(1-u*u),z),Vector3.FORWARD if z<0 else Vector3.BACK)

func beetle_decks(wz: float, cb: float) -> void:
 for span in [[front,wz],[cb,rear]]:
  for j in 10:
   var za:=lerpf(span[0],span[1],j/10.0); var zb:=lerpf(span[0],span[1],(j+1)/10.0)
   for i in 12:
    var xa:=lerpf(-1,1,i/12.0); var xb:=lerpf(-1,1,(i+1)/12.0)
    quad("paint",deck(xa,za),deck(xb,za),deck(xb,zb),deck(xa,zb),Vector3.UP)
 for j in 6:
  var z:=1.50+j*.055
  box("detail",Vector3(0,deck(0,z).y+.012,z),Vector3(.54,.016,.020),DARK)
 for z in [front,rear]:
  for side in [-1.,1.]:
   var edge:=deck(side,z)
   quad("paint",Vector3(side*side_width(z),.26,z),Vector3(side*side_width(z),edge.y-.075,z),edge,Vector3(edge.x,.26,z),Vector3.FORWARD if z<0 else Vector3.BACK)
  for i in 12:
   var xa:=lerpf(-1,1,i/12.0); var xb:=lerpf(-1,1,(i+1)/12.0)
   var a:=deck(xa,z); var b:=deck(xb,z)
   quad("paint",Vector3(a.x,.26,z),Vector3(b.x,.26,z),b,a,Vector3.FORWARD if z<0 else Vector3.BACK)
 beam("detail",deck(0,front+.18)+Vector3.UP*.009,deck(0,wz-.10)+Vector3.UP*.009,.014,METAL)

func deck(x: float,z: float) -> Vector3:
 var edge:=belt_y-.23*clampf((absf(z)-1.3)/.7,0,1)
 var dome:=.13*(1-x*x)
 var fender:=.13*exp(-pow((absf(x)-.72)/.22,2))*(1-pow(absf(x),6))*clampf((absf(z)-1.15)/.65,0,1)
 return Vector3(x*(side_width(z)-beetle_shoulder(z)),edge+dome+fender,z)

func truck_bed() -> void:
 var start:=-.46
 box("paint",Vector3(0,.72,(start+rear)*.5),Vector3(skin*2,.10,rear-start))
 for s in [-1.,1.]:
  box("paint",Vector3(s*skin,.98,(start+rear)*.5),Vector3(.07,.48,rear-start))
  for z in [start+.1,.85,rear-.1]:
   box("detail",Vector3(s*(skin+.044),.96,z),Vector3(.025,.30,.035),DARK)
  box("paint",Vector3(s*(skin+.025),1.23,(start+rear)*.5),Vector3(.08,.045,rear-start))
  box("detail",Vector3(s*.60,.48,.70),Vector3(.29,.30,.50),DARK)
 box("paint",Vector3(0,.98,rear-.03),Vector3(skin*2,.48,.07))
 box("paint",Vector3(0,1.08,start),Vector3(skin*2,.66,.07))
 for j in 7: box("paint",Vector3(lerpf(-skin+.1,skin-.1,j/6.0),.78,.80),Vector3(.024,.018,2.40))

func fascia_new() -> void:
 var bes:=car_id=="besouro_1300"
 var round_lamps:=car_id!="toco_minitruck"
 active="Body"
 for z in [front-.015,rear+.015]:
  box("detail",Vector3(0,.38,z),Vector3(skin*1.94,.13,.14),METAL if round_lamps else DARK)
  for s in [-1.,1.]: box("detail",Vector3(s*skin*.68,.40,z-.015),Vector3(.055,.22,.17),DARK)
 for s in [-1.,1.]:
  var p:=Vector3(s*skin*.72,.67,front-.013)
  if round_lamps:
   ellipse("detail",p,Vector3.RIGHT,Vector3.UP,.145,.117,Vector3.FORWARD,METAL,20)
   active="HeadlightL" if s<0 else "HeadlightR"
   ellipse("headlight",p+Vector3.FORWARD*.006,Vector3.RIGHT,Vector3.UP,.117,0,Vector3.FORWARD,Color.WHITE,20)
  else:
   box("detail",p,Vector3(.32,.21,.035),DARK)
   active="HeadlightL" if s<0 else "HeadlightR"
   box("headlight",p+Vector3.FORWARD*.022,Vector3(.26,.15,.020))
  active="Body"
  box("detail",Vector3(s*skin*.76,.49,front-.034),Vector3(.17,.065,.025),Color("d18528"))
  active="Tail"
  box("tail",Vector3(s*skin*.82,.56 if bes else .67,rear+.022),Vector3(.125,.16 if bes else .20,.027))
  active="Body"
 if not round_lamps:
  box("detail",Vector3(0,.68,front-.02),Vector3(.83,.20,.04),DARK)
  for j in 3: box("detail",Vector3(0,.62+j*.055,front-.044),Vector3(.75,.014,.012),Color("56616a"))
 box("detail",Vector3(0,.40,rear+.09),Vector3(.29,.10,.015),Color("c8c9bf"))

func wheels_new() -> void:
 for c in axles:
  var s:=signf(c.x)
  active="Wheel_%s_%s" % ["L" if s<0 else "R","F" if c.z<0 else "R"]
  var r:=c.y-.015
  for j in 20:
   var a:=TAU*j/20.; var b:=TAU*(j+1)/20.
   tint=Color("24282a")
   quad("wheel",c+Vector3(-.10,sin(a)*r,cos(a)*r),c+Vector3(-.10,sin(b)*r,cos(b)*r),c+Vector3(.10,sin(b)*r,cos(b)*r),c+Vector3(.10,sin(a)*r,cos(a)*r),Vector3(0,sin(a),cos(a)))
  ellipse("wheel",c-Vector3(s*.10,0,0),Vector3.UP,Vector3.BACK,r,0,Vector3(-s,0,0),DARK,20)
  var face:=c+Vector3(s*.104,0,0)
  ellipse("wheel",face,Vector3.UP,Vector3.BACK,r,r*.66,Vector3(s,0,0),DARK,20)
  ellipse("wheel",face+Vector3(s*.002,0,0),Vector3.UP,Vector3.BACK,r*.66,0,Vector3(s,0,0),pale if car_id=="besouro_1300" else METAL,20)
  for j in 8:
   var a:=TAU*j/8.
   ellipse("wheel",face+Vector3(s*.005,sin(a)*r*.49,cos(a)*r*.49),Vector3.UP,Vector3.BACK,.022,0,Vector3(s,0,0),DARK,6)
  ellipse("wheel",face+Vector3(s*.012,0,0),Vector3.UP,Vector3.BACK,r*.31,0,Vector3(s,0,0),METAL if car_id=="besouro_1300" else DARK,16)
  active="Body"
  box("detail",c+Vector3(s*.06,.08,.11),Vector3(.03,.12,.06),Color("775f4a"))
 tint=Color.WHITE

func bake_new() -> Dictionary:
 var nodes:={}
 for bucket: String in groups:
  var parts:=bucket.split("/"); var label:=parts[0]; var key:=parts[1]
  if not nodes.has(label):
   var n:=MeshInstance3D.new(); n.name=label; n.mesh=ArrayMesh.new(); model.add_child(n); n.owner=model; nodes[label]=n
  var n:MeshInstance3D=nodes[label]
  var st:SurfaceTool=groups[bucket]
  st.index()
  if car_id=="besouro_1300" and key=="paint": st=soften(st)
  st.set_material(material(key)); st.commit(n.mesh)
  var roles:Array=n.get_meta("civilian_surface_material_keys",[]); roles.append(key); n.set_meta("civilian_surface_material_keys",roles)
 for s in [-1,1]:
  var leaf:MeshInstance3D=nodes["DoorL" if s<0 else "DoorR"]
  leaf.set_meta("new_civilian_door_side",s)
  leaf.set_meta("new_civilian_door_hinge",Vector3(s*skin,0,float(door.zf)))
 for c in axles:
  var n:MeshInstance3D=nodes["Wheel_%s_%s" % ["L" if c.x<0 else "R","F" if c.z<0 else "R"]]
  n.set_meta("wheel_center",c); n.set_meta("wheel_spins",true)
 var path:="res://assets/fleet/redesigned/"+car_id+".scn"
 var p:=PackedScene.new(); p.pack(model)
 var err:=ResourceSaver.save(p,path,ResourceSaver.FLAG_BUNDLE_RESOURCES)
 var result:=preload("res://tools/fleet_fixups/FleetBatchMesh.gd").counts(model)
 result["path"]=path; result["save_error"]=err
 model.free()
 return result

func run() -> void:
 var metrics:={}
 var only:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--id="): only=arg.trim_prefix("--id=")
 var report_path:="res://artifacts/car-design-implementation-20261019/new-model-geometry.json"
 if not only.is_empty() and FileAccess.file_exists(report_path): metrics=JSON.parse_string(FileAccess.get_file_as_string(report_path))
 for id: String in CATALOG.IDS:
  if not only.is_empty() and id!=only: continue
  setup(id); lower_body(); cabin_shape(); fascia_new(); wheels_new()
  metrics[id]=bake_new()
  print("NEW_CIVILIAN_BAKED ",id," ",JSON.stringify(metrics[id]))
 var folder:="res://artifacts/car-design-implementation-20261019"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 FileAccess.open(folder+"/new-model-geometry.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
 quit()
