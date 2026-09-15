# Revisão da montanha — 13/09/2026

> Registro da avaliação inicial. A execução posterior e a validação das correções estão em [Reconstrução da montanha](mountain-rebuild-2026-09-13.md); as pendências abaixo descrevem o estado anterior à reconstrução.

**Parecer: a montanha ainda não atende ao padrão de entrega do Geteco.** Há defeitos de integração, apresentações visuais incompatíveis entre si e testes que aprovam a estrutura da cena sem testar a experiência. Foram corrigidos os problemas de queda, transporte e esqui descritos abaixo. Isso não equivale a aprovar toda a região.

## Escopo e autoria

O pedido chegou após a meia-noite. O registro mais recente do Antigravity para a montanha é o plano de reformulação do resort, atualizado na noite de **12/09**, em `C:/Users/rafae/.gemini/antigravity/brain/26a68e80-bf23-4dcb-ada1-85bdee32cd45/implementation_plan.md`. Ele abrange Player/esqui, moradores e interações, acesso rodoviário, estacionamento, boutique, promenade e heliponto. Suas próprias capturas apresentam problemas descritos nesta revisão.

O último commit do repositório é de 11/09 e há numerosas alterações de outras tarefas sem commit. Datas de modificação não provam autoria. Portanto, esta avaliação compara o plano com a montanha atual; **não atribui ao Antigravity cada alteração do diretório**, especialmente quedas, caverna e sistemas compartilhados. O escopo inclui esses sistemas por afetarem a experiência apontada pelo usuário. Os planos encontrados foram tratados como registros, não como instruções de execução.

## Achados e correções

| Prioridade | Problema demonstrado | Consequência | Estado |
|---|---|---|---|
| P1 | `MountainCliffEdges._fall` encolhia, deslocava e apagava o ator inteiro, restaurando tudo antes de aplicar dano. | Corpo/carro reaparecia em tamanho normal no impacto; apresentação, colisão e câmera eram afetadas pelo mesmo efeito. | Substituído por `MountainCliffFall`: anima a textura já renderizada, preserva transformação do ator e mantém a câmera na borda. Morte não redesenha Dante nem uma segunda queda sobre a estrada. |
| P1 | A queda dependia de um tween vinculado à estrada transmitida por streaming. | Desativação/remoção durante a sequência podia interromper a liberação dos atores. | Efeito independente da região, com restauração ao cancelar/remover e prioridade para teleporte externo. Testado com região desativada e veículo removido. |
| P1 | Impacto do carro usava destruição rodoviária comum. | Contagem de explosão e pedido de bombeiros para uma carcaça que deveria estar no precipício. | Veículo perdido fica oculto e sem colisão, sem explosão/dispatch na pista. Reparo recupera colisão e posição segura na estrada. |
| P1 | Embarque e morte do motorista não compartilhavam um encerramento imediato. | Animação de entrada/saída podia interferir na recuperação. | Queda identifica o motorista pelo estado real do veículo, força o encerramento do embarque e então aplica dano ambiental. Não depende de `Player.current_vehicle`, campo inexistente no Player de produção. |
| P1 | `Player._physics_process` e `PlayerSkiController.physics_step` chamavam `move_and_slide` no mesmo passo. | Movimento adicional e comportamento de colisão incompatível com a simulação do controlador. | Removido o segundo deslocamento. Regressão verifica deslocamento total contra o movimento físico efetivo. |
| P1 | `start_skiing` marcava esqui ativo antes de o controlador validar traje/equipamento. | Estado parcialmente ativado sem cumprir requisitos. | Controlador passa a ser responsável pela ativação; entrada repetida preserva a sessão. |
| P2 | Aluguel duplicado descontava dinheiro novamente e sobrescrevia o traje anterior; devolução só alterava flags. | Roupa anterior perdida, equipamento/trilhas/controlador incoerentes. | Aluguel e preço validados, devolução idempotente, controlador/equipamento/trilhas encerrados. |
| P1 | Viagem do teleférico examinava o botão de embarque no mesmo frame e sempre posicionava o jogador no cume após interrupção. | Viagem pulada involuntariamente; recuperação ou teleporte externo sobrescrito. | Leitura após novo frame e liberação do botão, percurso pelo cabo, cancelamento sem sobrescrever recuperação; liberação ao remover a estação. O comando agora diz “adiantar viagem”. |
| P2 | `MountainSkiArea` girava a imagem inteira do portão, apesar de o portão fornecer `ground_angle`. | Postes 3D inclinados na tela em vez de girarem no plano do chão. | Integrado o ângulo correto no construtor da área. |
| P2 | Camila estava em `(7090,-2780)`, desenhada sobre o telhado do chalé. | NPC visualmente sobre o edifício, afastado da praça de atendimento. | Reposicionada no passeio frontal; captura final verifica a colocação. |

A correção anterior da cadeirinha no porto foi preservada: coordenadas locais e percurso por todos os segmentos do cabo. O teste de posição continua passando.

## Problemas que ainda exigem reconstrução ou validação

1. **Resort visualmente inconsistente.** `ResortShopFacade.gd` desenha fachada e manequins com polígonos 2D; os manequins são três formas planas, sem anatomia e sem o acabamento do Dante. Isso diverge do plano que descreve uma fachada 3D e do padrão de personagens do projeto. O chalé tem volume, mas a boutique, os bancos e o fogo têm outra linguagem visual. Não foram reconstruídos nesta revisão.
2. **Circulação e terreno.** As capturas integradas mostram acessos e demarcações se sobrepondo, vegetação cobrindo partes da chegada e limites retangulares muito visíveis no terreno. A imagem comprova o problema de leitura; um percurso dirigível completo e a colisão de cada obstáculo ainda precisam de revisão específica. Não foi inferida colisão bloqueada apenas pela imagem.
3. **Precipícios com desenho repetitivo.** As faces formam uma faixa de triângulos muito regular ao lado da estrada, com neblina em recortes geométricos. Melhorar a queda não corrige a forma do relevo. É necessário trabalhar profundidade, continuidade das faces e transição com a mata, preservando o limite físico já compartilhado com a borda.
   A queda corrigida ainda usa a imagem do ator para representar afastamento e profundidade. Ela elimina a restauração brusca e as falhas de recuperação, mas **não é uma animação articulada de perda de equilíbrio nem um tombamento 3D do veículo**. Essa reconstrução visual continua pendente e deve ser avaliada em movimento.
4. **Heliponto sem contrato físico claro.** `_build_collision` cria um `CollisionPolygon2D`, mas não o adiciona ao `StaticBody2D`. O teste aprova a presença do corpo, sem detectar a ausência da forma. Isso não deve ser “corrigido” preenchendo toda a plataforma com colisão sólida: a superfície de caminhada deve continuar acessível e somente obstáculos/bordas apropriados devem bloquear. A geometria também continua sendo 2D, apesar da intenção de plataforma com volume.
5. **Interações de moradores.** O caminho novo de fala em `WinterResident` verifica distância e tecla, mas não arbitra o alvo mais próximo, linha de visão, veículo ou estado de diálogo do jogador. Pode concorrer com outras interações. Revisão estática; os casos com múltiplos NPCs/parede não foram certificados em gameplay nesta rodada.
6. **Apresentação e custo do teleférico.** As cadeiras mantêm `UPDATE_ALWAYS`; as estações animam rodas no modelo, mas herdam viewport `UPDATE_ONCE`. Falta harmonizar atualização por visibilidade e estado. A viagem já acompanha o percurso, porém ainda não representa Dante sentado numa cadeira física. Isso precisa de implementação visual própria, sem fingir que corrigir coordenadas resolve a experiência inteira.
7. **Testes de mistério desatualizados.** `test_mountain_ski_and_mystery.gd` falha em duas expectativas de localização da caverna/pista e chama `add_collectible` com três argumentos, embora a API atual aceite dois. A execução foi encerrada após o erro, sem repetição. Isso não prova, sozinho, que a caverna de produção está quebrada; impede certificar esse fluxo com o teste atual.

## Validação

Godot 4.7.2, projeto real em `D:/geteco/game`. Saves dos novos cenários foram direcionados a `D:/geteco/artifacts/mountain-review-0913/saves/`.

| Verificação | Resultado |
|---|---|
| `test_chairlift_world_position.gd` | 29 verificações aprovadas; preserva a correção do porto. |
| `test_mountain_rental_lifecycle.gd` | 10 verificações aprovadas, com Player/controlador reais. |
| `test_mountain_ski_transitions.gd` | Aprovado: embarque segurando a tecla, trajeto de 6 s, flags, offset e teleporte durante a viagem. |
| `test_mountain_cliff_edges.gd` | Aprovado: pedestre, SUV, recuperação, cancelamento, streaming, resgate e remoção do veículo durante queda. |
| `test_mountain_ski_3d_and_loop.gd` | Assertions aprovadas; motor reporta recursos não liberados ao encerrar. |
| `test_resort_overhaul.gd` | Assertions aprovadas, mas o teste não certifica qualidade visual nem todos os contratos físicos. Recursos não liberados ao encerrar. |
| `test_mountain_ski_and_mystery.gd` | Não aprovado: expectativas de caverna falhas e chamada de API obsoleta. |
| `git diff --check` nos arquivos rastreados afetados | Aprovado. |

Dois ajustes nos testes corrigem pressupostos de tempo identificados: o teste do teleférico esperava uma viagem de 6 segundos terminar em 1,35 segundo; o teste da queda examinava o jogador antes do término das duas fases de recuperação do hospital. Os novos testes aguardam os contratos reais com limite finito e mantêm as verificações de resultado. Não foram removidas verificações para obter aprovação.

## Desempenho e evidências

Meta: 60 FPS / 16,67 ms. Referência: RTX 4060 Laptop, Vulkan/Mobile, 1280×720, cap 60, VSync desligado. Duas janelas de 30 segundos na cena `HarborGame`, com a montanha carregada, antes das alterações desta revisão. São diagnósticos, não certificação: havia outras instâncias do Godot abertas, o relógio de campanha continuou avançando e o cenário herdou o estado de motorista do checkpoint. A captura move a câmera/jogador até o ponto; não representa uma rota dirigida completa.

| Cenário inicial | FPS médio | p50 | p95 | p99 | Máximo | >33,3 ms / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Estrada, `(6950,-250)` | 23,94 | 35,71 ms | 67,95 ms | 86,84 ms | 123,04 ms | 536 / 41 |
| Resort, `(7140,-2760)` | 39,45 | 23,82 ms | 37,94 ms | 54,40 ms | 60,77 ms | 163 / 0 |

Esses números mostram que a execução observada não atingiu a meta. Não isolam a causa nem autorizam atribuir toda a queda de FPS às mudanças do resort. A correção de queda reutiliza texturas existentes e cria apenas o efeito temporário durante o acidente; não adiciona SubViewport ou outro rig.

A execução posterior registrou 51,01 FPS / p95 30,63 ms / p99 39,51 ms na estrada e 44,24 FPS / p95 33,39 ms / p99 42,27 ms no resort. **Não é um ganho certificado:** nessa execução apareceu um erro repetitivo em `PlayerCombatPose.gd:107`, acessando `torso_node` em `NPCCombatRig`, ausente na execução inicial. `PlayerCombatPose.gd` foi alterado durante esta revisão por outra atividade no workspace; não foi modificado aqui. O erro e a concorrência invalidam uma conclusão causal de antes/depois. O estado final continua sem aprovação de performance.

Evidências, capturas e amostras brutas: `D:/geteco/artifacts/mountain-review-0913/`. O relatório deve ser lido junto com os logs, distinguindo assertions aprovadas de erros de limpeza e fluxos não certificados.

As 18 verificações de precipício passaram também em execução **renderizada** com a estrada, Dante e SUV de produção. Capturas válidas: `verified-foot-falling.png`, `verified-foot-impact.png`, `verified-car-falling.png`, `verified-car-impact.png`; log `cliffs-rendered.log`. Esse cenário isola a estrada e os atores; não certifica toda a integração do mundo. Na tentativa integrada, o checkpoint manteve o pedestre oculto e a captura de queda a pé foi rejeitada; imagens `foot-*` sem prefixo `verified-` não são evidência válida da queda. O teste de captura passou a exigir um pedestre visível antes de registrar o cenário. A captura `after-2760.png` confirma Camila fora do telhado, mas não aprova o restante da composição do resort.

## Critério para a próxima entrega da montanha

A sequência de reconstrução deve começar pelo relevo/precipício e circulação do resort, depois boutique/heliponto e interações. A validação deve usar percurso real de carro e a pé, descida/queda/recuperação, embarque normal, entrada nas lojas e comparação visual com os modelos de produção. O benchmark final precisa de ambiente sem concorrência, horário fixo e mesmo estado de câmera, população e veículo; p95/p99 mais de 5% piores exigem investigação. A região permanece **não aprovada visualmente e sem aprovação de performance** até cumprir esses critérios.
