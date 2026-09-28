# Cruzamentos no editor de mundo

O botão **Cruzamentos** habilita a seleção dos encontros das ruas de Harbor nas vistas 2D, 3D e lado a lado. Clique no círculo central ou num marcador numerado; o painel permite escolher outra entrada do mesmo cruzamento.

- **Faixa automática / Com faixa / Sem faixa** controla apenas a entrada selecionada. Automático herda a opção da rua e as exceções autoradas.
- **Afastar faixa** e **Profundidade** ajustam a geometria. Arrastar o marcador altera o afastamento ao longo da entrada, com passos de 0,5 m usando Shift. Os guias acompanham o mouse; a malha é reconstruída ao soltar, sem reconstruir o mundo por movimento de mouse.
- **Mostrar linha de parada** controla a pintura, sem desligar regras de trânsito ou semáforos.
- **Restaurar esta entrada** remove só seus ajustes. Desfazer/refazer e salvar usam o histórico/documento já existente. O jogo usa as alterações na próxima execução após salvar.

O verde dos pontos da rua continua indicando uma conexão; não determina a presença de faixa. Uma continuação ou curva com dois braços não recebe faixas de cruzamento. Calçadas, acessos protegidos e a identidade das ruas permanecem no fluxo existente.

## Implementação

`WorldCrossingLayout.gd` deriva entradas da geometria efetiva das ruas. O editor aplica a mesma normalização de pontas de `WorldEditRoads` antes de gerar os marcadores. `HarborRoadGeometry3D` usa essas entradas para construir faixas e retenções; `ProductionWorld` entrega o layout a `TrafficJunctions` ao configurar as rotas residentes.

`TrafficJunctions.along` escolhe a entrada pelo rumo de aproximação e projeta a posição da retenção na curva real do veículo. O alvo fica na lista de cruzamentos da rota, evitando pesquisar todas as ruas por frame. `Vehicle` calcula a distância da frente do carro até esse alvo. Entradas sem espaço seguro conservam o comportamento anterior de parada; esconder pintura não libera o cruzamento.

Os ajustes ficam em `road.crossing_entries`, indexados pela combinação ordenada de IDs das ruas, ocorrência ao longo da rua de referência e sentido do braço. Mover o encontro ou inserir pontos colineares preserva o ajuste. Alterar quais ruas se encontram, inverter a ordem dos pontos ou inserir outro encontro anterior entre as mesmas ruas pode mudar essa identidade; revise as entradas nesses casos. Não é uma migração automática de identidade após qualquer mudança topológica.

O corredor de arraste termina antes de uma curva ou do fim da rua e reserva espaço para o próximo cruzamento. Pontos colineares intermediários não reduzem o corredor. Faixas conflitantes são omitidas, com indicação funcional no painel. As duas travessias especiais autoradas fora de cruzamentos na área Cobra continuam sob os ajustes gerais de suas ruas.

## Validação

- `test_junction_entries.gd`: 23 verificações; T, curva, direção real de braços, independência de entradas, espaço entre encontros, identidade após translação, pontos colineares, JSON, parada projetada, ruas de 30 m no afastamento máximo e limpeza de estado entre configurações.
- `test_junction_editor.gd`: 22 verificações renderizadas; arraste 3D/2D, cancelamento, soltura fora da vista, histórico, salvar/reler/restaurar, correspondência com o runtime e vértices da malha final da prévia. Arquivo oficial não gravado pelo teste.
- `test_world_editor_roads.gd`: 19 verificações aprovadas.
- `test_world_editor_junction_drawing.gd`: 469 verificações aprovadas.
- `test_world_editor_paving.gd`: 20 verificações aprovadas. A primeira execução revelou dependência indevida da ordem dos polígonos; a implementação passou a preservar a ordem original das ruas. Uma execução seguinte ficou bloqueada pela validação concorrente de número de pistas em JSON; foi corrigida a aceitação de valores numéricos 1 e 2.
- `test_edited_traffic_drive.gd`: 7 de 8 verificações aprovadas, incluindo os dois carros físicos cruzando Market → Quay e Medical → Warehouse. A verificação final de igualdade do hash do mapa falhou: o arquivo foi alterado concorrentemente durante a execução com `--no-save`. Não foi repetida para esconder essa interferência; o teste completo não está marcado como aprovado.
- A espera compartilhada dos testes de prévia agora exige `applied_revision == revision`, além de a solicitação coincidir com o documento desejado. Antes disso podia aceitar uma imagem intermediária.
- Captura: `evidence/junction-editor/editor.png`. Os processos renderizados ainda emitem avisos de recursos de textura no encerramento, também presentes na medição anterior à mudança; isso não é tratado como eliminação de todos os erros do projeto.

## Desempenho

Medição em `Main.tscn`, RTX 4060 Laptop, Mobile/Vulkan, 1280×720, limite 144 FPS, VSync desligado, 8 s de aquecimento e 30 s de amostra. O alvo provisório continua 60 FPS; aumento acima de 5% em p95/p99 exigiria confirmação em condições equivalentes.

Antes: 24,27 FPS, p50 33,591 ms, p95 87,439 ms, p99 187,979 ms, máximo 244,832 ms; 429 frames acima de 33,3 ms e 61 acima de 66,7 ms. Amostras em `evidence/junction-editor/before/performance.json`.

Depois: 28,80 FPS, p50 33,444 ms, p95 43,960 ms, p99 66,121 ms, máximo 107,077 ms; 464 frames acima de 33,3 ms e 9 acima de 66,7 ms. Amostras em `evidence/junction-editor/after/performance.json`; mapa estável durante esta amostra, mas diferente do baseline. A tentativa anterior à amostra final falhou no carregamento por erros de tipagem em `FootbridgeCrossers.gd`, corrigidos pela sessão que estava trabalhando nesse arquivo. Somente depois dessa correção foi feita a amostra acima.

**Desempenho pendente, não aprovado.** Havia várias instâncias do Godot em execução e outras sessões alteraram código e mapa durante o trabalho. O hash do mapa mudou entre o baseline e o fim da implementação. Não é uma comparação controlada, nem evidência de que a mudança causou ou resolveu o desempenho ruim observado antes. Nenhuma instância alheia foi encerrada, e as edições do usuário não foram revertidas para tentar obter uma medição favorável.
