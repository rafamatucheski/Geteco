# Bagagem em campo — 28/09/2026

## Regras confirmadas

- Dois bolsos iniciais, mais doze células na mochila (4 × 3). A mala oferece 24 (4 × 6), conforme a capacidade da implementação anterior. Apenas uma bagagem pode estar equipada.
- A mochila inicial é descoberta uma única vez ao abrir o porta-malas da Monaliza conquistada no Primeiro Giro. Não há mochilas/malas gratuitas nas lojas ou na montanha. Saves antigos mantêm sua bagagem e os itens de migração.
- Armas longas **guardadas na grade** ocupam 4 × 1. Armas equipadas no corpo ficam no equipamento; demais armas guardadas ocupam 2 × 1. Arraste posiciona por célula; giro exige um retângulo livre que caiba na grade.
- Até 99 tiros vinculados a cada arma, somando carregador e reserva junto da arma. O carregador mantém o tamanho do catálogo, limitado a 99. A munição adicional usa pilhas de até 99 em células de 1 × 1; comprar sem espaço cancela a transação integralmente.
- A Monaliza pode ser consultada à distância. Todas as mutações pelo adaptador exigem a checagem real de distância, obstrução, velocidade e estado do veículo em `PersonalCar._near_trunk()`. Manter uma tela antiga aberta não preserva o acesso.
- A Monaliza aceita **somente armas e munição**. A grade tem 24 células (4 × 6), com no máximo seis pilhas de munição de até 99 tiros cada, compartilhando esse espaço com as armas. Comida, bebidas, quests, ferramentas e bagagens são recusadas por botões, arraste e regras da economia.
- Comida, bebida e primeiros socorros aplicam cura real antes de descontar o item. Vida cheia não consome. Descrições e marca discreta `(quest)` foram autorizadas pelo usuário para itens.
- A UI fica à direita, sobre o jogo. Trava as ações do jogador, sem pausar a simulação; dano ou transição fecha a bagagem. Tab abre/fecha e Esc fecha. **Soltar mochila/mala** é um botão destacado abaixo da grade; **G funciona somente com o inventário aberto**, sem mudar a lanterna fora dele. Soltar fecha o painel e deixa a bagagem recuperável no mundo.
- Descrições ficam nos tooltips; detalhes e ações aparecem ao selecionar. Clique direito usa consumíveis ou equipa armas. Shift+clique transfere, arraste mostra o encaixe e R gira o item selecionado. A Monaliza remota mantém os controles de transferência bloqueados.
- A bagagem aparece no personagem, move-se das costas para a frente ao abrir e abre a tampa. É uma apresentação procedural do objeto; não uma nova animação esquelética completa de mãos/retirada.
- A mochila padrão é marrom, compacta (corpo de 32 × 36 × 17 cm) e acompanha a coluna por `BoneAttachment3D`, inclusive nas poses de corrida e combate. Ao fechar, retorna ao mesmo encaixe; no chão, as alças ficam recolhidas e a colisão acompanha o tamanho menor. Cores alternativas serão skins de compra futura no shop; a capacidade não depende da aparência.
- Soltar guarda identidade, posição, região, interior e grade inteira. A bagagem no chão tem modelo e corpo de colisão estático, permanece no estado salvo e pode ser recuperada uma única vez. Descarregar a apresentação por distância não apaga seu registro. A mochila preserva os bolsos quando é solta.
- A mala impede equipar/disparar armas longas; o recuo apresentado pelas armas de fogo permitidas é multiplicado por três. As proibições da garagem continuam passando pelo GameState.

## Integração

`GridInventory.gd` é o modelo espacial puro. `Economy.gd` continua sendo dono das compras, munição, inventário e persistência; `grid_inventory` integra o snapshot existente. Não há segundo save.

`FieldInventoryRuntime.gd` liga contexto físico, coleta, cura, bagagem e UI à sessão. `InventoryPanel.gd` especializa a interface base `FieldInventory.gd` sem sobrescrevê-la. `GridBoard.gd` e `GridEntry.gd` implementam apresentação/arraste; cada operação confirma as condições no adaptador, além de desabilitar ações na UI.

`InventoryIcons.gd` reutiliza os ícones de armas do catálogo visual existente e remove margens transparentes para preencher a área da arma. Os demais ícones são SVGs rasterizados uma vez e reutilizados. Sem SubViewport por item e sem reconstrução por frame.

As operações da grade trabalham em uma cópia e só publicam o resultado quando toda a movimentação cabe. A restauração verifica sobreposição, limites, pilhas, propriedade única das armas e correspondência com as quantidades da economia. Campos inteiros são normalizados após JSON.

`InventoryMigration.gd` converte a grade antiga de 10 mil células para a versão 2. Itens incompatíveis com o porta-malas vão para bolsos/mochila; excedentes legítimos ficam em malas recuperáveis, posicionadas junto ao jogador em solo livre. A migração preserva dinheiro, missões, recibos e propriedade das armas.

O estoque antigo de cheat é identificado pelo arsenal completo e pelo menos seis armas com 9 mil tiros ou mais. Somente nesse padrão a reserva sintética é removida; munição registrada em recibos de compra é preservada. Quantidades grandes isoladas não acionam essa limpeza. A migração é idempotente e ocorre ao restaurar/carregar; o save corrigido é publicado pelo fluxo normal, sem apagar o arquivo pessoal externamente.

Armas, munição e seleção do cheat agora vivem fora de `_data`; ativá-lo, disparar e recarregar não alteram o snapshot. Recompensas e compras legítimas continuam persistindo. O cheat não oferece acesso remoto ao estoque real da Monaliza.

## Coletáveis colocados no mundo

Os pontos ficam nos acessos exteriores e se baseiam nas coordenadas do catálogo de lugares, com admissão por consulta física ao solo. São encontrados e recolhidos com a interação normal do jogo. A marca de coleta persiste, evitando duplicação ao retornar.

| Lugar | Item |
|---|---|
| Fuel, Harbor | Água e sanduíche |
| Bay Medical, Harbor | Maçã |
| Union, Harbor | Mochila |
| Ammu-Nation, Harbor | Mala de mão |
| Chalé dos Pinhais | Maçã |
| Summit | Água |
| Último Abrigo | Mochila |

Esses oito pontos não representam uma distribuição completa por todas as lojas/casas. Não foram adicionados fome/sede, restock, animações de alimentação nem menus de venda de alimentos; o pedido de comer/encontrar está integrado como coleta e recuperação de vida.

## Validação e evidências

- `tests/test_inventory_grid.gd`: grade, capacidade, pilhas, movimentação atômica, consumo, propriedade, compras, migração, save, exclusividade da bagagem e restrições da garagem.
- `tests/test_inventory_field.gd`: Main real, coleta no mundo, UI compacta, cura, acesso remoto/físico à Monaliza, perda de acesso com tela aberta, drop/recuperação, snapshot completo e garagem.
- Regressões executadas de economia/campanha, save completo, recompensas da garagem, restauração do motorista e transferência física de veículo.
- `tests/measure/measure_inventory_grid.gd`: Main renderizada, oito segundos de aquecimento e pelo menos trinta segundos por cenário (UI fechada/aberta). Baseline e resultado em `evidence/inventory-grid-20260928/`.
- Protótipo HTML no mesmo arquivo de visualização da conversa, com 20 verificações de navegador aprovadas após a revisão da Monaliza e do drop.

O comparativo de desempenho é diagnóstico: havia outras instâncias de Godot e alterações concorrentes em polícia/tráfego durante a medição. Erros transitórios de compilação em scripts da polícia também aparecem em parte dos logs. Não interpretar capturas ou resultados headless como aprovação de FPS. O estado final das execuções está em `evidence/inventory-grid-20260928/validation.md`.

### Refinamento da mochila

`tests/test_backpack_visual.gd`: 15 condições aprovadas de vínculo ao esqueleto real, caminhada, corrida, postura armada, abertura/fechamento, drop aberto e limpeza/recriação do encaixe. Capturas de costas/lateral das poses em `evidence/backpack-subtle-20260928/`. Essas capturas isoladas não medem desempenho.

`tests/test_inventory_field.gd`: 30 condições aprovadas na Main renderizada após o ajuste final, incluindo colisão e recuperação. A execução headless intermediária passou nas condições funcionais, mas falhou nas duas verificações de layout por não fornecer o viewport esperado; ambas passaram na janela real de 1280 × 720, sem alterar as expectativas.

Comparação na Main renderizada, RTX 4060 Laptop, Vulkan Mobile, 1280 × 720, VSync desligado e limite 144 FPS; oito segundos de aquecimento e trinta segundos por cenário. Amostras em `evidence/inventory-grid-20260928/backpack-before/` e `backpack-after/`:

| Cenário | FPS antes → depois | p95 ms antes → depois | p99 ms antes → depois |
|---|---|---|---|
| UI fechada | 62,50 → 70,36 | 29,144 → 19,409 | 33,428 → 29,072 |
| UI aberta | 36,77 → 38,66 | 48,178 → 35,146 | 73,013 → 138,576 |

**Desempenho pendente:** outras instâncias de Godot e trabalho concorrente impedem atribuir a variação à mochila. A UI aberta segue abaixo do alvo provisório de 60 FPS e o p99 piorou; a melhora da média não aprova o resultado. Necessária comparação isolada para confirmar a origem dos picos. As execuções renderizadas também reportam avisos de textura/RID no encerramento, já observados antes desta mudança.

### Revisão da Monaliza e interface

Estado final: `test_inventory_limits.gd` passou em 30 condições, `test_inventory_panel.gd` em 11, `test_inventory_field.gd` em 39 na Main renderizada e `test_inventory_migration_world.gd` nas seis condições de preservação/colocação/recuperação física. A regressão da grade passou em 36 condições, campanha/economia em 162, e o save completo passou. O teste de painel usa um adaptador de apresentação; os 39 checks de campo e a recuperação da migração usam a sessão real.

As capturas do novo painel estão em `evidence/inventory-ux-20260928/`; as integradas na cidade, em `evidence/inventory-grid-20260928/review/`. Erros transitórios em scripts de veículos/motocross impediram as primeiras execuções integradas enquanto outras sessões escreviam arquivos. As execuções finais de campo e migração passaram depois que essas dependências voltaram a compilar. Permanecem avisos preexistentes de liberação de textura/RID no encerramento.

Novo comparativo diagnóstico: RTX 4060 Laptop, Vulkan Mobile, **1920 × 1080 efetivos** (configuração carregada do usuário), VSync 0, limite 144, oito segundos de aquecimento e trinta por cenário. Dados brutos em `evidence/inventory-grid-20260928/ux-before/` e `ux-after/`.

| Cenário | FPS antes → depois | p95 ms antes → depois | p99 ms antes → depois |
|---|---|---|---|
| UI fechada | 12,40 → 36,02 | 160,979 → 51,550 | 186,345 → 66,059 |
| UI aberta | 18,84 → 23,64 | 103,325 → 79,466 | 141,091 → 91,865 |

**FPS não aprovado:** carga externa e alterações concorrentes variaram, com múltiplas instâncias Godot ativas. A base já apresentou 12–15 FPS e o resultado continua abaixo de 60. Esses números não permitem atribuir a melhora à UI nem comprovar ausência de regressão. Não foi encerrada nenhuma sessão alheia para obter uma medição melhor.
