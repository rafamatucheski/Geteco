shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// VERSÃO ANTIGA do lago alpino, só para A/B (HARBOR_ALPINE_LAKE_DEPTH=1): fundo lido no depth. Com
// MSAA, isso tirava do jogo inteiro a pré-compilação de pipelines; o jogo usa mountain_lake_alpine.gdshader.
#define LAKE_DEPTH_TEXTURE
#include "res://world/regions/mountain_lake.gdshaderinc"
