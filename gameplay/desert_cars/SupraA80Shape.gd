extends RefCounted
## Authored A80 surface in metres, nose at -Z. Rounded long bonnet, narrow
## greenhouse and broad rear quarters; door skins stay planar for boarding.
const SECTIONS := 48
const CROSS_SECTIONS := 12

static func build(root: Node3D, s: Dictionary, paint: Material, glass: Material, dark: Material) -> void:
	_shell(root,s,paint)
	_cabin(root,s,paint,glass,dark)
	_arches(root,s,paint)

## Flat door skins preserve the real door cutter and side-vinyl contract;
## muscular haunches and the rounded ends begin beyond the door area.
static func _half_width(s: Dictionary, z: float) -> float:
	var w := float(s["size"][0])
	var t := absf(z)/float(s["size"][2])
	var shoulder := .012*exp(-pow((t-.285)/.075,2.0))*smoothstep(.20,.255,t)
	return w*(.48+shoulder-.075*smoothstep(.40,.495,t))

static func _rounded_z(s: Dictionary, x: float, z: float) -> float:
	var t := absf(z)/(float(s["size"][2])*.495)
	return z-signf(z)*.13*pow(absf(x)/_half_width(s,z),2.0)*pow(t,10.0)

static func deck_point(s: Dictionary, x: float, z: float) -> Vector3:
	var t := absf(z)/(float(s["size"][2])*.495)
	var half := _half_width(s,z)
	var end_drop := .215*smoothstep(.73,1.0,t) if z < 0.0 else .025*pow(t,3.0)
	var y := float(s.shoulder)-end_drop+.032*(1.0-pow(x/half,2.0))
	return Vector3(x,y,_rounded_z(s,x,z))

static func _rounding(s: Dictionary,z: float) -> float:
	return smoothstep(.17,.255,absf(z)/float(s.size[2]))

static func _deck_width(s: Dictionary,z: float) -> float:
	return _half_width(s,z)-.042*_rounding(s,z)

static func side_point(s: Dictionary, side: float, z: float, y: float) -> Vector3:
	var sill := float(s.wheel_radius)*.72
	var top := deck_point(s,_deck_width(s,z),z).y
	var fraction := clampf((y-sill)/maxf(.1,top-sill),0.0,1.0)
	var inset := (.023*(1.0-smoothstep(0.0,.22,fraction))+.042*smoothstep(.64,1.0,fraction))*_rounding(s,z)
	var x := side*(_half_width(s,z)-inset)
	return Vector3(x,y,_rounded_z(s,x,z))

static func _lower(s: Dictionary, z: float) -> float:
	var r := float(s.wheel_radius)
	var low := r*.72
	var arch := r+.042
	for axle in [-1.0,1.0]:
		var gap: float = absf(z-axle*float(s.get("wheelbase",2.55))*.5)
		if gap < arch: low = maxf(low,r+sqrt(maxf(0.0,arch*arch-gap*gap)))
	return low

static func _sections(s: Dictionary) -> Array[float]:
	var l := float(s["size"][2])
	var arch := float(s.wheel_radius)+.042
	var sections: Array[float] = []
	for i in SECTIONS+1: sections.append(lerpf(-l*.495,l*.495,float(i)/SECTIONS))
	# Near-vertical arch ends are explicit stations, not a coarse diagonal cut.
	for axle in [-1.0,1.0]:
		for sign_z in [-1.0,1.0]:
			sections.append(axle*float(s.get("wheelbase",2.55))*.5+sign_z*(arch+.001))
			sections.append(axle*float(s.get("wheelbase",2.55))*.5+sign_z*(arch-.001))
	# The cabin aperture starts on exact rows, so no deck triangles extend
	# underneath the windscreen or hatch when their glass becomes transparent.
	sections.append(l*float(s.cabin_front))
	sections.append(l*float(s.cabin_back))
	sections.sort()
	return sections

static func _shell(root: Node3D, s: Dictionary, paint: Material) -> void:
	var st := _tool()
	var sections := _sections(s)
	var cabin_half := float(s["size"][0])*.456
	var cabin_front := float(s["size"][2])*float(s.cabin_front)
	var cabin_back := float(s["size"][2])*float(s.cabin_back)
	var window_end := minf(float(s["size"][2])*float(s.door_back)-.13,float(s["size"][2])*.235)
	for z in _cabin_sections(s,cabin_front+.105,window_end,float(s.get("shoulder",.76))+.067):
		sections.append(z)
	sections.sort()
	for i in sections.size()-1:
		var za := sections[i]
		var zb := sections[i+1]
		if zb-za < .00001: continue
		if (za+zb)*.5 > cabin_front and (za+zb)*.5 < cabin_back:
			for side in [-1.0,1.0]:
				_quad(st,deck_point(s,side*cabin_half,za),deck_point(s,side*_deck_width(s,za),za),deck_point(s,side*_deck_width(s,zb),zb),deck_point(s,side*cabin_half,zb),Vector3.UP)
		else:
			for j in CROSS_SECTIONS:
				var ua := lerpf(-1.0,1.0,float(j)/CROSS_SECTIONS)
				var ub := lerpf(-1.0,1.0,float(j+1)/CROSS_SECTIONS)
				_quad(st,deck_point(s,ua*_deck_width(s,za),za),deck_point(s,ub*_deck_width(s,za),za),deck_point(s,ub*_deck_width(s,zb),zb),deck_point(s,ua*_deck_width(s,zb),zb),Vector3.UP)
		for side in [-1.0,1.0]:
			var top_a := deck_point(s,side*_deck_width(s,za),za)
			var top_b := deck_point(s,side*_deck_width(s,zb),zb)
			for row in 6:
				var low := float(row)/6.0
				var high := float(row+1)/6.0
				_quad(st,side_point(s,side,za,lerpf(_lower(s,za),top_a.y,low)),side_point(s,side,zb,lerpf(_lower(s,zb),top_b.y,low)),side_point(s,side,zb,lerpf(_lower(s,zb),top_b.y,high)),side_point(s,side,za,lerpf(_lower(s,za),top_a.y,high)),Vector3(side,0,0))
	for end in [-1.0,1.0]:
		var z: float = end*float(s["size"][2])*.495
		for j in 20:
			var xa := lerpf(-_deck_width(s,z),_deck_width(s,z),float(j)/20.0)
			var xb := lerpf(-_deck_width(s,z),_deck_width(s,z),float(j+1)/20.0)
			var a := deck_point(s,xa,z)
			var b := deck_point(s,xb,z)
			for row in 6:
				var low := float(row)/6.0
				var high := float(row+1)/6.0
				_quad(st,_end_point(s,a,z,low),_end_point(s,b,z,low),_end_point(s,b,z,high),_end_point(s,a,z,high),Vector3(0,0,end))
	_commit(root,"SupraBodyShell",st,paint)

static func _end_point(s: Dictionary,top: Vector3,z: float,ratio: float) -> Vector3:
	var y := lerpf(float(s.wheel_radius)*.72,top.y,ratio)
	var x := top.x/_deck_width(s,z)*side_point(s,1.0,z,y).x
	return Vector3(x,y,_rounded_z(s,x,z))

## x = half width, y = edge height, z = longitudinal station.
static func _stations(s: Dictionary) -> Array[Vector3]:
	var w := float(s["size"][0])
	var h := float(s["size"][1])
	var l := float(s["size"][2])
	var belt := float(s.get("shoulder",.76))
	var front := l*float(s.cabin_front)
	var back := l*float(s.cabin_back)
	var roof_front := l*float(s.roof_front)
	var roof_back := l*float(s.roof_back)
	return [Vector3(w*.402,belt+.023,front),Vector3(w*.358,lerpf(belt,h,.62),lerpf(front,roof_front,.52)),Vector3(w*.335,h-.062,roof_front),Vector3(w*.332,h-.043,(roof_front+roof_back)*.5),Vector3(w*.342,h-.062,roof_back),Vector3(w*.385,lerpf(h,belt,.55),lerpf(roof_back,back,.55)),Vector3(w*.409,belt+.023,back)]

static func _station_at(s: Dictionary, z: float) -> Vector3:
	var stations := _stations(s)
	for i in range(1,stations.size()):
		if z <= stations[i].z:
			var ratio := clampf((z-stations[i-1].z)/(stations[i].z-stations[i-1].z),0.0,1.0)
			return stations[i-1].lerp(stations[i],ratio)
	return stations[-1]

static func roof_point(s: Dictionary, x: float, z: float) -> Vector3:
	var station := _station_at(s,z)
	var crown := .040*(1.0-pow(x/station.x,2.0))
	return Vector3(x,station.y+crown,z)

static func _cabin_side(s: Dictionary, side: float, z: float, y: float) -> Vector3:
	var station := _station_at(s,z)
	var half := float(s["size"][0])*.456
	var base := deck_point(s,side*half,z)
	var ratio := clampf((y-base.y)/maxf(.01,station.y-base.y),0.0,1.0)
	return Vector3(side*lerpf(half,station.x,ratio),y,lerpf(base.z,z,ratio))

static func _cabin_sections(s: Dictionary, window_begin: float, window_end: float, low: float) -> Array[float]:
	var stations := _stations(s)
	var sections: Array[float] = []
	for station in stations: sections.append(station.z)
	# Share every deck-edge vertex with the cabin foot to avoid tiny cracks
	# between differently tessellated curves.
	for z in _sections(s):
		if z > stations[0].z and z < stations[-1].z: sections.append(z)
	for i in 25: sections.append(lerpf(window_begin,window_end,float(i)/24.0))
	# Include the exact tapered window tip; the opening closes to one vertex
	# instead of leaving a skipped segment or a sudden rectangular notch.
	for i in stations.size()-1:
		var a := stations[i]
		var b := stations[i+1]
		var tip := low+.065
		if (a.y-tip)*(b.y-tip) < 0.0:
			sections.append(lerpf(a.z,b.z,(tip-a.y)/(b.y-a.y)))
	sections.sort()
	return sections

static func _cabin(root: Node3D, s: Dictionary, paint: Material, glass: Material, dark: Material) -> void:
	var shell := _tool()
	var glazing := _tool()
	var trim := _tool()
	var stations := _stations(s)
	var belt := float(s.get("shoulder",.76))+.012
	var half := float(s["size"][0])*.456
	for i in stations.size()-1:
		var a := stations[i]
		var b := stations[i+1]
		for j in 16:
			var ua := lerpf(-1.0,1.0,float(j)/16.0)
			var ub := lerpf(-1.0,1.0,float(j+1)/16.0)
			# Windshield and hatch glazing are bounded by painted outer strips;
			# no buried rectangular glass planes or opaque cabin box.
			var is_glass := i in [0,1,4,5] and j>0 and j<15
			var target: SurfaceTool = glazing if is_glass else shell
			_quad(target,roof_point(s,ua*a.x,a.z),roof_point(s,ub*a.x,a.z),roof_point(s,ub*b.x,b.z),roof_point(s,ua*b.x,b.z),Vector3.UP)
	# The side windows replace the skin rather than floating on painted panels.
	# Broad rear pillars frame the A80's long, rounded hatch glass.
	var l := float(s["size"][2])
	var window_begin := l*float(s.cabin_front)+.105
	var window_end := minf(l*float(s.door_back)-.13,l*.235)
	var low := belt+.055
	var sections := _cabin_sections(s,window_begin,window_end,low)
	for side in [-1.0,1.0]:
		for i in sections.size()-1:
			var za := sections[i]
			var zb := sections[i+1]
			if zb-za < .00001: continue
			var top_a := _station_at(s,za).y
			var top_b := _station_at(s,zb).y
			var base_a := deck_point(s,side*half,za).y
			var base_b := deck_point(s,side*half,zb).y
			var outward := Vector3(side,0,0)
			var middle := (za+zb)*.5
			var window := middle > window_begin and middle < window_end and maxf(top_a,top_b) > low+.065
			if not window:
				_quad(shell,_cabin_side(s,side,za,base_a),_cabin_side(s,side,zb,base_b),_cabin_side(s,side,zb,top_b),_cabin_side(s,side,za,top_a),outward)
				continue
			var lower_a := minf(low,top_a)
			var lower_b := minf(low,top_b)
			var upper_a := clampf(top_a-.065,lower_a,top_a)
			var upper_b := clampf(top_b-.065,lower_b,top_b)
			_quad(shell,_cabin_side(s,side,za,base_a),_cabin_side(s,side,zb,base_b),_cabin_side(s,side,zb,lower_b),_cabin_side(s,side,za,lower_a),outward)
			_quad(shell,_cabin_side(s,side,za,upper_a),_cabin_side(s,side,zb,upper_b),_cabin_side(s,side,zb,top_b),_cabin_side(s,side,za,top_a),outward)
			_quad(glazing,_cabin_side(s,side,za,lower_a),_cabin_side(s,side,zb,lower_b),_cabin_side(s,side,zb,upper_b),_cabin_side(s,side,za,upper_a),outward)
			var rail := Vector3(side*.003,0,0)
			_quad(trim,_cabin_side(s,side,za,lower_a-.018)+rail,_cabin_side(s,side,zb,lower_b-.018)+rail,_cabin_side(s,side,zb,lower_b)+rail,_cabin_side(s,side,za,lower_a)+rail,outward)
	# Close the cowl and parcel lip onto the real deck, including its crowned
	# surface and rounded longitudinal edges. Only the glazing spans the cabin.
	for station: Vector3 in [stations[0],stations[-1]]:
		var outward := Vector3(0,0,-1 if station.z < 0.0 else 1)
		for j in 16:
			var ua := lerpf(-1.0,1.0,float(j)/16.0)
			var ub := lerpf(-1.0,1.0,float(j+1)/16.0)
			_quad(shell,deck_point(s,ua*half,station.z),deck_point(s,ub*half,station.z),roof_point(s,ub*station.x,station.z),roof_point(s,ua*station.x,station.z),outward)
	# A recessed underbody closes the aperture below the separate cabin floor;
	# boarding can reveal the interior without exposing the road through it.
	var floor_front := stations[0].z
	var floor_back := stations[-1].z
	var underbody_y := float(s.wheel_radius)*.72-.018
	_quad(trim,Vector3(-half,underbody_y,floor_front),Vector3(half,underbody_y,floor_front),Vector3(half,underbody_y,floor_back),Vector3(-half,underbody_y,floor_back),Vector3.UP)
	_commit(root,"SupraCabinShell",shell,paint)
	_commit(root,"SupraGlazing",glazing,glass)
	_commit(root,"SupraWindowSeals",trim,dark)

static func _arches(root: Node3D, s: Dictionary, paint: Material) -> void:
	var st := _tool()
	var r := float(s.wheel_radius)
	for side in [-1.0,1.0]:
		for axle in [-1.0,1.0]:
			for i in 20:
				var a := PI*float(i)/20.0
				var b := PI*float(i+1)/20.0
				var za: float = axle*float(s.get("wheelbase",2.55))*.5+cos(a)*(r+.042)
				var zb: float = axle*float(s.get("wheelbase",2.55))*.5+cos(b)*(r+.042)
				var aa := side_point(s,side,za,r+sin(a)*(r+.042))+Vector3(side*.006,0,0)
				var bb := side_point(s,side,zb,r+sin(b)*(r+.042))+Vector3(side*.006,0,0)
				_quad(st,aa,bb,bb+Vector3(0,.026,0),aa+Vector3(0,.026,0),Vector3(side,0,0))
	_commit(root,"SupraArchLips",st,paint)

static func _tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	return st

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (c-a).cross(b-a)
	if normal.length_squared()<0.00000001: return
	var points := [a,b,c] if normal.dot(outward)>=0.0 else [a,c,b]
	for point: Vector3 in points:
		st.set_uv(Vector2(point.x,point.z))
		st.add_vertex(point)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_triangle(st,a,b,c,outward)
	_triangle(st,a,c,d,outward)

static func _commit(root: Node3D, label: String, st: SurfaceTool, material: Material) -> MeshInstance3D:
	st.generate_normals()
	st.index()
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = st.commit()
	part.material_override = material
	root.add_child(part)
	return part
