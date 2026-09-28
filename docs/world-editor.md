# Editor do mundo Geteco

Abra `D:/geteco/game/project.godot` no Godot e clique na aba **Mundo**, ao lado de 2D/3D/Script. O plugin já está habilitado. Se o projeto já estava aberto, reabra-o ou ative **Mundo Geteco** em Projeto → Configurações do projeto → Plugins.

## Prédios com serviços — 26/09

Delegacia, hospital, bombeiros, banco, Ammu-Nation, loja Union, Fuel e residencial Canal North permitem mover, girar, ampliar largura/profundidade/altura e trocar a cor da fachada. O modelo original, serviço e interior permanecem associados ao mesmo ID; duplicar, excluir ou trocar por um modelo genérico permanece indisponível. As dimensões vão do tamanho original até três vezes esse tamanho, dentro do limite de 40 m, mantendo espaço mínimo das portas. Entradas, retornos, indicadores do editor e vagas funcionais da polícia acompanham a transformação. A edição não refaz o interior nem move automaticamente toda a decoração independente da quadra.

Maciota e Northgate Auto continuam protegidas. A integração de transformação/entrada da garagem do Maciota foi bloqueada pela revisão automática; nenhum código de `MaciotaPlace.gd` foi alterado nesta tarefa.

A prévia passa a consumir cada resposta uma única vez. Antes, uma edição durante o carregamento podia descartar o snapshot, apagar seu arquivo e depois solicitar o mesmo `.scn` durante o intervalo de debounce. `test_world_editor_live_preview.gd --supersede-loading` passou em 27 verificações, incluindo essa sequência com carregamento real.

Comparação em Main renderizado, delegacia original versus movida 2 m, ampliada 20% em planta e 25% em altura: Mobile/RTX 4060 Laptop, 1280×720, limite 144 FPS, oito segundos de aquecimento e 30 segundos medidos. Original/editada: 143,82/143,94 FPS, p95 11,639/11,479 ms, p99 13,083/13,314 ms, máximos 19,856/17,314 ms; nenhuma amostra estável acima de 33,3 ms. É comparação dos cenários original/editado na implementação atual, não um benchmark do código anterior à tarefa nem aprovação de qualquer tamanho/posição. JSONs completos e capturas: `evidence/service-editor-20260926/{before,after}/performance.json`.

Validação dirigida: `test_world_editor_service_controls.gd` passou em 46 verificações headless e 47 com prévia renderizada; inclui rejeitar uma entrada sobre outro acesso. `test_service_facade_physics.gd` passou em 32 verificações das oito fachadas, cor, cápsula completa na entrada e corpos rígidos após abrir portas ampliadas e giradas. `test_world_editor_service_buildings.gd` validou a delegacia movida/ampliada no jogo real e uma variante girada em local livre: porta fechada/aberta, entrada a pé, câmera, NPCs, spawn livre, saída, retorno e liberação de controle. O teste usa direção automática no corpo real para não depender do mapeamento diagonal da câmera atual. A regressão `test_world_editor_piece_shapes.gd` passou em 23 verificações. Capturas em `evidence/service-editor-20260926/`; `editor.png` mostra os controles e a fachada alterada. Permanecem os avisos de liberação de recursos no encerramento do motor, também presentes nas execuções anteriores.

1. Use **Mundo inteiro**, **Harbor**, **Montanha** ou **Ir para local…**. Cemitério, ferro-velho, lagos, porto, navios, teleférico, vilarejo e madeireira estão no catálogo.
2. Roda do mouse aproxima/afasta; botão direito arrastado navega.
3. Na **Biblioteca de assets**, pesquise por nome (prédio, pallet, lixo, Neko, Cobra), filtre a categoria e dê duplo clique no modelo; depois clique no mapa. Prédios e objetos têm miniaturas reais. Há 11 presets de prédios em seis famílias, nove presets de objetos em oito modelos, árvores, ruas e luzes. A região de uma colocação nova é determinada pela posição. O menu **Adicionar** oferece atalhos para árvore, prédio, rua e luz.
4. Selecione um objeto: as setas **X (vermelha)** e **Z (azul)** movem em um eixo por vez; o **anel verde Y** gira sobre o chão. Segure **Shift** para girar em passos de 15°. A grade controla o encaixe de posição. **Esc** cancela o arraste; soltar confirma uma única ação de desfazer. As peças mostram a prévia durante a transformação. Na lateral continuam os campos numéricos de posição, rotação, dimensões, variante e luz. Em ruas, as setas movem o traçado inteiro, o anel gira ao redor do centro e os pontos amarelos continuam editáveis separadamente.
5. **Salvar mundo**, no botão verde fixo no canto superior direito, ou Ctrl+S grava mudanças reais. Elas entram na próxima execução do jogo, inclusive na geometria, colisões e rede de ruas usada pelo tráfego. Não é necessário criar um novo save; é necessário reiniciar a execução para recarregar a geografia.
6. **2D + 3D** mantém o mapa e a visão 3D lado a lado, atualizando as alterações não salvas automaticamente. No painel: botão direito gira, botão do meio move e roda controla o zoom. **Prévia 3D** continua abrindo a cena real em uma janela separada; nela, setas movem a câmera e Esc fecha. As prévias não gravam progresso.

**Ctrl+C / Ctrl+V:** com o mapa em foco, selecione um objeto, copie, cole e clique no destino. Cada cópia recebe uma identidade própria e preserva modelo, cor, escala, rotação e o formato de ruas. Pode colar em outra região. Esc cancela a colocação. Enquanto a busca ou um campo de texto está em foco, os atalhos de texto continuam funcionando. Peças específicas existentes podem ser movidas e redimensionadas; para criar novas peças use os modelos da biblioteca.

Desfazer/refazer têm botões; Ctrl+Z/Ctrl+Shift+Z funcionam com o mapa em foco. Delete exclui o selecionado. **Excluídos** restaura itens apagados; **Restaurar original** remove a alteração do selecionado. Um rascunho recuperável fica em `.godot/`, separado do arquivo aplicado ao jogo.

## Espaço de trabalho

### Visão 2D + 3D lado a lado

Correção do seletor de cor: a aplicação é adiada até terminar o evento nativo de fechamento do popup. Antes, esse evento removia o próprio controle ao reconstruir as propriedades. A alteração agora captura a identidade e região do objeto, preserva uma seleção posterior e ignora eventos obsoletos após exclusão ou outra alteração de cor. `tests/test_world_editor_color.gd -- --no-save --live`: **15 checks aprovados**, com criação de casa, seletor real aberto/fechado repetidamente, cor na prévia 3D, troca de seleção, exclusão, desfazer/refazer e salvamento isolado. O teste reproduziu a remoção prematura do controle antes da correção. Os erros de carregamento de `Vehicle.gd` mostrados pelo scanner não ocorreram na execução direta de `tests/test_traffic_headlights.gd`: **45 checks aprovados**; o arquivo também consta no índice atual do editor. Isso não estabelece esses erros do scanner como causa do crash relatado.

Ative **2D + 3D** na barra do editor. O mapa continua editável à esquerda e a geometria real da região aparece à direita, incluindo alterações ainda não salvas. Ao soltar um objeto, mudar uma propriedade, adicionar/excluir algo ou desfazer/refazer, a visão atualiza automaticamente após uma espera curta que agrupa as edições. A reconstrução pode levar alguns segundos; a imagem anterior permanece disponível até a nova ficar pronta. O botão desativa o painel e encerra seu processo auxiliar.

Selecionar outro objeto foca sua posição. Em Harbor, focos próximos usam imediatamente a região já carregada. **Focar seleção** volta ao selecionado (ou ao centro do mapa, sem seleção); **Recentrar** restaura o ângulo e o zoom. No painel 3D: botão direito arrastado gira, botão do meio arrastado move e roda aproxima/afasta. Ao terminar de mover a câmera, o mapa acompanha sua posição e a área necessária é atualizada. Use a divisória para ajustar os tamanhos e **Ampliar mapa** para ganhar espaço. Em áreas muito estreitas, as laterais são recolhidas para manter as duas visões utilizáveis.

A prévia é de posicionamento, com iluminação diurna fixa e sem simulação de partidas, NPCs ou trânsito. Um processo auxiliar persistente gera a geometria de `EditableRegion`; a aba renderiza uma cópia sem scripts de gameplay e sem colisões ativas num SubViewport próprio. Não é necessário abrir outra janela nem salvar o mapa. A renderização é suspensa quando não há mudança e ao sair da aba. O gerador reutiliza o processo, mas reconstrói a área ao mudar a geografia; os snapshots temporários consumidos são removidos. Ao fechar, o viewport é liberado imediatamente; uma leitura de recurso já iniciada é coletada antes de descartar o painel. O teste adicional `--close-loading` passou em **26 checks**, incluindo fechar durante uma atualização. A checagem na aba nativa passou em **7 checks**. A janela **Prévia 3D** anterior continua disponível.

Validação: `tests/test_world_editor_live_preview.gd -- --no-save --mountain` passou em **28 verificações**, com objeto não salvo, movimento, desfazer, foco imediato, câmera, três tamanhos de janela, troca para a montanha, altura do terreno, conteúdo sem scripts/colisões ativas, preservação do mapa oficial e encerramento do auxiliar. `tests/test_world_editor_live_host.gd` verifica a aba nativa do Godot, ocultação/retorno e fechamento. Regressões: layout **100 checks** e conexões **31 checks** aprovados. Capturas: `evidence/world-editor-live.png`, `world-editor-live-mountain.png` e `world-editor-live-host.png`.

Medição do **editor com câmera parada**, Godot 4.7.2 Mobile, RTX 4060 Laptop, janela solicitada 1440×900, VSync/limite 60, 8 s de aquecimento e 30 s de amostras: antes 60,00 FPS, p95 16,700 ms, p99 16,812 ms; painel 3D aberto 60,00 FPS, p95 16,695 ms, p99 16,764 ms. Sem frames acima de 33,3 ms nas duas amostras. Resultados em `evidence/world-editor-live-before.json` e `world-editor-live-after.json`. Não houve regressão observada no editor parado; isso não mede fluidez durante reconstruções, arrastes da câmera ou gameplay. A geração observada das áreas ficou entre aproximadamente 1,3 e 5 s, além do carregamento/renderização na aba. O runtime do jogo não foi alterado. Os avisos conhecidos de texturas/RIDs no encerramento permanecem; o scanner do editor também aponta erros de scripts de testes fora desta alteração.

### Conectar ruas e controlar a rotação

### Calçadas, pisos existentes e faixas

Em Harbor, selecione uma rua para ajustar **Calçada (m)**, ativar/desativar **Faixas de pedestres**, **Afastar faixas (m)** e **Profundidade faixa (m)**. Esses ajustes se aplicam às travessias daquela rua e preservam os eixos/IDs usados pelos carros. A faixa acompanha a direção local da via; as linhas de parada ocupam somente a mão de aproximação, fora da travessia. A linha amarela não atravessa a faixa.

O mapa 2D mostra as bordas de calçada, os pisos existentes e as zebras. Use o filtro **Pisos e calçadas** para selecionar áreas pavimentadas sob árvores/prédios. Os pisos existentes permitem mover com X/Z, redimensionar, trocar acabamento/cor, excluir e restaurar; mantêm formato retangular, sem rotação ou edição de vértices. Terrenos novos mantêm os controles de contorno anteriores. A edição substitui a superfície original, mantém a ordem das camadas e preserva a abertura do esgoto. Todos os ajustes participam de desfazer/refazer, rascunho, Salvar mundo e prévia ao vivo.

Validação de 26/09: `test_world_editor_paving.gd` passou em 23 verificações de controles, geometria, persistência, aplicação em produção e prévia; `test_world_editor_connections.gd` passou em 31 verificações; `test_harbor_road_fidelity.gd` e `test_sidewalk_surface_coverage.gd` passaram sem falhas, incluindo continuidade física e ausência de sobreposição coplanar dos pisos. Captura: `evidence/world-editor-paving.png`. A integração nativa `test_world_editor_live_host.gd` passou nas sete verificações. O scanner do editor ainda registrou erros de referências em testes alheios (`test_modal_ui_accept_independent`, `test_motorcycle_handlebar_pose`, `test_video_phase4_muzzle`); não são aprovação desses testes e não foram alterados nesta tarefa. Log em `evidence/sidewalk-editor-20260926/native-editor.log`.

Comparação renderizada em Main/Market St, Mobile/RTX 4060 Laptop, 1280×720, VSync desligado, limite 144 FPS, oito segundos de aquecimento e 30 segundos de amostra: antes/depois 134,35/131,29 FPS, p95 12,864/13,125 ms e p99 14,133/14,515 ms. Máximos 34,296/37,548 ms; frames acima de 33,3 ms: 1/2; acima de 66,7 ms: 0/0. Variação de p95/p99 abaixo de 5% neste cenário; não certifica edição contínua ou configurações arbitrárias de mundo. O relatório registra 40 pessoas e zero filhos no nó de tráfego, portanto não comprova carga com carros ativos. Amostras e capturas em `evidence/sidewalk-editor-20260926/{before,after}/`. Avisos de liberação de texturas no encerramento também ocorreram na base.

### Encontros e continuação das ruas

O mapa desenha a rede inteira em camadas comuns de borda e asfalto. Encontros em T, X e diagonais têm cantos arredondados e faixas centrais interrompidas no cruzamento, sem uma borda atravessando a outra rua. Uma avenida pode ter vários encontros ao longo do mesmo traçado; seus pontos, identidade e possibilidades de seguir reto ou virar permanecem intactos. A geometria de apresentação é recalculada somente quando o conjunto de ruas visíveis muda; pan, zoom e seleção reaproveitam o resultado. Ruas fechadas preservam as ilhas centrais.

Validação do acabamento: `tests/test_world_editor_junction_drawing.gd` passou em **474 verificações**, incluindo o catálogo completo, três conexões na mesma avenida, rotas reais para seguir reto e virar em cada saída, geometria de Harbor existente, cache, ilha de rua fechada e pixels dos encontros renderizados. A regressão de conexões é coberta por `tests/test_world_editor_connections.gd`. Captura: `evidence/world-editor-junctions.png`. A alteração é exclusiva da apresentação do editor; o runtime de Harbor já usa camadas comuns e recuo das faixas nos encontros. Não houve mudança de malhas, colisões, rotas ou custo por frame no jogo, nem edição do mapa oficial. Os avisos conhecidos de texturas/RIDs no encerramento renderizado persistem.

Arraste uma ponta perto de outra rua: **Encaixar ruas**, ligado por padrão em **Opções**, projeta a ponta no eixo da outra via, mesmo com a grade ligada. Pontas verdes indicam encontro geométrico entre ruas com largura mínima de 5 m; pontas laranja indicam ausência desse encontro. Caminhos de pedestres e vias estreitas não recebem indicação de conexão de tráfego. O indicador não certifica acesso físico livre nem circulação em toda a rede.

Selecione a ponta e use **Continuar rua**, depois clique no destino; Esc cancela. **Criar retorno**, disponível em pontas livres de ruas de tráfego, acrescenta um circuito que reencontra o trecho de chegada antes da ponta. A rua original conserva sua identidade. Confira espaço disponível, obstáculos e circulação na prévia e no jogo: o circuito usa a seleção de rotas existente, sem reprogramar todos os carros para passar por ele. As ações aceitam desfazer/refazer e Salvar mundo; reinicie a execução para recarregar a rede.

O botão **Girar**, ao lado de Selecionar, ativa/desativa o círculo verde. Começa desligado; desligado, o anel não aparece nem captura cliques. Os campos numéricos de rotação continuam disponíveis.

Validação: `tests/test_world_editor_connections.gd`, **31 verificações aprovadas** em execução renderizada Mobile, incluindo conexão em T no grafo real, circuito fechado incluindo o trecho final, persistência, desfazer/refazer, cancelamento, vias estreitas/pedestres e ativação/rotação/desativação do anel. `tests/test_world_editor_layout.gd`: **95 verificações aprovadas**, de 640×480 a 1920×1080. Captura: `evidence/world-editor-connections.png`. A suíte anterior de gizmos ficou bloqueada pela ausência de `piece/neco/Office` no catálogo disponível. O encerramento renderizado ainda emite os avisos de texturas/RIDs documentados anteriormente. Mudanças restritas ao plugin e testes: nenhum traçado foi gravado no mundo oficial nem houve alteração do runtime de tráfego. Não foi medido FPS de gameplay com novos circuitos autorados.

A barra superior mantém **Salvar mundo** visível. **Assets** e **Propriedades** recolhem ou abrem suas laterais. Sem seleção, as propriedades ficam ocultas; selecionar um objeto mostra os campos, exceto se você recolheu esse painel manualmente. Em áreas com menos de 1100 pixels de largura, aparece uma lateral por vez. As ações se distribuem em mais linhas quando necessário.

**Ampliar mapa** recolhe as duas laterais e os painéis externos do Godot. **Restaurar painéis** recupera a configuração anterior; sair da aba Mundo também restaura o modo anterior do Godot. A posição e o zoom do mapa são preservados. **Opções** reúne grade de 1 m, colocação livre, retorno ao início e atualização da base.

## Terrenos e pisos

Na biblioteca, escolha **Terrenos e pisos** ou pesquise por grama, terra, areia, cascalho, concreto, asfalto ou piso de blocos. Dê duplo clique no material e clique no mapa. **Adicionar → Terreno / grama** coloca uma área de grama diretamente.

As propriedades permitem trocar o material, ajustar largura/profundidade de 1 a 64 m e girar a área. Setas X/Z, anel Y, Ctrl+C/Ctrl+V, desfazer/refazer, excluir e **Salvar mundo** também funcionam para pisos. O filtro **Terrenos** facilita selecionar o chão sob outros objetos.

São superfícies com textura e colisão reais; começam retangulares e aceitam contornos editados por pontos. Quando pisos se sobrepõem, a área criada depois recorta a anterior, evitando malhas e colisões duplicadas no mesmo ponto. Acompanham exatamente os triângulos do relevo da montanha; não esculpem, escavam nem nivelam o terreno existente. Em Harbor também fornecem apoio físico onde forem colocadas. A vegetação e os objetos já existentes continuam independentes; aplicar um piso não remove automaticamente esses elementos. Os acessos marcados e prédios de serviços continuam protegidos. Aplicar asfalto como piso muda o chão, mas não cria uma rota de tráfego; para isso use **Rua**.

A geração divide cada área pelos chunks que ela cruza: descarregar um trecho remove também sua malha e colisão, e os trechos vizinhos continuam independentes. Os sete materiais compartilham texturas pequenas, sem luzes, sombras próprias ou processamento por frame.

## Mover, diminuir e editar pontos

Clique na casa ou peça e arraste para mover. A seleção considera a geometria visível, evitando que a caixa vazia de um caminho inclinado capture o clique na casa ao lado. **Alt+clique** alterna entre objetos sobrepostos. As propriedades abrem ao soltar o mouse, preservando as coordenadas durante o primeiro arraste.

A alça amarela **tamanho**, abaixo e à esquerda do centro, diminui/aumenta casas, peças, objetos e terrenos. Nas peças, os campos **Largura** e **Profundidade** permitem ajustar cada eixo separadamente; a altura é preservada. A escala suportada das peças vai de 10% a 400% do original. Malhas e colisões acompanham o tamanho salvo.

Para terrenos e pisos/caminhos planos dos Cobra, ative **Editar pontos** nas propriedades. Arraste os pontos amarelos para mudar o contorno. **Adicionar ponto** divide a borda depois do ponto selecionado, ou a borda mais longa se nenhum ponto estiver selecionado. **Remover ponto** remove o ponto selecionado. O contorno aceita de 3 a 32 pontos, inclusive formatos côncavos; bordas cruzadas e áreas inválidas são recusadas. Nas ruas, os pontos existentes continuam diretamente arrastáveis e têm prioridade quando se sobrepõem às setas.

Desfazer/refazer e **Salvar mundo** incluem tamanho e contorno. Prensa, botão, guindaste e locais protegidos continuam sem transformação. A edição de pontos de peças se aplica aos pisos e caminhos planos elegíveis dos Cobra; objetos tridimensionais mantêm sua forma ao redimensionar.

## Conteúdo e limites

- O catálogo registra 761 registros nativos de Harbor e 885 da montanha. As peças dos conjuntos são projetadas a partir das malhas reais, com transformações de MultiMesh obtidas no renderizador, além de terrenos, trilhas e ligação entre regiões.
- O mapa é uma vista de trabalho de cima. Cores/texturas e iluminação completas são conferidas em **Prévia 3D**. Pequenos parafusos e lâminas individuais de grama não recebem polígonos próprios no mapa.
- Árvores, ruas, sete trilhas da montanha, prédios comuns (inclusive casas dos Cobra), postes e objetos da biblioteca podem ser alterados. O Neko agora tem escritório, contêineres, carros sucateados, pneus, barris, motores, cercas e pisos separados. Nos Cobra, árvores, bancos, cercas, caminhos, pisos e outros objetos também são peças individuais; o catálogo contém 215 peças de cenário. Malhas e colisões acompanham a movimentação e a recarga dos chunks.
- **Limites atuais:** peças específicas do cenário podem ser movidas, giradas e redimensionadas dentro da região de origem, mas não duplicadas nem excluídas. Prensa, botão e guindaste do Neko, fachadas ligadas a serviços/interiores e conjuntos como cemitério, navios, lagos e teleférico continuam protegidos. Não há edição individual de túmulos, NPCs ou interiores nesta versão.
- **Opções → Colocação livre** permite sobrepor objetos e vias; desligue-a para bloquear sobreposições comuns. Prédios de serviços e os acessos marcados continuam protegidos. Confira a circulação e as colisões na prévia 3D após rearranjar o cenário. Mudanças grandes no traçado ainda exigem conferir rotas, cruzamentos e missões no jogo; o editor não redesenha automaticamente todos os roteiros de missão.
- Novos pallets, caixotes, tambores, caçambas, sacos de lixo, lixeiras e barreiras têm geometria e colisão reais, sem loops por frame ou luzes próprias.
- Luzes autoradas são constantes, sem sombras; energia zero apaga. Prédios novos são exteriores, sem criar um novo interior jogável.
- **Opções → Atualizar base** gera novamente o catálogo após alterações do gerador por código. Usa um processo minimizado do Godot e mantém a ferramenta responsiva. Não substitui as alterações salvas.

## Arquivos

- Alterações aplicadas: `world/editing/world_edits.json` (vazio na entrega; o mapa não foi rearranjado como demonstração).
- Adaptador do mundo: `world/editing/EditableRegion.gd`; `runtime/ProductionWorld.gd` aponta para ele. O gerador original `NativeRegion.gd` foi preservado.
- Plugin: `addons/geteco_world_editor/`. O plugin fica fora do jogo exportado; o JSON de alterações está incluído na configuração de exportação.
- Gravação usa arquivo temporário, cópia `.bak` e verificação de alteração externa. Se outro editor modificar o arquivo, a gravação é recusada e o rascunho fica preservado.

## Validação

Testes em `tests/test_world_editor.gd`: persistência e conflito de gravação, dados inválidos, modificação de ruas/prédios existentes, exclusão de árvore original, geração de árvores/luzes, colisão física, descarga/recarga, terreno da montanha, clique/arraste, desfazer/refazer, proteção da garagem e cobertura do catálogo. A distribuição espacial dos túmulos é verificada para detectar a limitação do renderizador dummy.

Evidências em `evidence/world-editor-20260925/`: capturas do mapa completo, cemitério e montanha; prévias reais; logs; amostras de frame time.

Godot 4.7.2, Mobile, RTX 4060 Laptop, 1280×720, VSync/limite de 60, sessão real sem save, semente fixa, 8 s de aquecimento e 30 s por cenário:

| Cenário | Base FPS / p95 / p99 | Integração, confirmação FPS / p95 / p99 |
|---|---|---|
| Caminhada | 60,00 / 17,60 / 18,40 ms | 60,00 / 17,62 / 18,52 ms |
| Direção à noite | 59,97 / 18,05 / 19,36 ms | 60,00 / 17,59 / 18,39 ms |

A primeira amostra após integração teve travadas na caminhada (53,10 FPS; p99 57,67 ms), que não se repetiram na confirmação. A amostra com uma árvore, poste, prédio e rua adicionados teve 55,84 FPS / p95 28,33 / p99 47,80 ms na caminhada e 60,00 FPS / p95 17,52 / p99 18,09 ms à noite. **Desempenho com alterações autoradas permanece pendente**: não há causa isolada das travadas, e sessões concorrentes alteraram arquivos do mundo durante o trabalho. Estes resultados não certificam desempenho de quantidades arbitrárias de objetos nem da montanha. Há avisos de liberação de texturas no encerramento do Godot também vistos nas execuções da cena existente.


## Biblioteca e peças — ampliação de 25/09

Validação específica: `test_world_editor_assets.gd` (30 checks: busca, teclado real, copiar/colar, destinos, peças, ruas e salvar), `test_world_editor_props.gd` (71: oito modelos, física, persistência e streaming), `test_world_editor_pieces.gd` (27: peças do Neko, colisões e múltiplos chunks), `test_world_editor_cobra.gd` (16: equivalência de geometria/colisão original e transformações), `test_world_editor_roads.gd` (19: caminhos de pedestres e integração no adaptador de produção). Regressão `test_world_editor.gd`: 46 checks. Capturas reais: `evidence/world-editor-20260925/library-editor.png` e `library-assets.png`.

A biblioteca fica no plugin de edição. Os objetos novos usam materiais compartilhados e corpos estáticos; as alterações de peças são aplicadas na montagem dos chunks. Objetos e peças de teste usam documentos isolados: o mapa oficial não foi rearranjado como demonstração.


Comparação renderizada desta ampliação (Godot 4.7.2 Mobile, RTX 4060 Laptop, 1280×720, VSync/limite de 60 FPS, 8 s de aquecimento + 30 s medidos por cenário, sem salvar progresso):

| Cenário | Antes: FPS / p95 / p99 | Depois: FPS / p95 / p99 |
|---|---|---|
| Caminhada | 57,49 / 18,24 / 30,86 ms | 60,00 / 17,46 / 17,86 ms |
| Direção à noite | 60,00 / 17,51 / 18,54 ms | 60,00 / 17,44 / 18,21 ms |
| Neko, sem/com biblioteca | 60,00 / 17,32 / 17,90 ms | 60,00 / 17,39 / 18,00 ms |
| Cobra, sem/com biblioteca | 60,00 / 17,70 / 19,08 ms | 60,00 / 17,52 / 18,26 ms |

O comparativo Neko/Cobra acrescentou 18 objetos (nove em cada área), moveu/girou o escritório e um banco, mantendo a mesma câmera, posições, população e semente. Nenhuma amostra medida desses dois locais teve frames acima de 33,3 ms; os aumentos de p95/p99 ficaram abaixo do critério de 5%. **Sem regressão observada nesses cenários.** Isso não certifica quantidades arbitrárias de assets, outras rotas ou a montanha. A travada anterior de caminhada ocorreu na base e não se repetiu depois; não foi atribuído ganho causal a esta ferramenta. Arquivos de amostras e aquecimento: `library-before/report.json`, `library-after/report.json`, `library-areas-before/report.json` e `library-areas-after/report.json`, dentro da pasta de evidências. Os avisos de textura ao encerrar continuam iguais aos da base.


Controles por eixo: `tests/test_world_editor_gizmo.gd` passou em 22 verificações, incluindo restrição X/Z sem alterar o outro eixo, giro em Y, encaixe angular, prévia sem gravar, Esc, perda de foco, desfazer/refazer, transformação rígida de ruas, proteção de locais e salvar durante o arraste. Regressões do editor (46) e biblioteca (30) também passaram. Captura: `evidence/world-editor-20260925/gizmo-editor.png`. Esta mudança atua somente na ferramenta de edição, sem alterar o processamento do jogo.

Layout validado em áreas de 640×480, 720×480, 1024×640, 1440×900 e 1920×1080: `tests/test_world_editor_layout.gd` passou em 90 verificações, cobrindo encaixe, botão Salvar, laterais, ampliação e preservação da navegação. Capturas renderizadas conferidas: `layout-1440.png`, `layout-720.png` e `layout-expanded.png`, na pasta de evidências. A integração com o modo de foco do Godot passou em cinco verificações no editor real, incluindo restauração ao sair da aba e desativar o plugin. Regressões da biblioteca (30) e controles por eixo (22) passaram. A reorganização afeta apenas a interface do editor, sem mudanças no processamento do jogo.

Correção do encaixe no editor: a tela principal agora solicita expansão horizontal e vertical ao VBoxContainer nativo do Godot. Somente usar âncoras deixava a aba na altura mínima, com uma faixa vazia abaixo. O teste real `tests/test_world_editor_host.gd` reproduziu a falha antes da correção e passou em 15 verificações depois, com renderização, redimensionamento e modo ampliado. Capturas: `host-filled.png` e `host-expanded.png`. A medição considera a altura disponível após as barras, o tema e os painéis do Godot; não presume a mesma proporção de mapa em qualquer escala de interface. O scanner ainda reporta erros em scripts de testes fora deste plugin (referências ausentes), que não foram corrigidos nesta alteração.

Se a janela aberta ainda mostrar o título antigo MUNDO / GETECO e os botões + Árvore/+ Prédio, salve o mundo e reabra o projeto para reconstruir a interface do plugin.

## Fachadas na prévia lado a lado — 26/09

O renderer dummy do processo headless não conserva os transforms de MultiMesh: a leitura devolve identidade e buffer vazio. Isso fazia os prédios da biblioteca aparecerem como blocos sem janelas. O gerador agora transporta uma cópia dos transforms somente quando executado pelo worker da prévia. O painel restaura esses dados antes de exibir a cena e remove a cópia auxiliar. A geração normal do jogo mantém seus batches existentes.

Comparativo do editor renderizado com o prédio em (5,95), Mobile/RTX 4060 Laptop, 1440×900, VSync e limite de 60 FPS, oito segundos de aquecimento e 30 segundos de amostra: antes/depois 60,00/60,00 FPS, p95 16,704/16,724 ms e p99 16,867/16,999 ms; nenhum frame acima de 33,3 ms. Arquivos: `evidence/world-editor-live-infill-before.json` e `evidence/world-editor-live-infill-after.json`. Medição de câmera parada no editor; não certifica desempenho durante órbita/reconstrução ou gameplay.

`tests/test_world_editor_facades.gd`: seis verificações aprovadas em execução renderizada, comparando todas as 149 instâncias de detalhes do prédio estreito com o modelo de produção, mantendo a cena passiva e o mundo oficial intacto. Captura conferida: `evidence/world-editor-facades.png`. Os avisos de liberação de texturas no encerramento também ocorreram antes da correção.

## Validação dos terrenos — 25/09

`tests/test_world_editor_ground.gd`: 59 verificações aprovadas, cobrindo sete materiais, limites de tamanho, persistência, copiar/colar, edição, desfazer/refazer, exclusão, malha e colisão por chunk, descarga/recarga, recorte de sobreposições e contato físico sobre o relevo inclinado. Biblioteca: 30 verificações aprovadas; controles por eixo: 22. Captura dos materiais: `evidence/world-editor-20260925/ground-materials.png`. Os testes e medições usam documentos isolados; `world/editing/world_edits.json` permaneceu vazio.

Amostras renderizadas na cena real Main, Godot 4.7.2 Mobile, RTX 4060 Laptop, 1280×720, VSync/limite 60 FPS, semente 25092026, 8 s de aquecimento + pelo menos 30 s por local. A versão final tem sete pisos de 8×8 m, girados e com sobreposições, em cada um dos três locais. Os arquivos `report.json` guardam também p50, máximo, contagens de frames lentos, população e todas as amostras de aquecimento/medição.

| Local | Amostra sem pisos: FPS / p95 / p99 (ms) | Versão final: FPS / p95 / p99 (ms) |
|---|---|---|
| neko | 57.77 / 17.92 / 20.13 | 60.00 / 17.62 / 18.00 |
| cobra | 60.00 / 17.30 / 17.56 | 60.01 / 17.86 / 18.73 |
| mountain | 60.00 / 16.91 / 19.73 | 60.00 / 16.91 / 19.88 |

A versão final não teve frames acima de 33,3 ms nos três trechos medidos. **Comparação de regressão permanece inconclusiva:** `runtime/ProductionWorld.gd` mudou por outra sessão entre as amostras (hash 84DA3B… para CA224E…), e a montanha na execução final veio depois dos dois locais de Harbor, enquanto sua base foi isolada. O p99 nos Cobra foi 6,7% maior que a amostra de base; com essas condições diferentes, isso não confirma nem descarta regressão e exige comparação estável para aprovação. A base do Neko já teve uma travada de 1,13 s. Não foi atribuído ganho causal aos pisos. Os avisos de liberação de texturas no encerramento também ocorreram sem pisos.

Evidências: `ground-baseline-current/`, `ground-mountain-before/` e `ground-final/`, em `evidence/world-editor-20260925/`. Os comparativos intermediários, anteriores ao recorte de sobreposições, foram preservados como diagnóstico e não certificam a implementação final.

## Redimensionamento e contornos — 26/09

Validação: `test_world_editor_shape_ui.gd` (21), `test_world_editor_selection.gd` (14), `test_world_editor_piece_shapes.gd` (23), regressões de peças (27), Cobra (16), controles por eixo (22) terrenos (59) e integração geral do editor (46): **228 verificações aprovadas**. O teste integrado reproduz a casa e o caminho da captura: primeiro clique/arraste sem mudar o tamanho do mapa, redução, pontos, desfazer/refazer e gravação. A seleção isolada cobre bordas do telhado, formas inclinadas, Alt+clique e prioridade de vértices. Os testes físicos verificam escala por eixo, preservação da altura, colisão no novo local, ausência de colisão fantasma, contorno côncavo, reaplicação sem acumular transformações e máquinas protegidas.

Captura da ferramenta: `evidence/world-editor-20260925/shape-editor.png`. O teste antigo de gizmos passou a clicar na ponta da seta, longe do vértice da rua: agora o vértice visível tem prioridade naquela sobreposição; as assertions de movimento rígido e rotação foram preservadas.

Comparação renderizada na cena Main, Mobile, RTX 4060 Laptop, 1280×720, VSync/limite 60 FPS, semente 25092026, 8 s de aquecimento e pelo menos 30 s por caso, sem salvar progresso:

| Local | Antes FPS / p95 / p99 | Depois FPS / p95 / p99 |
|---|---|---|
| Neko, escritório reduzido e movido | 57,78 / 18,09 / 34,94 ms | 59,92 / 17,63 / 18,34 ms |
| Cobra, câmera sobre casa/caminho editados | 59,92 / 17,48 / 18,04 ms | 60,00 / 17,53 / 18,02 ms |

Sem regressão observada nesses casos: nos Cobra o p95 aumentou 0,25% e o p99 ficou praticamente igual, dentro do critério de 5%. Ainda houve um frame de 81,9 ms no Neko após a mudança (base: máximo 380,4 ms); nos Cobra o máximo foi 19,8 ms, sem frames acima de 33,3 ms (base: 84,8 ms); não foi atribuído ganho causal à ferramenta. As amostras, p50, máximos, frames acima de 33,3/66,7 ms e aquecimento estão em `shape-before/report.json`, `shape-after/report.json`, `shape-cobra-before/report.json` e `shape-cobra-final/report.json`, na pasta de evidências. A amostra Cobra genérica em `shape-after/` não substitui a câmera específica sobre as alterações. Esses dados não certificam quantidades arbitrárias de peças nem terrenos com polígonos complexos. Avisos de texturas no encerramento também ocorreram na base.

A revisão visual encontrou e corrigiu a altura fixa de 7,5 m nos catálogos antigos: mover ou reduzir uma casa agora preserva sua altura nativa. O cálculo é compartilhado com o gerador do jogo; catálogos antigos são corrigidos ao abrir a ferramenta. Alturas explicitamente salvas em edições existentes continuam preservadas. A captura final está em `shape-cobra-final/cobra.png`; `shape-cobra-after/` é diagnóstico anterior à correção.

Os documentos de teste são isolados; nenhum rearranjo de demonstração foi gravado no mundo oficial. O arquivo oficial contém edições do usuário, preservadas pela tarefa.

## Expansão rural no 2D — 28/09/2026

Vértice, bosque e estrada rural agora aparecem também nos catálogos antigos.
`WorldSessionContext.gd` mescla o suplemento estático `session_context.json`
e os terrenos/estradas atuais antes de aplicar as alterações salvas do usuário.
O exportador completo inclui esse contexto; `--session-only` regenera apenas
o suplemento. Árvores usam silhuetas com cores e transformações extraídas dos
arrays CPU, inclusive no export headless. Abrir/redesenhar o editor não instancia
árvores, NPCs ou a empresa. O suplemento tem aproximadamente 900 KB.

O enquadramento considera terrenos, todos os pontos das ruas e contornos,
não somente centros/primeiros pontos. Vértice e bosque são pesquisáveis em
“Ir para local” e protegidos contra mover os ambientes operados pelo runtime;
a estrada continua editável. Reabra a aba Mundo para carregar o catálogo
atualizado. A prévia 3D não foi alterada por esta correção.

`test_world_editor_freight_context.gd`: **24 checks aprovados**, incluindo
catálogo antigo, cores/altura de mais de 300 copas, enquadramento, navegação,
cache e preservação do documento salvo. Triângulos estáticos são reutilizados;
o mesh limita-se às células visíveis e mantém a ordenação de profundidade.

Fotos: `evidence/port-logistics-20260928/editor-before/` e
`evidence/port-logistics-20260928/editor-after-culled/{full-map,company-map}.png`.
Medição: 1440×900, RTX4060/Mobile, VSync desligado, limite144, centro(-340,-55),
4px/m, 5s de aquecimento e 30s de redraw contínuo. Média antes/depois:
27,16/28,97 FPS; p95 42,163/35,044ms. **Performance ainda pendente**: a base
já não cumpria 60 FPS e o p99 final aumentou de48,64 para84,9ms, com28 amostras
acima66ms concentradas nos últimos2,4s. Não foi demonstrada a causa desse pico
nem declarada aprovação de FPS. Métricas completas no JSON das respectivas
pastas. A limitação foi mantida explícita para a sessão de performance.
