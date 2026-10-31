extends RefCounted
## Uma máscara de união no terreno: cruzamentos nunca empilham quads translúcidos de estrada.
const CELL := 64.0
const STEP := 0.5
const SIZE := 129
var cells: Dictionary = {}

func configure(roads: Array) -> void:
	cells.clear()
	for road in roads:
		var points: PackedVector3Array = road.points
		var asphalt: bool = road.get("surface", "asphalt") == "asphalt"
		var half: float = float(road.width)*0.5
		var outer := half + (1.65 if asphalt else 1.4)
		var inner := half + 0.25 if asphalt else half*0.65
		for i in range(points.size()-1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i+1].x, points[i+1].z)
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(outer)
			var first := Vector2i((bounds.position/CELL).floor())
			var last := Vector2i((bounds.end/CELL).floor())
			for x in range(first.x,last.x+1):
				for y in range(first.y,last.y+1):
					var key := Vector2i(x,y)
					if not cells.has(key): cells[key] = []
					cells[key].append({"a":a,"b":b,"inner":inner,"outer":outer,"bounds":bounds})

func image_for(rect: Rect2) -> Image:
	return Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_R8,mask_for(rect))

## Só os bytes da máscara: conta pura sobre `cells` (escrito apenas em configure), segura num trabalhador.
## O terreno da serra calcula a máscara fora do thread principal e cria a Image/textura ao montar o trecho.
func mask_for(rect: Rect2) -> PackedByteArray:
	var values := PackedByteArray()
	values.resize(SIZE*SIZE)
	for segment in cells.get(Vector2i((rect.position/CELL).floor()),[]):
		var bounds: Rect2 = segment.bounds.intersection(rect)
		var first := Vector2i(((bounds.position-rect.position)/STEP).floor()).clamp(Vector2i.ZERO,Vector2i(SIZE-1,SIZE-1))
		var last := Vector2i(((bounds.end-rect.position)/STEP).ceil()).clamp(Vector2i.ZERO,Vector2i(SIZE-1,SIZE-1))
		var a: Vector2 = segment.a
		var b: Vector2 = segment.b
		var outer := float(segment.outer)
		for y in range(first.y,last.y+1):
			# Só a faixa da linha que a cápsula do trecho (raio outer) cruza: fora dela o peso é 0 e não muda o
			# máximo. A caixa inteira de um trecho diagonal cobria quase o trecho de 64 m (16.641 pixels por
			# segmento em GDScript) no estágio de superfícies da serra, que travava 20-80 ms em jogo (15/10).
			var row_y := rect.position.y+y*STEP
			var t0 := 0.0
			var t1 := 1.0
			if not is_zero_approx(b.y-a.y):
				t0 = (row_y-outer-a.y)/(b.y-a.y)
				t1 = (row_y+outer-a.y)/(b.y-a.y)
				if t0 > t1:
					var swap := t0
					t0 = t1
					t1 = swap
				t0 = maxf(t0,0.0)
				t1 = minf(t1,1.0)
				if t0 > t1: continue
			elif absf(row_y-a.y) > outer: continue
			var x0 := a.x+(b.x-a.x)*t0
			var x1 := a.x+(b.x-a.x)*t1
			var row_first := maxi(first.x,floori((minf(x0,x1)-outer-rect.position.x)/STEP))
			var row_last := mini(last.x,ceili((maxf(x0,x1)+outer-rect.position.x)/STEP))
			for x in range(row_first,row_last+1):
				var point := rect.position+Vector2(x,y)*STEP
				var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,segment.a,segment.b))
				var weight := 1.0-smoothstep(float(segment.inner),float(segment.outer),distance)
				var index := y*SIZE+x
				values[index] = maxi(values[index],roundi(weight*255.0))
	return values
