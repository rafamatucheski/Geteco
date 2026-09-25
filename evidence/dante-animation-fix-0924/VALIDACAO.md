# Dante — correções e validação

24/09/2026. Alterações aplicadas ao jogo, com revisão visual do modelo real e testes da Main. A [avaliação anterior](../dante-animation-review-0924/AVALIACAO.md) conserva as evidências dos defeitos originais.

## O que mudou

- **Recuo atirando:** usa a passada própria para trás. Corrida desativada enquanto mira; velocidade de recuo limitada a 1,65 m/s e lateral a 1,35 m/s. Diagonais misturam as direções, e o lado oposto usa espelhamento do ciclo. O analógico parcial escolhe a pose pela velocidade efetiva.
- **Braços:** solução comum para mão aberta, punho e arma; continuidade do cotovelo e da torção do antebraço, transição de orientação e apoio bilateral. O esqueleto conserva comprimentos e escalas. A mudança de sinal da torção em ±π não provoca mais o salto observado antes.
- **Golpes:** guarda com as duas mãos, socos alternados com extensão e recuperação, orientação dos punhos da soqueira, guarda da faca e participação do tronco/quadril. Machado e taco mantêm as duas mãos no cabo. Estados de recarga não contaminam armas brancas.
- **Repouso e giro:** base autoral de pés, respiração discreta, dois passos para reorientar a base e rotação gradual do corpo. Costura dos ciclos suavizada. Teleporte e respawn limpam os apoios antigos.
- **Eventos de combate:** dano ocorre no contato do golpe, uma vez. Granada é criada e consome munição na soltura, aos 0,20 s; troca de arma, morte e bloqueios cancelam ações pendentes. O disparo não teleporta a rotação do corpo.
- **Reações e interações:** morte usa o clipe articulado; dano não fatal tem reação breve. Entrada em veículos dobra joelhos e, em veículos abertos, ergue uma perna. Transições de escada para assento são misturadas. A escada retira o deslocamento vertical acumulado do clipe, pois a sessão já move o personagem.
- **Interrupções:** corrigidos dois acessos a veículo removido durante embarque/restauração, preservando o restante das alterações concorrentes de `FullSession.gd`.

## Resultado funcional

417 verificações aprovadas nos testes abaixo, além do teste de travessia e de 32.280 poses no teste de deformação. Nenhum `SCRIPT ERROR` nos logs finais desses cenários. A suíte completa do jogo não foi executada.

| Teste | Resultado |
|---|---:|
| `test_actor_locomotion_idle` | 13 checks |
| `test_dante_idle_return_independent` — entrada real na Main | 8 checks |
| `test_weapon_presentation_contract` | 152 checks |
| `test_dante_animation_continuity` | 26 checks |
| `test_dante_combat_timing` — sessão real, dano/munição/cancelamento | 39 checks |
| `test_combat_flow` — combate, garagem, Maciota e mecânico | 74 checks |
| `test_vehicle_body_transitions` | 21 checks |
| `test_garage_rewards` | 47 checks |
| `test_garage_driver_restore` | 26 checks |
| `test_garage_vehicle_transfer` | 11 checks |
| `test_dante_traversal_pose` | aprovado: escada, joelhos e elevação de perna |
| `test_dante_deformation` | 600 poses iniciais + 30.720 transições + 960 trocas |

Os testes antigos foram ajustados às mudanças de comportamento: recuo usa seu ciclo próprio; mira e empunhadura levam tempo para entrar; dano aguarda o contato; repouso admite respiração apenas no osso correspondente. O teste de apresentação agora avança alvos e esqueleto juntos, sem pular 20 quadros do controlador. Não foram ampliadas as tolerâncias de contato ou deformação.

Comando-base: Godot 4.7.2 `--headless --path D:/geteco/game --script res://tests/<teste>.gd -- --no-save --skip-arrival --population=8 --seed=7`. Logs individuais estão nesta pasta. `test_garage_rewards` ainda emite aviso de dois objetos no encerramento; isso não foi tratado como prova de ausência de vazamentos gerais do jogo.

## Revisão visual e medidas

Capturas separadas do benchmark: modelo produtivo em estúdio (frente, perfil e três quartos), Main renderizada com repouso/caminhada/corrida/giro/recuo e lateral atirando/socos/machado/embarque e saída, e acesso real ao esgoto.

- Main: maior mudança local por passo de física nos socos, machado e recuo armado **17,19°**, contra saltos anteriores de **109–142°**. Esses valores medem continuidade entre quadros, não limites anatômicos absolutos.
- Costuras de Walking e Running: diferença final/inicial de aproximadamente **0,056°** na amostra.
- Teste de deformação: maior erro de posição/escala **0,000000253**; maior distância da palma ao apoio **0,033 m**, em transições forçadas do taco. Armas de fogo ficaram abaixo de **0,015 m** nesse teste.
- Morte: **20 articulações** mudam efetivamente de pose; respawn cancela a queda.
- Escada: oscilação restante da raiz de **0,060 m**, sem duplicar a subida inteira. Assento altera o joelho em **0,725 rad**; embarque aberto eleva uma perna.
- Sola calculada da malha deformada, em chão plano: repouso **0,0019 m** acima do chão; caminhada **0,0031–0,0131 m**; corrida **−0,0181–0,1038 m**, incluindo a fase aérea do ciclo importado. Não é uma certificação de apoio em todos os terrenos inclinados.
- Esgoto: acesso, tampa, espaço da cápsula, descida, retorno, câmera e desbloqueio dos controles passaram. Evidências `sewer-*.png` e `sewer-render.log`.

As recargas de estúdio percorrem a sequência normalizada para conferir poses; os tempos reais de recarga continuam no gameplay. Clipes importados sem mecânica ativa, como nado e chute, não foram transformados em novas ações do jogo.

## Evidências para rever

- [Recuo atirando, animado](backfire.webp) e [sequências na Main](main-sequences.jpg).
- [Socos em três vistas](punches.jpg), [soqueira](knuckles.jpg), [faca/machado/taco/granada](melee.jpg).
- [Locomoção, giro e morte](locomotion.jpg), [recargas 1](reload1.jpg), [recargas 2](reload2.jpg).
- [Dados da Main](main-review.json), [dados do estúdio](review.json).

## Desempenho

Godot 4.7.2 / Vulkan Mobile / RTX 4060 Laptop / 3440×1440 / população 24 / limite 60 FPS / VSync desligado. Main real, clima e câmera equivalentes, sequência das 16 armas, movimentos e recargas, sem gravar saves ou capturar PNG durante medição. Foram medidos aproximadamente 56 s após aquecimento em cada variante. Scripts antigos foram carregados por cópias isoladas, sem reverter a árvore de trabalho.

| Par inicial estável | Antes | Depois |
|---|---:|---:|
| FPS médio | 59,70 | 57,64 |
| p50, ms | 16,669 | 16,602 |
| p95, ms | 19,335 | 18,769 |
| p99, ms | 26,289 | 45,283 |
| Máximo, ms | 60,619 | 141,333 |
| Frames >33,3 ms | 12 | 45 |
| Frames >66,7 ms | 0 | 15 |

A piora de p99 exige confirmação. Os quinze frames >66,7 ms do resultado novo ficaram concentrados em um trecho curto; isso, isoladamente, não identifica o responsável. Hashes dos demais scripts foram iguais entre as duas execuções acima. Amostras brutas: `stable-before-measure/report.json` e `stable-after-measure/report.json`; os registros de processos confirmam ausência de outro runtime durante o par.

A confirmação em ordem inversa ficou incompleta: a variante nova registrou 53,42 FPS, p95 de 20,458 ms, p99 de 36,279 ms e máximo de 1.569,469 ms; a execução da variante antiga foi interrompida quando outro runtime iniciou. Portanto, esse resultado não constitui um segundo par comparável. Também houve alteração concorrente em `Driving.gd` desde o primeiro par. Dados: `confirmation-after-measure/report.json`.

Execuções com outro runtime Godot concorrente foram interrompidas e não contam como resultado válido. Há também um erro de referência de objeto em impactos do tráfego nos logs das duas variantes. A revisão automática bloqueou a correção adicional em `StreetPhysics.gd`, por estar fora desta tarefa e ser arquivo concorrente; o usuário escolheu manter o escopo nas animações. Esse arquivo não foi alterado por esta tarefa.

**Estado final de desempenho: pendente e não aprovado.** Após a otimização de CPU abaixo, a última tentativa aguardou por até cinco minutos uma janela de 60 segundos sem outros runtimes Godot; a janela não ocorreu e nenhum novo par foi iniciado. Falta comparar a versão final e a referência na Main renderizada, em condições equivalentes, e esclarecer os picos de frame time. Não é possível afirmar ausência de regressão ou 60 FPS estáveis com estas medições.

Investigação de CPU: o controlador novo copiava poses completas mesmo quando a mistura já estava 100% no recuo ou no passo lateral. Foram removidas quatro cópias desnecessárias por quadro nesses casos, preservando o resultado. Após a otimização, os testes de continuidade e deformação passaram novamente. Em 3.840 poses por variante, o controlador final mediu p50/p95/p99 de **0,147/0,265/0,368 ms**, contra **0,051/0,149/0,198 ms** da versão anterior às correções. O p95 da implementação nova antes dessa otimização era **0,622 ms**. Esta medida é apenas CPU do controlador, em headless; não certifica FPS ou GPU. Dados: `pose-cost.json`.
