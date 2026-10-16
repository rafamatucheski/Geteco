shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Lagos sem bacia (glacial, secreto): não leem o buffer de profundidade. Basta UM material
// vivo com hint_depth_texture para o Forward Mobile, com MSAA, desenhar o jogo inteiro num
// framebuffer que a pré-compilação de pipelines não cobre (ver occluded_silhouette.gdshader);
// o lago alpino tira o fundo do mapa de alturas do terreno (mountain_lake_alpine.gdshader).
#include "res://world/regions/mountain_lake.gdshaderinc"
