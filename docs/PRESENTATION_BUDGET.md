# Apresentação sob demanda dos moradores do porto

HarborWalker opta por `defer_presentation` antes da inicialização base. Colisão,
rota, estado e cores existem imediatamente; uma silhueta Polygon2D representa
o cidadão enquanto ele aguarda o rig. Os demais tipos mantêm criação síncrona.

PresentationBudget seleciona o cidadão visível mais próximo do centro da câmera,
incluindo uma margem de 220 pixels de tela. Cria no máximo um rig por frame,
com orçamento de 2000 microssegundos verificado entre construções. Um rig
individual não pode ser interrompido. O processamento continua durante cutscenes
pausadas e descarta referências liberadas nas trocas de cena.

CitizenDetails aguarda presentation_ready para aplicar acessórios. Incapacitação
ou morte anterior à construção é aplicada ao modelo recém-criado. Rigs já criados
continuam usando o LOD existente; não há descarregamento ou pool de rigs neste patch.
O tráfego e carros estacionados da ModernTrafficFactory também participam da fila,
com atlas 2D e colisões definitivas enquanto aguardam. Repintura fica registrada;
entrada do jogador ou impacto força conclusão para preservar portas e danos.
Moradores e chefe das Cobras aplicam armas/acessórios pelo sinal de conclusão.
Unidades de emergência mantêm o sprite no pool e constroem o modelo no despacho,
antes de usar colisões e portas derivadas da geometria; reutilizações mantêm o rig.
Carros específicos derivados de PlayerCar e cenários ainda usam seu fluxo original.

Extensão: perfil Vulkan registrou pico de 5047 ms, 118 viewports, VRAM 745,3 MB
e memória estática 425,2 MB. Ainda há congelamento inicial. Testes específicos
de streaming e chefe passaram, assim como o LOD de tráfego. Os testes amplos
do cupê e estacionamento ainda falharam respectivamente no embarque do cupê
e despacho policial; a ambulância saiu e retornou corretamente. Não se afirma
que essas falhas são anteriores ao patch sem uma reprodução comparativa.

Validação: teste novo test_presentation_budget, pedestrian_render_lod,
pedestrian_life_routines, opening_cutscene_runtime e menu_flow_integration
concluíram com código zero. check_references não encontrou quebras novas.

Perfil Vulkan desta versão: 185 SubViewport, 4113 MeshInstance3D, VRAM 1014,9 MB,
memória estática 533,3 MB, pico inicial 8075 ms. A referência anterior registrada
tinha 249 SubViewport e 1292,7 MB de VRAM. São amostras individuais; não demonstram
ganho estável de tempo nem isolam a causa do congelamento restante. O aviso de
uma instância ObjectDB ao sair continua presente nos testes de mundo/menu.
