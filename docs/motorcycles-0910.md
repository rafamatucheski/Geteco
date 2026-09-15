# Motos no trânsito — 10/09/2026

Três veículos originais adicionados ao catálogo e à população normal de HarborLife:

| ID | Modelo | Estilo | Cores |
|---|---|---|---|
| bike_sport | Vortex RR 900 | Esportiva carenada, quatro cilindros | Vermelho, azul, amarelo, branco, preto |
| bike_cruiser | Ironhorse 1700 | Cruiser inspirada no estilo Harley, V-twin | Preto, vinho, laranja, verde, creme |
| bike_urban | Cometa City 250 | Urbana, monocilíndrica | Azul, vermelho, branco, grafite, amarelo |

Geometria procedural nativa, sem modelos ou gravações de terceiros. Tanque, banco, motor aletado, escapamento com saída escura, suspensão, discos, pinças, rodas raiadas, retrovisores, painel, faróis, setas, placa e para-lamas. A cruiser também tem alforjes e escape duplo. Capacete fechado, viseira, jaqueta, luvas e botas no piloto.

As motos usam o controlador e as rotas reais dos carros, incluindo regras de cruzamento e reposição da população; o total de veículos não aumenta. A colisão fica mais estreita. A apresentação permanece adiada e limitada pela visibilidade, com silhueta própria durante o carregamento.

Roda dianteira, garfo e guidão esterçam pelo eixo da direção; pneus giram separadamente. As mãos acompanham os punhos, a moto inclina nas curvas e o pé esquerdo alcança o chão quando parada. Sem ocupante, o piloto desaparece e o descanso aparece. A entrada/saída do jogador usa os controles existentes, com animação de montar e piloto capacetado como representação durante a condução. Motos não criam portas nem rádio de carro.

Três famílias de motor, cada uma com três camadas e câmbio próprio; esportiva com seis marchas, cruiser e urbana com cinco. NPCs próximos à câmera têm áudio posicional, mais baixo que o veículo do jogador. Danos, pintura, reparos e queima usam os sistemas existentes.

## Verificação

- `tests/test_motorcycles.gd`: catálogo, cores, colisão antes/depois do carregamento, movimento de NPC, duas rodas, esterçamento, inclinação, estacionamento, pintura isolada, dano/reparo, montar/descer, áudio/câmbio e troca entre modelos. **0 falhas**.
- `tests/test_motorcycles_live.gd`: HarborGame real gerou 5 esportivas, 5 cruisers e 6 urbanas; os 16 NPCs avançaram. Dante montou/desceu e recuperou visibilidade, física e controle. **Passou**.
- `tests/test_motorcycle_geometry.gd`: amostragem das superfícies pintadas contra os pneus a -0,58 / 0 / +0,58 rad, após montagem do rig. **0 interseções detectadas**. Mãos e pé de apoio verificados após batching.
- `tests/test_engine_loop_seam.gd -- bikes-only`: nove camadas verificadas com áudio realmente mixado; **0 estalos detectados, 0 resultados inconclusivos**.
- Regressões `test_vehicle_engine_and_name.gd`, `test_vehicle_presentation_streaming.gd` e `test_coupe_wheel_mounts.gd`: **0 falhas**.
- Revisão visual: `tests/capture_motorcycles.gd`, saída em `D:/geteco/artifacts/motorcycles-fleet.png`.

Godot emitiu o aviso de câmera com interpolação física. O encerramento do teste completo de Harbor e da suíte preexistente de motores também mostrou avisos de ObjectDB (1 e 12 instâncias, respectivamente), sem falha nas verificações acima.

## Dante e capacete

O jogador montado agora usa cópias das peças articuladas do próprio Dante, com o mesmo rosto, cabelo, barba e traje. O piloto genérico fica oculto durante a condução do jogador. Os encaixes de cabeça/pescoço preservam o contrato do rig de caminhada; o capacete é um filho da cabeça, sem reparentar ou modificar a geometria original do ator.

Depois de montar, 3 segundos contínuos parado iniciam o gesto de colocar o capacete (0,75 s). Movimento reinicia a espera; o tempo da animação de embarque não conta. Ao descer equipado, Dante mantém o capacete por 10 segundos e então faz o gesto de retirada (0,75 s). Subir novamente cancela a retirada, inclusive durante o gesto. Descer antes de equipar cancela a colocação. Pausar o jogo congela os tempos. O estado pertence ao Dante e continua funcionando enquanto a pilotagem oculta o ator e desliga sua física.

O capacete fechado alterna a visibilidade das peças originais do rosto/cabelo, preservando suas transformações e materiais. Ao retirar, a visibilidade original retorna. Trocas de roupa reconstroem o encaixe e atualizam a representação montada.

- `test_dante_motorcycle_helmet.gd`: limites de tempo, movimento, embarque/desembarque, remonte durante espera e retirada, rosto/traje originais, cabeça ligada ao pescoço em três ângulos, troca de traje, processamento sem física e pausa. **0 falhas nos três modelos**.
- `test_dante_natural_gait.gd`, `test_motorcycle_geometry.gd`, `test_motorcycles.gd` e `test_motorcycles_live.gd`: **passaram**.
- Captura dos seis estados reais: `tests/capture_dante_motorcycle_helmet.gd` → `D:/geteco/artifacts/dante-motorcycle-helmet.png`.
