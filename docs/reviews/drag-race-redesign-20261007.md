# Arrancada — revisão de 7 de outubro de 2026

Implementação com três agentes: HUD/áudio, fluxo/progressão e seleção/personagens/torcida. Integração, céu, materiais e revisão visual na sessão principal.

## Entrega

- HUD com RPM segmentado atualizado a cada frame, faixa de troca, marcha e velocidade grandes, progresso dos dois carros, semáforo e mensagens curtas. Pausa oculta o HUD da prova e restaura ao continuar.
- Seleção de cinco rivais com retratos cinematográficos, recorde e revanche para adversários vencidos.
- Resultado permanece aberto com **Revanche**, **Voltar à entrada** e **Ficar aqui**. Retorno verifica suporte físico na concentração. Prêmios de primeira vitória não se repetem.
- Correção do perfil mecânico: carros de rua usam o catálogo real do seu motor. Anteriormente vários esportivos recebiam o perfil de um hatch. Rivais têm preparação progressiva e erros de largada/troca importam; não há aceleração artificial para alcançar Dante.
- Derrapagem com ganho reduzido e supressão da duplicação entre voz específica de patinagem e efeito genérico de pneus.
- 24 espectadores, 12 carros estacionados e 12 barreiras em seis grupos nas laterais. Recursos pertencem aos chunks, carros decorativos não têm controladores/luzes/áudio; espectadores distantes deixam de animar. Reações a ameaças e dano permanecem.
- Céu local com nuvens e trajetórias de sol/lua ligadas ao relógio. Material das montanhas com estratos e variação mineral; geometria física preservada. Sem adicionar fontes de luz ou sombras.

## Evidência e limites

Godot **4.7.2 .NET**, projeto `Harbor.csproj` compilado sem avisos ou erros. Os testes integrados verificam o caminho C# e usam checkpoints isolados, sem salvar na campanha do usuário.

| Verificação | Resultado |
|---|---|
| Progressão e recompensa idempotente | 49 verificações aprovadas |
| Equilíbrio dos rivais e perfis de motor | 29 verificações aprovadas |
| Seleção, revanche e recorde | 10 verificações aprovadas |
| Torcida: terreno, colisões, dano e descarregamento | 227 verificações aprovadas antes do ajuste final de gestos |
| Gestos de torcida, pânico, recuperação e distância | 9 verificações aprovadas em headless e na cena isolada renderizada |
| Áudio de carros/luzes e pneus | 216 + 19 verificações aprovadas |
| Escopo e restauração do céu | 7 verificações aprovadas |
| Main renderizada: carro V12, chegada e retorno à entrada | 82 verificações, zero falhas |
| Main renderizada: céu temporal, corrida, pausa, chegada e recuperação | 76 verificações, zero falhas |

O fluxo completo de três corridas encontrou um defeito no retorno à entrada (retornava ao grid em uma sequência de cancelamentos). A correção foi validada pelo teste dirigido de 82 verificações. As demais verificações da sequência, incluindo revanche e preservação de recompensa, passaram. Não foi repetida a sequência inteira após a correção.

Evidência integrada:

- `evidence/drag-redesign-street-entry-20261007.log`
- `evidence/drag-redesign-street-entry-20261007/result-1.png`
- `evidence/drag-redesign-temporal-20261007.log`
- `evidence/drag-redesign-temporal-20261007/sequence.json`: 1.967 frames em 66,37 segundos, zero frames renderizados omitidos. Captura limitada a 30 FPS, com custo de gravação incluído: **não é benchmark**.
- `evidence/drag-redesign-temporal-20261007/sky-contact-sheet.jpg`
- `evidence/desert-drag-board/board.png` e `board-960.png` (1280×720 e 960×640).
- `evidence/drag-spectator-cheer.png`: revisão isolada do gesto final de torcida. O comportamento preserva o movimento normal e interrompe a comemoração durante ameaças.

A revisão temporal cobre a pista e os horários amostrados; não certifica a iluminação de todo o jogo. Não houve validação auditiva humana do volume final.

**Performance pendente:** testes renderizados de outras sessões (mineração e armas) disputaram a GPU. As tentativas de baseline não produziram um comparativo válido. Não há aprovação de FPS nem alegação de ganho de performance. O runner `tests/measure/measure_drag_ui.gd` está preparado para medir Main renderizada, seleção e corrida com tempos reais entre frames, mas precisa de uma janela sem outros jogos/testes renderizados. Uma cópia anterior das fontes foi preservada fora do projeto em `D:/geteco/drag-baseline-20261007`; dependências de outras sessões e recursos importados compartilhados limitam seu isolamento.

O teste genérico `audio/test_vehicle_sound_migration.gd` apresentou duas falhas legadas de fixture relacionadas à voz de colisão e ao cooldown do pool de áudio; as verificações de pneus passaram. Essas duas falhas não foram contadas como aprovação nem corrigidas fora do escopo.

## Referências consultadas

- [CSR Racing 2](https://www.zynga.com/games/csr-racing-2/) — apresentação de carros e progressão competitiva.
- [CSR2: Perfect Shift](https://zyngasupport.helpshift.com/hc/en/55-csr-2/faq/5912-how-do-i-get-the-perfect-shift/) — leitura da faixa de troca e feedback imediato.
- [Need for Speed: ProStreet — Drag](https://nfs.fandom.com/wiki/Need_for_Speed%3A_ProStreet/Drag) — atmosfera de evento e instrumentação.
- [Godot: Environment](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html) e [sky shaders](https://godotengine.org/article/custom-sky-shaders-godot-4-0/) — implementação do céu.

Os retratos foram gerados para o projeto a partir dos personagens existentes. Referências externas orientaram a direção visual, sem reutilizar seus assets.

## Complemento: chuva e tempestade

Após o pedido de chuva inclinada e raios no fundo:

- Chuva da câmera lateral alinhada à velocidade e ao vento, com rajadas suaves e gotas mais finas. Reutiliza as 600 partículas existentes e restaura direção, tamanho e alinhamento ao sair da câmera da arrancada.
- Raio distante visível no céu, atrás da geometria das montanhas, sincronizado com o clarão e o trovão atrasado já existentes. Não cria outra luz ou outro agendador de tempestades.
- Nuvens de tempestade mais densas, com controle local da mistura da névoa no céu para manter seus contornos visíveis; a névoa sobre o terreno permanece.

Validação: build .NET sem erros; 10 checks do céu; 9 asserts de direção, alinhamento e restauração da chuva. Main renderizada com tempestade e corrida física: **82 checks, zero falhas** (`evidence/drag-storm-20261007.log`). Após o ajuste visual de névoa e espessura das gotas, captura dirigida em Main: **54 checks, zero falhas**, 1.011 frames em 34,08 s (`evidence/drag-storm-final-20261007/sequence.json`). Revisão amostral dos frames de chuva/clarão de dia e noite; não foi realizada revisão auditiva humana nem reprodução integral do vídeo em velocidade normal.

Captura de referência: `evidence/drag-storm-final-20261007/00151.jpg`. Os 30 FPS da captura são um limitador de gravação, não uma medição de desempenho.

Comparativo de desempenho deste complemento **não executado**: outras sessões continuaram iniciando testes renderizados (combate e acessórios) na GPU compartilhada. Runner preparado e sintaticamente validado: `tests/measure/measure_drag_weather.gd`, amostras pareadas de 32 s em Main, sem gravação. Precisa de janela exclusiva e do shader anterior via `--baseline-sky`. Seu escopo é tempestade com câmera parada; não aprova o redesign completo nem o desempenho em movimento.

Referência técnica: [alinhamento das partículas do Godot](https://docs.godotengine.org/en/4.3/classes/class_gpuparticles3d.html), conferido no runtime 4.7.2 .NET do projeto.

## Painéis personalizáveis

O quadro de adversários agora tem **PAINÉIS**, com prévia, seleção, compra e retorno ao quadro. O circular é o padrão; o painel em barras permanece gratuito. Novas primeiras vitórias anunciam os estilos liberados na tela de resultado. Revanche não conta como outro rival vencido.

| Painel | Formato | Desbloqueio | Preço |
|---|---|---|---|
| Clássico | Circular escuro, ponteiro coral | Inicial | Grátis |
| Barras | Instrumentação digital segmentada | Inicial | Grátis |
| Street | Circular com aros verde/ciano | 1 rival vencido | R$ 1.500 |
| Pro | Circular de fundo claro e luzes de troca | 3 rivais vencidos | R$ 3.500 |
| Campeão | Circular âmbar e luzes de troca | 5 rivais vencidos | R$ 6.500 |

Os painéis são cosméticos, usam a carteira da campanha e custam uma única vez. A seleção e a propriedade ficam em `world.drag_instruments`. Recibos, preço e requisito são validados no contrato de save; saves antigos recebem os dois modelos gratuitos. Compra exige confirmação e equipar um painel adquirido não debita novamente. Se o salvamento for recusado, a UI informa que a seleção está na sessão e o salvamento está pendente, seguindo o estado em memória da carteira.

O ponteiro lê RPM diretamente. Geometria estática dos círculos e rótulos é reutilizada; riscos são desenhados em grupos, sem SubViewport, textura dinâmica, interpolação do ponteiro ou novo timer.

Validações concluídas: catálogo/carteira/persistência **47 checks**, incluindo duas gravações e duas leituras reais do SaveStore em arquivo isolado; regressão de save/garagem **32 checks**; loja **14 checks**; renderer **22 checks**, capturas 1280×720 e 960×540; geometria/cache **10 checks**. O fluxo integrado final passou em **48 verificações**, incluindo vitória física, desbloqueio, confirmação da compra, débito único, reequipagem gratuita, retorno por Esc e aplicação na próxima corrida. Foram **2.931 frames renderizados com zero divergências** entre HUD e velocidade/RPM/marcha atuais. O cenário completo está registrado em `evidence/drag-instrument-session-complete-20261007.log`.

Evidências visuais: `evidence/drag-hud-styles-20261007/` e `evidence/desert-drag-instruments/`. O teste da loja usa checkpoints isolados e protege o save pessoal com `--no-save`; o teste de persistência usa seu próprio arquivo real.

Integração final fotografada em `evidence/desert-board-session-171812-8385782/instrument-shop-in-game.png`. A revisão identificou que o aviso do circular cobria parte dos carros na largada: foi movido para a região superior durante a corrida; na preparação, a orientação aparece sobre fundo escuro junto dos instrumentos. Essa correção final é de layout, mantendo leitura e transações já verificadas.

**FPS inconclusivo:** a tentativa pareada de 32 s com HUD anterior, circular e Campeão (`tests/measure/measure_drag_instruments.gd`) foi interrompida quando outra sessão abriu `measure_world_map.gd`. O log parcial `evidence/drag-instruments-perf-20261007.log` não permite atribuir ganho ou regressão aos painéis. A otimização posterior de geometria passou nas verificações funcionais, mas não recebeu um novo comparativo renderizado exclusivo. A cópia anterior do HUD está preservada em `D:/geteco/drag-hud-before-instrument-styles-20261007.gd` para a medição posterior.
