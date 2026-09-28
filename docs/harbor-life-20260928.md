# Harbor — terminal público e vida do porto

Implementação de 28/09/2026, executada por um único agente. O pequeno terminal
fica ao lado da operação de cargas, com passarela elevada de circulação, abrigo,
bancos, defensas, amarrações, caixas, armadilhas de pesca e dois barcos de pescador.
A marca pública passou a Harbor; o diretório de saves continua compatível.

## Comportamento entregue

- A abertura conserva a história anterior à viagem e corta antes dos planos de
  ônibus. Dante desembarca fisicamente do barco; delegacia, telefonema e encontro
  continuam na mesma sequência. Saves antigos não reiniciam a abertura.
- O barco permanece 120 s, parte em 32 s, fica ausente 100 s e retorna em 32 s.
  Desembarcam até seis passageiros por viagem, separados por cinco segundos,
  com limite de 12 presentes. Eles atravessam o cais e a passarela até a cidade.
- A embarcação espera se o jogador ou passageiros ainda estiverem a bordo.
  O acesso fecha durante a ausência. O barco desaparece apenas depois de sair
  da vista; a operação é suspensa longe do terminal.
- Dois pescadores alternam lançamento, espera e recolhimento em ciclos de 26 s.
- Trabalhadores do porto, carregadores e portaria recebem dano e atropelamentos.
  A orientação do corpo e da carga acompanha a frente do modelo, corrigindo a
  caminhada de ré. A morte interrompe a tarefa, mantendo o total de carga.
- Funcionários e pescadores retornam após 180 s, com posto livre e fora da vista,
  e retomam o trabalho. Corpos são removidos após 60 s ou pelo socorro existente.
  Temporizadores e fase do barco integram o save; Maciota e mecânico permanecem
  protegidos.

## Construção e custo

Detalhes estáticos usam MultiMesh por acabamento, consolidados entre cais e
barcos de pesca. O barco móvel mantém seus próprios lotes. Colisores simples
representam pisos, bancos, pilares e guarda-corpos; detalhes pequenos não geram
uma malha física por peça. Não há SubViewport novo.

A iluminação quente usa o conjunto exterior existente, limitado a seis luzes
locais sem novas sombras. Fontes do porto não desaparecem pela distância da
câmera ortográfica alta; continuam selecionadas pela proximidade ao jogador.

## Validação funcional e física

Execuções finais sem falhas ou erros de script nos logs abaixo, todas com
`--no-save`. Os testes de física usam Main e corpos reais; não servem como prova
de desempenho renderizado.

| Teste | Evidência |
| --- | --- |
| Terminal, travessia completa, bancos, pescadores, morte/retorno, partida, nova viagem e save | [log](../evidence/harbor-life-20260928/complete-test_harbor_life.log) |
| Orientação, tiro, morte, atropelamento, retorno e proteção de Maciota | [log](../evidence/harbor-life-20260928/test_port_worker_combat.log) |
| Morte do carregador, conservação de carga, restauração e retomada | [log](../evidence/harbor-life-20260928/complete-test_port_loading_death.log) |
| Abertura sem planos de ônibus | [log](../evidence/harbor-life-20260928/final-test_opening.log) |
| Chegada e sequência da campanha | [fluxo](../evidence/harbor-life-20260928/test_arrival_flow.log), [estado](../evidence/harbor-life-20260928/test_arrival.log) |
| Barreiras costeiras: 451 verificações | [log](../evidence/harbor-life-20260928/final-test_coastal_protection.log) |
| Limites e ciclo das luzes: 26 verificações | [log](../evidence/harbor-life-20260928/final-test_city_local_lighting.log) |
| Segurança e acesso ao porto | [log](../evidence/harbor-life-20260928/final-test_harbor_port_policy.log) |
| Garagem: recompensas, restauração e transferência física | [47 checks](../evidence/harbor-life-20260928/final-test_garage_rewards.log), [26 checks](../evidence/harbor-life-20260928/final-test_garage_driver_restore.log), [11 checks](../evidence/harbor-life-20260928/final-test_garage_vehicle_transfer.log) |

Foram encontrados e corrigidos dois bloqueios reais no percurso: a proteção
costeira anterior atravessava a conexão do novo cais, e o guarda-corpo do terminal
fechava o pé da escada. O percurso final chegou à saída urbana, sem dano ou
travessia de sólidos. A oclusão foi inspecionada separadamente nas fotos de banco
à frente, atrás e ao lado; a silhueta existente indica o personagem oculto pelo
abrigo, sem desenhar seu corpo sobre o teto.

## Capturas reais

[Terminal](../evidence/harbor-life-20260928/review/terminal.png) ·
[cais](../evidence/harbor-life-20260928/review/quay.png) ·
[pesca](../evidence/harbor-life-20260928/review/fishing.png) ·
[banco: frente](../evidence/harbor-life-20260928/review/bench-front.png) ·
[atrás](../evidence/harbor-life-20260928/review/bench-behind.png) ·
[lado](../evidence/harbor-life-20260928/review/bench-side.png).

![Terminal público à noite](../evidence/harbor-life-20260928/final/terminal-night.png)

## Performance: medida, aprovação pendente

Godot 4.7.2, Main real renderizada, Vulkan Mobile, RTX 4060 Laptop, 1280 × 720.
Mesma configuração, pontos, enquadramento, clima e semente; oito segundos de
aquecimento e 30 segundos de coleta por ponto. População, tráfego e streaming
permaneceram ligados. As médias ficaram próximas ao limite de apresentação de
144 FPS. Os JSON preservam configuração e cada frame das amostras.

| Cena | FPS antes → final | p95 ms antes → final | p99 ms antes → final |
| --- | --- | --- | --- |
| Cais, dia | 143,98 → 143,96 | 9,215 → 9,748 | 9,434 → 10,085 |
| Cais, noite | 144,01 → 144,02 | 9,100 → 9,624 | 9,370 → 9,868 |
| Terminal, noite | 144,00 → 143,87 | 10,102 → 10,343 | 10,332 → 10,714 |
| Terminal, chuva | 143,89 → 143,25 | 10,182 → 10,379 | 10,415 → 10,957 |

O p95 do cais aumentou cerca de 5,8% e alguns p99 excederam o limite de regressão
de 5% do projeto. Na chuva houve um frame de 83,399 ms na coleta final; a base
teve um de 41,680 ms. As demais três coletas finais não tiveram frames acima de
33,3 ms. Portanto, **não está aprovado como ausência de regressão**, apesar das
médias altas. A rodada intermediária revelou custo maior no terminal; agrupar a
geometria reduziu esse custo, mas não elimina a pendência dos percentis e picos.

Havia um editor Godot preexistente aberto e alterações concorrentes no workspace;
as revisões exibidas nas capturas mudaram durante a tarefa. As medições registram
o antes/depois observado, não isolam causalidade de todas as alterações externas.
Não se descartou trabalho de outras sessões para produzir uma comparação.

[Base](../evidence/harbor-life-20260928/before/) ·
[primeira implementação](../evidence/harbor-life-20260928/after/) ·
[iluminação corrigida](../evidence/harbor-life-20260928/lit/) ·
[final agrupado](../evidence/harbor-life-20260928/final/) ·
[log final](../evidence/harbor-life-20260928/final-measure.log).

## Refinamento dos barcos de pesca — 28/09/2026

A pedido do usuário, os dois barcos receberam casco aberto e afilado, bordas
acompanhando a proa, cavernas internas, tábuas, bancos proporcionais, defensas
redondas, remos, cordas, rede, caixa térmica e motor de popa com suporte e hélice.
Os detalhes estáticos continuam agrupados por material, sem novas luzes ou
SubViewports. O barco de passageiros e sua rota permanecem iguais.

Um cadeado de 14 × 18 pixels aparece sobre cada barco a até 4,5 m, sem texto ou
ação de embarque. A seleção é atualizada a cada 0,15 s; a projeção acompanha a
câmera e redesenha apenas quando muda. Não aparece fora do terminal ou dentro
de interiores.

Os pescadores ficam nas duas extremidades do píer. A linha chega à água livre,
além dos cascos, acompanha a vara e some durante a reação a ameaça ou morte.
O retorno à pesca recupera a direção correta. Dez verificações de proximidade,
apoio físico, destino da linha e morte passaram no
[teste dedicado](../evidence/fishing-boats-20260928/test.log).

![Barcos detalhados e cadeado de proximidade](../evidence/fishing-boats-20260928/after/near-day.png)

Comparação específica deste refinamento: Main renderizada, mesmo hardware e
1280 × 720, câmera próxima com tamanho 18; oito segundos de aquecimento e 30 s
por cenário, população e tráfego ativos. Base capturada antes da edição.

| Cena | FPS base / depois / confirmação | p95 ms base / depois / confirmação | p99 ms base / depois / confirmação |
| --- | --- | --- | --- |
| Barcos próximos, dia | 143,85 / 143,80 / 143,31 | 10,849 / 10,839 / 10,700 | 11,671 / 11,615 / 11,383 |
| Barcos próximos, noite e chuva | 143,81 / 143,95 / 143,66 | 10,035 / 10,177 / 10,234 | 10,550 / 11,430 / 10,848 |

O aumento inicial de p99 noturno excedeu 5%, motivando uma única confirmação
equivalente. Não se repetiu acima desse limite: confirmação +2,8%, p95 +2,0%.
Nenhum frame acima de 33,3 ms nas quatro amostras posteriores; a base noturna
teve um frame de 34,592 ms. Sem regressão confirmada neste recorte. Havia outros
processos Godot durante a confirmação, portanto não se atribui toda variação
ao refinamento. A pendência da reforma geral do porto descrita acima permanece.

[Base](../evidence/fishing-boats-20260928/before/) ·
[Depois](../evidence/fishing-boats-20260928/after/) ·
[Confirmação](../evidence/fishing-boats-20260928/confirmation/).
Os JSON guardam amostras, aquecimento, GPU, VSync e limite de FPS.
