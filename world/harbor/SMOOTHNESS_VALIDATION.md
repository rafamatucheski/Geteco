# Harbor — fluidez, 2026-09-05

Rodada limitada a cortes de animacao e freezes, com dois agentes. Sem commits,
sem novo conteudo e sem usar reset. Editor mantido aberto; benchmarks e testes
executados sem outra instancia de jogo/teste concorrente.

## Causas e alteracoes

1. `JunctionTrafficController.gd`: agora aproveita `get_routing_revision()` existente
   para nao copiar e serializar a malha inalterada a cada 0,5 segundo. Troca de fonte,
   rebuild e configure explicito invalidam corretamente. Providers sem revisao
   conservam a verificacao por assinatura.
2. No mesmo controlador, cada mudanca de fase chamava a atualizacao GLOBAL dos
   semaforos e travessias. Muitas juncoes mudando juntas repetiam esse trabalho no
   mesmo frame. O perfil de callbacks localizou ali picos acima de 500 ms no
   diagnostico sintetico. Agora as mudancas de estado e os sinais individuais
   continuam acontecendo, mas a publicacao global ocorre uma vez ao final do
   callback. Mudancas fora desse lote continuam publicadas imediatamente.
   Prioridades, reservas e duracoes dos sinais nao foram alteradas.
3. `AnimatedPedestrian3D.gd`: personagens grandes na tela atualizam a pose a 60 Hz;
   intermediarios a 30 Hz e pequenos a 15 Hz. O temporizador conserva a fracao
   restante, em vez de descarta-la e produzir frequencia menor/irregular. Um stall
   nao dispara uma rajada de pedidos. Movimento, colisao e combate nao sao pulados.
4. `prototypes/living_cast/HarborCoupe.gd`: carro dirigido atualiza sua pose a 60 Hz,
   incluindo direcao e giro das rodas, em vez de 30 Hz. Conserva fracao temporal e continua
   evitando atualizacoes de pose quando distante, oculto ou parado sem mudanca.

Nao houve evidencia suficiente para modificar novamente a camera ou o Player.
Nao afirmamos que qualquer cintilacao de cenario/material foi eliminada: os
resultados demonstram melhora da cadencia das poses e dos freezes medidos.

## Medicoes reais

Godot 4.7.2 Compatibility, RTX 4060 Laptop, 1920x1080, VSync desativado no benchmark.
Cada amostra tem 600 frames, aceleracao real, partida em (700,425), com transito e
fisica ativos. Sao amostras curtas, nao garantia de 60 FPS em qualquer situacao.

| Medida | Antes desta rodada | Depois A | Confirmacao B |
| --- | --- | --- | --- |
| FPS medio | 71,0 | 79,4 | 80,5 |
| Frame mediano | 12,52 ms | 12,14 ms | 12,04 ms |
| P90 | 15,70 ms | 14,42 ms | 14,31 ms |
| P99 | 41,40 ms | 30,59 ms | 28,92 ms |
| Pior frame | 196,90 ms | 33,45 ms | 36,06 ms |
| Frames acima de 16,67 ms | 34/600 | 23/600 | 19/600 |
| Distancia percorrida | 2699 px | 2746 px | 2745 px |

Uma medicao intermediaria, ja com revisao de cache e cadencia das poses mas SEM
agrupar publicacoes, ainda teve 205,03 ms de pior frame. Agrupar as publicacoes
foi a mudanca decisiva para esses grandes picos, nao apenas aumentar FPS medio.

Logs em `D:/geteco/smooth-before.log`, `smooth-trace.log`, `smooth-batched.log` e
`smooth-confirm.log`. O perfil de callbacks invoca metodos manualmente e serve
apenas para localizar custo, nunca como validacao de FPS ou navegacao.

## Instrumentacao e testes

- `tests/measure_harbor_sustained_driving.gd`: argumento `-- trace` registra frames
  acima de 30 ms, posicao e monitores de renderizacao. Metricas continuam incluindo
  o tempo de frame inteiro; monitores nao devem ser confundidos com esse tempo.
- `tests/profile_harbor_callbacks.gd`: modo `-- physics` inclui callbacks fisicos
  no diagnostico sintetico, mostrando chamadas individuais acima de 20 ms.
- Novos testes: `test_junction_revision_cache.gd` e
  `test_junction_stage_publication.gd`.
- Estendidos: `test_pedestrian_render_lod.gd` e `test_harbor_coupe.gd`.

## Pendencias preservadas

- Ainda existem frames de aproximadamente 29-36 ms nessas amostras.
- Visao geral e outras condicoes climaticas nao foram novamente benchmarkadas.
- Fila Courtyard Lane nao foi corrigida. Inspecao sugere perda da transicao quando
  um passo ultrapassa o conector: o plano e descartado e a entrada ja passou.
  Isso e hipotese, nao diagnostico comprovado por novo teste. Nao alteramos
  tolerancias, prioridades ou testes para esconder a fila.
- Nao foi implementado streaming completo de bairros.

## Resultado final: 11/11 testes selecionados passaram

Executados sequencialmente, exit 0, sem SCRIPT ERROR nem assercoes falhas:

- test_junction_revision_cache
- test_lane_projection_cache
- test_junction_stage_publication
- junction_traffic_contract_test
- district_one_traffic_integration_test
- test_pedestrian_render_lod (120 pedidos proximos / 30 pequenos em 2 s)
- test_harbor_coupe (movimento, rodas, colisao/deformacao, pintura e reparo)
- test_living_cast_contract
- rail_level_crossing_runtime_test (ciclo natural, zero conflitos, folga 243 px)
- test_harbor_safety (91 travessias, 61 transferencias de faixa)
- test_harbor_road_contract (20 ruas, 40 faixas, 38 juncoes)

Logs: `D:/geteco/smooth-final-<teste>.log` e `-errors.log`. Persistem avisos do
ambiente sobre escrita de logs/certificados, ObjectDB no encerramento de algumas
fixtures e lotes inseguros ignorados do distrito antigo. Nao e uma execucao de toda
a suite do repositorio; o teste longo Courtyard nao foi repetido nesta rodada.
Ao terminar, somente o editor Godot anterior (PID 88668) permaneceu aberto.
