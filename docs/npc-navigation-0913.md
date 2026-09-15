# Navegação de pedestres — 13/09/2026

## Comportamento implementado

- O navegador e o movimento social usam o mesmo espaço permitido. Desvios podem ultrapassar a faixa habitual de 14 px, dentro de um corredor de até 28 px e sem colocar o corpo na pista. A geometria das ruas do porto é compartilhada pela população; travessias conservam a faixa estreita.
- A busca começa com passos de 12 px e refina para 6/3 px apenas se a grade anterior se esgotar. Isso permite usar faixas livres estreitas entre as colunas da grade, sem aumentar o orçamento compartilhado por frame.
- Trechos longos usam pontos intermediários estáveis, normalmente 96 px à frente, com ocupação verificada na seleção. A busca local não precisa mais enxergar o fim de um quarteirão inteiro com vários obstáculos. O destino da rotina e a sequência das esquinas permanecem separados desses pontos locais.
- A posição inicial é validada antes do primeiro movimento. Um ponto de nascimento sobreposto a um obstáculo é substituído por uma posição livre no mesmo trecho; essa escolha inicial não é usada como recuperação durante a caminhada.
- O tempo sem progresso acompanha o avanço em direção ao próximo ponto. Consultas de caminho, tentativas e pequenos movimentos repetidos não apagam esse histórico.
- O temporizador de uso de um caminho é separado do histórico total de bloqueio: uma rota nova não é descartada por herdar a espera da anterior. O acumulador de consultas a 30 Hz consome o tempo efetivamente acumulado, sem somar a mesma sobra repetidamente.
- Pontos internos de contorno são alcançados com precisão de até 2 px (menor na grade refinada), evitando cortar uma curva contra o poste. Essa precisão é distinta da tolerância de chegada de 8 px da rotina.
- A fila compartilhada deixa de expirar pedidos após um frame renderizado. Pedestres consultam a 30 Hz; a regra antiga podia descartar sua posição antes da próxima consulta a 60+ FPS. Pedidos vivos conservam prioridade; um solicitante suspenso sai da fila após 500 ms.
- Recuperação escalonada: nova busca após 2,5 s sem progresso; se o bloqueio persistir, tentativa de recuo físico no mesmo trecho após mais 3 s. Um espaço totalmente fechado mantém espera com tentativas limitadas. Nenhum teletransporte foi acrescentado.
- O recuo verifica a ocupação do destino e usa o navegador para chegar lá; também pode contornar um obstáculo que já ficou para trás, em vez de exigir retorno em linha reta.
- A chegada usa tolerância de 8 px. A recuperação não pula esquinas. Circuitos preservam o sentido invertido durante um recuo.
- Desvio de obstáculos tem preferência pelo lado direito do sentido da rota. O desvio social mantém o lado escolhido e a proteção física final usa essa mesma decisão. No meio-fio, quem não tem espaço cede por um período limitado, sem espera mútua.
- Estados observáveis: caminhada, contorno, recuperação, espera por caminho, espera por pessoa, espera por travessia, pausa e visita. Pausas e sinais não contam como falha de navegação.
- Visitas usam ponto externo à fachada com verificação de espaço para o corpo. Ao terminar ou abortar, o pedestre retoma uma calçada próxima caminhando. A reação a tiros continua interrompendo a visita.
- Aparência, rig e proporções dos personagens foram preservados. A animação de passos já usava deslocamento físico real.

## Validação

Evidências em `D:/geteco/artifacts/npc-navigation-0913/`.

Os 13 scripts de teste comportamental abaixo passaram; logs de entrega usam o sufixo `-delivery.log`, exceto o recuo (`retrace-verified.log`).

- `test_npc_obstacle_navigation.gd`: poste fino, largura do corpo, veículo comprido e obstáculo novo.
- `test_living_pedestrian_navigation.gd`: encontro frontal, espaço entre corpos e retorno após pânico.
- `test_pedestrian_route_recovery.gd`: poste junto à rua, recuo sem cortar esquina, histórico sem progresso, pausa, encontro no meio-fio e sinal vermelho/verde.
- `test_pedestrian_group_passage.gd`: dois pedestres no mesmo sentido e um no sentido contrário passando por um poste.
- `test_pedestrian_spawn_and_narrow_path.gd`: nascimento fora de um objeto sólido e passagem estreita entre colunas da grade de busca.
- `test_pedestrian_search_fairness.gd`: pedido pendente mantém prioridade entre consultas espaçadas por dois frames.
- `test_pedestrian_long_sidewalk.gd`: avanço físico em calçada de 600 px com quatro postes sucessivos, além do alcance de uma busca local única.
- `test_pedestrian_retrace.gd`: recuo por trás de um poste quando uma parede fecha o caminho à frente.
- `test_responder_contact_escape.gd`: contato com margens de segurança, colisão rasa, obstrução profunda e espaço físico de equipes de resgate.
- `test_pedestrian_avoidance_budget.gd`: caminho sem vizinhos não repete consultas físicas; desvio social mantém a checagem necessária.
- `test_pedestrian_life_routines.gd`: variação de caminhada, repouso e ciclo de visita.
- `test_civilian_gunfire_response.gd`: fuga, cobertura, renovação do medo e retomada da rotina.
- `test_harbor_turn_pedestrian_startup.gd`: pedestres na calçada não bloqueiam indevidamente veículos em curva; pessoas na trajetória continuam bloqueando.

O teste de visita antigo colocava o centro do corpo em y=200, sobrepondo o raio de 11 px à fachada que terminava em y=199. O caso foi corrigido para y=214 e ganhou verificações de rejeição da origem sobreposta e de acessibilidade do destino. As asserções do ciclo de visita foram mantidas.

Durante a integração, o sistema de residências estava sendo introduzido no workspace e uma inferência de tipo impedia seu carregamento. `ResidenceManager.gd` recebeu apenas a anotação `bool` na variável `owned`; a checagem de compilação passou. A observação que carregou com esses erros (`city-progress/`) foi descartada. Esse trabalho concorrente também limita a atribuição causal de variações entre medições.

## Desempenho e integração

Comparação renderizada em HarborGame, checkpoint do centro, mesma máquina (RTX 4060 Laptop), Godot 4.7.2 Mobile, 1280×720, limite de 60 FPS, VSync desligado, dia e tempo limpo, semente 12092026. Saves redirecionados para a pasta da medição. Cada amostra estável dura 30 s, após aquecimento separado de 10 s e preparação da cena. População/tráfego continuam ativos; suas posições e ocorrências podem variar com o escalonamento da simulação.

Baseline: 52,03 FPS; p50 17,185 ms; p95 30,700 ms; p99 40,055 ms; máximo 69,495 ms; 45 frames acima de 33,3 ms e 2 acima de 66,7 ms. A base já estava abaixo da referência de 60 FPS / 16,67 ms.

A observação final da cena real (`city-delivery/pedestrians.json`) acompanhou 15 pedestres durante 30 s: todos avançaram mais de 20 px e nenhum acumulou mais de 8 s sem progresso na janela observada. A captura correspondente está em `city-delivery/gameplay.png`. Esse diagnóstico conserva pausas, sinais, tráfego e colisões reais.

Comparativo final sem a instrumentação adicional dos pedestres (`performance-delivery/driving.json`):

| Métrica | Antes | Entrega |
|---|---:|---:|
| FPS médio | 52,03 | 59,97 |
| Frames / duração | 1.562 / 30,019 s | 1.800 / 30,015 s |
| Frame time p50 | 17,185 ms | 16,681 ms |
| Frame time p95 | 30,700 ms | 17,961 ms |
| Frame time p99 | 40,055 ms | 20,008 ms |
| Maior frame | 69,495 ms | 59,390 ms |
| Frames > 33,3 ms | 45 | 1 |
| Frames > 66,7 ms | 2 | 0 |

As amostras por frame e os aquecimentos separados estão nos CSV/JSON das duas pastas. A captura final está em `performance-delivery/gameplay.png`. Os arquivos de navegação mantiveram os hashes durante a validação final; não houve erros de script nos dois carregamentos de entrega.

Resultado: melhora observada nesse checkpoint, sem regressão medida nele. Não se certificam 60 FPS constantes: o p95 ainda supera 16,67 ms e houve um pico de 59,39 ms. A medição não certifica todos os bairros, horários ou hardware. Alterações concorrentes no sistema de residências e a evolução dinâmica da população impedem atribuir todo o ganho exclusivamente a esta correção (43 pedestres ativos no fim do baseline, 40 na entrega; ambos com 10 veículos ativos).

## Limites

Esta mudança melhora a navegação local sobre as rotas existentes; não substitui o mapa por uma malha global nem reproduz os sistemas proprietários dos GTA. Um corredor realmente fechado não se torna transitável. O mapa deve fornecer rotas e entradas fisicamente acessíveis. A fila de busca conserva o orçamento compartilhado de 1 ms por frame.
