# Coupe: montagem, direcao e efeitos — 2026-09-05

## O que foi corrigido

- `PlayerCar.gd`: extraido gancho de direcao mantendo a formula antiga para
  carros comuns. Corrigidas escalas das particulas: uma textura de 64 px era
  multiplicada por 3–7 no escapamento, produzindo manchas de 192–448 px para um
  carro de 74 px. Agora os efeitos usam diametros em pixels do mundo (escapamento
  3–9, fumaca 12–32, faiscas 2–5; bola de fogo de explosao 50–120 por particula).
  Dano, raio de explosao, colisao e tempos de combustao nao foram reduzidos.
- `HarborCoupe.gd`: direcao progressiva baseada em distancia entre eixos; sem giro
  da carroceria parado, inversao correta em re, curvas mais abertas em alta
  velocidade e velocidade acompanhando a orientacao das rodas. Mantidos limite
  de 450 px/s no Harbor, dimensoes e todos os contratos herdados de gameplay.
  Rodas dianteiras usam o mesmo angulo da direcao; pinças nao giram com o pneu.
  Acrescentada sombra de contato, porta menor e emissao nas duas ponteiras de
  escapamento. Fumaca/fogo do motor ficam na traseira deste modelo.
- `RearEngineCoupe.gd`: pecas das rodas identificadas explicitamente por metadados,
  substituindo selecao geometrica aproximada na integracao. Geometria original
  preservada. Os eixos do carro intacto ja estavam corretamente centrados:
  isso foi testado antes de editar e nao houve deslocamento arbitrario deles.

## Evidencia visual

A captura com comandos reais reproduziu uma mancha enorme de escapamento com
`health=100` e `exploding=false`. Portanto, a nuvem por si so NAO comprova uma
explosao; corrige-se aqui a leitura inicial excessivamente conclusiva do video.
Isso nao prova qual foi o estado de saude durante toda a gravacao enviada.

Capturas em `D:/geteco/coupe-handling-street.png` e
`D:/geteco/coupe-handling-turn.png`, geradas por
`tests/visual/capture_coupe_handling.gd`. Nenhuma imagem conceitual substitui o
render do jogo nesses arquivos.

## Testes

- Novos: `test_coupe_handling.gd` e `test_coupe_wheel_mounts.gd`.
- Direcao parada, retorno ao centro, limite de angulo por velocidade, aderencia,
  re, preservacao da direcao dos carros comuns e dimensao/emissao de particulas.
- Comandos reais para esquerda/direita/re: cerca de 559–566 px por viagem, vida100.
- Eixos centrados, uma pinça nao giratoria por roda, dano sem deslocar eixos e
  reparo restaurando lataria.
- Regressao: `test_harbor_coupe`, `test_rear_engine_coupe`,
  `test_vehicle_crash_and_explosion`, `test_police_car_alarm_theft`,
  `test_harbor_bridge`. Logs `D:/geteco/car-final-<teste>.log`.

## Continuacao do plano

Resultado final: sete testes acima aprovados (exit 0 e sem SCRIPT ERROR). Persistem
mensagens ambientais de logs/certificados e ObjectDB em algumas fixtures.
Benchmark grafico final, 1920x1080/Compatibility, 600 frames: media 79,3 FPS,
P99 29,09 ms, pior frame 38,91 ms, 2730 px percorridos. Nao e garantia de 60 FPS
constantes nem uma execucao da suite inteira. Captura final: vida100, exploding=false.

Esta entrega trata o carro, nao declara o distrito inteiro pronto. Antes da
missao completa ainda ha a fila Courtyard e a integracao entre a previa Harbor e
o jogo de campanha. A leitura de `MissionManager.gd` encontrou coordenadas fixas
do mapa antigo; nao foi conectado cegamente ao Harbor. `CampaignState.gd` ja tem
estado de campanha baseado em dados e deve ser reaproveitado.

Proximo bloco: validar circuito de deslocamento, mapear os pontos da missao
existente para locais/entradas Harbor e fechar inicio, objetivos, falha/checkpoint
e hospital. Cinematicas curtas e atividades secundarias entram depois desse fluxo,
sem inventar outro roteiro ou aumentar a cidade nesta entrega.

Sem commits, sem uso de reset e sem alteracoes em missoes/save/settings.
