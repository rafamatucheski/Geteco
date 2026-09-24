# Santa Mare: doca, porão e estacionamento secreto

Escopo desta entrega na V2: **1 navio com acesso novo, 1 interior 3D distinto, 1 escotilha, 2 tripulantes, 1 tesouro persistente, 3 caminhões de carga e 1 cupê secreto dirigível**. O circuito dos caminhões usa os três guindastes existentes e os trabalhadores do porto.

## Espaço e apresentação

- [x] Escotilha no corredor livre entre a ponte de comando e os contêineres, com indicador compacto compartilhado.
- [x] Porão de 18 × 12 m com corredor central, pilhas laterais, maquinário, escada, iluminação quente sem sombras dinâmicas e câmera fixa ortográfica de 14,5 m.
- [x] Dois NPCs 3D em posições livres; sem textos decorativos no cenário.
- [x] Baú escondido na proa com recompensa de R$ 2.800, concedida uma vez pelo sistema central de economia/save.
- [x] Piso, paredes, prateleiras, máquina e baú têm volumes físicos correspondentes. Entrada, NPCs e recompensa ficam fora desses volumes.
- [x] O enquadramento permite ver os NPCs e o corredor; vigas altas não atravessam o centro da imagem.

## Percurso e evidência visual

- [x] Embarque e retorno à mesma escotilha validados em `tests/test_port_expansion_3d.gd`.
- [x] Colisão de entrada, NPCs, pilhas de carga e circulação verificada no teste integrado.
- [x] Oclusão conferida separadamente na captura final do porão: corredor, baú e os dois tripulantes visíveis, sem vigas sobre suas cabeças.
- [x] Foto anterior do cais: `C:/Users/rafae/.codex/visualizations/2026/09/22/01a0cb72-e1ff-7f03-999f-ecb9602def0a/port-work-v2/before-santa-mare.png`.
- [x] Fotos renderizadas do navio, pátio, porão e carro: `C:/Users/rafae/.codex/visualizations/2026/09/22/01a0cb72-e1ff-7f03-999f-ecb9602def0a/port-work-v2/`.

## Operação e desempenho

- [x] Três caminhões e dois empilhadores aparecem fisicamente no cais; operadores carregam caixas; guindastes pousam contêineres nos caminhões.
- [x] A volta completa até o depósito e de volta ao estado de aproximação passou em `tests/test_port_real_loading_3d.gd` (88,7 s de execução, sem forçar os estados).
- [x] `tests/test_port_expansion_3d.gd`, `tests/test_regions.gd` e `tests/test_coastal_protection.gd` passaram; este último verificou 445 pontos de proteção costeira.
- [ ] Frame time renderizado de 30 s comparado à captura anterior nas mesmas condições. A referência anterior tinha população 3 e perseguição; o jogador morreu durante a captura. O cenário atualizado tinha população 5. Portanto, os p95 de 17,96 ms antes e 17,62 ms depois não demonstram ausência de regressão. Uma amostra adicional com o jogador imóvel e operação ativa teve p95 de 17,60 ms, p99 de 19,41 ms e nenhum quadro acima de 33,3 ms, mas não tem referência anterior controlada.
- [ ] `tests/urban_detail/test_harbor_road_fidelity.gd` retorna 3 falhas: exige que o raio identifique `HarborRoad_202932Solid` em vez do piso do terreno. As duas colisões usam y=0 por decisão anterior de travessia sem degrau; a ordem do primeiro contato varia. Os raios encontraram piso físico e a foto renderizada mostra o asfalto com textura. Falta ajustar essa checagem ao contrato de colisão atual ou confirmar a prioridade da malha da rua.
