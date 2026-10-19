# Evidências da experiência atual

Rodada de 17/10/2026, horário do usuário em America/Sao_Paulo. Os identificadores de sessão do motor usam UTC de 18/10.

## Escopo e método

Cena real `Main.tscn`, Godot 4.7.2 .NET, Vulkan Forward Mobile, RTX 4060 Laptop. `dotnet build Harbor.csproj -c Debug --nologo` concluiu com zero avisos e zero erros. Os dois runners confirmaram backend C# ativo e usaram checkpoint isolado junto de `--no-save`.

Primeira execução: `tests/test_drag_open_meet.gd --no-save --night`. Segunda execução: `artifacts/rachas-design-20261017/capture_flow.gd --no-save --drive`, extensão apenas de captura do runner existente `tests/test_desert_drag_board_session.gd`. A segunda cobre quadro e corrida ranqueada, com circulação livre desligada pelo próprio teste para isolar o fluxo. Não é repetição da fila defeituosa nem correção dela.

O setup posiciona o jogador no local por fixture: não comprova a viagem normal até o deserto. O fluxo usa ações públicas do encontro, movimento físico real e entradas automatizadas. Na preparação, o runner injeta pedal `.54`, portanto não reproduz o desconforto do teclado. Não houve escuta auditiva nem benchmark de frame time. As leituras de FPS estampadas nas imagens não são uma medição aprovada.

## Etapas e achados

### 1. Circulação e fila — reprovada na execução

O jogo iniciou, o backend C# foi encontrado e o embarque devolveu controle. A condição de dois corredores autônomos mais um par aguardando falhou. Cinco verificações passaram e uma falhou. Os seis visitantes estavam parados em `routing=arrival`, `waypoint=5`, `speed=0`, aproximadamente em `z=-1279.95`.

[Log completo da fila](../../../output/rachas-design-audit-20261017.log).

O teste interrompeu antes de abrir o quadro de baterias livres e antes das capturas próprias daquele runner. Por isso esta etapa tem evidência funcional em log, **sem captura visual aceita**. Não houve inscrição do jogador nem teste de recuperação nesta execução. O estado permanente `blocked` encontrado na leitura é outro defeito; não foi demonstrado como causa dos seis carros parados nesta rodada.

### 2. Quadro de rivais — funcional, apresentação parcial

![Quadro de rivais capturado no jogo atual](../../../evidence/desert-board-session-3912-7075325/board-in-game.png)

O fluxo abriu e fechou duas vezes, permitiu inspecionar rival bloqueado, explicou ausência de veículo e iniciou o duelo depois do embarque. As identidades e retratos dos seis rivais já são úteis. O quadro ocupa quase toda a tela e organiza o encontro como uma lista de rivais bloqueados; o prêmio visível é dinheiro, sem antecipar uma preparação ou habilidade do carro. Há mistura de idiomas nos comandos e títulos na configuração desta sessão.

O usuário pediu peças e motivos para voltar: a tela futura deve indicar a próxima conquista relacionada ao rival e manter uma entrada rápida para treino. Cor/linha de seleção estão visíveis, mas navegação integral por controle/teclado e acessibilidade não foram auditadas manualmente.

### 3. Preparação — visível, controle humano ainda não validado

![Preparação e HUD atuais](../../../evidence/desert-board-session-3912-7075325/03-staging.png)

A câmera enquadra os dois carros. Três painéis no topo, contagem central e instrumentos grandes embaixo disputam atenção. A faixa ideal é um pequeno arco dentro de um mostrador muito maior. A mistura entre inglês e português continua. O corredor aparece amplo e o cenário é dominado por areia e relevo; há pouca atividade humana próxima desta câmera.

O controle da preparação é o principal risco: leitura do código mostra passagem pela faixa ideal em aproximadamente 221 ms com W binário. A captura não mede dificuldade; essa conta explica uma hipótese de experiência consistente com o relato do usuário. O teste usa pedal analógico constante e não pode aprovar o teclado.

### 4. Corrida e horizonte — corrida concluiu; continuidade temporal pendente

![Corrida aos 150 metros](../../../evidence/desert-board-session-3912-7075325/04-corrida.png)

![Trecho avançado da corrida](../../../evidence/desert-board-session-3912-7075325/05-horizonte.png)

Carros, posição relativa, marcha e giro são legíveis. O mostrador e a legenda inferior consomem uma parte grande do campo visual. A faixa do horizonte repete volumes arenosos com variação limitada; a grande área intermediária vazia contribui para a falta de escala e identidade. Os pequenos grupos visíveis no trecho avançado ajudam a situar a pista, mas não formam sozinhos uma experiência de encontro.

Estas duas imagens foram capturadas em posições diferentes. **A diferença de objetos entre elas não prova popping.** O descompasso entre alcance da câmera e residência dos chunks é uma hipótese técnica a investigar com vídeo/frames contínuos e identificação do mesmo objeto. Nenhuma alteração de streaming foi feita.

### 5. Resultado e retorno de controle — funcional, pouco orientado à melhoria

![Resultado da prova atual](../../../evidence/desert-board-session-3912-7075325/victory.png)

A prova física terminou: Dante 19,929 s, Digo 20,598 s. O resultado mostrou vitória, recorde, desbloqueio de painel e três destinos. O teste confirmou controle liberado ao fechar. Essa é uma base útil para repetição.

Falta uma explicação concreta de onde o jogador melhorou ou perdeu tempo e uma ligação clara com a preparação seguinte. A proposta é acrescentar uma única dica baseada em telemetria, mantendo repetir/ajustar/voltar fáceis de encontrar. Os rótulos precisam seguir o idioma selecionado.

[Log completo do fluxo e capturas](../../../output/rachas-design-visual-20261017.log). Resultado: 27 verificações aprovadas, zero falhas; processo terminou com código 0. A execução anterior da fila terminou com código 1 e sua falha permanece aberta.

## Captura rejeitada

`01-encontro.png` foi obtida no primeiro frame em que `ready_for_play` ficou verdadeiro, antes de a instrumentação confirmar apresentação estável. Ela mostra entrada muito vazia, mas não comprova a população do encontro após aquecimento. Foi **rejeitada como evidência de densidade estável** e não deve ser usada como referência para aprovar ou condenar a população final. Uma visita normal a pé, com tempo de assentamento e rota pelo pátio, continua pendente.

## Limites e estado final

| Dimensão | Estado desta rodada |
|---|---|
| Build .NET | Aprovado: zero erros/avisos |
| Formação da bateria livre | Reprovada: seis carros parados no trajeto de chegada |
| Quadro → embarque → duelo ranqueado → resultado → controle | Verificações do runner aprovadas, com setup e pedal automatizados |
| Conforto de teclado e gatilho | Não validado por jogador; diagnóstico estático disponível |
| Áudio próprio/rival, vozes e música | Não ouvido; diagnóstico estático e relato do usuário |
| Popping/flicker | Não certificado; faltam evidências temporais dirigidas |
| Performance/regressão | Não medida nesta rodada; sem mudança de runtime para comparar |
| Encontro estável, circulação a pé e aproximação | Pendente; captura precoce rejeitada |
| Progressão nova e migração | Proposta, ainda não implementada |

Os diagnósticos detalhados dos três agentes estão em [ambiente.md](ambiente.md), [pilotagem.md](pilotagem.md) e [progressao.md](progressao.md). A [proposta principal](README.md) separa a base de conforto das etapas posteriores de conteúdo e progressão.
