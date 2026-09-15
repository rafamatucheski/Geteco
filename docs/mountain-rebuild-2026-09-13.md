# Reconstrução da montanha — 13/09/2026

Continuação executada da [avaliação inicial](mountain-review-2026-09-13.md), incluindo os pedidos posteriores sobre aparência dos esquiadores e moradores gigantes nos chalés. Os documentos do Antigravity foram usados como registros de escopo, sem assumir autoria de todas as mudanças do workspace.

## Alterações

- **Escala dos moradores:** o adaptador de interiores aplicava a altura-base do Dante (1,45) a rigs de moradores construídos em 1,79. Agora cada rig informa sua altura, incluindo a variação de escala individual. Os três moradores do chalé de esqui foram medidos em 1,80 no espaço da sala, mesma referência do Dante. Entrada, reentrada, restauração de save e recuperação devolvem a apresentação correta; a reconfiguração volta a acompanhar o ator.
- **Modelos e animação:** casacos com volume ajustado, membros afunilados, cotovelos, joelhos, luvas e botas usando os construtores nativos do Dante. Faces e roupas mantêm identidades próprias. Esquiadores flexionam os joelhos com as solas presas às fixações; bastões acompanham as mãos. Dante usa as próprias articulações e recupera sua pose ao devolver o equipamento. Comparação frontal, lateral e traseira em `people.png`.
- **Descida dos NPCs:** removida a queda obrigatória por volta. As trajetórias antigas, deslocadas 22 pixels, cruzavam os postes dos portões. Guias de entrada/saída agora atravessam o corredor livre, com separação longitudinal entre os esquiadores e posições de espera distintas. Só impactos reais iniciam a queda. A reciclagem da volta acontece quando origem e destino estão fora da câmera, sem desaparecimento visível.
- **Precipício:** preservadas as correções de impacto único, cancelamento, streaming, recuperação e resgate do veículo. O rig real agora gira e articula durante a queda, inclusive o tombamento 3D do SUV; a imagem projetada representa o afastamento enquanto a câmera fica na borda. Faces rochosas em camadas contínuas substituem o leque repetitivo de triângulos. Não é uma simulação física de ragdoll.
- **Teleférico:** Dante senta no espaço 3D da cadeira, atrás da barra de segurança. A apresentação emprestada devolve rig, pose, visibilidade e processamento ao desembarcar. Limpeza repetida não interfere na apresentação da estação. Garra permanece no cabo durante o balanço. Estações ficam fora das largadas/chegadas e árvores respeitam todos os segmentos do cabo. Atualizações de cadeiras são limitadas por visibilidade e distribuídas entre frames.
- **Resort:** boutique com vitrines e manequins 3D, heliponto caminhável com barreiras reais, postes, racks, bancos e braseiro com volume. Moradores e Dante próximos compartilham a profundidade desses objetos. Colisões são derivadas das malhas marcadas, sem retângulos independentes do objeto visível. O chalé de aluguel também usa esse contrato para paredes e mobiliário.
- **Circulação:** acesso e área de retorno separados do passeio frontal, faixas recortadas nas junções e na ilha, vegetação afastada da chegada, boutique e braseiro reposicionados. O limpa-neve fica numa vaga lateral, liberando os dois acessos testados com o SUV de produção.
- **Interação e mistério:** conversa exige proximidade, linha de visão, estado livre e arbitragem do morador mais próximo. Uma tecla não abre duas conversas. A caverna da cachoeira foi ligada ao gerenciador de interiores; coleta usa a API atual e conquistas consultam pistas e tempos persistidos.

## Validação funcional

Godot 4.7.2. Evidências em `D:/geteco/artifacts/mountain-rebuild-0913/`; cenários de captura e desempenho usam saves próprios.

| Cenário | Resultado |
|---|---|
| `test_mountain_rental_lifecycle.gd` | 17 verificações: aluguel, cobrança única, restauração de roupa, movimento único por passo, fixação das botas e bastões. |
| `test_mountain_ski_transitions.gd` | 31 verificações: viagem de 6 s, tecla de embarque, morte/teleporte, rig real sentado e limpeza idempotente. |
| `test_chairlift_world_position.gd` | 31 verificações: região deslocada, segmentos desiguais, cabo degenerado e garra estável durante balanço. |
| `test_mountain_cliff_edges.gd -- --capture` | 18 verificações em execução renderizada, com Dante, SUV, hospital, streaming e resgate. |
| `test_projected_interior_contract.gd` | 136 aproximações físicas em 17 grupos de sólidos; controles renderizados de oclusão e visibilidade aprovados para Player e NPC. |
| `test_mountain_rebuild_contract.gd` | 331 verificações: sólidos dos exteriores, circulação no heliponto, escala, profundidade e restauração dos atores; fila de emergência com alvo removido. |
| `test_mountain_cabin_scale.gd` | Entrada/saída/reentrada reais, circulação, pickups, efeitos, hospital, save antigo e acompanhamento após reentrada aprovados. |
| `test_mountain_people_motion.gd` | Postura, impacto/recuperação, espera sem desaparecimento e conversa através de parede/múltiplos NPCs aprovados. |
| `test_mountain_ambient_courses.gd` | Seis NPCs completaram as três pistas em 1.500 passos físicos na montanha completa, com zero frames em queda. Inclui postes, vegetação, estações e iluminação do passeio. |
| `test_resort_overhaul.gd` | Cinco blocos funcionais e passagem do SUV pelos dois acessos, com cenário e carros estacionados presentes. |
| `test_mountain_ski_and_mystery.gd` | Aluguel, equipamento, acesso à pista, rastros, colisão, três pistas do mistério e devolução aprovados. |

As verificações usam resultados físicos e controles negativos de renderização, além da estrutura das cenas. Alguns testes completos ainda reportam recursos/RIDs não liberados no encerramento, também observados na referência inicial; não são tratados como uma execução sem erros de limpeza.

## Desempenho

Meta: 60 FPS / 16,67 ms. `measure_mountain_rebuild.gd` usa HarborGame real, RTX 4060 Laptop, Vulkan/Mobile, 1280×720, VSync desligado, cap 60, seed 912, mesmo checkpoint, clima e relógio fixos. Cada ponto tem 120 frames de aquecimento e 30 segundos de amostras. São pontos de observação com jogador imobilizado, não uma medição de toda a rota dirigida.

A primeira execução posterior piorou p95/p99, especialmente na pista. Foram investigados recálculos de projeção para atores distantes, atualizações simultâneas de viewports e colisões repetidas dos NPCs nos portões. O registro final deve ser lido com as amostras brutas; médias próximas de 60 FPS não certificam estabilidade.

| Ponto | FPS antes → final | p95 antes → final | p99 antes → final | Máximo final | Frames >33,3 / >66,7 ms, final |
|---|---:|---:|---:|---:|---:|
| Estrada `(6950,-250)` | 58,00 → 59,69 | 21,98 → 21,96 ms | 30,85 → 25,61 ms | 73,01 ms | 3 / 1 |
| Centro do resort `(7140,-2760)` | 59,55 → 58,95 | 20,59 → 22,01 ms | 25,04 → 28,35 ms | 40,84 ms | 4 / 0 |
| Pistas `(7000,-3450)` | 59,95 → 60,00 | 22,12 → 18,29 ms | 24,96 → 20,30 ms | 22,91 ms | 0 / 0 |

Dados finais: `delivered-250.json`, `delivered-2760.json`, `delivered-3450.json`, com todas as amostras; log `performance-delivered.log`. O zoom solicitado pelo harness é 1, mas a câmera da região o ajusta: o zoom efetivo registrado foi **1,8**. Não houve erro de script nessa execução; permanecem avisos de limpeza no encerramento.

O p95/p99 das pistas caiu 17,3%/18,7% em relação à referência. No resort, piorou 6,9%/13,2%, acima do limiar de investigação. Esse ponto mantém o ator artificialmente no centro sólido do chalé: o novo contrato de profundidade passa a renderizar o prédio junto com ele. Foi acrescentado o modo `--resort-walkable`, que preserva a câmera no mesmo ponto e coloca Dante 125 pixels à frente, na área caminhável. Seus números são um diagnóstico adicional, não uma substituição silenciosa da comparação anterior. Não há certificação de 60 FPS constantes para o mundo inteiro.

No passeio caminhável, a janela adicional registrou **59,83 FPS**, p50 **16,20 ms**, p95 **20,52 ms**, p99 **23,20 ms**, máximo **71,79 ms**, com 2 frames acima de 33,3 ms e 1 acima de 66,7 ms. Fonte: `walkable-2760.json` e `performance-walkable.log`. O ponto não apresenta a piora contínua do cenário artificial dentro do prédio, mas o pico isolado permanece registrado. A validação funcional está aprovada nos cenários listados; estabilidade absoluta de frames e os avisos de limpeza ainda não estão certificados.

Durante a validação, mudanças compartilhadas de áudio impediram a inicialização de HarborGame. Foi restaurada a constante de duração coerente com as camadas procedurais de um segundo em `VehicleEngineSound`, e a importação inválida da rádio reggae foi regenerada preservando seu UID. Não foi revertido o trabalho de áudio. Alterações concorrentes e outras instâncias abertas limitam a atribuição causal de diferenças de desempenho.

Capturas: `resort.png`, `lodge-people.png`, `people.png`, `dante-ski.png`, `skiers.png`, `dante-chairlift.png` e `verified-*-falling.png`. A captura do teleférico mantém a física desativada apenas para posicionamento do cenário; a devolução de física/controle é verificada separadamente com o Player real.
