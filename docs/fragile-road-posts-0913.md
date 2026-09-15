# Postes e semáforos frágeis

Impactos usam a velocidade de aproximação perpendicular à superfície, já calculada por VehicleMotionSafety. Abaixo de 15 px/s não há reação; de 15 até 70 px/s há balanço; a partir de 70 px/s ocorre queda em uma batida. O poste de iluminação antes exigia 170 px/s. Caminhar não chama essa reação e continua bloqueado pela base. Um impacto suficiente interrompe o balanço mesmo durante seu cooldown.

Semáforos agora têm corpo estático na base visual de 8 × 4 px, queda por tween e luzes apagadas após quebra. A mudança de fase não reacende o objeto caído. As reservas de cruzamento permanecem funcionando. A renovação restaura pose, colisão e iluminação. Postes quebrados liberam a colisão e não anulam a velocidade do carro no resolvedor de movimento.

Validação headless com Godot 4.7.2: `test_fragile_road_posts.gd`, `test_street_lamp_impact.gd` e `junction_traffic_contract_test.gd` passaram. O novo teste cobre bloqueio a pé, manobra leve, impacto físico de 80 px/s durante balanço, travessia, pose caída, luz apagada após troca de fase e restauração.

Performance e inspeção visual integrada pendentes: havia outra medição renderizada de floresta, editor e processos de validação concorrentes; não foi feito comparativo de FPS. Risco específico: novos corpos estáticos de semáforos e maior frequência de animações de queda. Semáforos não ganham processamento por frame permanente nem SubViewports; postes de iluminação reutilizam o mecanismo de apresentação existente. Meta provisória: 60 FPS / 16,67 ms, com comparação renderizada de pelo menos 30 s no mesmo cruzamento e investigação se p95/p99 aumentarem mais de 5%. Esta alteração não certifica desempenho nem circulação de todos os cruzamentos.
