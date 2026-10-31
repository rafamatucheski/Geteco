extends RefCounted
## Trilhos elevados podem entrar no plano próximo ortográfico enquanto o Dante está na
## rua embaixo. Recua ao longo do eixo de visão, preservando o enquadramento da tela.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const MARGIN := 2.0
var _segments: Array[PackedVector3Array] = []
var _last_focus := Vector3.INF
var _last_back := Vector3.ZERO
var _last_view := Vector2.ZERO
var _required := 0.0
var _clock := 1.0

func offset_for(focus: Vector3, nominal: Vector3, view: Vector2, near_clip: float, delta := .1) -> Vector3:
	if nominal.length_squared()<.01: return nominal
	if _segments.is_empty():
		for edge in NETWORK.edges(): _segments.append(edge.points)
	var back := nominal.normalized()
	_clock+=maxf(delta,0.0)
	if focus.is_equal_approx(_last_focus) and back.is_equal_approx(_last_back) and view.is_equal_approx(_last_view):
		return back*maxf(nominal.length(),_required)
	var fresh := not _last_focus.is_finite() or focus.distance_to(_last_focus)>4.0 or back.distance_to(_last_back)>.08 or view.distance_to(_last_view)>2.0
	if not fresh and _clock<.1: return back*maxf(nominal.length(),_required)
	_clock=0.0; _last_focus=focus; _last_back=back; _last_view=view
	var right := Vector3.UP.cross(back).normalized()
	var up := back.cross(right).normalized()
	var distance := nominal.length()
	# Inclui o volume inteiro do tabuleiro/parapeito elevado e uma guarda de entrada, em vez
	# de só a linha central do trilho. Isto não carrega nem revela chunk nenhum.
	var half_view := view*.5+Vector2.ONE*8.0
	for points in _segments:
		for i in points.size()-1:
			var a := points[i]-focus
			var b := points[i+1]-focus
			var screen_a := Vector2(a.dot(right),a.dot(up))
			var screen_b := Vector2(b.dot(right),b.dot(up))
			if not Rect2(-half_view,half_view*2).intersects(Rect2(screen_a,Vector2.ZERO).expand(screen_b),true): continue
			# Half-width 3.4m, rail/fence +1.1m and slab underside -0.8m.
			var support := absf(back.x)*3.4+absf(back.z)*3.4+maxf(back.y*1.1,-back.y*.8)
			distance=maxf(distance,maxf(a.dot(back),b.dot(back))+support+near_clip+MARGIN)
	_required=distance
	return back*distance
