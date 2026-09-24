# Depurador: erros repetidos — 20/09/2026

## Diagnóstico

O contador relatado (~11.700) acumulava repetições de poucas falhas. Na primeira leitura dos logs:

- `godot.log`: 10.432 mensagens `Couldn't get Vulkan surface capabilities (VkResult error -1000000000)`; o número continuava crescendo.
- `godot2026-09-20T22.22.39.log`: outras 869 mensagens Vulkan, 564 ocorrências de `Parameter "body" is null`, 11 avisos de normalização de Vector2 e um acesso a `global_position` de passageiro já removido.
- As 564 mensagens de física vinham de `ResponderNavigation._segment_queries` (326) e `TrafficBodySweep.clear` (238). A conversão das exceções de colisão em objetos falhava antes de o código conseguir verificar `is_instance_valid`.
- A falha de passageiro aparece imediatamente antes da sequência Vulkan. O código Vulkan significa superfície de janela perdida; essa sequência não demonstra que o script causou a perda da superfície.
- Vários testes de outras sessões compartilhavam o log padrão. A falha de assertion de `test_harbor_citizen_routines.gd` pertence a outra execução, não à pilha da sessão do jogo travada.

A execução antiga foi identificada pelo PID 34020, projeto Geteco, `--remote-debug tcp://127.0.0.1:6007` e editor pai 48296. Ela já não possuía janela principal. Após as verificações, apenas esse processo de jogo foi encerrado. O editor e os processos de outras sessões foram preservados. Reiniciar o jogo no editor é necessário para carregar as correções; um contador histórico não revalida o código atual.

## Correções

- `CollisionExceptionLifetime.gd`: limpa a referência de colisão no objeto sobrevivente quando o outro é destruído. Usa referências fracas e a notificação de destruição; não adiciona processamento por frame nem desfaz exceções quando o ônibus apenas muda de pai ao trocar de pista.
- Aplicado ao embarque de passageiros, à articulação dos ônibus e à queda de motoristas de motocicleta.
- `HarborSoundscape.gd`: rejeita coordenadas não finitas antes de consultar a física. Pessoas com posições válidas continuam audíveis e paredes continuam bloqueando o som.
- A proteção contra passageiros removidos na lista de `UrbanTransit.gd` já estava no workspace. Foi preservada e validada; a sessão antiga ainda executava a versão anterior.

## Verificação funcional

Executados com Godot 4.7.2, logs próprios em `_codex_diag` e testes focados:

| Teste | Resultado |
| --- | --- |
| `test_transit_collision_lifecycle.gd` | Antes: 5 verificações falharam e reproduziram `body is null`. Depois: 11 passaram, incluindo remoção imediata, remoção diferida, articulação, reembarque, mudança de pai e exceção unidirecional de motocicleta. |
| `test_soundscape_invalid_positions.gd` | 5 passaram: multidão válida, ouvinte infinito/NaN, pedestres inválidos e bloqueio por parede. |
| `test_urban_transit_removed_passenger.gd` | PASS. |
| `test_responder_contact_escape.gd` | 9 passaram; colisões e acesso à vítima preservados. |
| `test_garage_weapon_restrictions.gd` | 0 falhas funcionais; imortalidade dos personagens e proibição de armas preservadas. |

Não houve os erros investigados nas novas amostras renderizadas. Os testes que carregam o mundo inteiro ainda imprimem mensagens de recursos não liberados **ao encerrar**. Essas mensagens também ocorreram no baseline; não foram corrigidas nem tratadas como aprovação de limpeza de memória. O benchmark existente também avisa `Exponent too high` ao reler JSON contendo infinito.

## Desempenho — pendente, não aprovado

Cena real `HarborGame`, cenário `measure_city_scenarios.gd --normal-cap --chaos`, 1280×720, Mobile/Vulkan, RTX 4060 Laptop, limite 60 FPS, VSync 0. Saves isolados por execução. Aquecimento separado e aproximadamente 30 segundos de amostragem por execução. Editor e testes alheios já estavam abertos; não foram encerrados para fabricar um resultado melhor.

| Amostra | Frames | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms | >66,7 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Antes | 1705 | 56,81 | 16,645 | 24,588 | 33,807 | 59,059 | 19 | 0 |
| Depois | 1658 | 55,23 | 16,863 | 26,956 | 35,597 | 64,856 | 22 | 0 |
| Confirmação | 1496 | 49,84 | 16,884 | 26,973 | 35,756 | 2172,630 | 28 | 3 |

A confirmação foi motivada pelo aumento superior a 5% no p95/p99. A piora permaneceu nas medidas e a confirmação teve travamento adicional de 2,17 segundos. Não há evidência suficiente para atribuir esse custo às correções, mas também não há base para aprovar performance ou afirmar ausência de regressão. A meta provisória de 60 FPS já não era atingida no baseline. É necessária investigação de frame time em ambiente sem trabalho concorrente para fechar essa pendência.

Evidências: `_codex_diag/debugger-before/`, `debugger-after/`, `debugger-confirm/` (CSV com frames, JSON de métricas e rastros de travamentos), além dos logs próprios de cada teste.

Referência para o código Vulkan: https://docs.vulkan.org/refpages/latest/refpages/source/VkResult.html
