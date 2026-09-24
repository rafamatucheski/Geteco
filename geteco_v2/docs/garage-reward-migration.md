# Garagens especiais e recompensa Cobra

`runtime/GarageRewards.gd` mantém os cinco IDs de `world/places/PortBossStock.gd` separados da recompensa `cobra_boss_ironback`. A frota original e o modelo exportado BossMuscleModel são reutilizados; Ironback preserva os parâmetros do controlador HarborBossMuscle, sem confundi-lo com o Cobra V8 de Ashbend.

Fontes V1: `world/harbor/PortBossGarage.gd` (cinco baias, acesso 01:00–05:00, alarme 15 s, crime 60 e mínimo três estrelas), `cars/ChopShopZone.gd` (Porto Rosso R$ 50.000, sem procura, carro íntegro/parado, proximidade física, limite compartilhado de seis entregas/dia) e `world/harbor/campaign/CobraBossReward.gd` (derrota mais finale concluído, recuperar sem curar, reparo gratuito explícito). A baia Maciota usa o getter atual de HarborGarageInterior, centro do showroom; a coordenada antiga do controlador de recompensa não corresponde ao showroom atualizado.

O nó publica configure, on_location_changed, can_enter, nearest_action, perform, snapshot, restore_snapshot e validate_snapshot. Só sincroniza carros depois de ready_for_play e sala construída. Meta garage_reward exclui os carros dos saves e descarte de frota genérica. Cada registro usa ID estável, região, local, posição relativa ao local, orientação, saúde, pintura e condutor. A origem capturada por carro impede converter coordenadas usando uma sala recém-trocada. Residences preserva garage_id ao guardar/retirar e libera o vínculo ao vender o Porto Rosso.

FullSession fornece transfer_garage_vehicle e restore_garage_driver: consultas físicas do casco e dos pontos de aproximação precedem transições. A garagem Maciota mantém bloqueio de armas e câmera fixa. Falta de espaço recusa a operação sem empurrar obstáculos. O horário limita somente a garagem do chefe. Snapshot fica em world_state.garage_rewards com validação do GameState.

Carros comuns aceitos na transição recebem ownership explícito garage_guest_N somente depois da transferência. Há no máximo 64 hóspedes, IDs inteiros canônicos e modelos do catálogo de 49 veículos. Registrar salva a entidade antes de marcar garage_reward e limpar o registro legado do carro atual; guincho/carga da missão, veículo pessoal e carro de residência sem ownership correspondente não são convertidos. O vínculo acompanha armazenamento em residência. A restauração permite no máximo um condutor e aguarda o resultado do embarque físico; recusa mantém carro preservado e jogador a pé no checkpoint.

Lote final de hóspedes: 37 checks GarageRewards e 65 Activities aprovados em 21/09/2026, exit0, sem erros de script. Inclui roundtrip JSON de hóspede, cap64, rejeição de modelos/IDs adulterados, conflito de ownership e dois condutores simultâneos. A restauração física do condutor é validada separadamente pela integração Gameplay/FullSession.

Escopo ainda parcial: a animação da prensa de Neco não está neste módulo. A entrega remove fisicamente o veículo e paga uma única vez após checagem da baia; não reproduz a sequência visual da prensa. O despacho utiliza Wanted nativo; perseguição policial veicular completa é uma pendência do sistema de polícia. A validação de regras headless não certifica FPS; a medição renderizada fica com a integração.

## Guardas privados

`runtime/garage_guards` reutiliza a geometria articulada 3D extraída de PoliceOfficer, sem SubViewport. Fonte HarborPortSecurity: uniforme454b42, escala relativa(.84,1,.90), posições PortBossGarage(7.3,5.7) e(-8,1), vida50 e pistola. O alarme começa ao roubar Porto Rosso ou ferir um guarda como jogador; tiros sem impacto continuam sob a regra geral de crime de disparo. A flag local_security impede somar o crime genérico12 do dano por cima do alarme específico60/min3 estrelas.

Os guardas recebem dano pelo Gameplay nativo, perseguem usando navegação com colisão e raycasts, disparam projéteis físicos880px/s convertidos em55m/s, dano6 e falloff original170–420px. Mantêm visão430px, disparo360px, mira contínua.65s, intervalo.85–1.05s, rajadas de2 com pausa1.7–2.5s e recarga12balas/1.691875s (duração máxima dos três WAVs originais). Movimento120px/s, recuo72px/s e agressividade12 enquanto alertados preservam os parâmetros fonte. A navegação3D substitui a navegação2D, sem alegar trajetos idênticos.

Snapshot guards opcional aceita saves anteriores e preserva saúde, posição relativa, carregador e recarga dos dois atores. Guarda morto não ressuscita ao voltar/recarregar. A sala inativa remove ambos do processamento; disparos transitórios também cessam. Não há ainda os drops aleatórios35% de pistola e12% de colete do PoliceLoot original, nem a apresentação completa de queda/corpo. A validação renderizada neutra está registrada abaixo; custo de combate e percurso completo de perseguição não estão certificados por ela.

`tests/garage_guards/test_guards.gd`: 18 checks aprovados em 21/09/2026, sala nativa real, incluindo admissão física dos dois pontos, geometria/uniforme/arma, bloqueio da mira por parede, consumo de munição/cadência, dano e alarme único, morte, snapshot e retorno sem ressuscitar. Regressão GarageRewards37 também passou, exit0 e sem erros de script. Teste headless não certifica trajetória de perseguição completa, oclusão visual do corpo ou FPS.

## Apresentação e comparação renderizada — 21/09/2026

Fixture `tests/garage_guards/measure_guards.gd` carrega Main real: 24 moradores, tráfego habilitado, cinco carros originais na garagem, horário02:24, câmera original fixa tamanho20.5/posição(0,18.7,-2385), caminhada frontal x±4/z6 de52.525m, sem escrever save. Controle remove somente o módulo dos dois guardas pela fixture, sem flags ou alteração do produto. Ambas as variantes: cinco segundos de aquecimento e30.016s/1801frames medidos. Inventários de processos confirmaram ausência de jogos concorrentes; stdout e stderr sem erros.

Hardware e configuração: NVIDIA GeForce RTX4060 Laptop GPU; Godot4.7.2; renderer mobile;1280×720; VSync1 e limitador60. Critério previamente definido: alvo60FPS no hardware medido e investigar aumento>5% em p95/p99. O limitador significa que a medição não quantifica margem de GPU acima de60FPS.

| Variante | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | Frames>33.3/66.7ms | Draw calls |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Controle, cinco carros/sem guardas | 60.0015 |16.661|17.460|18.019|19.748|0/0|416 |
| Produto, cinco carros/dois guardas |60.0015|16.671|17.615|18.309|21.086|0/0|456 |

Resultado estável: aumento de0.89% no p95 e1.61% no p99, abaixo do limiar definido. Os dois guardas neutros não produziram regressão relevante de frame time neste cenário. CPU process p95:4.436→4.531ms; física p95:5.168→4.986ms. Não há instrumentação separada do tempo de GPU; os intervalos reais de frame incluem CPU, GPU e espera.

A primeira visita foi registrada separadamente e continua com travadas de carregamento: máximo1454.737ms/8frames>33.3ms no controle e1361.132ms/6frames>33.3ms no produto. Essas pausas já existem no controle; não foram incluídas na média estável nem consideradas resolvidas por este lote.

Imagens abertas e inspecionadas: os cinco carros ocupam as cinco baias; ambos os guardas têm proporção humana e pés no piso livre, à esquerda diante das baias e à direita junto à entrada. Não há interpenetração aparente com carros, paredes ou balcão nas poses capturadas. Geometria, iluminação, câmera e apresentação das baias permanecem iguais entre variantes. Essa inspeção estática complementa a admissão física dos pontos; não certifica todas as poses de combate.

Evidências: [controle](../evidence/garage-guards-control.png), [produto](../evidence/garage-guards-product.png), [amostras controle](../evidence/garage-guards-control.json), [amostras produto](../evidence/garage-guards-product.json), [processos controle](../evidence/garage-guards-control-processes.json), [processos produto](../evidence/garage-guards-product-processes.json).

Testes direcionados: test_garage_rewards.gd teve 26 checks aprovados em 21/09/2026; verifica autorização, horário, identidade, alarme, entrega, limite diário, snapshot, recuperação e reparo. test_garage_vehicle_transfer.gd usa Main e a física real nos helpers. Após a integração recolher os braços originais do elevador junto às colunas antes de derivar os colisores, os 11 checks passaram: casco Ironback, condutor, entrada/saída de ambas as garagens, câmera fixa e bloqueio de armas. Execução root com --no-traffic --population=0 --skip-arrival --no-save; não certifica entrada em tráfego/pedestres ocupando a vaga. Validação visual e performance dessa mudança permanecem pendentes. Pintura está preservada no estado; Vehicle ainda não reaplica essa cor aos materiais exportados.
