# Resgate com maca — validação de 13/09/2026

Atualização posterior: [passagem de emergência no trânsito](emergency-traffic-passage.md). A integração final passou com a segunda ambulância vindo do hospital e ambas as vítimas embarcadas; inclui a correção da busca diante de pessoas. Os resultados abaixo registram a etapa anterior e suas limitações naquele momento.

## Problema e implementação

Referência observada: `20260913-2313-20.6431641.mp4`, 00:08–00:34. O vídeo mostra a equipe parada junto ao semáforo, com o poste desenhado sobre a maca. A inspeção encontrou problemas independentes:

- A navegação original consultava um círculo de raio 13 na maca. Os dois socorristas se deslocavam separadamente; essa consulta não provava espaço para a formação nem para suas curvas.
- Extração e recolhimento da maca usavam alteração direta da posição por interpolação, sem varredura física do percurso.
- A ordem visual fixa dos sprites não representava a posição da equipe à frente ou atrás do poste. A projeção dos pés dos socorristas também estava deslocada da origem física.

`MedicalFormationNavigation.gd` usa o contorno de chão derivado dos meshes da maca e as cápsulas reais dos socorristas. A busca incremental considera posição e orientação; as consultas varrem translação e rotação. A execução coordena os três corpos, testa o próximo passo e usa movimento físico. A equipe pode recuar ou deslocar a maca lateralmente, contornar obstáculos e replanejar quando o caminho muda. A animação acompanha o deslocamento efetivo.

`MedicalRescueSequence.gd` integra essa formação ao desembarque, extração, atendimento, colocação da vítima original, retorno, recolhimento e embarque. Mantém os pontos de estacionamento atuais. Na entrada do hospital, utiliza a porta real; o antigo deslocamento adicional colocava o socorrista da frente contra o veículo. A vítima acompanha a maca em cada passo da extração hospitalar.

`NPCMedicalCare.gd` reserva vítima e transportador de forma exclusiva. Uma segunda equipe não pode tomar a reserva durante a aproximação ou a colocação na maca. A vítima inacessível recebe motivo explícito, mantém sua posição e libera a reserva com intervalo de 30 segundos. A equipe tenta voltar e embarcar. Se o próprio retorno ficar fisicamente impossível, a sequência assume `access_blocked`, mantendo corpos visíveis e sólidos; não os teleporta ou despacha o veículo com a equipe fora.

A verificação prévia do estacionamento ganhou busca incremental para percursos com várias curvas. Quando a ambulância parada passa 45 segundos sem melhorar sua aproximação, registra `parking_access_blocked`, libera a vítima e solicita retorno físico. Manobras de ré não reiniciam esse prazo simplesmente por movimentarem o veículo.

`MedicalOutdoorDepth.gd` e `MedicalPostForeground.gdshader` reutilizam as texturas dos atores para compor apenas a região sobreposta ao semáforo, conforme seus apoios no chão. Não criam novos modelos ou SubViewports. A correção é específica dos semáforos fixos; não certifica oclusão de todos os objetos da cidade. HUD e regras de dano não foram alterados por este trabalho.

## Evidências e resultados

Arquivos de evidência em `D:/geteco/artifacts/rescue-0913/`:

- `resgate-duas-vitimas.mp4`: captura do renderer real, com tempos de captura preservados, cobrindo os dois resgates até o embarque. Não contém áudio. As ambulâncias começam estacionadas; a posição da segunda passa pelo contrato de acesso de produção.
- `passagem-poste-movimento.png`: sequência de movimento durante a passagem ao lado do semáforo.
- `parked-pair-solids-checked-frames.json`: amostra sem gravação contínua, com duas equipes no cruzamento de `warehouse_way` / `dock_street`, vítimas em `(2070,2330)` e `(2180,2330)`. Ambas embarcaram. Consultas de sobreposição dos corpos durante as fases externas: **zero violações**.
- `formation-final.log` e `depth-final.log`: verificações separadas de colisão e profundidade.

O cruzamento e a situação foram reconstruídos na cena de produção a partir da referência. Não há save do vídeo que permita certificar identidade de todo o estado de tráfego original.

| Verificação | Resultado observado |
| --- | --- |
| `test_medical_formation.gd` | Passou: poste na curva, recuo, cápsula junto à quina, deslocamento grande sem atravessar obstáculo, desvio com mudança de orientação e parede surgindo durante o movimento. Zero contatos com sólidos; passo máximo 1,068 px; erro máximo nos apoios aproximadamente 0,000002 px. |
| `test_medical_post_depth.gd` | Passou no Vulkan: equipe e maca à frente e atrás do poste, posições fisicamente livres e controles positivos de sobreposição de pixels. |
| `test_medical_multiple_access.gd` | Passou: duas equipes, duas vítimas, rejeição de disputa de reserva e colocação na maca, todas as fases e ambos os socorristas embarcados em cada unidade. |
| Mesmo teste com `--blocked` | Passou: vítima em recinto fechado não é deslocada, motivo explícito, reserva liberada, equipe retorna e embarca; a outra equipe completa o resgate. |
| `test_rescue_junction.gd -- parked-pair-solids-checked --near-post --parked-teams` | Passou: duas vítimas embarcadas na cena real; nenhuma interseção dos corpos observados com sólidos. |
| `test_medical_parking_walk_route.gd` | Passou: acesso com várias curvas, varredura livre de paredes e da futura posição do veículo, limpeza da sonda. |
| `test_medical_parking_inaccessible.gd` | Passou: estacionamento cercado encerra tentativa, libera alvo, preserva vítima e não desembarca equipe. Ré limitada, sem atravessar o recinto; passo máximo 7,5 px para o passo de teste de 0,25 s. |
| `test_ambulance_parking_contract.gd` | Passou após integração: acesso lateral/traseiro, parada alternativa, percurso da maca, curva e varredura do veículo, limites do pavimento e reserva da manobra. |
| `test_medical_work_zone_lifecycle.gd -- --native-hospital`, renderer real | Passou: ciclo completo até hospital e disponibilidade, identidade preservada, passo visual máximo 1,807 px, zero erros de ciclo da proteção. Inclui sete segundos de observação após estacionamento e reutilização. |
| `test_medical_reserve_admission.gd` | Passou: admissão pela vaga reserva e retorno da maca, sem deslocar a ambulância da vaga principal. |
| `test_medical_single_bay_queue.gd` | Asserções passaram: escassez de unidades, segunda vítima na fila, reutilização sem reposicionar a primeira ambulância. A saída do processo registrou recursos ainda em uso; não é uma execução limpa de teardown. |
| `test_medical_triage_and_reporting.gd` | Passou: regressão de triagem, relato e interrupção/posse da vítima. |

## Limites e falhas preservadas

O teste adicional com a segunda ambulância vindo autonomamente do hospital, antes do novo encerramento por falta de progresso, **falhou em transportar a segunda vítima em 95 segundos**. O primeiro resgate terminou. A segunda unidade ficou sem manobra válida entre trânsito, ônibus e semáforos; os diagnósticos registraram rejeições de envelope, raio de curva e obstáculos no percurso. O encerramento desse caso foi validado em recinto bloqueado, mas a chegada autônoma completa sob aquele congestionamento **não foi certificada**. O modo padrão de `test_rescue_junction.gd` continua exigindo o transporte de ambas e não aceita um fracasso como sucesso.

Uma execução anterior do ciclo hospitalar em headless com tempo acelerado atingiu o prazo global depois de estacionar, durante a observação final. A execução posterior no renderer real completou todas as asserções. Não foram ampliados prazos ou removidas asserções para obter aprovação. Alguns testes isolados reportaram objetos ainda vivos na saída; isso permanece registrado como limitação de teardown.

Não foram certificados: todos os interiores, todos os tipos de poste/objeto, todas as orientações de estacionamento, trânsito arbitrário, passagem por cada ferrovia ou remoção de um bloqueio após o estado terminal `access_blocked`.

## Desempenho

Godot 4.7.2, Forward Mobile/Vulkan, RTX 4060 Laptop, janela 1280×720, limite de 60 FPS. A linha de base e a execução intermediária usavam um resgate acompanhado; a execução final acompanha duas equipes e adiciona consultas de validação. Há outras alterações e uma instância do jogo em execução no workspace. Estas medições são evidência local, não uma comparação isolada ou aprovação de 60 FPS.

| Amostra | Duração | FPS médio | p95 | p99 | Máximo |
| --- | ---: | ---: | ---: | ---: | ---: |
| `baseline-frames.json` | 34,80 s | 46,82 | 35,13 ms | 44,91 ms | 224,99 ms |
| `after-frames.json`, intermediária | 34,84 s | 53,33 | 28,64 ms | 37,58 ms | 259,52 ms |
| `parked-pair-solids-checked-frames.json`, duas equipes | 39,85 s | 47,50 | 34,83 ms | 56,95 ms | 274,40 ms |

A meta de 60 FPS e ausência de regressão de p99 **não estão aprovadas** por esses dados. A gravação contínua de PNG não foi utilizada como benchmark.
