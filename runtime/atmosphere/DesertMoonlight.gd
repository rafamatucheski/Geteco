extends RefCounted
## O luar do deserto reaproveita a única fonte direcional e o mapa de sombra do Weather.
## Quem chama fornece a fase lunar existente depois da atenuação das nuvens, para que
## restauração de save, o ciclo de oito dias e tempestades mantenham uma fonte de verdade.

static func apply(sun: DirectionalLight3D, env: Environment, daylight: float, clouds: float, moon: float, desert: float) -> void:
	var night := clampf(desert,0.0,1.0)*(1.0-smoothstep(0.0,0.32,daylight))
	if night<=0.0: return
	var lunar := clampf(moon,0.0,1.0)
	var overcast := clampf(clouds,0.0,1.0)
	var clear := 1.0-overcast*.70
	# Realces prateados pálidos mantêm as cores minerais quentes da areia e da rocha.
	# O contraste direcional deixa o relevo legível sem lavar a noite.
	sun.light_color=sun.light_color.lerp(Color("c9d8ec").lerp(Color("b7c2d0"),overcast),night)
	sun.light_energy*=1.0+night*lunar*clear*.42
	env.ambient_light_energy*=1.0-night*lunar*clear*.08
	env.ambient_light_color=env.ambient_light_color.lerp(Color("8f9eb8"),night*.55)
	# Mantém a lua elevada e as configurações de mapa de sombra existentes: mudar a
	# direção pela posição do jogador faria as sombras deslizarem na costura da região.
	# Silhuetas distantes ficam frias e mais escuras que o terreno próximo ao luar.
	# O céu encoberto mantém o céu escrito do Weather; o StormPresentation aplica depois.
	var air_weight := night*(1.0-overcast)
	env.background_color=env.background_color.lerp(Color("151c2a").lerp(Color("28364e"),lunar),air_weight)
	env.fog_light_color=env.fog_light_color.lerp(Color("161e2b").lerp(Color("293447"),lunar),air_weight)
	env.adjustment_contrast=lerpf(env.adjustment_contrast,1.045,night)
