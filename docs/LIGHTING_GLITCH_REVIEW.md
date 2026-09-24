# Revisão de glitches visuais — V2 nativo 3D

Revisão do vídeo de 22/09: [calçadas e integração dos quatro sintomas](SIDEWALK_GLITCH_REVIEW_2026-09-22.md).
O gerador de acabamentos agora elimina faces coplanares sobrepostas. Há evidência
visual localizada; performance, combate integrado e vídeo final seguem pendentes.

Atualização de 22/09: a [migração de atmosfera](regional-atmosphere-migration.md)
substituiu a elevação noturna de −15° por um arco de 42°–70°. A comparação de
rua às 20:09 mostra sombras mais curtas; não houve correção de geometria nesta
tarefa. Os achados e capturas de 21/09 abaixo permanecem como histórico.

Data: 21/09/2026  
Projeto: `geteco_v2`  
Renderer: Forward Mobile / Vulkan  
GPU observada: NVIDIA GeForce RTX 4060 Laptop GPU  
Saída: 1280×720, MSAA 2×, câmera ortográfica

## Resultado executivo

Foi reproduzido **um defeito visual confirmado** na transição Harbor → serra: uma cunha clara de concreto fica exposta entre as duas faixas de asfalto na junção da ponte. O defeito parece uma mudança de luz à distância, mas permanece com câmera parada, movimento, zoom, rotação, dia e noite. As duas regiões estavam carregadas com 9 chunks cada e zero pendências; portanto, não é desaparecimento por streaming ou recorte.

Não foi reproduzido z-fighting, vazamento de luz, normal invertida ou sombra que aparece/desaparece nos pontos amostrados da garagem, ruas próximas e porto. As grandes faixas diagonais noturnas são sombras reais, estáveis, produzidas pelo direcional ainda ativo a apenas 15° no período noturno. Elas podem explicar parte da percepção de “glitch de luz”, mas nesta rodada não piscaram nem desapareceram.

Nenhuma correção visual foi aplicada por esta frente. A única causa confirmada exige alteração em geometria compartilhada reservada à equipe de terreno/streaming. Não foi criado controlador paralelo, não foram desligadas sombras, a luz ambiente não foi aumentada e nenhum cenário foi removido.

## Método reproduzível

O roteiro `tests/capture/capture_lighting_glitches.gd` instancia `Main.tscn` com `--no-save`, tempo limpo, população e tráfego desativados para isolar o cenário. Para cada local, registra duas imagens paradas, uma durante a interpolação da câmera, outra após estabilizar, zoom próximo, zoom distante e rotação de 90°. Repete em dia (`time_of_day = 0.36`, aproximadamente 08:38) e noite (`0.84`, aproximadamente 20:10).

| Local | Posição inicial → final (m) | Câmera | Condição de carga |
|---|---|---|---|
| Garagem exterior | `(46.875, 0.04, 105.2375)` → `(49.375, 0.04, 105.2375)` | rumo 0°, ortho 16/28/46 | Harbor: 9 chunks, 0 pendentes |
| Ruas próximas | `(77.875, 0.04, 96.2375)` → `(81.875, 0.04, 96.2375)` | rumo −22,5°, ortho 16/28/46 | Harbor: 12 chunks, 0 pendentes |
| Porto sul | `(243.75, −0.009, 237.5)` → `(248.75, −0.009, 237.5)` | rumo 22,5°, ortho 16/28/46 | Harbor: 12 chunks, 0 pendentes |
| Transição para a serra | `(452.0, 0.036, −285.0)` → `(460.5, 0.040, −285.0)` | rumo −90°, ortho 16/28/46 | Harbor + Mountain: 9+9 chunks, 0 pendentes; conexão ativa |

Relatórios brutos:

- `evidence/lighting_glitch_review/capture-report.json`: rodada completa.
- `evidence/lighting_glitch_review-current2/capture-report.json`: rechecagem isolada e válida da transição após a alteração concorrente de 17:33.

Uma rodada intermediária em `lighting_glitch_review-current` foi descartada: o salto direto da garagem fotografou o primeiro quadro antes de a câmera e os chunks chegarem à ponte. O harness passou a aguardar `pending_chunks = 0` e registrar a posição real; essa rodada inválida não sustenta nenhuma conclusão.

## Classificação por local

### Garagem exterior

- **Superfícies sobrepostas piscando:** não reproduzido. Duas capturas paradas de dia e duas à noite foram idênticas na amostragem.
- **Sombras que mudam ou desaparecem:** não reproduzido. As sombras acompanharam a geometria em movimento, zoom e rotação sem sumiço abrupto.
- **Luz atravessando sólidos:** não reproduzido. A abertura da baia é vazada por autoria; paredes e prédio vizinho conservaram sombra/oclusão coerentes.
- **Materiais/normais incorretos:** não reproduzido no telhado, fachada, pátio, carro ou mobiliário exterior.
- **Geometria desaparecendo por streaming/recorte:** não reproduzido; 9 chunks residentes e zero pendentes.

Exemplos:

![Garagem exterior de dia](../evidence/lighting_glitch_review/garage_exterior-day-still-a.png)

![Garagem exterior à noite](../evidence/lighting_glitch_review/garage_exterior-night-still-a.png)

### Ruas próximas

- **Superfícies sobrepostas piscando:** não reproduzido nas pistas, linhas e calçadas do cruzamento.
- **Sombras que mudam ou desaparecem:** não reproduzido. As bandas noturnas permaneceram estáveis com a câmera parada; são sombras longas de volumes altos, não flicker.
- **Luz atravessando sólidos:** não reproduzido nos edifícios enquadrados.
- **Materiais/normais incorretos:** não reproduzido.
- **Geometria desaparecendo por streaming/recorte:** não reproduzido em ortho 46 nem após rotação; 12 chunks residentes e zero pendentes.

Exemplos:

![Ruas próximas de dia](../evidence/lighting_glitch_review/nearby_streets-day-still-a.png)

![Ruas próximas à noite](../evidence/lighting_glitch_review/nearby_streets-night-still-a.png)

### Porto sul

- **Superfícies sobrepostas piscando:** não reproduzido no pátio, vias ou contêineres enquadrados.
- **Sombras que mudam ou desaparecem:** não reproduzido.
- **Luz atravessando sólidos:** não reproduzido nos contêineres.
- **Materiais/normais incorretos:** não reproduzido; corrugação e faces mantiveram leitura consistente após rotação.
- **Geometria desaparecendo por streaming/recorte:** não reproduzido; 12 chunks residentes e zero pendentes.

Entre as duas imagens paradas diurnas, 78 de 57.600 amostras mudaram (`0,1354%`). A diferença fica no trabalhador animado visível à esquerda de Dante. À noite, a diferença parada foi zero. Isso não constitui flicker de superfície.

Exemplos:

![Porto de dia](../evidence/lighting_glitch_review/south_port-day-still-a.png)

![Porto após rotação](../evidence/lighting_glitch_review/south_port-day-rotated.png)

### Transição Harbor → serra

- **Superfícies sobrepostas piscando:** não reproduzido; a cunha não pisca, é estática.
- **Sombras que mudam ou desaparecem:** não reproduzido.
- **Luz atravessando sólidos:** não reproduzido.
- **Materiais/normais incorretos:** não é a causa. A cor clara é o material correto do tabuleiro de concreto aparecendo onde falta asfalto.
- **Geometria desaparecendo por streaming/recorte:** **descartado como causa**. O defeito permanece com Harbor e Mountain residentes, conexão ativa, 9 chunks em cada região e zero pendentes.
- **Geometria ausente na junção:** **glitch reproduzido e causa confirmada**.

Antes da alteração concorrente no grafo de tráfego:

![Cunha exposta antes da alteração concorrente](../evidence/lighting_glitch_review/mountain_transition-day-still-a.png)

Rechecagem do estado atual, depois da alteração concorrente:

![Cunha ainda exposta após a alteração concorrente](../evidence/lighting_glitch_review-current2/mountain_transition-day-still-a.png)

Rotação de 90° confirma que a superfície clara pertence à junção física das pistas, e não a uma mancha de iluminação:

![Junção vista após rotação](../evidence/lighting_glitch_review-current2/mountain_transition-day-rotated.png)

## Causas e encaminhamentos

### 1. Responsável por terreno/streaming — superfície da ponte

**Estado:** causa confirmada; correção não aplicada nesta frente por propriedade de arquivo.

- Arquivos/funções: `world/regions/WorldConnection3D.gd::traffic_connectors`, `WorldConnection3D.gd::_build_bridge` e `world/regions/NativeRegion.gd::_build_chunk` no caso `"road"`.
- Evidência visual: imagens `mountain_transition-*` acima.
- Causa demonstrada: os corredores `mountain_bridge_outbound` e `mountain_bridge_inbound` chegam separados ao seam com 3,875 m cada. `traffic_connectors()` agora os conduz a `TRAFFIC_MERGE_X`, mas retorna apenas dados para o grafo de tráfego. `_build_bridge()` cria o tabuleiro claro (`HarborConnectorDeck` / `ContinuousBridgeDeck`) e não cria a pele de asfalto da fusão. O renderer regional cria caixas de asfalto somente para os records `"road"`. Assim, o concreto fica exposto como cunha entre as duas fitas de asfalto.
- Alteração proposta: fazer o proprietário da ponte criar uma única superfície de asfalto triangulada/quadrangulada, contínua e elevada ao mesmo topo `y = 0.05` das pistas, ligando os endpoints das duas faixas ao trecho único depois de `TRAFFIC_MERGE_X`. Usar o mesmo acabamento de asfalto; preservar o tabuleiro estrutural e as barreiras. Se a junção também receber colisão, ela deve integrar o sólido já existente sem duplicar faces coplanares.
- Validação exata: iniciar em `(452, −285)`, caminhar até `(460.5, −285)` com rumo −90°; repetir ortho 16/28/46 e rotação para 0°, em `time_of_day 0.36` e `0.84`; exigir Harbor + Mountain 9/9 chunks, zero pendentes, conexão ativa e nenhuma cunha clara ou costura piscando.

Observação de concorrência: `WorldConnection3D.gd` e `NativeRegion.gd` foram alterados por outra frente às 17:33:26 durante esta revisão. A rechecagem `current2` usa o estado posterior e demonstra que a alteração de conectividade ainda não corrige a superfície visual.

### 2. Responsável por iluminação central — sombras noturnas muito longas

**Estado:** aparência reproduzida e causa confirmada; não foi demonstrado flicker/desaparecimento, portanto é proposta visual, não correção aprovada.

- Arquivos/funções: `runtime/ProductionWorld.gd::build` cria o direcional com sombra e alcance 110 m; `runtime/Weather.gd::_update` mantém a mesma luz ativa à noite e define rotação X como `−15°` quando `daylight = 0`, energia `0.12` e ambiente `0.32`.
- Evidência visual: `garage_exterior-night-*`, `nearby_streets-night-*` e `south_port-night-*` mostram grandes polígonos diagonais estáveis.
- Causa demonstrada: o ângulo noturno baixo alonga sombras de prédios e postes por grande parte do quadro. As duas capturas paradas foram estáveis; não há evidência de instabilidade do shadow map nesta rodada.
- Alteração proposta, se a direção visual considerar essas bandas um defeito: manter sombras, mas separar a elevação noturna da solar (ou usar uma direção de lua mais alta), sem aumentar a luz ambiente e sem desligar sombras globalmente. Confirmar que a mudança não achata o volume diurno nem remove leitura de obstáculos.
- Validação exata: garagem `(46.875, 105.2375)`, rua `(77.875, 96.2375)` e porto `(243.75, 237.5)`, noite `0.84`, ortho 16/28/46, rumos original +90°, câmera parada e deslocamento de 4–5 m; conferir também dia `0.36` para regressão.

### 3. Porto — hipótese estática não promovida a defeito

`OriginalSouthPort.gd::extra_surfaces` e `NativeRegion.gd::_authored_surface` criam superfícies autoradas em `y = 0`, enquanto o topo de `Land` também fica em `y = 0`. Há interseções de borda entre `WALKWAY`/acesso e `LAND` nos dados de `OriginalSouthPortLayout.gd`. Isso é risco de coplanaridade, porém **não houve flicker visual no ponto solicitado do porto**. Não alterar sem uma reprodução localizada na passarela/quebra-mar; uma hipótese de código não substitui evidência renderizada.

## Correções aplicadas

- Adicionado `tests/capture/capture_lighting_glitches.gd`, harness sem save para repetir as condições acima e registrar carga regional/câmera.
- Corrigida a espera do próprio harness após um salto diagnóstico: agora ele só fotografa depois de todos os chunks residentes chegarem a zero pendências e registra a posição real do jogador.
- Nenhum arquivo de runtime, material ou shader foi alterado. Nenhuma causa demonstrada pertence a material/shader exclusivo disponível para esta frente.

## Validação e limites

- Captura final concluída com código de saída 0 no Godot 4.7.2, Forward Mobile/Vulkan.
- Rodada completa: garagem, ruas, porto e transição; dia/noite; parada/movimento; zoom próximo/distante; rotação.
- Rechecagem `current2`: transição atual com duas regiões, 18 chunks residentes no total e zero pendentes.
- Não foram alterados saves ou configurações persistentes.
- Não foi executado benchmark: havia sessões Godot de outras equipes. Estas imagens validam conteúdo visual, não FPS nem regressão de frame time. Desempenho permanece **não medido nesta revisão**.
- A sessão renderizada concorrente pode afetar tempo de captura, mas não foi usado nenhum tempo de frame como evidência. As conclusões usam imagens, estado de chunks e repetibilidade espacial.
