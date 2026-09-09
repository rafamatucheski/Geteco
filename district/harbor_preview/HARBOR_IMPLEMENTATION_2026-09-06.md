# Harbor: execução ordenada após auditoria

Sem commits. Worktree anterior e integrações de terceiros preservados.

## 1. Base de gameplay — corrigida e testada

- Corrida: os dois resultados vermelhos anteriores eram provocados pelo piloto
  de teste, que seguia o centro da rua e atingia veículos na contramão e o rival.
  Instrumentação identificou HarborTraffic_02/03/04 e CobraRaceRival. O teste
  agora respeita faixa, tráfego à frente e espaço para ultrapassar. Produção,
  dano, colisão e trânsito não foram enfraquecidos. Três execuções consecutivas
  verdes: 1825,2 / 1826,2 / 1824,3 px; últimas duas com carro/jogador em 100 HP
  e 28 veículos ambiente ativos. Isto valida o percurso físico automatizado,
  não certifica ainda a dificuldade/diversão para um jogador humano.
- FoundryLofts: sólido único substituído pelas duas alas desenhadas. O Player
  real percorreu quatro trajetos pelo pátio e foi bloqueado pelas duas paredes,
  mantendo a máscara original. Prédios não-L mantêm suas dimensões de colisão.
- HarborEmergencyDirector: adaptador do diretor/pool existente, integrado no
  HarborPreview (herdado pelo HarborGame). Bombeiros, polícia e ambulância usam
  acessos autorados; nenhum caminhão dirigível do interior é retirado.
  Incêndio no PlayerCar real despachou caminhão que percorreu cerca de 1077 px,
  desembarcou dois bombeiros e apagou o fogo. Polícia/ambulância verificadas
  quanto ao spawn no acesso correto, não quanto a uma perseguição completa.
  Limpeza de unidades e equipes na saída da cena tem teste específico.

## 2. Acabamento funcional — testes verdes e imagens conferidas

- 17 postes dos três providers: cinco Westgate e seis próprios em East/North,
  sem duplicatas nem ocupação de pista/prédio/acesso. Ligação com dia/noite.
- Retirada da pintura antiga de beco que invadia Laundry e dos grandes nomes
  decorativos desenhados no chão em East/North.
- Driveway de 64 px agora interrompe a guia no lado correto; testes comparam
  o lado oposto com as máscaras anteriores, preservando a travessia existente.
- Três emendas do círculo usam a curva real, não um polígono de cruzamento.
  Operações booleanas nativas substituem a extração de bordas que perdia
  continuidade nas curvas. Testes incluem anel com vazio, ilha e preenchimento
  parcial: 3766 segmentos, 44 contornos fechados, 143 máscaras e zero falhas.
  Margem numérica de clipping de 0,02 px evita linhas dentro das máscaras.
- Prédios, becos, portas, gateway, vida urbana, trem e segurança: testes verdes.
  Gateway preserva as 20 ruas/40 faixas originais e confere os IDs dos providers
  adicionais, em vez de rejeitar a expansão por uma contagem total obsoleta.

Capturas das bordas: `D:/geteco/road-edge-court-seam.png` e
`D:/geteco/road-edge-secret-drive.png`, conferidas visualmente pelo agente principal.
Não houve alteração no roteamento global, nem em UnifiedRoadNetwork2D nesta etapa.

Observação técnica: a contagem de braços do renderer compartilhado usa uma
projeção que ignora segmentos menores que 2 px no progresso acumulado, mas os
inclui no comprimento total. Isso pode classificar uma ponta densamente amostrada
como interior. A superfície Harbor agora usa as pontas reais nessas três emendas;
a navegação compartilhada não foi alterada inadvertidamente junto do acabamento.

## 3. Integração externa — contratos funcionais verificados independentemente

Os arquivos de Dante/garagem e UI já aparecem no worktree; isso não prova que
as entregas externas terminaram. `test_harbor_campaign_flow.gd` passou novamente
com zero falhas: chegada/telefone, contato, primeira entrega, recompensa única,
respawn e aplicação de snapshots em memória. O teste prepara parte dos trajetos
por posição e aciona diretamente a confirmação de pular CGI; não equivale a uma
sessão inteira dirigida por uma pessoa. Log: `D:/geteco/harbor-stage3-campaign-flow.log`.
O diário/descanso passou com renderização Compatibility e eventos reais de
mouse/teclado, PT/EN, bloqueios de distância/missão/perseguição e liberação de
controles. `test_cobra_journal_rest_isolated.gd` preserva as asserções do teste
externo, redirecionando suas gravações de idioma para um diretório temporário.
Log: `D:/geteco/harbor-stage3-journal.log`.

`test_harbor_dante_contract.gd` passou headless e renderizado: corpo real andou
50 px/correu 75 px, pernas articularam, armas usam o socket, dano/flash funcionam,
E entra/sai do carro e o viewport desliga/retoma. É checkpoint pós-chegada explícito,
não um segundo teste da CGI; a foto não equivale a aprovação artística definitiva.
O teste externo de dez etapas continua com limitações documentadas separadamente;
não foi usado como prova de que a campanha toda estaria certificada.

## 4. Boss e recompensa — contratos testados, não balanceamento humano

- CobraBoss preserva HP/arma/colisão/fases, com jaqueta vinho/carvão, detalhes de
  cobre, barba e corpo próprio sobre o rig articulado existente. Teste executou
  dois encontros e dois impactos de Bullet reais; parte das fases usa passos
  de teste e o término usa a API de dano, não uma vitória humana completa.
- Ironback V8: muscle 3D de capô longo, rodas/portas alinhadas, faróis em barras,
  dano/reparo/pintura herdados e áudio V8 sintetizado/cacheado próprio. Cupê
  original mantém seus defaults; testes de rodas e dirigibilidade passaram.
- Recompensa exige finale concluída E defeated; baia real da garagem, sem
  sobrepor parede, quadro, Maciota ou props. Entrada E, direção pelo corredor
  e saída E passaram headless e com renderização real.
- UI contextual separa recolher (preserva danos) e reparar. Testes cobrem baia
  ocupada, carro dirigido, carro destruído, clique real, saúde/velocidade após
  reparo, pintura e JSON em memória em cena recriada com uma única instância.
  Não foram escritos saves pessoais; a gravação em disco continua pelo fluxo
  existente de salvar. Persistem HP/pintura/pose, não a malha exata das amassadas.
- Testes capturaram e corrigiram somente no muscle a câmera estacionada disabled,
  processamento posterior ao Player que consumia E duas vezes e motor com
  velocidade zero após reparo de um carro destruído.

Imagens conferidas: `D:/geteco/boss-muscle-reference.png`,
`D:/geteco/boss-muscle-door-open.png`, `D:/geteco/cobra-boss-reference.png` e
`D:/geteco/harbor-stage4-boss-recovery.png`.
Log integrado renderizado: `%TEMP%/harbor-stage4-boss-reward-render.log`.

## 5. Obra e epílogo — integrados e validados

- Obra autorada como filha do Gateway existente: operários, equipamento,
  andaimes, dois tabuleiros alinhados aos eixos atuais e aproximação em concreto.
  Retorno mantém as duas faixas e suas colisões; fronteira permanece fechada.
- Dante liga para Maciota após a vitória e em situação segura; quatro falas
  PT/EN com voz simulada, notificação curta sem toque infinito. Depois de sete
  segundos de gameplay seguro, tomada com fade/aproximação mostra a conclusão.
- Estado JSON separa chamada/obra concluídas. Cancelar, carregar no meio e sair
  da cena devolvem pausa/câmera; não disparam campanha legada nem duplicam prêmio.
- Teste armado revelou que botões também disparavam pelo polling do Player.
  Bloqueio local nos dois adaptadores (telefone e recompensa) corrige a causa;
  não se mascarou o problema trocando o jogador por uma fixture desarmada.
  Munição e HP são conferidos antes/depois dos cliques e os controles retornam.
- Teste headless e renderizado de epílogo passou: mouse/F8/Escape reais,
  bloqueios de interior/morte/perseguição/diálogo, tempo seguro, snapshots,
  saída durante pausa, retorno físico desobstruído e malha sem avisos.

Capturas conferidas: `D:/geteco/harbor-stage5-works-before.png` e
`D:/geteco/harbor-stage5-works-after.png`.
A conclusão é da obra LOCAL; não existe ainda uma ilha jogável de Mapa 2.

## 6. Paisagismo e acabamento — implementados, testes e capturas

- East/North: 24 árvores com estilos já existentes, copas e materiais variados;
  três casas Northbank com tipos e dimensões distintos, mantendo centros/acessos.
  Quatro composições na promenade substituem a fileira de treze módulos iguais.
- Cobra: onze grupos autorados de sombra, vegetação seca e pedras costeiras.
  Todos os IDs precisam existir no teste; rejeições de posição são reportadas,
  não escondidas removendo toda a decoração. Copas facetadas permanecem estáticas.
- Ramal de 30 px do jardim chega ao acesso norte sem pintar asfalto. O caminho
  do jardim East também foi corrigido no desenho: antes invadia Courtyard Lane;
  agora fica em y=1711..1743, acima da faixa física. Três copas e uma pedra foram
  ajustadas sem afrouxar recuos exigidos pelos testes.
- Auditoria diferencia copas opacas, sombras e troncos. Bancos à sombra podem
  existir, mas troncos/caminhos não se sobrepõem. Seis trajetos usam a cápsula
  original do Player, incluindo jardim, acesso de bombeiros e garagem.
- Terreno visual Cobra recortado na divisa x=6760 para não cobrir a promenade;
  LAND físico, ruas, missões, acessos e conexões não foram alterados nesse recorte.

Imagens: `D:/geteco/harbor-stage6-east-garden.png`, `harbor-stage6-promenade.png`,
`harbor-stage6-north.png`, `harbor-stage6-cobra-garden.png` e `harbor-stage6-cobra-coast.png`.
Medição final de desempenho e regressão estão na etapa abaixo.

## 7. Validação final — concluída, com limites explícitos

Regressão focada em Harbor/Cobra e benchmarks com renderização real.

- **34/34 testes headless passaram**, sem erros de script/parsing/asserção.
  Não corresponde a todos os testes de todos os distritos do repositório.
- Interiores: primeiro executor interrompeu em 150 s enquanto ainda avançava.
  Repetição sem alterar o teste concluiu 22 ciclos, 23 diálogos e 21 interações,
  com 32 veículos/45 pedestres ativos no percurso integrado; zero falhas.
- Navio: 641 amostras da cápsula, 38 sweeps e 1089 amostras de água aprovados.
- Rodoviária: duas visitas/partidas, quatro embarques/desembarques, 3185 px.
  Console reportou quatro ObjectDB remanescentes ao encerrar esse teste:
  aviso de limpeza pendente, não uma asserção de gameplay aprovada por engano.
- Certificados do Windows geram erro ambiental nas execuções sandbox headless.
- Save REAL renderizado fora do sandbox: **zero falhas**. Slot exclusivo
  `qa_harbor_275372_2202067` criado, lido pela API de produção, mundo recriado,
  jogador/HP/armadura/posição e recompensa única/pintura/HP/epílogo restaurados.
  Arquivo validado pelo slot_id e removido; ausência confirmada posteriormente.
  Nenhum save pessoal sobrescrito. Log `D:/geteco/harbor-final-real-save.log`.
- Paisagismo também passou com renderização real e capturas revistas após
  ampliar o workshop para 180 px, contendo suas janelas dentro da fachada.

Logs individuais: `D:/geteco/harbor-release-<nome_do_teste>.log`.

### Desempenho medido (1920x1080, Compatibility, 600 frames)

| Cena | FPS médio | p99 do frame | Frames acima de 16,67 ms |
| --- | ---: | ---: | ---: |
| Preview antes desta etapa | 59,9 | 36,52 ms | 158/600 |
| Preview final | 59,6 | 36,04 ms | 165/600 |
| HarborGame chegada, amostra final | 53,2 | 42,74 ms | 371/600 |
| HarborGame pós-Boss | 56,5 | 37,28 ms | 307/600 |

Preview ficou essencialmente estável; não equivale ao custo da campanha real.
As amostras não são três repetições controladas com a mesma semente: não atribuir
ganho causal à pequena otimização do adaptador de epílogo. Essa otimização evita
cancelar áudio/interface em todo frame antes de haver vitória. Ainda NÃO há
garantia de 60 FPS estáveis nem validação de todos os renderizadores.
Logs: `D:/geteco/harbor-final-preview-performance.log`,
`D:/geteco/harbor-final-game-performance-2.log` e
`D:/geteco/harbor-final-postboss-performance.log`.

Os testes de campanha usam checkpoints e trajetos preparados onde explicitado;
uma sessão humana contínua de ponta a ponta e o balanceamento não são equivalentes
a esses testes e não serão declarados aprovados com base apenas em asserts.

Não abrir passagem para uma cena inexistente. A saída norte x5880/6120 é o eixo
reservado para a ilha de floresta; a ponte Foundry oeste/leste é outra estrutura.
O legado campaign_v1 ainda contém uma narrativa e destinos regionais diferentes:
a conclusão Cobra não deve disparar seus desbloqueios de deserto/costa nem seus
eventos sobre o irmão.

### Limites de entrega

- A obra tem operários/equipamento decorativos animados, não um minigame de obra.
- Pedras pequenas e bancos decorativos não receberam novos obstáculos físicos.
- A corrida/combate usam trajetos e checkpoints de teste; falta uma sessão humana
  contínua para julgar dificuldade, ritmo e diversão de todo o capítulo.
- Recompensa persiste identidade, pintura e HP; não promete persistir cada vértice
  visual amassado. Só existe um carro do Boss por estado de campanha.
- Não foram realizados commits nem alterações nas integrações de terceiros
  mencionadas na revisão independente para simplesmente fazer um teste passar.
