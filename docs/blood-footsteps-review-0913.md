Revisão de sangue e pegadas — 13/09/2026

Referência examinada: `20260913-2313-20.6431641.mp4`, 00:39–00:45. Quadros em `D:/geteco/artifacts/blood-footsteps-0913/reference.jpg`.

A trilha reunia origens diferentes. `BodyWound.apply` aplica a apresentação do ferimento, cria a mancha inicial e antes também chamava `BloodTransferSystem.splash`, carregando as duas solas com o orçamento de pneus (210 px), sem contato com o solo. `BodyWoundTrail` repetia manchas não letais de raio 6 a cada 0,8 s, por 12 s. As novas manchas podiam renovar o sangue transportado. `BloodTransferSystem` carimba o sangue adquirido do chão; suas próprias marcas não são fontes de contaminação. Os bursts de impacto de `WeaponEffects` e as poças letais têm origens separadas e foram preservados.

Agora o impacto não carrega as solas diretamente. A mancha inicial permanece; o gotejamento usa raio de aproximadamente 1,1–2,8 px, com no máximo uma gota secundária, intervalo de 1,15 s e duração de 6 s. Exige deslocamento mínimo de 28 px desde a última emissão. O relógio conserva a fração de tempo; um travamento não reproduz uma fila de emissões atrasadas. Parado, o personagem mantém a mancha inicial sem empilhar gotas. Morte/recuperação encerra o gotejamento; movimento aéreo não pinga.

Pegadas usam a fase existente de CitizenGait ou walk_clock, interpolando a posição no cruzamento de apoio e alternando os pés. Personagens sem fase exposta usam cadência por distância de 20 px. O contato é consultado no apoio de cada sola, com posição lateral e orientação do movimento. O resíduo decresce ao longo de 85 px; a última impressão pode ficar bem tênue. Comprimento nominal da impressão: 3,4 px, largura 1,9 px, variação de escala 0,86–1,06, rotação até aproximadamente 4 graus e intensidade 0,88–1. A paleta vinho e a geometria procedural permanecem. A fase é reiniciada ao acordar/teleportar para não conectar deslocamentos inválidos.

Limites: 900 marcas compartilhadas, vida de 14 s com fade nos últimos 4 s; 64 manchas registradas, vida de 18 s com fade nos últimos 6 s. O descarte agora retira a poça antiga do registro imediatamente e a oculta antes de queue_free, impedindo que várias emissões no mesmo frame descartem repetidamente a mesma entrada. A referência chegou a 74 poças apesar do limite declarado. Não foram alterados dano, IA de fuga, HUD, rigs ou regras de pneus; splash de veículos continua disponível.

Validação funcional e visual:

| Verificação | Resultado |
| --- | --- |
| `tests/test_blood_footsteps_revision.gd` | 119 verificações aprovadas: ferimento parado/52/125 px/s a 24/30/60/144 Hz, contatos interpolados, curva, intensidade, parada, movimento aéreo, morte, 140 emissões no mesmo frame, saturação e expiração |
| `tests/test_blood_transfer.gd` | 16 verificações aprovadas; preserva pneus, moto, lavagem, contato unilateral e teleporte |
| `tests/test_blood_transfer_native.gd` | Aprovado com rigs reais; última execução: 142/71 marcas de carro/moto, 4 pegadas de pedestre e 2 de paramédico; parado não acrescenta marcas |
| `tests/test_ground_blood_variation.gd` | Aprovado: contornos, reprodução por seed e ciclo de vida |
| `tests/test_vehicle_person_impact_0911.gd` | Aprovado |
| `tests/test_garage_weapon_restrictions.gd` | Aprovado, zero falhas |
| `tests/visual/capture_blood_footsteps.gd` | Renderizado: oito rigs, parado/andando/correndo e contato; capturas paths-90/210/299.png inspecionadas na amostra intermediária |
| `tests/test_forest_melee_and_wounds.gd` | Sete falhas em dano/equipamento/geometria e reação. Mesmas sete falhas com as versões anteriores dos quatro scripts de efeitos, recarregadas somente no processo de diagnóstico; arquivos atuais não foram substituídos |

As expectativas antigas de pelo menos oito pegadas foram substituídas por trilhas curtas limitadas, respeitando que apenas uma sola pode ter tocado uma poça. O teste nativo move os atores manualmente e agora também avança sua animação real. Testes novos verificam os contatos entre taxas de atualização e o desgaste, além da contagem.

Medição renderizada: `tests/measure_blood_footsteps.gd`, derivado do benchmark existente de estabilidade. HarborGame real, checkpoint do cais, dia/tempo seco, 1280×720, Godot 4.7.2 Mobile/Vulkan, RTX 4060 Laptop GPU, limite normal de 60 FPS, VSync efetivo desligado. Save redirecionado para o diretório de evidências. Aquecimento de 10 s separado; janela de pelo menos 30 s com os 12 pedestres mais próximos recebendo efeitos a cada 6 s. A injeção chama apenas o efeito de ferimento, sem simular dano ou modificar a IA; caminhada/corrida foram adicionalmente verificadas nas trajetórias controladas.

| Métrica | Antes | Final |
| --- | ---: | ---: |
| Duração / frames | 30,044 s / 1145 | 30,027 s / 1424 |
| FPS por frames/tempo | 38,11 | 47,42 |
| p50 / p95 / p99, ms | 20,704 / 58,084 / 68,306 | 18,697 / 33,085 / 39,233 |
| Máximo, ms | 220,743 | 72,289 |
| Frames >33,3 / >66,7 ms | 222 / 16 | 69 / 2 |
| Pico de marcas / poças | 66 / 74 | 8 / 64 |

Desempenho **não certificado**: alvo de 60 FPS/16,67 ms não atingido; editor/jogo e testes de outras tarefas foram identificados em execução paralela. As populações ativas também variaram ligeiramente entre amostras. Portanto os números não isolam o ganho causado pelos efeitos. Não foram encerrados processos alheios. A tolerância prévia foi de 5% em p95/p99, mas não se aplica como certificação a este ambiente concorrente. CSVs incluem tempos de processo/física; não houve medição isolada de tempo de GPU. O aquecimento registrou picos de 894,32 ms antes e 671,107 ms na execução final, separados da janela principal.

Evidências completas em `D:/geteco/artifacts/blood-footsteps-0913/`: snapshots dos quatro arquivos anteriores, logs dos testes, baseline-forest.log, capturas, e pastas before/after/final com CSVs, JSONs e gameplay.png. A pasta after registra a primeira implementação; final corresponde ao ajuste de precisão das fases e ao fade residual. As capturas controladas são revisão visual isolada, não certificação do desempenho do mapa.
