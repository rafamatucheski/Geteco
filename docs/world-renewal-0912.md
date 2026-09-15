# Renovação do mundo

O relógio de limpeza fica nos autoloads `NPCMedicalCare` e `WorldRenewal`, independente da simulação das regiões. Pausar o jogo pausa esse relógio; afastar-se de uma região não pausa a limpeza. Não é necessário iniciar uma campanha nova.

| Estado | Comportamento inicial |
| --- | --- |
| Pessoa/urso caído sem atendimento | Espera 30 s, desaparece em 5 s e aguarda 20 s para reposição. |
| Ocorrência médica já comunicada | A fila tem até 180 s; cada atendimento tem até 120 s. O limite absoluto de 300 s impede que tentativas sucessivas mantenham a vítima para sempre. |
| Internação | Conserva a alta por dias do jogo e tem recuperação alternativa após 120 s, seguida da espera de reposição. |
| Carcaça de veículo | Espera 35 s, desaparece em 5 s e aguarda 25 s para reposição. Bombeiros designados têm até 90 s. |
| Carro danificado ainda utilizável | Só começa a contar abandono fora da vista, por 180 s. |
| Poste, lixeira ou carga destruída | Espera 90 s, desaparece em 5 s e aguarda 25 s para reconstrução. |
| Destroços / sangue no chão / restos de explosão | Limites de 30 / 120 / 150 s, inclusive em regiões inativas. |

A reposição espera um ponto fora da câmera e longe do jogador, com verificação de colisão. Pedestres usam suas rotas; animais permanecem no habitat; objetos fixos voltam à posição original. Os prazos de retorno são mínimos: se o ponto estiver visível ou ocupado, o objeto aguarda oculto.

A frota reaproveita a mesma instância. Carros de trânsito voltam à rota com a velocidade de circulação restaurada; veículos de emergência voltam ao pool. A Monaliza mantém a propriedade e retorna à garagem. Veículos ocupados, em embarque ou carregados pela empilhadeira não são recolhidos. Inimigos de encontros finitos da campanha continuam derrotados.

As vítimas conservam o prazo e a fase de limpeza no registro médico já salvo pela campanha. Registros antigos sem prazo entram no fluxo automaticamente; registros de regiões descarregadas também expiram. Caixas destruídas deixam de ser removidas definitivamente e passam a ocupar um lugar reutilizável.

## Validação

`tests/test_world_renewal.gd` cobre fade, região inativa, resgate preso, retorno da frota, reposição dos ursos, colisões, objetos fora da câmera, destroços, ciclos repetidos e recriação de NPC a partir do save. Regressões complementares: persistência médica, impacto nos postes, explosão veicular e limpeza das marcas de derrapagem após reparo.

O teste completo `test_medical_choreography_continuity.gd` também foi executado com a nova limpeza desativada: ambos os cenários atingiram o timeout na aproximação da maca. Essa falha de navegação permanece independente da renovação; o novo prazo de limpeza evita que a vítima permaneça indefinidamente no mundo.
