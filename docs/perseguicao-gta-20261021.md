# Perseguição de carro estilo GTA — 21/10/2026

Regras, números e arquivos: [gameplay/dispatch/README.md](../gameplay/dispatch/README.md), seção
"Perseguição de carro estilo GTA". `GETECO_GTA_CHASE=0` volta ao comportamento anterior inteiro.

## Por que

Avaliação feita só lendo o código (nada rodado): a perseguição se sabotava.

| Problema antes | Onde estava | Efeito |
|---|---|---|
| Rota terminava onde o jogador **estava** e a viatura freava até lá; novo plano só 2,5–3,7 s depois | `DispatchDriver` (frenagem de fim de rota), `DispatchUnit._replan_towards` | anda e freia em ciclos |
| Sensor frontal freava diante do carro do jogador | `DispatchDriver._obstacle_ahead` | ficava ~16–27 m atrás, nunca encostava |
| Teto 21/25 m/s, curva a 4 m/s | `DispatchRules`, `DispatchDriver` | carro comum empatava, esportivo sumia |
| Só rua, só na mão | `DispatchRoadRouter.plan` | fora do asfalto parava na ponta da rua |
| Viatura a > 130 m congelava e segurava a vaga por até 45 s | `DispatchUnit._tick_suspension` | pressão sumia ao abrir distância |
| Reforço nascia no ponto mais próximo | `DispatchController.dispatch_police_to` | quase sempre atrás |
| Formação decorativa (flanco a 2 m, mesma faixa) | `DispatchRules.formation_goal` | fila indiana |
| Visão de 40 m e fuga só por tempo, minimapa sem polícia | `DispatchUnit._sees_target`, `Gameplay._update_police` | despistar sem leitura espacial |
| Bloqueio perto da última posição, só com 4+ estrelas | `PoliceRoadblocks.try_place` | muitas vezes atrás |
| Sem prisão dentro do carro | `Gameplay.police_can_arrest` | — |

## O que foi feito

Fases 1 a 3 da avaliação; detalhes no README do despacho. Não feito: contramão em mão única no
roteador (só as rampas da ponte e da rodovia são mão única; exigiria mudar o espelho C# e a montagem
das curvas). Voz no rádio: só as frases-base e os sentidos em PT-BR; a cota mensal da ElevenLabs
acabou no meio do lote (nomes de rua e inglês ficam em texto até gerar o resto).

## Verificação (21/10)

**Laboratório** (`tests/dispatch/test_dispatch_gta_chase.gd`, `Run.ps1 -Suite gta`): 74/74. Anel de
ruas com avenidas cruzadas, carro em fuga dirigido por um robô a 18 m/s (mesma física de `Vehicle`
das viaturas), duas estrelas, contato mantido por "testemunhas", 50 s:

| | `GETECO_GTA_CHASE=1` | `GETECO_GTA_CHASE=0` |
|---|---|---|
| Contatos físicos com o carro em fuga | 24 | 4 |
| Giros de PIT aplicados | 7 | — |
| Maior velocidade das viaturas | 36,6 m/s | 21,0 m/s |
| Viaturas recicladas / reforços nascidos à frente | 4 / 7 | 0 / 0 (2 suspensas) |
| Maior deslocamento por quadro de física | 0,61 m | 0,35 m |

Também passaram: reciclagem (vaga e orçamento devolvidos; sem contato recente continua só
suspensa), nascimento à frente (3/3), busca em leque (pontos distintos dentro da área, ninguém
desce), bloqueio com pregos 70 m à frente sobre a avenida do alvo, bloqueador no cruzamento em que
chega antes, fora do asfalto (viatura sai da rua e chega a 4,9 m), prisão dentro do carro parado
com duas estrelas sem força, regras puras, rádio (texto e pedaços de voz) e o interruptor desligado.

**Suítes antigas**: regras do despacho, resposta terrestre, casos policiais, escalada e HUD compacto
no mundo real (54/54) passaram. Falhas que existem também com `GETECO_GTA_CHASE=0` ou antes deste
trabalho (não são desta mudança): `test_dispatch_police` (9; falha desde 11/10 nos relatórios de
`evidence/test-suite/`), `test_dispatch_lifecycle` (espera a ambulância 5 s, mas ela sai em 12–22 s
desde `b63d8615`), `test_dispatch_emergency` (1, bombeiro), `test_stolen_officer_budget` (2,
pendência declarada), `test_gameplay` (armas, Cobra, seis estrelas) e as integradas que não terminam
de carregar o mundo no prazo do teste.

**Não verificado**: ninguém jogou uma fuga com controle; nenhuma medição de quadro em release ainda
(a exportação foi interrompida porque `runtime/ProductionWorld.gd`, em edição por outra sessão,
não compilava às 13:20 e o jogo exportado não carregaria). `tools/perf_gta_chase_ab.sh` faz o A/B
quando der. A voz do rádio só foi ouvida fora do jogo (amostra montada dos WAVs instalados).
