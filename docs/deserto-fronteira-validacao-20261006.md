# Fronteira do deserto — validação de 06/10/2026

## Casa abandonada, cabana e segredos

**90/90 verificações aprovadas no Main renderizado; 0 ambientes certificados integralmente / 2 em validação.** Este registro cobre somente os dois abrigos, suas interações e persistência. Iluminação noturna e comparação controlada de desempenho permanecem pendentes. Não estende a aprovação a cânion, combate ou outras áreas.

Os locais são ruínas abertas e contínuas no exterior. O jogador atravessa os acessos caminhando, sem portal, transferência de sala ou modal de entrada. A câmera de gameplay permanece a do exterior. Eles ficam a oeste do campo de relevo do cânion, em terreno plano, com reserva contra decoração sobre os acessos e um caminho de aproximadamente 35 m entre os dois.

| Local | Identificador | Centro em metros `(x, y, z)` | Aproximação da interação | Recompensa própria |
| --- | --- | --- | --- | --- |
| Casa abandonada de adobe, 9 × 7 m | `desert_abandoned_house` | `(-1300, 0, -1720)` | `(-1298.95, 0, -1720.8)` | Pista e R$ 5.000 |
| Cabana de madeira, 5 × 4 m | `desert_abandoned_cabin` | `(-1335, 0, -1714)` | `(-1334.9, 0, -1714.4)` | R$ 5.000 |

As ações funcionais são **Recolher pista** e **Recolher dinheiro**, pela interação normal do jogo. A casa contém uma folha de transporte dos Cobras com anotação recente de Vicente sobre seguir caminhões após uma mudança de rota. Essa pista opcional não altera flags da campanha principal nem antecipa a revelação maior do ato 2. Não há placas ou textos decorativos explicando os objetos.

### Integração e persistência

O cenário é construído por [DesertAbandonedSite.gd](../world/desert/DesertAbandonedSite.gd). [DesertFrontierRuntime.gd](../runtime/desert/DesertFrontierRuntime.gd) exige jogador vivo, a pé, apoiado no piso, no exterior do deserto, sem modal ou transição, próximo da aproximação autorada e com o cenário efetivamente carregado. A interação passa pelo dispatcher e pelo comando real de `FullSession`.

[DesertSecretState.gd](../runtime/desert/DesertSecretState.gd) guarda os dois flags em `world.desert_secrets`. Cada recompensa usa um recibo próprio da economia: `desert_abandoned_house_cache` ou `desert_abandoned_cabin_cache`. Reentrada, repetição da ação e recarga fria não concedem dinheiro novamente. Um teste dirigido também confirmou que um recibo existente permite reparar um marcador ausente sem repetir o pagamento. Jogador morto não recebe a recompensa.

Na fixture com saldo inicial zero, o saldo final foi **R$ 10.250**: R$ 5.000 de cada local, mais os bônus existentes de conquista `first_grand` (**R$ 50**) e `shark` (**R$ 200**). Os valores das conquistas foram conferidos contra o [catálogo](../data/catalogs/AchievementCatalog.gd), os recibos e as conquistas efetivamente registradas. Os R$ 250 adicionais não são duplicação do segredo nem uma terceira recompensa nova. Repetição e recarga foram comparadas ao saldo após esses bônus.

### Evidência física e visual

Execução final: [relatório de 90 checks](../evidence/desert-secrets-session-107108-5011442/report.json), sem falhas e com stderr vazio segundo a execução coordenada. Usou Godot **4.7.2 .NET**, backend C# ativo, renderer **Mobile**, **NVIDIA GeForce RTX 4060 Laptop GPU** e população solicitada de 20. A fixture está em [desert_secrets_session.gd](../tests/desert_secrets_session.gd).

Foram verificados os seguintes comportamentos:

- Caminhada real pela porta da casa até o cofre, saída, caminho entre os abrigos e acesso ao esconderijo da cabana.
- Mesa da casa e cama da cabana bloqueando varredura do corpo inteiro e caminhada sustentada do jogador, sem permitir subir sobre os móveis pelo movimento comum.
- NPC real entrando nos dois locais, varrendo o corpo contra esses sólidos e saindo da cabana; jogador e visitante coexistindo em posições distintas.
- Interação real, recibos únicos, recusa a jogador morto, reparação de marcador, captura do estado por `FullSession` e recarga fria no Main.
- Profundidade de jogador e NPC, separadamente, com controles positivos que ocultam a arquitetura para medir a silhueta desobstruída. Não se ocultou o ator para fazer esses controles passarem.

| Área / pose diagnóstica | Jogador visível | NPC visível | Interpretação |
| --- | ---: | ---: | --- |
| Casa / porta | 93,7% | 91,7% | Acesso legível |
| Casa / sob a cobertura da varanda | 0% | 0% | Oclusão total pela cobertura opaca |
| Casa / atrás da parede baixa, lado sem varanda | 72,5% | 78,0% | Oclusão parcial pela parede |
| Casa / ao lado da mesa | 100% | 100% | Controle livre |
| Cabana / entrada | 96,5% | 98,7% | Acesso legível |
| Cabana / atrás da parede baixa | 74,0% | 75,3% | Oclusão parcial pela parede |
| Cabana / sob a viga | 83,2% | 79,7% | Oclusão parcial pelo elemento elevado |
| Cabana / fora da projeção da viga, ao lado da cama | 100% | 99,9% | Controle livre |

A cobertura da varanda pode esconder completamente um personagem na pose autorada sob sua projeção. Isso foi mantido e medido como profundidade real, separado da passagem principal e dos controles livres; não há garantia de visibilidade em qualquer posição. As fotografias naturais usam o enquadramento frontal diagnóstico, enquanto a sequência da primeira visita registra a câmera normal diagonal do exterior.

Fotos reais: [casa com jogador](../evidence/desert-secrets-session-107108-5011442/house-player-natural.png), [casa com NPC](../evidence/desert-secrets-session-107108-5011442/house-npc-natural.png), [cabana com jogador](../evidence/desert-secrets-session-107108-5011442/cabin-player-natural.png) e [cabana com NPC](../evidence/desert-secrets-session-107108-5011442/cabin-npc-natural.png). Elas mostram escala humana, objetos e circulação; não comprovam desempenho.

### Revisão temporal diurna limitada

A [sequência](../evidence/desert-secrets-session-107108-5011442/sequence/sequence.json) contém **591 quadros em 19,8558 s**, com `skipped_rendered_frames = 0`, gravação concluída e nenhuma falha de captura. Foi gravada a **1280 × 720**, com limite de captura de **30 Hz**, começando após a prontidão do Main e terminando antes da recarga fria. Inclui caminhada, coleta e testes de bloqueio na primeira visita.

Foram inspecionados as fotografias naturais e estes trechos específicos, não os 591 quadros individualmente:

- `00028–00031`: aproximação e passagem pela porta da casa; a sombra e a sobreposição do batente acompanham os passos e a câmera.
- [00120](../evidence/desert-secrets-session-107108-5011442/sequence/00120.jpg): personagem junto ao cofre, interior aberto e sombras dos elementos que restam do teto.
- [00300](../evidence/desert-secrets-session-107108-5011442/sequence/00300.jpg): caminhada pelo terreno entre as construções.
- `00538–00541`: entrada e aproximação da interação na cabana; personagem, vigas e sombras permanecem coerentes nos quadros consecutivos revistos.

Nesses trechos revistos, não foi observado desligamento ou popping evidente dos sólidos e de suas sombras. Essa observação amostral não certifica ausência de flickering no restante da sequência, à noite, na chuva ou em outros enquadramentos. Há um intervalo inicial de captura de **266,771 ms**, com primeira escrita de imagem de **241,679 ms**; nenhum quadro renderizado foi omitido, mas a cadência inicial não foi uniforme.

### Limites e pendências

O teste usa `--no-save`: o fluxo real de `FullSession` captura o estado, e a fixture escreve arquivos completos **isolados**, validados por `GameState`/`SaveStore`, para a recarga fria do Main. Não escreve no save normal do jogador. Os bandidos foram explicitamente pré-derrotados no checkpoint para isolar o acesso aos abrigos; esta rodada não valida combate.

As capturas, o limite de 30 Hz e as varreduras de pixels interferem no tempo de execução. Os picos de aproximadamente um segundo durante as máscaras diagnósticas não são uma medição de gameplay. Nenhum contador de FPS nas imagens aprova ou reprova desempenho por si só. **Falta comparação renderizada e controlada de frame time**, além de cobertura noturna pertinente. Os sólidos exercitados fisicamente foram os acessos e os móveis indicados; não se declara uma auditoria exaustiva de todo objeto e toda trajetória possível.

A [primeira rodada](../evidence/desert-secrets-session-32576-5003184/report.json) conserva dez falhas de expectativa: seis relativas aos bônus reais de conquista e quatro relativas à cobertura da varanda/viga. Após conferir recibos e imagens, corrigiu-se somente a fixture: classificação explícita dos oclusores, novos controles livres e cálculo de saldo pelos prêmios e conquistas. Não se removeu geometria nem se ocultaram colisões para obter a aprovação final.

Estado deste lote no [checklist de interiores](interior-standard-checklist.md): **2 lugares contínuos, 0 certificados integralmente, 2 em validação**. Não acrescentam portais ao catálogo de transições. Este documento poderá receber registros separados de cânion, bandidos e desempenho; suas conclusões não devem ser inferidas deste resultado dos abrigos.

## Acampamento remoto e combate

O acampamento em `(-1250, 0, -1640)` contém abrigo aberto, tambores, mesa e caixas sólidas. Três personagens próprios usam o combate existente: cápsulas físicas, projéteis móveis, proteção por obstáculos, dano e saque. O encontro é carregado por proximidade, admite um personagem por vez e guarda cada derrota no save; não cria novos inimigos para substituir os mortos. A interação com os segredos não depende de completar esse combate.

`tests/test_desert_bandit_runtime.gd` passou **33/33 checks** no Main .NET em [desert-bandit-runtime-48460-5547420](../evidence/desert-bandit-runtime-48460-5547420/report.json), com fontes estáveis, nenhum erro de script e nenhum outro motor concorrente. Os três personagens apareceram em 1,254 s após a prontidão; a aproximação física provocou tiros e 8 pontos de dano em Dante. A rodada observou 11 tiros, combate sem bloquear os controles, bloqueio de save durante confronto, respeito à proteção existente do jogador, pausa em menu, duas mortes por arma real do jogador, cobertura física pela caixa e persistência dos três bits de derrota. A última morte usou a API de dano de produção com seed que produz saque pela chance normal. O jogador percorreu 2,23 m apoiado no piso e recolheu a pistola a 1,004 m, dentro do raio normal de 1,05 m. O centro do item e a cápsula inicial estavam livres de sólidos.

A recarga usa `SaveStore` e arquivos isolados; as posições de teste de cobertura e descarregamento são diagnósticas, não prova de percurso. Ao descarregar e retornar, os derrotados não reapareceram. [Combate](../evidence/desert-bandit-runtime-48460-5547420/camp-active-combat.png), [cobertura](../evidence/desert-bandit-runtime-48460-5547420/camp-crate-cover.png) e [saque recolhido](../evidence/desert-bandit-runtime-48460-5547420/camp-loot-collected.png) possuem capturas reais. Ainda falta avaliação temporal própria do combate.

Histórico preservado: a primeira rodada passou combate e coleta, mas exigia chegar ao centro de um item já recolhido. A fixture passou a observar o contato de coleta e o trajeto apoiado, sem mudar o raio do jogo. Uma segunda rodada não admitiu o acampamento dentro de 10 s; sem telemetria suficiente, sua causa permanece em investigação. A terceira acrescentou somente observação de inicialização a 1 Hz e passou os 33 checks funcionais, sem correção do runtime entre essas duas execuções. A leitura do código identificou duas hipóteses ainda sem prova: a restauração pode rejeitar o ponto salvo e mover Dante ao retorno distante, ou a fixture pode avançar após seu prazo de inicialização sem confirmar novamente toda a prontidão. Não foi identificado um caminho que perca o registro da região após a inicialização completa. O resultado funcional aprovado não demonstra correção da falha intermitente.

## Relevo físico e acesso ao platô

O cânion além da rodovia de sal usa uma superfície contínua com os mesmos triângulos no desenho e na colisão. A entrada fica em `(-860, 0, -1540)`, seguindo para Z negativo. Há paredes rochosas, um corredor livre, uma alça de terra de 16 m e um platô a 22 m. Rochas, cactos e troncos maiores respeitam as reservas de circulação; cinco animais pequenos animados — três cobras e dois escorpiões — ficam nas margens. Fauna usa instâncias agrupadas e atualização física; não interfere com a direção nem acrescenta dano.

No percurso [desert-canyon-drive-131560-5166535](../evidence/desert-canyon-drive-131560-5166535/report.json), os **35 checks de física passaram**: Bison percorreu 551,6 m até o platô, Dante saiu, caminhou e embarcou novamente; houve retorno conduzido de 100 m, saída na descida, barreiras laterais sólidas e descarregamento/recarga com a mesma malha. A saúde do veículo permaneceu em 295. O carro recebe ajuste de velocidade vertical apenas sobre o terreno contínuo marcado, preservando colisão e dano dos obstáculos. A posição de saída é projetada no piso físico local, evitando rejeitar uma saída livre na encosta.

A execução terminou com falha de integridade de fontes porque outro chat alterou `DesertRegion.gd` durante o teste. Portanto registra evidência física observada, **não uma rodada final integralmente aprovada**. Foram gravados 3.078 quadros em 104,625 s, sem omissão de quadros renderizados. A inspeção identificou corte da encosta pelo enquadramento ortográfico e serrilhado da sombra; correções e validações visuais permanecem em andamento.

A rodada final, após corrigir a câmera, passou **37/37 checks**: [desert-canyon-drive-93908-6502652](../evidence/desert-canyon-drive-93908-6502652/report.json), fontes estáveis, sem erros nem outro motor concorrente. Repetiu os 551,595 m de subida e 100,720 m de retorno com saúde 295, caminhada e ambas as saídas normais. A câmera agora considera a pegada do alvo e a superfície sob o plano próximo inteiro, com cálculo limitado a 10 Hz, cache e ajuste local de inclinação/distância. Preserva zoom, orientação exterior, interiores e câmera da drag. A validação usa uma grade independente de 25 pontos do plano próximo, não o resultado do próprio solver: 677 grades na ida e 172 na volta, folgas mínimas de 1,062 m e 1,235 m, sem amostras dentro do terreno. A linha carro–câmera também permaneceu livre. Essa cobertura amostral não certifica todo o frustum continuamente nem colisão da câmera com qualquer objeto.

A sequência final registra **3.075 quadros em 104,650 s**, sem quadros renderizados omitidos ou erro de gravação, limitada a 30 Hz para captura. Não usar seus tempos como benchmark de jogo. O serrilhado das sombras permanece uma pendência separada da correção do recorte.

Na revisão amostral de `sequence/01835.jpg`, `01874.jpg`, `03000.jpg` e `03074.jpg`, o carro aparece inteiro na subida e na volta, sem a grande cunha clara; a parede próxima permanece sólida abaixo do veículo. A orientação diagonal está preservada. A oclusão parcial de Dante no último quadro vem do próprio carro. `plateau-arrival.png` e `natural-return.png` também foram revistos. O agente identificou os dentes ainda existentes nas sombras e a silhueta triangular simples das aves; não foram revistos individualmente todos os quadros.

### Validação final com malha refinada e aves

Após o refinamento local, [desert-canyon-drive-109516-7380471](../evidence/desert-canyon-drive-109516-7380471/report.json) passou **37/37 checks**, com fontes estáveis, stderr vazio e nenhuma sobreposição de motores. Este é o percurso final da versão integrada; a rodada `93908` acima documenta a etapa anterior da câmera. Foram 551,643 m até o platô e 100,719 m no retorno, sem dano ao veículo (295 antes/depois), incluindo caminhada, reembarque e saída na descida. As 677 grades de plano próximo na ida e 172 na volta tiveram folgas mínimas de 1,053 m e 1,182 m. O descarregamento e retorno recriaram o nó de colisão mantendo o hash dos vértices e a altura; desenho e colisão continuaram iguais. Essa parte usa reposicionamento diagnóstico, não representa a volta completa pela estrada.

A gravação contém **3.071 quadros em 105,268 s**, sem omissões de quadros renderizados ou falhas, com limite de captura de 30 Hz. A revisão de `01871/01875/01879` na subida e `02961/02965/02969` no retorno encontrou o carro inteiro, paredão sólido e nenhuma cunha clara ou salto grosseiro entre essas amostras. `mouth-to-plateau-02.png`, `plateau-arrival.png` e [natural-return.png](../evidence/desert-canyon-drive-109516-7380471/natural-return.png) também foram examinados. O contorno da sombra melhorou, mas conserva serrilhado fino.

As três aves mantêm o mesmo lote, escala, trajetórias e quantidade. A nova malha de 38 triângulos acrescenta tronco, cabeça, cauda e pontas de asas. Nos quadros `03000`, `03020`, `03040–03043` e `03060`, corpo e asas aparecem unidos, com forma e cor coerentes; a ave que sai pelo alto cruza o limite da tela. Não foram revistos individualmente todos os quadros, nem se certifica iluminação noturna ou desempenho pela gravação.

## Medição renderizada do estado atual

[desert-frontier-measure-155440-5629797](../evidence/desert-frontier-measure-155440-5629797/report.json) concluiu os três cenários no Main .NET, Vulkan Mobile / RTX 4060 Laptop, 1280 × 720, sem limite de FPS, sem outro motor concorrente, erros ou alterações de fontes. São 10 s de aquecimento e 30 s de coleta por cenário; as pausas de fotografia ficam fora da coleta. Esta rodada antecede a correção de frustum da câmera.

| Cenário | p95 / p99 | Máximo | Entidades confirmadas |
| --- | --- | --- | --- |
| Cânion diurno | 2,050 / 2,549 ms | 15,256 ms | 5 animais ativos; 10 lotes de flora seca |
| Ruínas diurnas | 2,313 / 3,284 ms | 30,609 ms | Casa/cabana residentes; jogador apoiado |
| Acampamento diurno | 2,919 / 3,918 ms | 9,603 ms | 3 bandidos vivos, residentes e no quadro |

Nenhuma amostra excedeu 33,3 ms. A população solicitada é 24, mas a população civil efetivamente residente nesses locais afastados foi **zero**; havia um veículo e, no acampamento, os três bandidos específicos. Dante permaneceu vivo, apoiado, sem modo invulnerável e sem menu. O acampamento foi medido a 33 m, fora do alcance de agressão, com o tamanho de câmera permitido pelo jogo em 45; isso não mede tiroteio nem prova acesso físico. A fauna não apresentou erros de interpolação nessa execução.

Essa é uma medição absoluta válida, **não aprovação de regressão de desempenho**: não existe referência anterior íntegra para a introdução conjunta de relevo/fauna/ruínas/bandidos. O teste de referência do horizonte teve fontes alteradas por outro chat. Os problemas de custo previamente registrados na ponte permanecem fora desta medição. Falta comparação equivalente e cobertura noturna dos novos abrigos.

A tentativa `desert-frontier-measure-22008-5387870` coletou somente o cânion após a câmera (p95/p99 2,169/3,329 ms, máximo 20,979 ms), com fontes estáveis e sem sobreposição. O relatório terminou inválido porque o novo seletor `--canyon-only` ainda encontrava uma condição final que exigia três cenários. A fixture foi corrigida para exigir exatamente o número selecionado e registrá-lo. Preservar essa tentativa com seu erro de protocolo; não convertê-la retroativamente em aprovação nem atribuir sua variação à câmera sem um par controlado.

### Medição final do cânion refinado e confirmação

O seletor corrigido concluiu [desert-frontier-measure-144564-7990552](../evidence/desert-frontier-measure-144564-7990552/report.json). Como o aumento superou 5%, realizou-se uma única confirmação equivalente, [desert-frontier-measure-20680-7387878](../evidence/desert-frontier-measure-20680-7387878/report.json). Ambas usam a versão final, Main .NET renderizado, mesmo hardware, 1280 × 720, câmera normal, VSync desligado, FPS sem limite, 10 s de aquecimento e 30 s de coleta. São válidas, com fontes estáveis, stderr vazio e nenhuma sobreposição registrada pelo coordenador externo. A consulta interna de processos via PowerShell falhou nas duas; a exclusividade é sustentada pelo histórico do runner, não por essa consulta.

| Cânion diurno | p50 | p95 | p99 | Máximo | FPS médio | Quadros >33,3 / >66,7 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Referência `155440` | 1,178 ms | 2,050 ms | 2,549 ms | 15,256 ms | 778,46 | 0 / 0 |
| Final `144564` | 1,917 ms | 3,637 ms | 4,892 ms | 10,889 ms | 468,04 | 0 / 0 |
| Confirmação `20680` | 1,802 ms | 3,442 ms | 4,591 ms | 11,333 ms | 494,56 | 0 / 0 |

**Desempenho não aprovado como regressão resolvida.** A confirmação repete a piora relativa (p95 +67,9% e p99 +80,1% sobre a referência), apesar de ficar abaixo do orçamento provisório de 16,67 ms nesse cenário. Não ampliar a conclusão para condução, combate, ruínas noturnas ou primeira visita. As coletas finais têm 13.976 quadros em 29,861 s e 14.777 em 29,879 s; são tempos reais entre frames, com fotos fora da amostragem.

Entre referência e primeira final, população residente e carga de entidades permaneceram equivalentes: zero civis, um veículo, cinco animais do cânion, nenhum bandido, 11 células, dez lotes de flora seca e três plantas da expansão em um lote. Os draw calls p95 passaram de 116 para 118; memória estática final de 635,44 para 647,28 MiB. Há aumento conhecido da geometria, mas também oito fontes alteradas e uma nova: câmera, terreno, aves, região, expansão, formas de terreno da expansão e fixture. O enquadramento mudou de inclinação de 45° para 37,51°, mantendo tamanho 20. Portanto, o par documenta a piora observada sem isolar qual mudança causou o custo. Não atribuir tudo ao refinamento ou às otimizações do outro chat.

Os monitores de CPU/física são snapshots repetidos, não tempos sincronizados de cada frame; não somá-los nem usar seu p99 para explicar o p99 de parede. Não há medição GPU ou térmica que resolva a atribuição. A versão final confirmou `scratch_released=true`, 214.389 amostras temporárias liberadas e caches de geração vazios, preservando as faces necessárias para renderização, câmera e colisão.

### Horizonte na câmera da drag

[desert-horizon-measure-30348-5822993](../evidence/desert-horizon-measure-30348-5822993/report.json) concluiu três cenários com fontes estáveis, sem erros e sem motor concorrente. A prova foi iniciada pelo fluxo real, mas seu controlador foi suspenso para manter o enquadramento durante a medição; posições de meio/fim são fixtures, não travessia. Os demais sistemas do Main permaneceram ativos. Cada coleta usa 10 s de aquecimento e 30 s de medição.

| Cenário | p95 / p99 | Máximo | Quadros acima de 66,7 ms |
| --- | --- | --- | --- |
| Largada noturna | 4,584 / 5,966 ms | 72,500 ms | 1 |
| Largada diurna | 4,170 / 5,710 ms | 82,415 ms | 1 |
| Câmera normal no cânion | 1,947 / 2,396 ms | 5,675 ms | 0 |

As [montanhas noturnas](../evidence/desert-horizon-measure-30348-5822993/grid-night-before.png) e [diurnas](../evidence/desert-horizon-measure-30348-5822993/grid-day-before.png) mostram cristas e patamares irregulares em profundidade, substituindo os cilindros anteriores. A revisão é dessas capturas, não uma aprovação artística integral ou temporal. Os dois picos de frame time permanecem registrados; não foram atribuídos ao relevo sem profiler. A referência anterior teve arquivos de carros alterados durante a coleta, portanto não é um par válido para aprovar regressão.

## Diagnósticos visuais do cânion: resultados e limites

As capturas separaram dois defeitos: a cunha clara em primeiro plano vem da câmera ortográfica entrando na colina próxima; o contorno serrilhado da sombra permanece independente desse recorte. Nenhum dos ajustes experimentais de sombra foi adotado no runtime.

| Controle na cena real | Resultado observado | Decisão |
| --- | --- | --- |
| Ocultar apenas `DistantThermalGliders` | A cunha grande permanece; as três aves estavam fora do quadro. | As aves não explicam essa cunha. Isso não identifica automaticamente todo triângulo claro de capturas anteriores. |
| Desligar apenas a projeção de sombras do terreno | Os dentes grandes desaparecem, mas a cunha clara permanece. | Os dois defeitos têm origens distintas; desligar a sombra não é uma correção aceita. |
| Material simples, inclusive sem iluminação | A cunha permanece. | O shader de areia/arenito não é a causa suficiente do recorte. |
| Raios físicos e interseções de triângulos das malhas | Os pontos investigados atingem o terreno do cânion; um triângulo da colina próxima está a aproximadamente 2,8 m do raio da câmera. Nenhuma malha externa sobreposta foi encontrada à frente nesses pontos. | Revisar o volume visível da câmera, além da linha central para o alvo. A cobertura se limita aos pixels registrados. |
| Dobrar a distância da câmera no eixo óptico, conservando projeção ortográfica, orientação e tamanho | O recorte desaparece, mas a colina passa a ocultar parte da traseira do carro. | Distância isolada não basta; a visibilidade da pegada do alvo também precisa orientar a inclinação. |
| Desativar o descarte de faces somente no terreno | O verso da mesma colina torna-se visível em primeiro plano. | Confirma a câmera dentro/atrás da superfície próxima. Não adotar material de faces duplas para mascarar o problema. |
| Projetar sombras das duas faces do terreno | Os dentes e a cunha permanecem. | Não adotado. |
| Normal geométrica por fragmento | As facetas ficam mais evidentes; o defeito não melhora. | Não adotado. |
| `LIGHT_VERTEX` deslocado 0,02/0,06 m pela normal geométrica | Não remove o defeito. | Não adotado. |
| `shadow_normal_bias` global 0/0,25/0,5, mantendo depth bias 0,1 | Os valores menores aumentam a auto-sombra. | Sol permanece com o valor original 2,0; nenhuma alteração global. |
| Normal de vértice apontada para cima e normal autorada restaurada no fragmento | Sem melhoria visível. | Não adotado. |
| Deslocamento local de receptor 0,3/0,6 m, limitado às encostas elevadas | Aumenta os dentes/artefatos triangulares. | Não adotado. |

As evidências principais são `evidence/desert-canyon-drive-131560-5166535`, `evidence/desert-shadow-diagnostic-113088-5657764`, `evidence/desert-shadow-diagnostic-117984-5367825` e `evidence/desert-shadow-diagnostic-15900-5652825`. Os arquivos JSON registram os estados e as restaurações. Essas sessões pausam a cena, trocam materiais e fazem leituras de imagem; os números de FPS exibidos nas fotos não são medições de desempenho.

### Limitação da captura estática do candidato de câmera

Em `desert-shadow-diagnostic-15900-5652825`, o helper estático recebeu `camera.offset` em vez do offset exterior efetivo. O azimute mudou de 45° para 0°. Portanto, a foto `camera-frustum-candidate.png` **não comprova a correção do enquadramento original**, apesar de registrar distância 55,95 m, folga conservadora de 1 m no plano próximo e ausência de limite de inclinação. O custo isolado do primeiro cálculo, cerca de 1,93 ms nessa sessão, também não é um benchmark.

A integração usa o offset exterior efetivo. A validação deve vir do percurso real posterior, com o carro inteiro visível, ausência de recorte da colina, estabilidade ao mover/virar/sair do cânion e comparação de frame time. A captura estática permanece como diagnóstico de implementação, sem certificar a câmera integrada.

### Refinamento local: contorno melhorado, serrilhado residual

O comparativo de pose, câmera, luz e material fixos em `evidence/desert-shadow-diagnostic-103892-5311327/terrain-mesh-refinement.json` mostrou redução dos dentes grandes com subdivisão local de 2 m para 1 m. As fotos `mesh-refinement-original.png` e `mesh-refinement-local-1m.png` conservam a mesma composição. A hipótese de diferença entre a superfície triangulada e as normais suavizadas é compatível com o resultado; não se afirma ter isolado toda a causa da sombra.

O refinamento foi integrado: áreas íngremes ou com erro de interpolação recebem células de 1 m; bordas vizinhas usam os mesmos pontos intermediários para não abrir fissuras. Permanecem o campo de alturas, materiais, normais e luz original. A malha passou de 106.720 para 264.248 triângulos em 35 células de cenário: 25.865 quadrados-base sem refinamento, 24.629 refinados e 2.866 de transição. Desenho, consultas de altura e colisão derivam das mesmas faces. Os caches temporários de geração são liberados quando a construção termina; as faces usadas por física e câmera são preservadas.

O diagnóstico visual registrou restauração das malhas e manutenção dos colisores, mas a execução combinada terminou com erro de tipo no helper separado de aves e timeout. Isso não é uma sessão integralmente aprovada. O erro do helper foi corrigido; a versão real integrada foi exercitada pelo percurso posterior de 37 checks, descrito acima. Os 167,8 MB e 6,04 s registrados na preparação do candidato incluem original e candidato coexistindo e caches ainda retidos; não são custo incremental medido do runtime final.

A comparação do retorno real `109516` com `93908` confirmou a melhoria: pontas grandes deram lugar a contorno fino e a encosta próxima perdeu facetas maiores. **Serrilhado fino ainda visível; iluminação não certificada globalmente.** Nenhum ajuste experimental de shader, bias ou desligamento de sombras foi adotado.
