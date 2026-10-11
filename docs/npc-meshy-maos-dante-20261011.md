# Revisão das mãos do policial de terno — 11/10/2026

O usuário reprovou as mãos nas capturas da entrega anterior. O erro do **osso do punho** abaixo de 3 cm não demonstrava uma empunhadura correta: a superfície tinha dedos esticados e triângulos abertos. As fotos `refinement-20261011/final-m4` e `final-smg` documentam essa falha, não aprovação visual.

## Escopo e referência

A correção usa as mãos e os morphs `GripRight`/`GripLeft` de `assets/dante.glb`, referência efetivamente apresentada por `scripts/Actor.gd`. Não altera o Dante nem utiliza créditos, downloads ou novos serviços Meshy. O alvo é `assets/civilians/meshy/police/suit_m.glb`; os outros corpos conservam o caminho anterior até receberem um perfil próprio validado.

O adapter lê o perfil de mãos nos extras do nó importado. A arma define orientação e ponto da palma; a IK alcança o punho descontando esse deslocamento. A pega reproduz a rotação calibrada do Dante, incluindo o apoio cruzado das armas longas. Os dedos usam os morphs autorados, com abertura durante a busca do carregador e liberação da orientação ao morrer. Há duas superfícies no mesmo corpo/esqueleto; cada superfície mantém a sua textura. O tom da textura das mãos é ajustado offline ao NPC.

O corpo com perfil usa a mesma escala de arma do Dante (`WeaponRigPose.V1_TO_V2`), aplicada também aos pontos de pega, apoio, coronha e recarga. A arma menor do kit atravessava a palma transplantada com o guarda-mato. O apoio fica mais próximo do centro do peito, dentro do alcance dos dois braços; a coronha acompanha o tronco também na corrida. Esses ajustes ficam restritos ao corpo com perfil, preservando as poses dos outros corpos. O driver conserva os valores de morph e evita ler a mesma propriedade por frame; a interpolação de orientação da recarga só ocorre quando há deslocamento para o cinto.

## Causas confirmadas e experiências rejeitadas

- A curva incremental anterior misturou vértices dobrados por duas extensões diferentes; a maior aresta passou de 8,06 para 104,15 mm (12,927 vezes).
- Só corrigir pesos e roll não consertou a geometria. Essas experiências permanecem em `evidence/npc-meshy/hands-review-20261011/offline-probes/`.
- No primeiro transplante, o recorte por faces inteiras também retirava trechos da manga. A borda avançava até 199 mm antes do punho, embora o limite pretendido fosse 40 mm.
- Na versão v5, os tubos novos tinham faces viradas para dentro: 144 faces de manga e 72 da ponte de pele. O shader descartava a parte exterior. A captura renderizada detectou a falha que os testes de posições/pesos não mostravam.
- A ponte regular da V9 não cobria a borda verdadeira do punho do Dante: a borda chegava a 1,86 vez o raio suposto, com até cerca de 17 mm descobertos. Na V11, a ponte segue a borda recortada, com posições e deltas iguais nos pares da emenda.
- A V10 ligou essa borda, mas interpolou UV entre ilhas diferentes e criou faixas de tecido na ponte. O diagnóstico com material de cor uniforme separou isso de um buraco. A V11 mantém coordenadas de pele constantes na ponte, sem alterar os UVs dos dedos.
- As marcas pretas restantes na mão direita desapareceram ao ocultar somente a arma depois de resolver a pose; eram interseções do guarda-mato, não manchas de textura. A escala da arma corrigida acima removeu a causa. As capturas de diagnóstico (`v10-solid/`, `v10-two-sided/`, `v10-no-gun/`) não são fotos de entrega.

## Evidência e validação

Pasta de trabalho: `evidence/npc-meshy/hands-review-20261011/`. As capturas de referência `dante-final-reference/dante-m4a1-aim-front.png` e `dante-final-reference/dante-m4a1-aim-side.png` mostram o Actor real com a arma produtiva, sob a mesma luz e câmera da comparação. Os candidatos com defeitos permanecem separados da produção.

Estado visual: **V11 instalada e revisada nas capturas reais de produção**, em `production-m4/` e `production-smg/`: frente, lado e lado oposto, com mira, recuo, três fases da recarga, corrida e repouso. São 42 fotos, com o GLB importado e a arma produtiva. A mão usa a geometria e os grips do Dante, sem os leques antigos; a ponte fica fechada, sem a faixa falsa de textura. Isso não aprova todos os outros corpos nem o desempenho. V9/V10 e as pastas anteriores `final-m4/` e `final-smg/` são experiências superadas.

O A/B alterna seis rodadas na mesma sessão (antes/depois/depois/antes/antes/depois), com as duas versões do GLB preservadas e sem trocar arquivos de trabalho para criar o baseline. Janela 1280×720, 5 s de aquecimento e 30 s de amostra por rodada, VSync/limitador desligados só no processo. Meta provisória 16,67 ms; aumento acima de 5% em p95/p99 impede aprovação. O palco usa 24 policiais. Main usa uma fixture explícita de dois PoliceAgent com IA, armas e física reais; isso não valida chegada pelo despacho, cuja falha anterior está registrada no relatório de refinamento.

V11: 11.317 triângulos, 24 ossos e duas superfícies (corpo/cuff 4.033 vértices; mãos/ponte 5.571). SHA256 instalado: `9615807B1BEA25C0DD4E6DA7DA5C46CD9D61DAD5FACB994DCF8074152F1CBFFF`. Reprodução byte a byte e auditoria da costura: `suit_m_dante_hands_v11_validation.json`; detalhes em `npc-meshy-graft-tool-20261011.md`.

### Regressões do adapter compartilhado

`dotnet build Harbor.csproj` passou, sem avisos/erros. O primeiro lote do runner passou 9/10: admission, guardas da garagem, ponte, country, transição Maciota, acessórios, mecânico, direção e catálogo de pedestres. Este lote exercita os outros corpos e os contratos do mundo com o adapter revisado; antecede a instalação do GLB final do terno.

`test_regions` concluiu suas asserções (`REGIONS PASS failures=0`), mas o runner o reprovou por vazamentos ao encerrar: 2 GodotBody3D e 2 GodotShape3D. A execução dirigida com `GETECO_NO_MESHY_BODIES=1` reproduziu exatamente esses vazamentos. Não atribuir essa falha à nova mão nem declarar a suíte totalmente aprovada. Relatório: `evidence/test-suite/suite-2026-10-11_065428_817-45eb8ada32fe415f9ee62251581cbe0c.json`; controle: `regions-catalog-off.log` na pasta da revisão.

O lote dirigido no GLB V9 passou 7/7: alinhamento de membros, 56 combinações de contato, morte Mixamo, fechamento do combate policial, geometria de equipamentos, catálogo/corpo policial e silhueta/oclusão. Relatório: `evidence/test-suite/suite-2026-10-11_071513_046-fe80728c28fe4f3898311f8066d29494.json`. O maior erro de ponto de palma do terno foi 0,00144 mm, com limite de 30 mm. Isso mede o ponto calibrado no osso, não a distância de cada dedo à superfície da arma. O teste também confirma a liberação da orientação e dos morphs ao morrer.

O teste completo de despacho terminou com as mesmas 10 falhas anteriores de chegada/desembarque, estacionamento e limpeza da equipe. O controle anterior com catálogo desligado também tinha essas 10 falhas; os sistemas de despacho não foram alterados nesta revisão. Relatório atual: `evidence/test-suite/suite-2026-10-11_065959_929-82a7ede784e94155a77b54d33414b9d9.json`. Somando os lotes, 16/18 scripts passaram; não há aprovação global da suíte.

A importação do GLB concluiu sem erro de parse/import, mas o encerramento do editor registrou avisos de recursos/RID e de EditorSettings. Esses avisos estão preservados em `final-import.log`.

No V11, o lote dirigido passou 4/4 (contatos, equipamentos, corpo policial e oclusão). Após ajustar a coronha na corrida, contato e corpo passaram novamente 2/2. Os metadados desses dois lotes avisam alteração do diff global durante a execução; as evidências foram revistas, e a verificação final de contatos foi repetida depois de congelar o runtime. Essa execução passou os 56 casos e a morte, sem alerta de fontes alteradas: `evidence/test-suite/suite-2026-10-11_075339_027-e28abb58def146418ebef787cad490f9.json`. Lotes anteriores: `suite-2026-10-11_074835_029-4bf93a68020a4434af660c25a87f6e63.json` e `suite-2026-10-11_075104_203-cf1beb73236d4a32883fa68299f133e4.json` na mesma pasta.

Main com V11 também passou abertura, caminhada física e encontro com dois policiais usando save isolado e C# nativo; o modo `--probe` conserva VSync/limitador normais do projeto. Há dois policiais no frustum, mas um fica parcialmente encoberto pelo prédio: essa contagem não é uma prova de visibilidade completa. Evidência: `production-main.log` e `production-main/fixture.png`. Esse check não mede FPS. A importação final está em `v11-import.log`, com os mesmos avisos de encerramento do editor descritos acima.

### Primeira comparação de desempenho — V9

Godot 4.7.2 .NET, Forward Mobile/Vulkan, RTX 4060 Laptop, 1280×720. Palco com 24 policiais; valores em ms, todas as rodadas preservadas:

| Rodada | Corpo | p50 | p95 | p99 | Máximo | >33,3 / >66,7 ms |
|---|---|---:|---:|---:|---:|---:|
| 0 | anterior | 2,220 | 3,510 | 6,985 | 41,360 | 3 / 0 |
| 1 | V9 | 2,248 | 2,527 | 2,863 | 7,463 | 0 / 0 |
| 2 | V9 | 2,222 | 2,505 | 2,829 | 7,046 | 0 / 0 |
| 3 | anterior | 2,076 | 2,313 | 2,527 | 7,044 | 0 / 0 |
| 4 | anterior | 2,067 | 2,302 | 2,525 | 6,967 | 0 / 0 |
| 5 | V9 | 2,285 | 2,725 | 3,201 | 9,928 | 0 / 0 |

Medianas por condição: p50 2,076→2,248 (+8,3%), p95 2,313→2,527 (+9,3%), p99 2,527→2,863 (+13,3%). Todas as rodadas marcaram 514 draw calls. O seletor troca os dois GLBs antes de criar cada grupo, mas esta primeira versão não gravava guardas de superfície/perfil por instância; a confirmação acrescenta essas guardas. **Não aprovado** pelo limite de regressão, apesar dos tempos absolutos baixos. Dados e amostras: `perf-palms/`.

Main foi executada com C# nativo ativo, save isolado, caminhada física real e dois PoliceAgent em cena. As guardas confirmaram malha anterior com uma superfície/sem perfil e revisada com duas superfícies/perfil. O A/B completou seis rodadas, mas todas ficaram inválidas para atribuição de custo: a população do mundo variou, de 45 a 56 corpos visíveis, enquanto os dois policiais permaneceram visíveis. Houve picos de streaming tanto no anterior quanto no revisado (máximo de 1.065,426 ms). Esses números **não aprovam nem isolam uma regressão das mãos na cidade**. Dados completos: `perf-game-palms/ab-game.json`, amostras brutas e seis capturas. A chegada nativa pelo despacho permanece fora desta fixture.

### Confirmação final — V11 e runtime congelado

Mesmo ambiente e seis rodadas, agora com guardas para os 24 corpos de cada rodada: anterior sem perfil/uma superfície; V11 com perfil/duas superfícies. Inclui a escala final da arma, a ponte V11 e a redução de operações repetidas do driver. Nenhum outro Godot ou trabalho pesado do agente auxiliar concorreu com a medição.

| Rodada | Corpo | Frames | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms |
|---|---|---:|---:|---:|---:|---:|---:|
| 0 | anterior | 14.329 | 477,65 | 2,047 | 2,339 | 2,735 | 9,101 |
| 1 | V11 | 13.158 | 438,59 | 2,221 | 2,591 | 3,047 | 7,430 |
| 2 | V11 | 11.983 | 399,41 | 2,261 | 3,550 | 7,265 | 16,022 |
| 3 | anterior | 14.292 | 476,40 | 2,055 | 2,320 | 2,660 | 6,991 |
| 4 | anterior | 14.334 | 477,79 | 2,051 | 2,301 | 2,661 | 6,780 |
| 5 | V11 | 13.294 | 443,15 | 2,213 | 2,485 | 2,812 | 7,778 |

Todas as rodadas: 514 draw calls médios, zero frames acima de 33,3/66,7 ms. Medianas por condição: p50 2,051→2,221 (+8,3%), p95 2,320→2,591 (+11,7%), p99 2,661→3,047 (+14,5%). A rodada V11 mais variável foi mantida, sem escolher apenas o melhor resultado. Dados completos e amostras: `perf-palms-final/ab-police-24.json` e `raw-*.json`; guardas em `perf-palms-final.log`.

**Desempenho reprovado pelo limite relativo de 5% no palco de 24 policiais.** O pacote visual novo continua mais caro, apesar de todos os tempos dessa amostra ficarem abaixo da meta absoluta de 16,67 ms. A medição não separou CPU e GPU; o aumento de geometria/morphs é uma hipótese de custo, não um gargalo isolado. Não houve redução de qualidade para esconder o resultado. O A/B da cidade ficou inconclusivo e não foi repetido até conseguir uma amostra verde. A correção visual está instalada; otimização do pacote e comparação integrada com população equivalente permanecem pendentes.

O último teste funcional do runtime final mediu erro máximo de palma do terno de 0,00146 mm (arredondado para cima), bem abaixo de 30 mm. As capturas reais continuam sendo a evidência da forma e do encaixe visível, separadamente desse número.
