# Correção do crash na ponte e desempenho — 08/09/2026

## Erros reproduzidos a partir dos logs do jogador

Os logs originais foram preservados em
`D:/geteco/qa-bridge-crash-2026-09-08/logs/` antes de executar testes.

1. `HarborEmergencyDirector._owns_unit`: atribuição de uma instância já destruída
   a uma variável tipada como Node durante `_exit_tree`, chamado pela viagem.
   O encerramento agora usa o ID de propriedade gravado na viatura, que continua
   existindo no pool; não depende de alvos ou depósitos destruídos. Consultas
   normais validam referências Variant antes de acessá-las. Também foi removido
   um caractere solto encontrado nesse script.
2. `MenuAudio._play_sfx`: foco inicial do menu criava um AudioStreamPlayer no root
   ocupado montando a cena e tentava reproduzi-lo fora da árvore. Inserção e
   reprodução agora são adiadas em ordem, reutilizando o player pendente para
   eventos de foco no mesmo quadro.

## Otimizações aplicadas

- Viewports 3D de veículos fora da câmera deixam de renderizar continuamente.
  Veículos visíveis recebem atualizações; pintura e rodas permanecem funcionais.
- Descoberta de controles viários é compartilhada por rua a cada quadro. A
  associação é renovada quando os nós mudam; estados de parada continuam lidos
  ao avaliar movimento, sem cache de permissões de semáforo.
- Projeções de cruzamentos em curvas são reutilizadas por faixa. Mudança da
  curva, substituição da curva, transformação do caminho ou deslocamento do
  cruzamento invalida a projeção correspondente.
- Tráfego distante decide movimento a aproximadamente 10 Hz, com delta acumulado
  e limite de passo compatível com sua velocidade. Continua circulando e obedece
  aos mesmos limites de frenagem, espaçamento, reservas e cancelas. Veículos
  próximos da câmera continuam atualizados a cada quadro. Física de colisões e
  controle do carro dirigido não foram reduzidos para 10 Hz.

## Medição real

Mesmo diagnóstico `profile_harbor_game_engine_costs.gd`, Vulkan Forward+, RTX 4060,
1920×1080, VSync desligado, 600 quadros de direção por execução.

| Medida | Antes | Após correções |
| --- | ---: | ---: |
| Tempo médio por quadro | 62,009 ms | 17,017 ms |
| FPS calculado pela duração real | 16,1 | 58,8 |
| Mediana do tempo por quadro | 58,810 ms | 14,631 ms |
| Percentil 90 | 80,319 ms | 25,296 ms |
| Percentil 99 | 102,515 ms | 43,602 ms |
| Chamadas de desenho médias | 4.750 | 1.581 |

Logs: `performance-before.log` e `performance-budgeted.log` na pasta de QA.
É um diagnóstico curto com mundo dinâmico e número fixo de quadros, portanto as
execuções têm duração e distância percorrida diferentes. Não comprova 60 FPS
constantes em todo o mapa; ainda existem picos de tempo de quadro. Os testes de
desempenho foram executados sem outros processos de teste concorrentes.

## Regressões verificadas

- `test_region_emergency_teardown`: menu inicial, viatura real despachada,
  referências de alvo/depósito destruídas, viagem, retorno da viatura ao pool e
  reabertura do menu. Passou em headless e com Vulkan, sem os erros originais.
- `test_harbor_mountain_drive`: percurso físico de ida e volta na ponte.
- `test_region_travel`: preservação do carro, jogador e reconstrução por JSON.
- `test_traffic_render_budget`: ausência de renders repetidos fora da câmera,
  continuidade do tráfego, retomada visual, pintura e invalidação geométrica.
  Passou também em Vulkan.
- `junction_traffic_contract_test`: reservas, semáforos, transição e zona customizada.
- `test_rail_canonical_lane_gates`: aproximação, parada, escape e liberação de ambas
  as faixas ferroviárias.
- `rail_level_crossing_runtime_test`: ciclo natural completo do trem, zero
  conflitos entre veículos e trem.
- `test_mountain_traffic_vehicle` e `test_in_game_fleet_integration`: modelos,
  circulação, pintura, melhorias e carro roubado atravessando regiões.

As asserções passaram. Alguns testes headless emitem avisos de objetos restantes
ao encerrar, particularmente a cena legada da ferrovia; não foram apresentados
como execução sem qualquer aviso. O teste de emergência em Vulkan terminou limpo.

Nenhum save do jogador foi substituído. O único autosave encontrado manteve a
data de modificação de 07/09/2026 às 22:19:52. As alterações estão salvas no projeto
local. Encerrar a execução antiga do jogo e iniciar novamente carrega os scripts
corrigidos.
