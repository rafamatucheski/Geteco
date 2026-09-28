# Saída de veículo em movimento — 28/09/2026

## Comportamento

F usa a saída normal até 2 m/s (~7,2 km/h). Acima disso, usa VehicleBailout: saída lateral admitida por cápsula e varredura, impulso herdado com limite, queda, rolamento e recuperação em cerca de dois segundos. O carro não tem sua velocidade zerada. A cápsula temporariamente mais larga protege o corpo recolhido contra obstáculos. Só o veículo de origem tem uma exceção de colisão por 0,35 s para evitar contatos antigos do corpo antes oculto; a exceção é removida também no cancelamento. Os demais sólidos continuam colidindo.

Dano ambiental aplicado uma única vez ao pousar: clamp((velocidade - 2) * 0,8 + 3, 3, 18). Não consome colete. Vida insuficiente pode causar morte e impede recuperação. Entrada e ações ficam bloqueadas enquanto o corpo está caído; pausa, interrupção, remoção e destruição do veículo são tratadas. A câmera acompanha o personagem. Nenhuma rotina de dano dos personagens da garagem foi alterada.

## Validação

- tests/test_vehicle_bailout.gd: 53 checks, zero falhas. Inclui marcha à ré, velocidades 9/22 m/s, dano único, controle e colisão restaurados, extremidades acima do piso, paredes, portas bloqueadas, pausa, cancelamento, limpeza da exceção/cápsula, queda fatal e remoção do carro.
- Quatro regressões passaram: test_vehicle_body_transitions (21 checks), test_garage_rewards (47), test_garage_driver_restore (26), test_garage_vehicle_transfer (11). As duas últimas verificam também restrições de armas dentro/fora da garagem. Relatório: ../test-suite/suite-2026-09-28_1225.json.
- Na Main renderizada, cinco saídas a 9 m/s foram admitidas e concluídas: vida 91,4/100 em todas, jogador a pé e controle restaurado. Dados: after-workload.json.
- Capturas roll-008/026/048/072/108.png revisadas: salto, giro com membros recolhidos e retorno à postura em pé. O cenário físico dirigido usa piso plano; não certifica todos os declives/veículos do catálogo.
- O validador histórico tests/validate_driving.gd foi atualizado para esperar a nova saída e reentrada; não foi executado integralmente nesta tarefa. A nova funcionalidade e a saída normal foram exercitadas pelos testes acima.
- Rodadas renderizadas registraram avisos de texturas remanescentes no encerramento. A rodada headless final concluiu sem erros de script. Uma primeira versão do fixture revelou contato indesejado com o carro; foi corrigido e protegido por assertion.

## Performance: pendente

Alvo provisório: 60 FPS / 16,67 ms. Tolerância de investigação: aumento >5% no p95/p99. Mesmo script antes/depois: tests/measure/measure_vehicle_bailout.gd, Main real, câmera fixa, clima/hora fixados, 5 s de aquecimento e 30 s de amostragem; Godot 4.7.2 Mobile, RTX 4060 Laptop, 1280x720, VSync desligado, limite 144, 40 pessoas e 44 carros. Antes os cinco pedidos eram recusados; depois os cinco exercitaram a sequência completa.

| Rodada | FPS | p50 ms | p95 ms | p99 ms | máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Antes | 96,95 | 11,488 | 15,769 | 17,544 | 25,459 | 0 | 0 |
| Depois | 61,43 | 13,363 | 48,637 | 87,767 | 170,929 | 130 | 47 |

A segunda rodada piorou materialmente. Havia várias instâncias Godot de outras sessões em execução (observadas às 12:27, inclusive processos iniciados durante a medição). Não foram encerradas. Assim, não se atribui a diferença à implementação nem se declara performance aprovada; é necessário comparar novamente sem concorrência e investigar caso a piora persista. As medições próprias foram sequenciais. O trabalho novo é limitado a um controlador por salto, sem busca de entidades ou processamento quando inativo. JSONs guardam amostras reais e ambiente.

Comandos usam --no-save e não alteram a partida do usuário. Alterações concorrentes foram preservadas.
