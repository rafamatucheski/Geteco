# Colisões de carros — 28/09/2026

A resposta linear do atingido era aplicada por crash_slide/move_and_collide, separada da velocidade usada na direção e no cálculo da próxima colisão. Agora ambos recebem a velocidade resultante na horizontal_velocity, speed e velocity. Restituição reduzida de 0,15 para 0,03; massa, dano e rotação de impacto preservados.

Validação funcional: test_vehicle_impact_momentum.gd reproduziu 13 falhas antes e zero depois (traseira, frontal, massas diferentes e impacto oblíquo; conservação de momento, energia não crescente e velocidade coerente). test_vehicle_crash_damage.gd passou, incluindo colisões físicas contra carro/parede e dano sem repetição por contato. O fixture deste teste inicializa somente o diretor de colisões, sem acessar controller ausente. O processo reportou objetos/recursos remanescentes ao encerrar; não houve falha de asserção.

Medição exploratória renderizada: tests/measure/measure_full.gd --drive --no-save --skip-arrival, 5 s de aquecimento e 30 s de amostragem, Main real, Godot 4.7.2 Mobile, RTX 4060 Laptop, 1280x720, VSync 0, limite 144. Meta provisória 60 FPS/16,67 ms; aumento >5% em p95/p99 requer confirmação controlada.

| Rodada | FPS | p50 ms | p95 ms | p99 ms | máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Antes | 88,37 | 12,824 | 15,789 | 19,018 | 44,429 | 1 | 0 |
| Depois | 81,12 | 13,017 | 17,858 | 28,275 | 60,953 | 8 | 0 |

Performance PENDENTE, comparação inconclusiva: outras instâncias Godot presentes, população 43 versus 41 e percurso 56,76 versus 78,29 m. A amostra não controla quantidade de impactos. P95/p99 pioraram nesta rodada; não é possível atribuir causalidade à correção. Não se certificam FPS nem ausência de regressão. É necessário repetir com cena/rota/impactos determinísticos e sem concorrência. Não foram encerrados processos de outras sessões. Os JSONs guardam amostras e ambiente; PNGs são capturas do benchmark, não revisão visual de uma colisão. Os benchmarks também reportaram texturas remanescentes ao encerrar.

A primeira tentativa de benchmark, no sandbox restrito, não conseguiu gravar arquivos e foi encerrada; a execução com permissão de gravação gerou before.json. As execuções before/after foram sequenciais. Alterações locais de outras sessões foram preservadas.
