# Muscle cars, lowriders e o encontro da Vila Cobra (27/10)

Pedido: os Cobras precisavam de carros diferentes (todos rodavam no mesmo `cobra_v8` verde),
muscle cars de vários modelos, lowriders e um evento de lowrider com a turma da quebrada, música
ambiente e a hidráulica subindo e descendo carroceria por lado.

## Frota nova (`runtime/MuscleFleet.gd`)

Desenhos próprios, inspirados nas escolas americanas sem copiar carro nenhum. Todos RWD.

| id | nome | tipo | ideia |
|---|---|---|---|
| `potro_68` | Potro 68 Fastback | muscle | fastback de capô longo, farol redondo nas pontas da grade, três barras verticais na lanterna, tomada lateral |
| `jararaca_v10` | Jararaca V10 | muscle | nariz longo e baixo, guelras no para-lama, escapamento lateral, faixas duplas, lanterna oval |
| `carcara_ss` | Carcará SS | muscle | notchback, grade colmeia com faróis dentro, faixa "abelha" no bico, tomada no pé do para-brisa |
| `trovao_440` | Trovão 440 | muscle | longo, grade escura de faróis escondidos, coluna-vela, teto de vinil, duas lanternas redondas por lado |
| `caiman_454` | Caimã 454 | muscle | quadrado, dois faróis por lado, tomada no capô, duas faixas largas, lanterna no para-choque |
| `brasa_hc` | Brasa HC | muscle moderno | quatro faróis com anel de LED, compressor no capô, lanterna de ponta a ponta, pinça laranja |
| `imperador_64` | Imperador 64 | lowrider | teto rígido sem coluna, quatro faróis, três lanternas redondas por lado, lança cromada |
| `imperador_64_conv` | Imperador 64 Conversível | lowrider | o mesmo aberto, banco inteiriço em capitonê, volante de corrente, estepe "continental" |
| `monte_rei_84` | Monte Rei 84 | lowrider | cupê quadrado anos 80, faróis retangulares, teto landau de vinil, aerofólio pequeno |
| `duque_76` | Duque 76 | lowrider | sedã de quatro portas enorme, grade de pé, ornamento no capô, saias nas rodas traseiras |

Os lowriders saem rebaixados (soleira a 17 cm, caixa de roda cobrindo o topo do pneu), com roda
raiada cromada ou dourada e pneu de faixa branca.

- Gerador: `tools/fleet_fixups/build_muscle_fleet.gd` herda o loft dos esportivos 2.0
  (`build_sport_fleet_v2.gd`, que ganhou `catalog()`/`designs()`/`report_path()` para isso) e
  acrescenta para-choque cromado que contorna a ponta, faixas no capô e no teto, teto de vinil,
  saia de para-lama, estepe continental, tomada de capô, costura de porta traseira e a cabine
  de banco inteiriço. Medidas reais em `evidence/muscle-lowrider-20261027/geometry.json`.
- O flanco de fora do pneu no gerador 2.0 tinha a normal virada para dentro e sumia no corte de
  faces (a faixa branca não aparecia). O gerador novo calcula a normal pelo perfil; os esportivos
  2.0 continuam assados com o defeito (pneu preto, então quase não se nota).
- Motor completo em `StreetPowertrainCatalog` (lowrider com câmbio de três marchas), som em
  `FleetEngineDesign` (V8; o Jararaca usa a classe V10/V12), peças de fábrica no `FACTORY_KIT`.
- Ritmo: muscle entre o Cobra V8 (610) e os esportivos 2.0 (660–700); lowrider 500–530.

```bash
GODOT_RUN_TIMEOUT=900 tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/build_muscle_fleet.gd -- --id=potro_68
tools/run_godot_locked.sh --path . --script res://tests/capture/capture_new_civilian_fleet.gd -- --ids=potro_68 --out=evidence/muscle-lowrider-20261027/photos
```

## Cobras

- Trânsito: o carro do Cobra sai de `MuscleFleet.cobra_pick()` (72 % muscle, 28 % lowrider) com
  pintura de gangue sorteada (`COBRA_PAINTS`: verde-ferro, preto, cobre, vinho).
- O emblema do capô usa o ponto `hood_badge` medido no gerador (antes o racha media a malha em jogo).
- Racha dos Cobras: o líder segue no Cobra V8; os outros dois vêm da garagem nova (um muscle e um
  lowrider no lugar da picape lenta).
- Lowrider dos Cobras parado no sinal às vezes "dança" (os dois sentados acompanham a carroceria).

## Hidráulica (`gameplay/lowrider/LowriderHydraulics.gd`)

Só apresentação: move o `visual` do Vehicle e devolve as rodas ao chão pela transformação inversa
(portas, pintura, amassados e lanternas acompanham). Curso de 34 cm por canto; a roda sai do chão
só depois de 38 cm (pulo cheio de 0,95 m). Motorista (`driver_seat_anchor`, `VehicleInterior.follow`)
e ocupantes registrados sobem junto. Parada na altura assada, custa um teste por quadro.

Controles (ação nova `hydraulics`, remapeável):

- Teclado: segure **Ctrl** e use **W/S/A/D** para levantar frente, traseira, esquerda e direita
  (diagonais levantam um canto); **Espaço** pula; toque rápido em Ctrl alterna carro alto/baixo.
- Controle: segure **L3** e use o analógico esquerdo; **A** pula.
- Pular de novo logo depois de aterrissar (0,35 s) encadeia e sobe mais, até 1,15 do pulo cheio.

Sons provisórios do banco existente (freio de mão grave, freio a ar, porta) até gravar os da
hidráulica.

## Encontro de lowriders (`gameplay/lowrider/LowriderMeet.gd`)

- Onde: acostamento norte da rua de acesso da Vila Cobra (x 409–447, z 100–103), em frente ao
  pátio da Torque (encontro de clássicos). Marcador "Encontro Lowrider (noite)" no mapa.
- Quando: toda noite, das 18 h às 3 h. De dia ficam dois lowriders estacionados.
  `GETECO_LOWRIDER_MEET=always` liga a noite toda hora (para testar).
- O quê: cinco lowriders fazendo hidráulica (um pulando), nove manos na calçada (três balançando
  no ritmo, o resto conversando e comemorando os pulos), som saindo do conversível com as faixas
  CC0 das rádios PORTO CRUISE ("Midnight Cruiser") e PORTO GROOVE ("Wednesday Night"). Perto do
  som o rádio do carro do jogador pausa.
- Desafio do pulo: chegando num lowrider, bata o recorde da noite (0,70–0,92 m) e ganhe R$ 600
  (uma vez por noite).
- Carros são Vehicle de verdade (dá para entrar e roubar); convidados são civis do encontro do
  racha. Uma peça por varredura, cena do carro e faixa carregadas em thread.

## Testes (27/10)

- `tests/test_muscle_fleet_models.gd` 212/212, `tests/test_lowrider_hydraulics.gd` 25/25,
  `tests/test_lowrider_meet.gd` 101/101.
- `tests/capture/capture_lowrider_meet.gd` (com janela, mundo de verdade, build de editor): à noite
  o encontro monta 5 carros e 9 convidados, o som toca, o carro do pulo sobe 0,91 m e um Cobra do
  trânsito apareceu num Imperador conversível. Pior quadro com o encontro parado 29 ms e no
  disparo dos cinco shows 23 ms; os picos de 270–317 ms da captura são as fotos que o próprio
  script grava (sem trabalho registrado no quadro). Não é medição de release.
- Sem regressão: esportivos 2.0 204/204 (gerador refatorado), frota civil 180, tuning 1734,
  racha/banco/balística dos Cobras, suíte core 12/12. O contrato de som de motor segue com as 6
  falhas antigas (Besouro, Maré, Toco).
- Torque: `calibrate_street_powertrain` bate no teto da busca para os novos (como já acontece com o
  Cobra V8 e outros); com o torque gravado, 400 m 3–4 % acima da ficha e final igual.

## Limites conhecidos

- Ninguém dirigiu, ouviu ou viu o encontro no jogo aberto; desempenho em release não medido.
- Música: são faixas funk/cruise já do jogo, não G-funk de verdade. Para a "música dos manos",
  gerar faixas próprias (ElevenLabs Music ou Gemini Lyria no navegador) e trocar `TRACKS`.
- Sons da hidráulica são provisórios.
- Muscle clássicos ainda têm estufa parecida entre si (loft esportivo); dá para afinar por carro.
