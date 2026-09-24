# Harbor V1 → V2: fechamento da migração urbana 3D

Data: 22/09/2026. Este documento registra somente o que foi conferido contra a
cidade produtiva criada por `HarborGame`/`HarborPreview`. Uma posição ou um ID
correto não basta para classificar uma área como visualmente fiel.

## Regra de aceitação desta rodada

- Fachada, vegetação, pedra, banco, luminária, ponte e demais elementos visíveis
  precisam ser geometria 3D real. `Sprite3D`, `QuadMesh` com imagem da fachada e
  `SubViewport` projetado não contam como migração.
- Colisão e oclusão são avaliadas separadamente da aparência.
- A fonte visual é o V1 produtivo em `world/harbor/`, não o V2 anterior nem a
  árvore `legacy/`.
- Adaptações da vista 2D para profundidade usam a mesma implantação, proporções,
  paleta e detalhes identificadores da fonte. A profundidade inexistente no V1
  não autoriza inventar outro estabelecimento ou relevo.

## Implementado e verificado

| Conjunto | Fonte V1 | Resultado V2 | Evidência |
|---|---|---|---|
| Malha viária urbana | `HarborRoadLayout`, `UnifiedRoadNetwork2D`, `HarborRoadNetwork` | 39 vias materializadas como superfícies 3D, com cruzamentos e colisão; acessos e quadras usam coordenadas produtivas | `test_harbor_road_fidelity.gd`: 0 falhas |
| Inventário de edifícios | fachadas e lotes instanciados pelos distritos produtivos | 60 edifícios não-Maciota carregam como volumes 3D; nenhum depende de projeção de fachada | `test_harbor_streamed_inventory.gd`: 60/60, 0 falhas |
| Casas geminadas V1 | perfis de brownstones dos distritos | quatro perfis de unidade, volumes e alturas próprios, cornijas, portas, bandeiras, caixilhos, chaminés, mansarda e adereços identificadores | `test_harbor_building_source_fidelity.gd`: 60 cobertos, 0 falhas |
| Fileira comercial | Anchor Diner, Wash & Dry e lojas produtivas | balcão e pendentes internos visíveis, toldos listrados volumétricos e vigias circulares reais da lavanderia | captura `v2-westgate-commercial-oblique.png` e teste de fonte |
| Ponte de Harbor | `HarborBridge.gd`, centro V1 `(3790,400)` | tabuleiro, duas guardas, quatro mastros, 32 estais, juntas, luzes e encontro leste em geometria 3D com colisão; asfalto da via permanece exposto | `test_harbor_bridge_fidelity.gd`: 0 falhas; `v2-bridge-oblique.png` |
| Vegetação e mobiliário inventariado | `HarborDistrict`, `HarborEastDistrict`, `HarborNorthDistrict` | 80 árvores, 10 pedras, 6 bancos e 70 luminárias nas posições da fonte, todos feitos de malhas 3D e carregados pelo chunk correspondente | `test_harbor_prop_3d_fidelity.gd`: 166/166, 0 falhas |
| Espaços públicos e bordas | praça, Northbank, Cobra, ferro-velho e cemitério produtivos | superfícies, caminhos, canteiros e elementos principais em volumes 3D; o cemitério preserva a grade produtiva de 34 sepulturas | capturas `v2-market-oblique.png`, `v2-northbank.png`, `v2-cobra-oblique.png` |

O antigo `HarborV1BuildingProjection.gd` ficou apenas como sentinela de
compatibilidade: não cria malha, textura ou viewport e falha explicitamente se um
chamador futuro tentar reativá-lo. A busca de chamadas atual não encontrou usuário
em runtime.

## Comparabilidade visual por área

| Área | Captura V2 | Estado honesto | Diferenças restantes |
|---|---|---|---|
| Maciota → fileira comercial | `v2-westgate-commercial-oblique.png` | conversão 3D comprovada; fidelidade parcial | Maciota é montado pela sessão, fora do `NativeRegion`; falta a comparação conjunta em jogo e ainda há laterais/fundos simplificados em alguns prédios |
| Market / Breakwater | `v2-market-oblique.png` | melhorado, ainda divergente | viaduto e trem produtivos ausentes; alguns acabamentos traseiros e cobertura ainda são aproximações |
| Northbank / expansão norte | `v2-northbank.png`, `v2-north-expansion.png` | geometria e adereços 3D presentes; fidelidade parcial | formas especiais de bocas terminais, alargamentos e quinas ainda não reproduzem toda a silhueta V1 |
| Ponte | `v2-pair-bridge.png`, `v2-bridge-oblique.png` | estrutura 3D funcional e reconhecível | precisa de comparação final em sessão completa com iluminação equivalente antes de declarar identidade material perfeita |
| Porto Sul | `v2-south-port-oblique.png` | conteúdo 3D existente, divergente | conjunto portuário continua simplificado em relação ao V1; não está aprovado visualmente |
| Cobra / Ashbend | `v2-cobra-oblique.png` | implantação e dressing 3D presentes; fidelidade parcial | faltam conferência a pé de todos os acessos e paridade das formas de borda |
| Viaduto, ferrovia e túnel | sem captura V2 equivalente aprovada | pendente e bloqueador de fidelidade global | portar `HarborRailLine.gd`/`RailStructure3D.gd`, incluindo estrutura elevada, entrada do túnel e oclusão; não substituir por decoração genérica |

## Validações dirigidas

- `test_urban_building_factory.gd -- --no-save`: 61 registros aprovados.
- `test_harbor_building_source_fidelity.gd -- --no-save`: 60 edifícios,
  0 falhas.
- `test_harbor_streamed_inventory.gd -- --no-save`: 60 edifícios carregados,
  0 falhas.
- `test_harbor_road_fidelity.gd -- --no-save`: 0 falhas.
- `test_harbor_bridge_fidelity.gd -- --no-save`: 0 falhas.
- `test_harbor_prop_3d_fidelity.gd -- --no-save`: 166 elementos, 0 falhas.

Os testes foram dirigidos e executados com `--no-save`; nenhum save pessoal foi
aberto. As capturas comprovam materialização e permitem comparação visual, mas não
substituem percurso jogável nem medição de FPS.

## Pendências priorizadas para implementação

1. **P0 — ferrovia, viaduto e túnel:** ausência muda a identidade e o horizonte do
   Market; é o maior bloqueador urbano restante.
2. **P0 — Porto Sul:** substituir simplificações pelos modelos, materiais,
   implantação e detalhes produtivos V1.
3. **P1 — ruas de borda:** fechar bocas terminais, alargamentos do norte, quina
   arredondada, acessos Ashbend e aberturas nas margens.
4. **P1 — edifícios:** completar identidade de laterais e fundos, além do frontão
   e das colunas do banco, sem reintroduzir imagem plana.
5. **P1 — comparação em sessão:** capturar Maciota e a fileira comercial juntos,
   no mesmo centro, horário e escala aparente do V1; depois percorrer todas as vias
   validando colisão e oclusão separadamente.
6. **P2 — desempenho:** repetir o benchmark renderizado somente quando não houver
   editor, importação ou teste concorrente. Não há aprovação de performance nesta
   rodada.

Tráfego, atores, HUD, câmera e iluminação central não foram alterados. Não houve
commit, descarte de alterações nem benchmark concorrente.
