# Quedas do carro no benchmark dirigindo (31/10/2026)

Card: "Carro abaixo do mapa: resgate de veículo que cai do mundo entrou em 13/10 (49d069fd); no
benchmark dirigindo ainda há quedas sob a passarela." Esta é uma investigação **estática**: o Godot
não rodou, nada foi medido.

## O que o código mostra

1. **O resgate de 13/10 não cobre o carro dirigido.** `ProductionWorld._rescue_fallen_vehicles`
   pula `world.driving.car` enquanto `world.driving.occupied`. Ele foi feito para o veículo
   persistente estacionado cujo chunk sai da memória (moto da serra, y≈-1300). No benchmark o
   jogador está dentro do carro, então esse resgate nunca dispara; quem trata a queda é
   `BenchmarkAutopilot.drive` (queda = 8 m abaixo da rota, campo `falls`). As duas coisas do card
   são mecanismos diferentes: o resgate entrar em 13/10 não diz nada sobre as quedas do benchmark.
2. **A passarela das quedas não existe mais.** A única passarela do Harbor
   (`world_edits.json`, `new/1790561382_7179923_934509863`, em x=120, z=78, sobre o trecho
   (64,82)→(150,82) da rota `oeste`) está `"deleted": true` desde 7accbd23 (21/10). As "27 quedas
   sob a passarela e em z≈60" são de perfinv3/4 de 17/10 (`docs/perf-exe-20261017.md`); não houve
   medição depois da remoção (o board de 26/10 confirma "sem nova medição").
3. **Hipótese para o que existia sob a passarela** (não verificável agora): a rampa de colisão de
   cada escada (`UrbanFootbridge3D`, caixa fina de 0,3 m inclinada 32°, `slope_length + 0.3`, com a
   ponta de baixo entrando no piso) tem face de baixo com normal para baixo. Um carro que passa
   sob o lance encosta nela por baixo e a despenetração o empurra para o piso — combina com a nota
   da sonda de 17/10, "o chão existe lá; carro empurrado através do piso". Com a passarela apagada,
   essa causa saiu do mapa junto; se a passarela voltar, vale reabrir (rampa só na camada do
   pedestre, ou uma caixa cheia sob o lance em vez da laje fina).
4. **z≈60** (trecho (143,60)→(84,60)) continua sem causa identificada.

## Mudança feita

`BenchmarkAutopilot.summary()` agora grava `fall_points`: até 32 quedas com `[x, y, z, progresso]`
no quadro em que foram detectadas. Antes só havia a contagem, e o local vinha de olhar os logs.

## O que medir

No export release, mesmo dia:

```
tools/perf_cross_bench.sh <pasta> quedas_20261031 3 oeste   # com --benchmark-drive
```

- Se `falls` = 0 perto de x≈120, z≈82: a parte "sob a passarela" do card fecha.
- Agrupar `fall_points` por (x, z); para o grupo de z≈60, conferir se a célula do chão já estava
  montada (`HARBOR_STALL_LOG=1`) e que corpo o carro tocava no quadro anterior.
- Separado do benchmark: jogando, um carro dirigido que atravessa o piso cai para sempre, porque o
  resgate de 13/10 o ignora. Decidir se ele deve cobrir o carro ocupado também (precisa testar com
  jogador dentro, já que o resgate desliga a física do carro até o chão carregar).
