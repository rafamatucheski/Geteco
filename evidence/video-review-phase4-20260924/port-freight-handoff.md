# Porto: frete existente, persistência e restauração

Implementado um ciclo jogável usando os três caminhões, guindastes, contêineres e o depósito que já existiam. Após a introdução, sem missão ativa e durante o turno 6–18h, o jogador autorizado pela portaria pode assumir explicitamente um caminhão carregado/parado junto à porta. Cada baia oferece um frete de R$300, até R$900 no total, com recibo persistente por entrega. A oferta fica disponível por 30 segundos da fase de amarração. O jogador dirige pela rua real, estaciona no depósito, desembarca e entrega por E; o caminhão vazio retorna ao circuito NPC. HUD e minimapa mostram o destino enquanto o frete está ativo.

Não foram adicionados frota, NPCs, luzes, geometria, moeda alternativa ou repetição infinita. Uma carga destruída/removida é encerrada sem pagamento. O recibo econômico impede duplicação mesmo se o marcador antigo do mundo for reaplicado. A autorização da portaria continua sendo por visita.

## Causas e arquivos

- [PortFreightDelivery.gd](D:/geteco/game/gameplay/urban_v1/PortFreightDelivery.gd:1): novo componente de aceite, destino, entrega, perda e persistência. A manutenção do frete ativo roda a 4Hz; ofertas passam pelo acesso físico de embarque e fazem poda de distância antes da consulta. Recibos são reconciliados no restore, não na consulta de oferta.
- [PortCargoOperations.gd](D:/geteco/game/gameplay/urban_v1/PortCargoOperations.gd:327): transfere a operação existente ao jogador, preserva carga física e evita que o diretor retome/esconda o caminhão emprestado; reconhece destruição e remoção sem confundir reparenting ou teardown.
- [UrbanOperations.gd](D:/geteco/game/gameplay/urban_v1/UrbanOperations.gd:31): agrega ações, status e snapshot opcional; snapshots legados continuam aceitos e dados inválidos são rejeitados antes de aplicar os componentes.
- [FullSession.gd](D:/geteco/game/runtime/FullSession.gd:603): somente caminhão/ônibus usam a âncora física da cabine ao restaurar motorista; cupês mantêm o ponto anterior. A âncora genérica ficava atrás da cabine longa.
- [FullSession.gd](D:/geteco/game/runtime/FullSession.gd:82) e [Driving.gd](D:/geteco/game/scripts/Driving.gd:379): o restauro ocorre antes de `ready_for_play`; Driving cancelava a animação por esse mesmo gate, levando Dante ao checkpoint e revogando a visita. A exceção é exclusiva da animação já admitida e exige o restauro dedicado, ausência de modal/transição e `!ready_for_play`. F, entrada, interação, ataque, disparo e menus continuam bloqueados. Morte/remoção continuam sendo verificadas antes da exceção.
- [PortFreightDelivery.gd](D:/geteco/game/gameplay/urban_v1/PortFreightDelivery.gd:195) e [ProductionWorld.gd](D:/geteco/game/runtime/ProductionWorld.gd:565): a troca de seleção retira o apoio distante antes do cleanup periódico. O callback agora conserva a última transformação apoiada, atualizando saúde/equipamento, e distingue descarregamento por distância de remoção explícita. Não mantém física ou chunks distantes vivos. O hook em ProductionWorld foi aplicado pelo agente de performance.

O carro pessoal anterior volta ao registro do jogador após a devolução/perda, sem substituir um novo carro escolhido durante o frete. Destruição conserva saúde zero; remoção explícita aposenta o registro. Os hooks HUD/FullSession de objetivos foram integrados pelo root. HarborPortSecurity e PortOperations não foram alterados nesta leva. Maciota/mecânico continuam Node3D protegidos, sem APIs de dano/morte; a regressão de garagem verificou punhos equipados e `can_attack=false` após a restauração.

## Validações e histórico, sem somar tentativas como cobertura

| Cenário | Resultado | Evidência |
|---|---|---|
| Baseline, operação anterior | Reprodução: embarcar/desembarcar deixava o caminhão interrompido, sem ação de frete | [log](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-baseline-render.log) |
| Fluxo longo headless inicial | 56 checks, 14 falhas; rota passou, restauro falhou e gerou falhas dependentes | [log original](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-freight-4.log) |
| Fluxo longo renderizado | 42 checks, 2 falhas de restauro/visita, 3 PNG; seis waypoints físicos, chão, carga, aceite, HUD e mapa passaram | [log original](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-freight-render.log) |
| Repro reduzido antes da correção | 5 checks, 2 falhas; cancelamento `session_transition`, `ready=false` nas duas portas | [log causal](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-reload-before.log) |
| Repro reduzido final, Main renderizado | **42/42 funcionais, 3 PNG**, exit 0. Restauro, gates, entrega, R$300, recibo repetido, NPC retomando, HUD/mapa, perda e seleção anterior | [log final](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-reload-final.log) |
| Seleção/remoção anterior isolada | **12/12**, exit 0; inclui snapshot no mesmo frame do queue_free por distância | [log](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-previous-final.log) |
| Garagens Maciota e Chefe | **26/26**, exit 0; restauro, colisão de casco, câmera, armas bloqueadas, duplicação e carro destruído | [log](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-garage-driver-final-3.log) |
| Piso anterior, Main independente | **9/9 após**. Ablação do callback anterior: 9 checks, 1 falha esperada; snapshot Y=-0,833114. Correção mantém Y=0,000219 | [após](D:/geteco/game/evidence/video-review-phase4-20260924/previous-floor-after.json), [ablação](D:/geteco/game/evidence/video-review-phase4-20260924/previous-floor-legacy.json) |

As falhas do fluxo longo foram corrigidas e comprovadas no repro reduzido, sem repetir a rota física já percorrida. Não houve uma nova execução integral verde do início ao fim após a correção de startup. A rota preservou apoio e carga; houve contatos menores com objetos da rua e saúde final 314,59/320, portanto não significa uma rota sem colisões.

## Fotos reais inspecionadas

Baseline: [operação](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-before-truck-operation.png), [interrompido](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-before-truck-interrupted.png).

Seis fotos após: [oferta](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-after-offer.png), [carga](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-after-loaded.png), [rota com HUD](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-after-route.png), [restaurado](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-after-reloaded.png), [entrega](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-after-delivery.png), [pago/devolvido](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-after-paid.png).

Confirmados carga acoplada, objetivo legível, Dante a pé na entrega, retirada da carga e saldo 400→700. A retomada do controle NPC e movimento do caminhão foram verificadas; a cabine opaca não exibe um motorista humano modelado. Na oferta há silhueta de Dante atrás da cabine: estas imagens não aprovam oclusão global.

## Reprodução e limites

[Checkpoint JSON portátil](D:/geteco/game/evidence/video-review-phase4-20260924/phase4-port-depot-save.json), copiado sem alteração da rota real. SHA256: `2159B94979633A53D528B338E832EFD5C490FFE955E1588FCD1E9AC880A88C87`.

O checkpoint histórico ainda contém o Y antigo do cupê anterior (-0,416447). Ele serve para reproduzir motorista/carga/entrega e foi mantido intacto; a prevenção desse Y inválido em novos empréstimos é comprovada pelo probe independente de piso acima. Não foi aplicada migração corretiva a snapshots já gravados pela implementação intermediária.

Na raiz do projeto, usando o executável Godot 4.7.2:

```powershell
& $Godot --headless --path . --script res://tests/test_video_phase4_port_reload.gd -- --no-save --skip-arrival
& $Godot --headless --path . --script res://tests/test_video_phase4_port_previous_vehicle.gd -- --no-save
& $Godot --headless --path . --script res://tests/test_video_phase4_port_garage_restore.gd -- --no-save --skip-arrival
```

Remover `--headless` e acrescentar `--capture` registra fotos. O repro usa por padrão o checkpoint em `res://evidence/video-review-phase4-20260924/`; aceita `--checkpoint=<arquivo>` e `--out=<diretório>`. A execução completa está em `tests/test_video_phase4_port_freight.gd`; o baseline em `tests/test_video_phase4_port_baseline.gd`. A alteração final de paths/argumentos no harness foi revisada estaticamente, sem repetir o runtime já validado.

Não houve escrita no save pessoal. A serialização JSON/GameState foi exercitada em uma nova Main; com `--no-save`, não foi validado o caminho de gravação do estado de combate em disco. O aviso de certificados do sistema aparece no início dos logs, sem falha de jogo; o probe de piso teve warning de teardown descrito pelo agente responsável. `git diff --check` dos arquivos compartilhados editados passou.

Performance do frete **não medida/aprovação pendente**: fotos não são benchmark, e editor/jogo do usuário (PIDs 76560/86396) continuaram abertos. Godot 4.7.2, Forward Mobile, RTX4060 Laptop, capturas 2560×1440. Nenhum processo de teste ficou ativo. Este lote adiciona um uso concreto ao porto, sem declarar toda a região finalizada.
