# Validação de motocross — 28/09/2026

## Dia de corrida — 29/09/2026

Mudanças: grade de largada com giro (holeshot/empinada/largada lenta), nota de pouso com dica de inclinação no HUD, cronometragem por ponto de controle, diferença para o rival à frente, anúncios, etiquetas dos rivais, cartão de classificação não modal, recorde da pista salvo (`best_lap`) e treino cronometrado. No local: estacas refeitas e fita, fardos nos escapes das curvas fechadas, arquibancada com cinco torcedores e placar da direção de prova, faixas na reta, tenda de mecânico no pátio. Descrição de jogo em `docs/motocross.md`.

Revisão de terrenos pela skill `docs/skills/validar-terrenos-pisos` (as skills `performance-do-jogo` e `testes-com-criterio` citadas por ela não existem neste checkout; foram aplicados os critérios do CLAUDE.md). Todo apoio foi medido com raios contra a colisão real do circuito montado (`tests/test_motocross_raceday.gd`, 28/28).

| Trecho | Visual | Física | Temporal | Performance |
|---|---|---|---|---|
| Estacas e fita (pista toda) | aprovado (`raceday-after-grid`, `-straight`, `-hairpin-*`, `-berm-stakes-close`) | aprovado: 109 estacas, nenhum canto com mais de 2,5 mm de folga; enterramento máximo 35 cm no pé voltado para a face íngreme da berma do grampo oeste; fita nunca a menos de 0,23 m além da largura de pilotagem | não executado | ver abaixo |
| Fardos (4 curvas, 31 fardos) | aprovado (`-hairpin-west`, `-hairpin-east`, `-grid`) | aprovado: sem folga sob nenhum canto, assento máximo 5 cm; 16 pontos descartados por declive >28 cm e 5 por reserva | não executado | ver abaixo |
| Arquibancada, placar, torcida | aprovado após correção (`-straight`, `-bleacher-close`) | aprovado: pés dos 5 torcedores a <2,5 cm do degrau, corpos sem interseção, passarela com colisão no topo visível, nenhum tronco/pedra no volume | não executado | ver abaixo |
| Grade de largada | aprovado (`-gate-close`, `-countdown-hud`) | barras abaixadas a no máximo 1,4 cm da argila inclinada; sem colisão por projeto (as motos ficam presas pelo controle) | animação de subida/queda conferida no teste; sem vídeo | ver abaixo |
| Tenda do mecânico | aprovado (`-paddock`, `-results`) | aprovado: pés sobre o piso do pátio a 13 cm; corredor físico do pátio 24/24 | não executado | ver abaixo |

**Defeitos encontrados e corrigidos.** (1) As estacas antigas ficavam na altura da crista da berma, não no talude onde estavam: **109 de 109 flutuavam mais de 2 cm, a pior 57 cm**. Agora ficam no ponto mais baixo da base, afundadas 5 cm, e são adensadas nas curvas para a fita reta não cortar a pista. (2) Primeira posição da arquibancada tinha um tronco dentro dela; (3) o placar ficava escondido sob outra copa; (4) uma pedra da pedreira atravessava a nova arquibancada; (5) a arquibancada virada para o norte mostrava só as costas à câmera de jogo. A arquibancada foi para o lado interno da reta, virada para o sul, a 4,3 m do tronco mais próximo; o placar fica atrás da última fileira; a pedra é pulada com os mesmos sorteios, então nenhuma outra pedra muda de lugar. Os testes cobrem os defeitos 1 a 4.

Capturas `raceday-after-*.png` (1920×1080, dia seco, Main, `--no-save`) são revisão visual, **não benchmark**: o contador do canto inclui a gravação dos PNG. Não há captura "antes" nova: o modo automático bloqueou restaurar temporariamente os arquivos do HEAD. Como referência anterior valem `finish-confirm-paddock-*.png` (mesmo código de motocross do HEAD). Chuva, noite e vídeo não foram capturados.

**Desempenho** (Main, Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, 1920×1080, VSync 0, limite 144 FPS; 5 s de aquecimento e 30 s medidos). A/B no mesmo build: `--without-raceday` remove em runtime arquibancada/torcida, fita, fardos, faixas, placar e grade (a tenda e as estacas em MultiMesh ficam). Não foi possível confirmar que nenhuma outra sessão rodava Godot durante as medições; por isso as rodadas foram intercaladas.

| JSON | Cenário | p50 ms | p95 ms | p99 ms | Máx. ms | >33,3 ms | Draw calls |
|---|---|---:|---:|---:|---:|---:|---:|
| `raceday-static-on1` | câmera parada na reta, com | 6,970 | 10,617 | 10,981 | 14,7 | 0 | 418 |
| `raceday-static-off1` | idem, sem | 6,991 | 10,639 | 11,099 | 14,1 | 0 | 330 |
| `raceday-static-on2` | com | 6,991 | 10,445 | 10,927 | 41,6 | 3 | 418 |
| `raceday-static-off2` | sem | 6,972 | 11,210 | 14,639 | 24,1 | 0 | 330 |
| `raceday-race-on1` | Expert, 6 motos, com (antes de congelar a pose da torcida) | 6,822 | 11,465 | 12,816 | 33,0 | 0 | 397 |
| `raceday-race-off1` | idem, sem | 6,975 | 11,044 | 11,631 | 31,9 | 0 | 310 |
| `raceday-race-on2` | Expert, com (pose congelada) | 6,972 | 11,070 | 11,704 | 30,0 | 0 | 397 |
| `raceday-race-off2` | Expert, sem | 6,961 | 11,233 | 12,256 | 64,4 | 1 | 310 |
| `raceday-race-on3` / `off3` | **contaminadas**: 31 e 16 quadros >33 ms, máx. 98,9 e 234,8 ms, p50 caiu para 6,1 ms nos dois lados | — | — | — | — | — | — |

Leitura: parado, sem diferença mensurável (a variação entre rodadas iguais supera a diferença com/sem). O primeiro par de corrida teve +3,8% no p95 e +10,2% no p99; a CPU de processo indicava a IK dos torcedores rodando a cada 1–2 quadros. Depois de congelar a pose assentada (reativa com tiro ou impacto), o par limpo seguinte ficou igual ou melhor que o lado sem a decoração. **Isso é uma amostra limpa, não certificação**: sem ambiente isolado, desempenho fica "sem regressão observada, não certificado". Custo fixo conhecido: +87 a +88 draw calls quando a arquibancada está em quadro (malhas dos cinco CivilianModel), relevante para o Android e ainda não medido lá.

Testes (29/09): `test_motocross_raceday` 28/28; `test_motocross_session` 44/44 (Main, `--no-save`; inclui grade subindo e caindo, holeshot, cartão de resultado, recorde e volta de treino); `test_motocross_combat` 10/10 (15 espectadores, torcida ligada ao combate); `start` 8/8; `ambient` 13/13; `progress` 27; `bike` 20/20; `pilot` 12/12; `contact` 5/5; `launch` 4/4; `models` 10/10; `art` 14/14; `spectators` 15/15; `scenery` 24/24. Verificação do CLAUDE.md: `test_regions`, `test_bridge_approach_terrain`, `test_native_driving --no-save` e `cold/test_admission` 11/11 aprovados. Os testes não certificam FPS nem aparência.

## Acabamento, terreno contínuo, combate e saltos — revisão final

Correções: faces exteriores dos troncos e raízes no solo; altura das árvores correspondente às faces físicas do morro; grama agrupada por células; textura em coordenadas globais compartilhada entre mata e parque; clareira única com acesso, locadora, mesa e motos, substituindo as bases retangulares. NPCs usam CivilianModel e os sinais reais de combate. Rampas conservam velocidade vertical, com postura aérea e compressão no pouso. HUD nativo concentra posição/volta/tempo e velocidade/estado/integridade.

Validação funcional: `test_motocross_scenery.gd` 24/24 (154 amostras de chão, maior diferença adjacente 1,51 cm, caminhada física entre áreas, suporte dos pneus/pés); `test_motocross_combat.gd` 9/9 na Main; espectadores 15/15; lançamento 4/4 (0,494 m, 0,45 s, compressão -0,053 m); grupos de motos 20/20; árvores 883/883; garagem 84/84. A contagem de saltos registra toda saída ascendente do contato, inclusive pequenas ondulações, e não equivale a grandes saltos. Logs `finish-connected-*`, `finish-bike-tests.log` e resultados da revisão anterior preservados.

Capturas `finish-review-*` são revisão de componentes renderizados, **não benchmark**. `finish-after-paddock-paddock.png` comprova o terreno unido na Main; `finish-after-race.png` mostra HUD, chuva e rastros; `finish-after-race-overview.png` mostra lama, lua cheia e holofotes. Não houve salto que atendesse ao critério da fotografia nos 30 s adicionais da corrida molhada; o lançamento foi comprovado no ensaio físico e na captura diurna. Contadores instantâneos em imagens pausadas não são métricas de desempenho.

Medição atual: Main, Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, **1920×1080, VSync 0, limite 144 FPS**, conforme JSON. Cinco segundos de aquecimento e 30 s medidos por cenário. Outros processos do usuário permaneceram abertos e houve mudanças concorrentes em Vértice/veículos/produção entre a base e o resultado. População ambiente natural no pátio: 36 antes, 33 depois; corrida: 0 pedestres ambientes e seis pilotos em ambas. Assim, o comparativo não isola causalmente o custo desta alteração.

| Cenário / JSON | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Pátio antes `finish-base-paddock` | 144,00 | 6,992 | 10,722 | 11,167 | 22,887 | 0 / 0 |
| Pátio depois `finish-after-paddock` | 142,85 | 5,634 | 11,482 | 12,146 | 26,826 | 0 / 0 |
| Pátio confirmação `finish-confirm-paddock` | 142,83 | 6,097 | 11,347 | 12,039 | 25,494 | 0 / 0 |
| Seis pilotos/noite/chuva antes `finish-base-race` | 93,53 | 10,785 | 18,668 | 36,875 | 89,103 | 49 / 2 |
| Seis pilotos/noite/chuva depois `finish-after-race` | 131,23 | 6,705 | 12,935 | 15,834 | 38,859 | 1 / 0 |

Máximos no aquecimento: pátio 25,612→32,084 ms; corrida 16,569→18,309 ms. A corrida final atende ao orçamento nos percentis, mas teve um quadro de 38,859 ms. O pátio ficou abaixo de 16,67 ms nos percentis, porém aumentou 7,1% em p95 e 8,8% em p99 na primeira amostra; isso exige confirmação e não autoriza declarar desempenho sem regressão aprovado.

A segunda amostra confirmou aumento observado no pátio: +5,8% em p95 e +7,8% em p99 frente à base, sem quadro acima de 33,3 ms. **Comparação sem regressão pendente/reprovada pelo limiar de 5%**, apesar de ambas as amostras finais atenderem ao orçamento absoluto de 60 FPS nos percentis. Não foi isolada a contribuição das mudanças concorrentes nem dos processos externos. Revisão de código constatou física desabilitada nos espectadores em repouso e decisões/binding a 5 Hz; não há evidência para atribuir todo o aumento aos novos modelos. A aprovação comparativa requer uma base isolada e diagnóstico de CPU/GPU, sem descartar alterações compartilhadas.

Tentativas excluídas: `finish-before-paddock` teve sobreposição temporária com outro benchmark nosso (interrompido), portanto foi substituído pela base limpa. Primeira tentativa `finish-after-paddock.log` saiu 1 antes de produzir amostras, sem diagnóstico suficiente; a execução seguinte recebeu diagnóstico de estágio e carregou em 17,5 s. Erros temporários de arquivos ausentes/tipos em alterações concorrentes de Vértice e veículos impediram ensaios intermediários; não foram contornados alterando código alheio e não ocorreram nos ensaios finais. O aviso de recurso de textura ao encerrar aparece também em revisões anteriores; não há erro de script nos benchmarks finais.

## Histórico anterior

Cena real `Main.tscn`, Godot 4.7.2, Vulkan Forward Mobile, RTX 4060 Laptop, 1280×720, VSync habilitado, limite efetivo de aproximadamente 144 FPS. `--no-save` em todas as execuções. Outros processos Godot do usuário permaneceram abertos: comparação diagnóstica, sem certificação de isolamento ou FPS universal.

Meta provisória: 60 FPS / 16,67 ms; variação superior a 5% em p95/p99 é sinal para investigação. Cada amostra tem 5 s de aquecimento e 30 s de intervalos reais. Carregamento inicial da cena ocorre antes da janela, portanto estes números não certificam a latência de primeira visita/streaming.

| Cenário | FPS médio | p95 ms | p99 ms | Máximo ms | Frames >33,3 ms |
|---|---:|---:|---:|---:|---:|
| Terreno original, câmera parada (`before`) | 143,96 | 8,511 | 8,891 | 21,719 | 0 |
| Parque completo, mesma câmera parada (`park-static`) | 143,95 | 8,795 | 9,302 | 23,793 | 0 |
| Corrida diurna, 4 motos (`park-day`) | 143,69 | 10,217 | 10,855 | 22,835 | 0 |
| Expert, 6 motos, noite, chuva e 4 refletores (`park-expert-night`) | 143,42 | 10,752 | 11,381 | 37,673 | 1 |

O comparativo estacionário aumentou p95 em 3,3% e p99 em 4,6%. As amostras de corrida ficaram dentro do orçamento em p95/p99; o cenário expert teve um pico de 37,67 ms. Corrida e terreno parado não são cenários equivalentes para atribuir regressão. A aprovação em ambiente isolado e o custo da primeira visita continuam não certificados. Nenhuma qualidade global do jogo foi reduzida.

`park-night-mud` é uma revisão intermediária: revelou brilho excessivo nas poças e lama sobre a grama. Isso foi corrigido antes de `park-expert-night`. `park-day-paddock` é anterior à ampliação da reserva sem árvores no estacionamento; `park-static-paddock` mostra a reserva final. Há um aviso de textura remanescente ao fechar Godot também presente na medição inicial; não houve erro de script durante as amostras finais.

## Verificações funcionais

- `test_motocross_progress.gd`: 26 verificações aprovadas (carteira, inscrição, vitória/derrota, desbloqueio, propriedade, saves, aluguel).
- `test_motocross_bike.gd`: 20 aprovadas (física real, saltos, recuperação, grupos de 4/6 pilotos, pista seca/molhada, rastros e limites de efeitos).
- `test_motocross_session.gd`: 24 aprovadas (Main real, duas voltas, pagamento, pausa, retorno à pista, moto própria, aluguel/devolução).
- `test_motocross_scenery.gd`: 20 aprovadas, incluindo 66 pontos físicos das bordas, pórtico, 30 árvores, pátio livre, barcos e luzes. Corrigiu faces invertidas no ombro de uma curva fechada.
- Garagem: recompensas 47, restauração do motorista 26 e transferência física 11 verificações aprovadas, incluindo restrições de armas.
- `test_freight_woodland_trees.gd`: 828 verificações aprovadas após reservar o pátio para impedir troncos entre as motos.

As capturas `*-overview.png`, `*-start.png`, `*-paddock.png` e `*-boats.png` foram feitas depois da medição, com câmeras de revisão. O contador instantâneo nelas não é evidência de performance; use os intervalos completos nos arquivos JSON.

## Seleção de motos, montagem e ambientação

Foram acrescentados três modelos com diferenças físicas, cena de montagem de 2,4 s e até três pilotos decorativos por proximidade. Na vitória que libera a moto, o modelo escolhido é salvo. A ambientação sai antes de corrida/aluguel/montagem e não altera carteira ou progresso.

Validação funcional: modelos 10/10, ambientação 13/13, progressão 27/27, início/interrupção da montagem 8/8 e sessão real 34/34. A primeira expectativa de saldo no teste estava incorreta: passar de R$ 2.000 também concede R$ 50 pela conquista já existente `first_grand`; o teste agora confere separadamente essa transação e o prêmio de R$ 280. A física e o pagamento do produto não foram alterados para acomodar o teste.

Mesmo protocolo de medição, mesma câmera parada e parâmetros da tabela anterior:

| Cenário | FPS médio | p95 ms | p99 ms | Máximo ms | Frames >33,3 ms |
|---|---:|---:|---:|---:|---:|
| Antes da ambientação (`selection-before`) | 144,00 | 8,621 | 9,290 | 20,626 | 0 |
| Ambientação inicial (`selection-ambient`) | 143,99 | 9,535 | 9,811 | 21,481 | 0 |
| Ambientação com decisões de direção a 12,5 Hz (`selection-ambient-tuned`) | 144,00 | 9,395 | 9,727 | 20,745 | 0 |
| Corrida com Víbora e montagem (`selection-race`) | 143,74 | 10,385 | 11,915 | 21,568 | 0 |
| Ambientação noturna com chuva (`selection-ambient-night`) | 144,02 | 8,905 | 9,322 | 11,559 | 0 |

A física da ambientação permanece na frequência do motor; só a decisão de direção foi reduzida. O custo estacionário adicional observado ficou em 0,774 ms no p95 (+9,0%) e 0,437 ms no p99 (+4,7%). As amostras atendem ao orçamento absoluto provisório, mas o aumento de p95 ultrapassa a tolerância comparativa de 5%; portanto desempenho sem regressão NÃO está aprovado. O custo residual e a confirmação isolada continuam pendentes, sem remover pilotos ou reduzir qualidade global. A tomada e a moto diferente tornam `selection-race` um cenário distinto do comparativo estacionário.

Capturas da interface e montagem: `selection-race-selection.png` e `selection-race-mounting.png`. Após essa captura, o botão do modelo escolhido também recebeu estado pressionado e foco consistente com o sinal de seleção.

## Motos e pilotos articulados

Comparativo renderizado da corrida diurna com Víbora e quatro pilotos, mesma cena, câmera e protocolo (`--race --presentation --model=2 --no-save`):

| Arte | FPS médio | p95 ms | p99 ms | Máximo ms | Frames >33,3 ms |
|---|---:|---:|---:|---:|---:|
| Anterior (`art-before`) | 143,67 | 10,297 | 11,122 | 21,427 | 0 |
| Final (`art-final`) | 143,64 | 10,536 | 11,308 | 22,383 | 0 |

A alteração visual ficou em +2,3% no p95 e +1,7% no p99 nesta amostra, dentro da tolerância comparativa de 5%. Isso não resolve a pendência anterior da ambientação nem certifica outros cenários ou uma execução isolada. A moto tem 4.757 triângulos, 18 MeshInstances e recursos compartilhados; detalhes estáticos dos pilotos são agrupados por material. Não foram adicionadas luzes ou corpos físicos.

`test_motocross_art.gd`: 13 verificações aprovadas, cobrindo 81 combinações de modelo, direção, inclinação e rampa; erro máximo de contato inferior a 0,003 mm, braços/antebraços sem alongamento e queda com colisão preservada. `test_motocross_bike.gd`: 20/20, incluindo saltos, queda, recuperação e grupos na pista seca/molhada.

`test_motocross_start.gd`: 8/8 na revisão final, incluindo montagem, desistência, câmera, pagamento e descarregamento da cena. A primeira execução revelou consulta a transformações globais durante a remoção dos filhos; a postura agora ignora nós fora da árvore. A repetição terminou sem erros de script. O benchmark final ainda apresenta o aviso de textura no encerramento já observado na linha de base.

## Encaixe das botas, disputa e chuva noturna

A revisão seguinte separa pé e cano da bota: a sola mantém o contato com a pedaleira e o cano acompanha a canela. Botas foram encurtadas e a calça recebeu perfil contínuo. Contatos entre motos usam velocidade relativa: encostada gera impulso limitado e desequilíbrio; colisão forte pode derrubar ambos. Frenagem, derrapagem e pouso afetam a postura.

O piloto automático planeja a 8 Hz, considera até seis participantes locais e usa aceleração/freio reais. Mantém o lado de ultrapassagem por alguns segundos, antecipa curvas e varia o traçado. A ambientação mantém decisões a 12,5 Hz e recebeu ritmo maior. Rivais de corrida ganharam 1 m/s no limite nominal, preservando progressão de dificuldade e diferenças dos modelos.

Validações: arte 14/14 (incluindo continuidade cano/canela em 81 poses), contato físico 5/5 (encostada sem dano, colisão forte com dano e recuperação dos dois), pilotagem 12/12 (ultrapassagem real, volta física de 401,81 m, traçado variando 3,53 m, velocidades-alvo de 8,14–17 m/s, frenagem e aceleração), ambientação 13/13. O ensaio de pilotagem manteve distância lateral máxima de 2,36 m, dentro dos 5,2 m físicos da pista.

Física/grupos: 20/20 com as velocidades finais e personalidades distintas. Quatro iniciantes no seco e seis experts no seco/molhado cruzaram todos os 32 gates. Experts tiveram uma queda no seco e quatro no molhado, com recuperação suficiente para todos completarem; quedas não foram forçadas pelo teste. Total desta revisão: 64 verificações aprovadas. Log integrado: `dynamic-bike-final.log`.

Medição na Main real, quatro motos, chuva forte, chão encharcado, lua cheia (~99,96%) e quatro refletores. Mesmos parâmetros de captura `--race --presentation --model=2 --wet --night --full-moon --no-save`, 5 s de aquecimento e 30 s medidos. GPU/renderer/resolução iguais aos anteriores; outras sessões permaneceram abertas. A lógica de pilotagem alterada percorre uma trajetória diferente durante a janela, portanto o comparativo representa o cenário completo e não isola o custo de cada mudança.

| Revisão | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | Frames >33,3 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes das botas/pilotagem (`boots-before-night`) | 142,70 | 6,962 | 9,971 | 11,597 | 19,565 | 0 |
| Botas corrigidas (`boots-moon-rain`) | 142,16 | 6,966 | 9,947 | 12,196 | 22,032 | 0 |
| Botas + pilotagem final (`dynamic-moon-rain`) | 143,35 | 6,959 | 9,782 | 10,364 | 49,271 | 1 |

A amostra final melhorou p95/p99 em relação à base e atende à meta provisória nesses percentis. Houve um pico de 49,27 ms cuja causa não foi isolada; isso não certifica ausência de travamentos nem resolve a pendência anterior da ambientação. A variação de p99 da revisão intermediária não persistiu na revisão final. Não houve frame acima de 66,7 ms. Capturas finais: `dynamic-moon-rain-overview.png` e `dynamic-moon-rain-rider-detail.png`; mostram chuva, lama, iluminação lunar atenuada pelas nuvens e holofotes existentes, sem alterar iluminação global do produto para a foto.

`art-after` é uma versão intermediária inválida visualmente: misturar superfícies sem índices com primitivas indexadas descartava pneus e capacetes durante o agrupamento. Todas as fontes agora têm índices. A captura final `art-final-rider-detail.png` confirma pneus, carenagens, capacetes, luvas no guidão e botas nas pedaleiras. `art-final-mounting.png` mostra a transição e os demais pilotos; as câmeras de detalhe são posteriores à medição.
