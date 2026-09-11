> Estado atualizado: [relatório da integração e matrizes de cenas](optimization-report.md). Os resultados abaixo são o histórico da primeira etapa.

# Anti-aliasing e investigação de FPS — 2026-09-11

Meta confirmada pelo usuário: mínimo de 60 FPS em todas as cenas, com boa imagem
e estabilidade de frame time. Este registro é uma etapa da investigação, não
uma declaração de que a meta foi atingida.

## Alterações entregues

- `RenderQuality.gd`, instalado por `SettingsManager`, aplica MSAA 2x ao canvas
  principal e aos SubViewports criados em runtime. Nos modelos, configura MSAA 3D;
  nos viewports exclusivamente 2D, configura MSAA 2D. Mantém níveis explícitos maiores
  (por exemplo, retratos em 4x) e não muda a frequência de atualização dos viewports.
- `PedestrianNeighborhood.gd` monta uma grade espacial compartilhada por tick.
  Os pedestres consultam células próximas em vez de percorrer a população inteira
  nas duas heurísticas de espaçamento/desvio. Mantém a ordem original dos candidatos,
  os filtros de direção/distância e uma margem para movimento entre consultas.
- A navegação dos pedestres não repete três raycasts quando o desvio social é zero:
  usa o segmento já validado pelo navegador. Se um vizinho altera a direção, a
  verificação de obstáculos continua ativa; `move_and_slide` continua executando.
- `SettingsManager` espera o `GameInput` registrar suas ações antes de reaplicar
  atalhos salvos. A inicialização anterior emitia erros para cada ação inexistente.

O renderizador padrão continua Forward+. MSAA na janela não suaviza o conteúdo
3D dos viewports internos; é necessário configurar ambos. Referências:
[MSAA 2D](https://docs.godotengine.org/en/stable/tutorials/2d/2d_antialiasing.html),
[MSAA 3D](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html),
[comparação dos renderizadores](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html).

## Validação isolada

Todos executados com saída 0:

- `test_pedestrian_neighborhood.gd`: compara a busca com força bruta para 441 atores,
  incluindo coordenadas negativas, bordas de célula, objeto removido e mudança de
  célula. Mesmos vizinhos e ordem; 50.625 candidatos contra 194.481 (74% menos).
- `test_pedestrian_avoidance_budget.gd`: ausência de desvio não repete raycasts;
  vizinho próximo ainda produz desvio e teste de obstáculos.
- `test_render_quality.gd`: AA no canvas e novos viewports, preservação de 4x e
  `UPDATE_DISABLED`.
- `test_pedestrian_render_lod.gd`: 120 pedidos próximos e 30 distantes; física
  continua ativa fora da tela.
- `test_pedestrian_life_routines.gd`: caminhada, visitas, pausa e retorno.

Esses testes usam headless para verificar comportamento, não para medir FPS.
As capturas e medições de partida usam Vulkan real na RTX 4060 Laptop GPU.

## Medições e limites

`measure_aa_performance.gd` usa a ação atual `move_up`, verifica distância percorrida
e grava JSON e PNG no projeto. O benchmark antigo `measure_harbor_game_driving.gd`
usa `ui_up`: nesta versão ele produziu distância zero, portanto não valida direção.

Foi possível reproduzir a lentidão: `before.json` registrou 16,5 FPS parado e
21,0 FPS dirigindo (2.743 px), em 1280×720, sem AA. O tempo médio da física foi
17–18 ms, suficiente para consumir o orçamento de um tick de 60 Hz.

Não tratar os arquivos como uma comparação controlada de ganho:

- O editor e a execução do usuário continuaram abertos. A execução do usuário e
  o benchmark consumiam cerca de 2,4 GB de VRAM cada; o uso total chegou a 7,5 GB.
- Outras sessões rodaram capturas/testes e editaram fontes durante a medição.
  `after.json` (14,4/13,7 FPS) foi coletado com essa concorrência variável.
- `mobile.json` foi invalidado: resolução mudou para 2550×1390 e o carro se moveu
  durante a fase parada. A execução Mobile seguinte encontrou referências
  temporariamente inválidas na rodoviária; não serve para decidir troca de renderer.
- O teste final fixa modo janela, resolução e clima e impede a janela de teste
  receber foco. Ainda compartilha CPU/GPU e fontes com as demais sessões.

Não há comprovação de 60 FPS sustentados nem de que a otimização dos vizinhos,
isoladamente, resolveu a queda. A redução de candidatos e de raycasts redundantes
foi validada; o ganho de FPS exige repetir antes/depois sem outras execuções de jogo
e sem mudanças concorrentes nos arquivos.

As execuções finais sem erros de script registraram 17,6 FPS dirigindo em
Forward+ e 21,2 em Mobile, ambas com AA. Pausando temporariamente a execução
aberta do usuário (retomada automaticamente e confirmada com status 0), Mobile
chegou a 26,9 parado / 29,6 dirigindo; física média de 14,7 ms no percurso,
p90 de 42,4 ms e p99 de 68,6 ms por quadro. Portanto ainda reprova a meta.

A fase seguinte trabalha numa cópia de laboratório (`performance-lab-0911`, fora
do repositório), com fontes congeladas e perfil por função, para investigar
simulação, carregamento e apresentação antes de integrar as próximas mudanças.
