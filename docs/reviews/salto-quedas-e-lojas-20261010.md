# Salto, quedas e proteção das lojas — 10/10/2026

O jogador pode pular a pé com Espaço (A no Xbox / X no PlayStation). Foram reutilizados os clipes CC0 já adaptados ao Dante: `ual/Jump_Start`, `ual/Jump` e `ual/Jump_Land`. A queda livre acrescenta articulação dos braços/tronco; a pegada da mureta usa o solver das mãos com alvos na posição real do guarda-corpo.

Nas coberturas, mover-se intencionalmente para fora ultrapassa a mureta com a cápsula física. Não existe mais a ação E “Saltar da cobertura”, nem abertura/desativação do collider do guarda-corpo. Em coberturas baixas a mão pode segurar a borda por 0,24 s antes de soltar; cornijas externas são verificadas por movimento varrido, e a pegada só acontece dentro do alcance dos braços. O salto comum não dá dano. Quedas acima de 2,5 m aplicam `(altura medida do ponto mais alto − 2,5) × 12` à vida, uma vez, sem consumir colete. Sobreviventes amortecem o impacto e levantam; impactos fatais usam a pose caída de frente, poeira, respingo e mancha de sangue dos pools existentes.

`PlayerAirMovement` pertence somente ao Dante. Não cria controlador por NPC, partículas por personagem ou loop extra de população. Colisão com teto, paredes e piso permanece no `CharacterBody3D`; teleportes e respawn limpam o estado aéreo. Combate, embarque e save ficam bloqueados durante salto/queda/recuperação. Os dois controladores de cobertura conservam seus próprios contratos de sala/câmera/streaming, mas não aplicam um segundo dano de queda.

`ShopSafety` protege 26 lugares existentes, com 31 pavimentos internos autorados: 11 serviços dedicados e 15 edifícios do catálogo classificados como comércio/hospitalidade. São regras compartilhadas, não reforma física nem novas salas. Luísa, Nelson e residentes das lojas recebem proteção contra dano direto e herdada da sala. A entrada exige zero estrelas; as portas e admissão usam a mesma política. Entrada e restauração guardam a arma, bloqueiam saque/troca/disparo/explosivos/corpo a corpo e preservam o inventário. Os bancos conservam combate e assalto; Maciota e mecânico conservam a proteção permanente anterior.

## Evidência funcional

Godot 4.7.2 .NET, `Harbor.csproj` compilado sem erros, renderização Mobile na RTX 4060 Laptop. Os checkpoints de teste são isolados; não simulam o cumprimento das missões anteriores. Os arquivos históricos de falhas foram preservados.

| Cenário | Resultado e alcance |
| --- | --- |
| Física do salto e queda | 23 checks aprovados: salto, teto, ausência de salto duplo, queda baixa, colete intacto, dano único, recuperação, mureta sólida, contato das duas mãos, queda fatal e respawn. [Rodada final](../../output/player-air-20261010/final-air.log). |
| Política das lojas | 116 checks aprovados, incluindo os 26 IDs, armas/munição, inventário, snapshot, preservação dos bancos e proteção de Luísa/Nelson. [Rodada](../../output/player-air-20261010/hand-and-shop-contracts.log). Não certifica circulação física dos 26 lugares. |
| Main: entrada/restore da Curitiba Cellar | 15 checks aprovados: perseguição recusa entrada, duas rotas reais de dano não matam os moradores, save gravado em arquivo próprio, restauração fria e saída. [Log](../../output/player-air-20261010/main-shops-fixed.log), [foto real](../../evidence/shop-safety-session-35200-19914180/protected-luisa-nelson.png). |
| Main: cobertura baixa | 13 checks aprovados: circulação na cobertura, saída pela borda sem botão, queda física, dano, câmera/controles e limpeza da sala. [Log](../../output/player-air-20261010/main-roof.log), [antes da saída](../../evidence/harbor-rooftop-fall-41152-9047930/roof-gate-before-jump.png), [queda](../../evidence/harbor-rooftop-fall-41152-9047930/falling-over-street.png), [retorno ao chão](../../evidence/harbor-rooftop-fall-41152-9047930/street-after-fall.png). A primeira rodada antecede o ajuste fino de mãos/cornijas; esses ajustes passaram na física dirigida. |
| Main: teclado | 8 checks aprovados: tecla remapeável, apoio/altura livre, salto real por Espaço, bloqueio de combate/embarque e aterrissagem sem dano. [Log](../../output/player-air-20261010/main-input.log). |
| Main: queda alta | Queda real, morte, pose de impacto e liberação da sala aprovadas na rodada de 19 checks; aquela rodada conserva uma falha da fixture de teclado, resolvida separadamente. [Log histórico](../../output/player-air-20261010/main-jump-final.log), [queda livre](../../evidence/player-jump-session-43184-7432590/high-freefall.png), [impacto](../../evidence/player-jump-session-43184-7432590/fatal-ground-impact.png). Não apresentar a rodada histórica inteira como verde. |
| Física/estrutura existentes | Curitiba Cellar e catálogo de acessos às coberturas passaram; vinho, controle DualSense e recompensas da garagem passaram na seleção anterior. [Contratos](../../output/player-air-20261010/final-contracts.log), [regressões](../../output/player-air-20261010/suite.log). |
| Garagem: driver restore / vehicle transfer | Dois runners excederam 90 s; um registrou falha de prontidão da Main. Permanecem pendentes, sem atribuição demonstrada ao salto. Não aumentar timeout ou declarar esses casos aprovados. |

As primeiras fixtures de persistência foram executadas com `--no-save`, retornando sucesso lógico sem escrita. Foram corrigidas para habilitar somente o store isolado e conferir o arquivo gravado. A primeira observação de Espaço assumia seis sinais de física após a chamada de input: o diagnóstico mostrou o evento sendo consumido apenas no último sinal (`phase=jump`, `age=0`, velocidade vertical 6,7). A fixture corrigida observa a subida real com limite finito; não foi afrouxado o requisito de deslocamento.

## Performance: inconclusiva

Duas amostras renderizadas de 30 s em Main, caminhada física diante do MarketHall, 1920×1080, Mobile, MSAA 1, VSync 1, limite 144, i7-13650HX / RTX 4060 Laptop. Meta provisória: 60 FPS / 16,67 ms; confirmar aumento superior a 5% em p95/p99 com carga equivalente, sem alterar critérios depois da medição.

| Medição | FPS | p50 | p95 | p99 | Máximo | >33,3 ms / >66,7 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Antes | 91,08 | 11,701 ms | 18,024 ms | 29,321 ms | 41,736 ms | 15 / 0 |
| Depois | 103,59 | 10,953 ms | 15,638 ms | 18,884 ms | 46,620 ms | 4 / 0 |

[Dados antes](../../output/player-air-20261010/before.json), [depois](../../output/player-air-20261010/after.json), [concorrência](../../output/player-air-20261010/after-concurrency.json). Há outras sessões renderizadas e alterações simultâneas no workspace. A densidade adaptativa passou de 0,86 para 0,93, o teto de tráfego de 35 para 38 e a população de 7 para 8. Esses números não comprovam melhoria nem ausência de regressão. As capturas também perturbam o frame time. Falta comparação exclusiva e equivalente nas rotas de salto/queda, mureta e lojas, além de cobertura visual/temporal dos demais lugares. Nenhuma certificação global de FPS, iluminação ou interiores é concedida.

## Cobertura restante

- Cobertura de serviço Fuel: **48 checks aprovados** na Main renderizada, incluindo circulação, mureta sólida sem botão, save realmente gravado, restauração fria, descida pelo acesso, reentrada e queda final até o piso da cidade com dano e controle humano. [Log final](../../output/player-air-20261010/main-service-final.log), [evidência da rodada](../../evidence/harbor-service-roofs-66288-18223408/result.json). A correção da fixture limita escritas ao store isolado; a primeira rodada sem escrita permanece no histórico.
- Demais coberturas de serviço, interrupções integradas de morte/prisão durante pegada e retomada após pausa, e garagem: não certificados por esta rodada local.
- Fotos reais dos casos exercitados estão vinculadas acima. Não há captura anterior à implementação da proteção/novo salto; a foto anterior à saída demonstra o cenário físico da mesma rodada.
- Inventário geral de lugares/interiores continua com as contagens anteriores: zero lugares e zero interiores novos; nenhuma área marcada como concluída integralmente com performance ou cobertura obrigatória pendente.
