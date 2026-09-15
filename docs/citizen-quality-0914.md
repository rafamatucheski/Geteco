# Qualidade dos pedestres — 14/09/2026

## Revisão após feedback: braços e diversidade

O usuário apontou corretamente que os cotovelos dobravam para trás na corrida. O sinal da flexão foi corrigido em `CitizenGait.gd`; o balanço de ombros continua em oposição às pernas. `test_citizen_run_arms.gd` reproduziu a falha anterior e passou depois da correção, verificando a posição real do punho em relação ao cotovelo nos cinco portes, quatro perfis e quatro direções. O braço do copo também foi corrigido, mantendo a compensação que deixa o copo vertical. Portes cheios ganharam afastamento lateral suficiente dos braços para acomodar a cintura.

`CitizenMorphology.gd` agora modela cintura, barriga e quadril durante a construção. Roupa, costuras e acessórios recebem a mesma deformação, com subdivisão vertical dos detalhes e do tronco para acompanhar a curvatura. Os cálculos por altura são reutilizados na construção; não há deformação de malha por frame. Pernas e mandíbula acompanham a diferença entre corpos magros e cheios.

O novo `beard_style_override` permite escolher entre automático (-1), sem barba (0), barba rala (1), curta (2), cheia (3), cavanhaque (4) e bigode (5). O modo automático deriva da identidade; reconstruir o mesmo cidadão no mesmo papel mantém sua barba. A barba cheia tem volume próprio abaixo do queixo; a barba não recobre a nuca.

Evidências desta revisão: `D:/geteco/artifacts/citizens-diversity-0914/`. `gallery/front.png`, `side.png`, `back.png` e `gallery/movimento.mp4` mostram seis variações e o Dante com câmera/luz equivalentes. É uma prévia dos rigs de produção, não uma medição de performance da cidade.

Validação da revisão: `test_citizen_run_arms.gd`, `test_citizen_diversity.gd`, `test_citizen_quality.gd` (24 arquétipos e objetos nos cinco portes), `test_npc_personality.gd`, `test_civilian_identity.gd` (85 verificações) e `test_npc_shared_presentation.gd` (283 verificações), sem falhas. A validação de FPS abaixo continua pendente: foram observados outros processos de gameplay renderizado e testes headless concorrentes; não foi produzida uma nova certificação de performance.

## Implementação

O caminho de produção de `AnimatedPedestrian3D` agora constrói o corpo e os detalhes em `CitizenSculpt.gd`, usando `CitizenGeometry.gd` para consolidar as peças estáticas de cada articulação. Isso alcança os 24 arquétipos da classe, os pedestres de rotas e os Cobras que a herdam. Não migra os construtores independentes de policiais de perseguição, atendentes, motoristas ou personagens especiais de interiores.

- Crânio e mandíbula com seções próprias, variação de bochechas, nariz, olhos e mandíbula; pele e detalhes faciais em uma malha.
- Cabelo com base contínua, oito estilos, mechas curvas, volume lateral e material fosco. Chapéus existentes preservados e ajustados à nova cabeça.
- Tronco com cintura e ombros, camisa/blazer, gola, punhos, mãos com polegar, calças e calçados com sola e cadarços. `BodyShell` continua apontando para a malha real.
- Coxa e canela articuladas de 0,32/0,29 unidades locais. A passada usa os comprimentos dos ossos e a projeção do deslocamento real no piso. Mantém quatro perfis, apoio na caminhada, voo na corrida e transição para repouso ao parar.
- Somente o braço ocupado reduz o balanço. O copo fica na vertical; a bengala liga a mão ao piso, inclusive nos cinco portes.
- Nenhuma mudança intencional em velocidade, colisão, navegação, vida, combate ou resolução/frequência dos SubViewports. A resolução permanece em 96 × 96 até haver orçamento renderizado confiável para ampliá-la.

As referências casual, executiva e morador estão em `tests/capture_citizen_quality.gd`, construídas pelo mesmo caminho de produção e com propriedades explícitas para comparação. Os novos detalhes são agrupados por articulação e material, sem loops de modelagem por frame. O Dante permanece como referência, sem alterações por esta tarefa.

## Evidências

Diretório: `D:/geteco/artifacts/citizens-quality-0914/`.

- `before/faces.png`: registro inicial dos modelos, com a câmera de comparação existente.
- `gallery/front.png`, `side.png`, `back.png`: três identidades e o Dante sob a mesma câmera, escala de projeção e iluminação.
- `gallery/movimento.mp4`: prévia isolada dos rigs reais em repouso, caminhada, corrida e parada. A cadência usa velocidade em unidades do modelo; não é um vídeo de deslocamento nativo pela cidade.
- `after-performance/street.png`: integração renderizada no mapa durante a primeira medição, antes dos refinamentos finais de cabelo e objetos carregados.
- `before-source/` e `character-changes.patch`: cópias anteriores e diferenças dos três arquivos de personagens existentes alterados.

## Validação funcional

Com Godot 4.7.2, chamadas `--headless --path D:/geteco/game --script res://tests/<arquivo>`:

| Teste | Resultado |
|---|---|
| `test_citizen_quality.gd` | 24 arquétipos sem falhas de apoio/voo/projeção; copo e bengala também verificados nos cinco portes |
| `test_npc_personality.gd` | Aprovado: repouso, oposição de perfis, cabeça, piso e braço armado |
| `test_citizen_gait_lifecycle.gd` | Aprovado: construção adiada, movimento antes do rig e reconfiguração dos pés |
| `test_civilian_identity.gd` | 85 verificações, zero falhas |
| `test_npc_shared_presentation.gd` | 283 verificações, zero falhas, incluindo suporte de armas em diferentes portes |
| `test_pedestrian_render_lod.gd` | Aprovado: 60 Hz perto, 30/15 Hz conforme projeção, culling e retomada |
| `test_npc_obstacle_navigation.gd` | Aprovado: poste, veículo estacionado, corredor e obstáculo novo |
| `test_pedestrian_life_routines.gd` | Aprovado: circulação, repouso e visita com restauração de colisão |
| `test_garage_weapon_restrictions.gd` | Zero falhas no fluxo real de entrada/saída, restrições e proteção dos personagens |

O teste antigo de personalidade presumia apoio durante metade de toda passada, mesmo correndo. Foi atualizado para exigir apoio na fase correspondente e complementado pela verificação de voo, contato e deslocamento real no novo teste. Nenhuma tolerância de penetração foi ampliada.

Durante o trabalho houve erros transitórios de compilação em arquivos de emergência sendo alterados por outras tarefas. A única correção desta tarefa fora dos personagens foi a anotação `Vector2` da variável `end` em `HospitalArrival.gd`. As execuções finais listadas acima carregaram sem aqueles erros. A suíte global não foi executada.

## Performance — pendente, não aprovada

Meta provisória: 60 FPS / 16,67 ms. Sinal de investigação: piora superior a 5% em p95/p99. Ambiente observado: RTX 4060 Laptop, Vulkan Mobile, Godot 4.7.2, 1280 × 720, limite 60 FPS, VSync efetivo desligado.

O medidor `tests/measure_citizen_quality.gd` usa HarborGame, salva em diretório próprio, separa 10 segundos de aquecimento e 30 segundos de amostra, e grava todos os frames em CSV.

| Amostra | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Inicial | 57,67 | 16,49 | 22,95 | 29,57 | 153,87 | 9 | 3 |
| Primeira integração | 38,94 | 25,07 | 36,99 | 45,24 | 75,86 | 124 | 1 |

Esses números não isolam o custo dos personagens: outros processos de testes renderizados e headless estavam usando a máquina, arquivos/autoloads do mapa mudaram durante a tarefa, e a população ativa final diferiu (44 contra 51 pedestres). O orçamento inicial já não era atendido. A piora observada não foi descartada nem atribuída definitivamente ao rig.

Uma tentativa A/B com `--baseline-rig`, que recarrega somente os scripts antigos em memória nesse processo, foi interrompida após erro de compilação de um autoload que estava sendo editado. Não há amostra A/B válida nem certificação dos refinamentos finais. Para concluir: executar inicial/novo no mesmo estado de mundo e máquina sem testes concorrentes, repetir os 30 segundos e investigar qualquer regressão confirmada. Aumentar resolução ou ampliar a migração para outros construtores depende desse orçamento.
