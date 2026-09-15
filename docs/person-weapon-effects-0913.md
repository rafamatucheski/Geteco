# Fogo nas vítimas e desmembramento — 13/09/2026

Revisão posterior dos modelos, variedade dos fragmentos e reações vocais: [remains-pain-revision-0913.md](remains-pain-revision-0913.md). A descrição de quatro fragmentos fixos abaixo é o registro da primeira implementação.

O lança-chamas agora inicia uma queimadura na pessoa atingida: chamas e fumaça acompanham a vítima durante seis segundos, com seis pontos de dano a cada meio segundo. Novos impactos renovam o mesmo estado, inclusive durante a cauda de fumaça. Civis entram em pânico; mortes usam a rotina normal do personagem. O fogo também aparece quando o impacto inicial já é fatal. Não são acrescentadas luzes por vítima.

Bazuca e granada acionam o sistema existente de quatro fragmentos quando o dano da explosão mata um NPC. Os fragmentos substituem o corpo, colidem com paredes e veículos, caem e param. Sobreviventes recebem impulso físico, sem uma segunda aplicação de dano por atropelamento. Dano respeita distância, cobertura e isolamento do mundo físico. A granada informa corretamente quando o jogador causou o dano. Maciota e o mecânico mantêm seus contratos de invulnerabilidade.

Na rua, os fragmentos reutilizam a apresentação existente de `ExplosionRemains`. Nos interiores projetados, cópias das malhas e materiais originais compartilham o viewport e a profundidade da sala; a física continua nos fragmentos 2D. Chamas internas também usam partículas 3D no rig original. Não há viewport adicional por fragmento. O corpo inteiro é ocultado imediatamente, e as malhas emprestadas são removidas no descarregamento.

Há um estado de queimadura por ator; os emissores detalhados têm orçamento de 24 vítimas simultâneas, com 24 partículas de fogo e oito de fumaça por vítima. O dano não depende desse orçamento visual. Foi mantido o limite preexistente de 16 conjuntos de fragmentos. A limpeza e coleta existentes de restos continuam disponíveis; não foi alterado o sistema de despacho.

## Verificação

Executável: Godot 4.7.2, em `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/`. Projeto: `D:/geteco/game`. Evidências: `D:/geteco/artifacts/person-weapon-effects/`.

| Cenário | Resultado |
| --- | --- |
| `tests/test_person_weapon_effects.gd` | Zero falhas: contato real do jato, dano persistente, pânico, acompanhamento, renovação e reativação, término, parede, granada com fusível, RPG por raio e por sobreposição de Area2D, sobrevivente periférico, isolamento físico e limpeza. Última execução com diagnóstico em `cleanup-diagnostic.log`. |
| `tests/test_person_effects_interior.gd` | Zero falhas em Vulkan: fogo e fragmentos no depth buffer real, oclusão por sólido com controle positivo de visibilidade, corpo inteiro oculto e remoção das malhas. `interior-delivery.log`. |
| `tests/test_garage_weapon_restrictions.gd` | Zero falhas: restrições de armas, invulnerabilidade, saída, save e respawn. `garage.log`. |
| `tests/test_explosion_incidents.gd` | Não aprovado. A execução mais recente para no despacho de incêndios: segundo veículo indisponível e `service_targets` acessado em alvo nulo, antes de testar a explosão ou a coleta. `explosion-regression-delivery.log`. |
| `tests/test_mountain_contact.gd` | Não concluído: a execução encontrou dependências de resgate em edição e depois acesso inválido a `water` no teste de respingos. Não foram modificados esses arquivos para passar o teste. |

Durante o trabalho houve falhas temporárias de compilação em `MedicalRescueSequence.gd`, fora dos arquivos desta implementação. As funções ausentes apareceram posteriormente no arquivo. Uma execução funcional também relatou recursos em uso no encerramento; o diagnóstico subsequente com `--verbose` terminou sem esse aviso. Não se atribui essa diferença a uma correção de memória nesta tarefa.

Capturas: `burning-person.png`, `explosion-remains.png`, `fire-interior.png` e `fragments-interior.png`. São verificações isoladas usando atores e efeitos de produção. `verified-performance/gameplay.png` mostra o checkpoint integrado de HarborGame; nenhuma dessas capturas certifica todos os interiores do mapa.

## Desempenho: pendente, não aprovado

Foi usado `tests/measure_person_weapon_effects.gd`: HarborGame real, checkpoint do centro, sequência de dez impactos de lança-chamas/granada/RPG sobre NPCs em 30 segundos após dez segundos de aquecimento. Meta: 60 FPS / 16,67 ms; aumento acima de 5% em p95/p99 exige investigação. GPU: RTX 4060 Laptop; Mobile/Vulkan; 1280×720; limite de 60 FPS e VSync desativado, conforme registrado pelo runtime.

| Medida de 30 segundos | Antes | Última execução depois |
| --- | ---: | ---: |
| Frames / duração | 1363 / 30,017 s | 809 / 30,012 s |
| FPS médio | 45,41 | 26,96 |
| p50 | 18,705 ms | 32,516 ms |
| p95 | 32,525 ms | 65,383 ms |
| p99 | 59,555 ms | 108,353 ms |
| Máximo | 290,923 ms | 227,288 ms |
| Frames acima de 33,3 / 66,7 ms | 63 / 12 | 369 / 35 |

Os números **não constituem um comparativo controlado**. Outras tarefas iniciaram testes renderizados e outro benchmark durante a medição posterior; também houve edições concorrentes no projeto. O aquecimento, antes de disparar os efeitos deste teste, já caiu de 53,36 para 33,57 FPS. A resposta policial também difere após atribuir as explosões ao jogador. Não é possível separar regressão desta implementação de concorrência, resposta do mundo e alterações externas com essas amostras. A meta já não era atingida na base e não foi atingida depois.

CSV e JSON completos: `before/` e `verified-performance/`. As tentativas intermediárias `after/` e `after-final/` foram descartadas: a primeira expôs erros de metadados e criação de colisores durante consultas físicas, corrigidos e cobertos pelos testes; a segunda foi interrompida para finalizar a reativação do fogo. Não há certificação de FPS, GPU ou regressão de desempenho nesta entrega.
