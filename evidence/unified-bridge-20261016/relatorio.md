# Reconstrução das pontes — 16/10/2026

## Escopo e diagnóstico

Pedido: substituir a construção inteira entre cidade inicial, deserto e montanha de gelo por um conjunto visual contínuo, com três agentes, preservando acessos, tráfego e a obra vinculada à última missão. Este relatório descreve o estado comprovado pelos logs disponíveis; a entrega integrada ainda tem pendências.

O diagnóstico separou trechos funcionais de peças de renderização:

- O braço leste anterior tinha **cinco trechos construtivos**: encontro da cidade, conector, vão principal, encontro da serra e túnel. Os **três lotes de malha** do acabamento não eram três pontes.
- O braço norte era um gerador independente, com **61 segmentos de eixo**, aproximação curva, tabuleiro, abertura de 13 m e chegada ao deserto. Esse número descreve tesselação; não significa 61 pontes nem 61 estilos visuais.
- São **dois braços rodoviários**, com destinos e condições independentes. A abordagem inteira também inclui o tronco das duas pistas originais e suas curvas; refazer apenas a reta depois de X=393,75 deixaria o começo antigo.
- As estruturas estreitas elevadas que cruzam o panorama pertencem à ferrovia: estação Northgate, north_throat, north_west, junction_chord e north_east, com ramais Cobre/Pinhais/coastal. Possuem trilhos e dormentes e estão a 12–14 m; não são alças rodoviárias legadas. A rodovia fica em Y=0 e o braço norte em Y=2,4. A ferrovia foi preservada.

Instruções utilizadas: AGENTS.md, CLAUDE.md e docs/HOW-TO-DEVELOP.md; skills auditoria-viaria, guardiao-do-jogo, testes-com-criterio, performance-do-jogo, validar-iluminacao e validar-terrenos-pisos, conforme as camadas alteradas. Motor das execuções próprias: Godot 4.7.2 .NET; Main renderizado em Vulkan Forward Mobile, RTX 4060 Laptop, 3440×1440 nas capturas estáticas e 1280×720 nas sequências JPEG finais. Compilações C# Debug/Release registradas como aprovadas, sem avisos/erros; execução nativa é verificada separadamente pelas fixtures.

## Construção atual

`UnifiedBridgeKit` gera pista, passeios chanfrados, estrutura e guardas compartilhados. O tronco começa em (375,0,-125), segue até Z=-262,5, percorre o eixo médio das duas curvas originais e continua até X=631,25, incluindo piso do túnel. O envelope contém os centros e bordas das pistas autoradas; o grafo original permanece separado da geometria nova.

O braço norte conserva eixo e progressão. A obra mantém barreira, trabalhadores, ausência de piso no vão incompleto e a mesma condição de conclusão. O encontro com a cidade nasce no piso físico zero. Calçadas possuem concordância longitudinal; no fim norte, a pintura usa o mesmo recuo e largura do trecho do deserto e os guardas recebem postes visuais finais, sem novos colisores.

A boca norte tem divisão explícita de superfícies: o leste recorta seu passeio pelo asfalto norte; o norte oferece asfalto e colisão até o asfalto principal, recortando seu asfalto contra o asfalto leste e seus passeios contra o tabuleiro leste. A faixa branca oeste é interrompida apenas na entrada. A avenida urbana permanece aberta para conversões; guardas começam depois do entroncamento. Não há tapa-vão central separado.

`UnifiedRoadAsphalt` compartilha instância de material, textura em coordenadas globais, chuva e reflexo costeiro entre cidade, pontes e vias de chegada. Concreto e metal também são compartilhados. Sete fontes de luz existentes no vão leste foram preservadas; seus postes foram apoiados no novo perfil. Os lotes curtos de desenho continuam necessários à distribuição de luzes e não implicam mudanças de acabamento.

Geradores regionais, suporte Land, proteção costeira e acabamento urbano são recortados exatamente pelos envelopes novos. A decoração reconhece o asfalto contínuo e evita mobília e remendos no antigo intervalo entre pistas. No deserto, o visual fica 2,6 cm acima do terreno, com colisão na cota física do terreno; foi retirada a lâmina física de 18 mm que criava obstáculo no encontro.

O clima costeiro segue até 12 m depois das saídas norte e do túnel, com mistura gradual em terra. A alteração não desloca a fronteira lógica usada pelo streaming. A variação artificial de exposição durante a travessia foi retirada.

Corpo leste/túnel e os três grupos norte possuem PackedScene geométrico preparado sob a cortina: raiz sem script/controladores, malhas/formas/materiais retidos e reutilizados na remontagem. Ownership é removido recursivamente antes de transferir os filhos da raiz temporária. As sete luzes noturnas são reencontradas uma vez por montagem por metadado; não há varredura por quadro. O prewarm inclui materiais reais de túnel, luminárias e canteiro, inclusive variante MultiMesh. **Reutilização de recursos não comprova custo de instanciação ou registro físico; isso depende de medição.** Streaming e liberação por distância continuam ativos.

`GETECO_UNIFIED_BRIDGE=0` mantém o construtor anterior exclusivamente para diagnóstico A/B no mesmo export. O padrão é o conjunto novo.

## Resultados funcionais disponíveis

| Evidência | Resultado e alcance |
| --- | --- |
| `climate-direct.log` | 1.189 verificações, zero falhas. Contratos de clima, paleta e frio; headless não comprova aparência ou estabilidade temporal. |
| `physics-fixed.log` | 57 verificações, zero falhas, sem drive: geometria, piso único nas amostras, guardas, boca norte, grupos de colisão, abertura/fechamento e cache em fixture. Há aviso de um ObjectDB no encerramento. |
| `drive-return-corrected.log` | 62 verificações, zero falhas; inclui os controles geométricos e a volta leste corrigida, 119 waypoints, 84,736 s, suporte contínuo, nenhum contato inesperado e saúde preservada. |
| `physics-direct.log` | Execução inicial: ida leste e norte nos dois sentidos percorridos com suporte, sem contatos e sem dano. A execução completa falhou por piso duplicado na cabeceira e por alvo de volta no passeio. Esses resultados não são apresentados como uma execução integral verde do estado final. |
| `bridge-approach-direct.log` | BRIDGE_APPROACH_TERRAIN PASS, zero falhas. Três avisos ObjectDB ao encerrar. |
| `test_north_gateway_progress-direct.log` | Política de progressão: 40 verificações, zero falhas; inclui pré-requisitos e dados malformados. Não substitui conclusão real da campanha. |
| `campaign-epilogue-fixed.log` | Integração funcional no Main/.NET com save isolado: **73 verificações, zero falhas, exit 0**, fontes iguais no início/fim. Evento final aceito, obra removida automaticamente, quatro avanços pelo botão real do epílogo, caminhada e apoio, streaming com carro persistente, save do desbloqueio e restauração de save legítimo versão 1. Relatório: `../north-gateway-integration-128756-10712295/report.json`. Execução headless; não certifica visual, temporal ou FPS. Há erros de descarte de nós/recursos no encerramento. |
| `main-drive-fixed.log` | Main renderizado, SUV e inputs produtivos: **três percursos concluídos**, apoio contínuo, sem contatos estáticos, tráfego observado e zero teleportes durante cada rota. A execução global teve 59 checks e duas falhas na preparação do quarto embarque e na contagem derivada de quatro rotas; não é uma execução integral verde. |
| `main-drive-north-return.log` | Retomada filtrada de `norte_volta`: **25 verificações, zero falhas**, percurso concluído, apoio contínuo, sem contatos/dano, tráfego produtivo observado e checkpoint isolado. Os quatro percursos estão cobertos pela união destas duas execuções. |
| `test_regional_atmosphere-direct.log` | 25 verificações, zero falhas. |
| `test_desert_entrance_geometry-direct.log` | Verificações de geometria, concordância do piso, largura e câmera da entrada passaram. |
| `regions-final.log` | REGIONS PASS, zero falhas, exit 0. |
| `bridge-approach-final.log` | BRIDGE_APPROACH_TERRAIN PASS, zero falhas, exit 0. |
| `cold-admission-final.log` | COLD_ADMISSION: 11 verificações, zero falhas, exit 0. |
| `native-driving-admission-fixed.log` | NATIVE_DRIVING_ENTRY PASS, exit 0: pose válida, apoio e porta livres, interação de embarque produtiva. Prontidão exige sessão e produção prontas, jogador sem input lock e cortina de carregamento removida. |
| `regions-observed-1536.log` | Execução observada de outra sessão: REGIONS PASS, zero falhas. Cobertura reaproveitada conforme o estado daquela execução. |
| `cold-admission-observed-1536.log` | Execução observada de outra sessão: 11 verificações, zero falhas. |

A volta inicial mirava (382,5,0,-120), que está no passeio: `northbank_gateway_avenue` é horizontal em Z=-125 e tem 7,5 m de largura, com asfalto em Z=-128,75..-121,25. O poste em aproximadamente (381,25,-120) era legítimo e foi preservado. A fixture foi corrigida para entrar pela avenida e fazer arco de raio 6 m; nenhuma assertion ou tolerância foi afrouxada. `--drive` continua selecionando quatro percursos, e `--drive-route=<id>` permite repetir somente um caso válido, com contagem de execuções e JSON imediato por percurso.

A campanha integrada está **aprovada no cenário funcional exercitado**. Antes da conclusão, o teste confirmou quatro trabalhadores e barreira física, aproximação a pé e veículo real bloqueado, acesso leste disponível e consulta ao roteador C# compilado. O evento `transfer_document_collected` foi aceito pelo estado vivo da campanha e a atualização produtiva removeu trabalhadores/barreira e completou o vão. O teste avançou as quatro falas pelo botão Continuar da UI real, verificando o callback `aftermath.call_complete`, fechamento do diálogo e devolução do controle antes da caminhada até o terminal. Não houve desbloqueio manual de input, godmode ou atribuição direta de conclusão à ponte.

Os checks de ciclo de vida confirmaram liberação/reentrada do canteiro, retenção de apoio por carro persistente distante, suspensão de carro sem chão, remontagem e retomada física, e liberação após sua retirada. O SaveStore isolado persistiu o desbloqueio real; uma segunda inicialização restaurou o save legítimo versão 1 como ponte concluída, sem recriar operários. Os hashes das fontes permaneceram iguais durante a execução. Trata-se de uma fixture validada no ponto anterior ao documento; não é uma campanha inteira jogada desde o começo.

As execuções anteriores continuam registradas: `campaign-direct.log` falhou com fixtures que deixavam o carro padrão junto ao jogador/canteiro e tentavam criar veículo acima do piso real da rampa; `campaign-fixed.log` revelou morte/cancelamento antes do documento; `campaign-observer-fixed.log` avançou a conclusão, mas tentou caminhar com o epílogo normal ainda aberto. A correção estacionou o carro da fixture em avenida com apoio fora do canteiro, amostrou chão e folga do observador atrás do veículo, derivou pose do carro por eixo/tangente e sondas reais, e concluiu a conversa pelo botão produtivo. As falhas de preparação não foram convertidas em passes retroativos. O log final ainda registra erros `!is_inside_tree()`, recursos/RIDs e ObjectDB no encerramento, que permanecem uma pendência distinta da aprovação funcional dos 73 checks.

Os **quatro percursos produtivos no Main foram cobertos em duas execuções**, mantendo as falhas de preparação do quarto embarque na primeira. Em cada rota, o SUV permaneceu ocupado, com apoio contínuo e zero teleportes de fixture durante o movimento. Os logs registram `source_stable=true` nos arquivos monitorados; alterações de pintura aplicadas durante a janela do MainDrive exigem captura posterior e não são aprovadas por estes percursos físicos.

| Percurso | Tempo | Saúde antes → depois | Contatos e tráfego |
| --- | ---: | ---: | --- |
| Tronco/curva/leste, ida | 91,020 s | 190 → 190 | Sem contatos; até 15 veículos ambientes. |
| Tronco/curva/leste, volta | 131,888 s | 190 → 188,2218 | Contatos com NPC dinâmico na curva; sem contatos estáticos nem dano estático sem contato dinâmico. Até 15 veículos ambientes. |
| Norte, ida | 33,504 s | 190 → 190 | Sem contatos; até seis veículos ambientes. |
| Norte, volta — execução filtrada | 35,454 s | 190 → 190 | Sem contatos; até sete veículos ambientes. |

A direção está **funcionalmente coberta nesses percursos**, incluindo ida/volta pelos dois braços e integração com o tráfego. Não se afirma ausência de colisões com NPCs ou saúde intacta na volta leste. `main-drive-fixed.log` reteve as falhas globais “Dante vivo e livre antes de criar e embarcar no SUV” e “quatro percursos completos”; `main-drive-north-return.log` exercitou somente o percurso ausente após corrigir a preparação da fixture. O resultado inicial `main-drive.log` — 14 checks, três falhas e nenhuma rota — permanece histórico: seu helper inválido de Array[RID] não comprova piso ausente.

O check obrigatório de embarque nativo também passou em `native-driving-admission-fixed.log`, perto de (640,1,0,-283,3). O teste passou a aguardar a admissão final do Main: `session.ready_for_play` isolado era transitório durante `restore_location`, antes do posicionamento e assentamento finais. Agora verifica produção pronta, cortina ausente e controle liberado antes de admitir a pose e a porta. A falha anterior observada no túnel do canal e os logs incompletos continuam registrados; não equivalem a uma execução final aprovada daquele local nem são atribuídos à ponte reconstruída.

## Capturas e diagnóstico visual

Captura final no **Main real**, checkpoint isolado e roteador C# nativo confirmado: `../unified-bridge-capture-116564-10659441/report.json`, log `capture-day-clean.log`. Foram obtidos 12 enquadramentos diurnos, estado concluído, clima seco, mais panoramas e comparação da câmera diagnóstica com near=0,05/1,0. Não houve execução temporal nessa captura (`temporal=false`, `sequences=[]`).

O panorama anterior `../unified-bridge-capture-109532-11928208/panorama_tronco_bifurcacao.png` mostrava faixas claras largas no tronco e no interior da curva. A investigação encontrou pisos urbanos quay/grass em Y=0,008 sob o asfalto novo em Y=0,026. `HarborUrbanSurface3D.build_chunk` passou a recortar exatamente o território da ponte. Nas capturas finais, **as faixas largas desapareceram inclusive com near=0,05**, e início, curva e conector mostram piso escuro contínuo sem emenda cromática abrupta.

Em `panorama_tronco_bifurcacao.png` final, a pintura fina distante ainda parece fragmentada; `panorama_tronco_near1.png` a mostra contínua. Isso difere da antiga sobreposição de pisos: preenchimento do asfalto permanece limpo nas duas imagens e os enquadramentos próximos têm pintura limpa. O near da câmera produtiva não foi alterado. A comparação sustenta o diagnóstico localizado, não certifica ausência global de flickering.

O inventário de triângulos usa **somente entradas já existentes de MeshArrayCache**, sem readback em cache miss. O relatório final indica `complete=false`, 11 superfícies ausentes do cache e zero hits conhecidos nas três amostras. **Zero hits não significa ausência de piso; esse inventário não comprova unicidade no Main.** A unicidade demonstrada pelos testes físicos/visuais da fixture permanece uma evidência distinta.

A revisão posterior de acabamento usou `../unified-bridge-capture-135428-9752433/report.json`: **dia, obra fechada**, com barreiras, operários e vão incompleto; o acesso leste continua independente. A pintura regional foi recortada pelo proprietário correto, com respiro de 0,75 m após o fim do conjunto; a separação foi conferida visualmente nessa captura. O túnel e a chegada ao deserto não apresentam a antiga fusão entre dupla contínua e tracejado. A captura anterior 116564 permanece como histórico do diagnóstico, não como prova da pintura posterior.

O conjunto `../unified-bridge-capture-134572-8925594/report.json` cobre as vistas estáticas **noturnas com chuva, obra concluída**. Foram revisados conector, curva, vão, entrada/interior/saída do túnel, braço norte, cabeceira e encontro com o deserto. Asfalto e calçadas permanecem contínuos; guardas acompanham as curvas e terminam com postes visuais. A vista chamada `norte_obra` pertence ao estado concluído e não demonstra o bloqueio anterior. Nas 12 vistas, pesos de montanha/deserto são zero, não há frio/neve e a chuva exterior é interrompida no interior do túnel. As sombras e volumes são coerentes nas imagens, mas essas fotos isoladas não comprovam estabilidade temporal. Suas sequências PNG de apenas 39/48/69 frames em cerca de 30 s foram insuficientes para essa conclusão.

A aquisição temporal final foi `../unified-bridge-capture-139052-12131635/report.json`, **Main real, roteador C# confirmado, noite/chuva, obra concluída**, janela e framebuffer efetivamente verificados em 1280×720, escala 3D 1,0 e JPEG qualidade 0,95. As três sequências têm zero frames renderizados omitidos no registro:

| Sequência | Frames | Duração registrada da sequência | Cadência de aquisição pelos timestamps |
| --- | ---: | ---: | ---: |
| Tronco e curva | 1.052 | 30,036970 s | 35,03 imagens/s |
| Encontros leste e túnel | 1.272 | 30,041387 s | 42,35 imagens/s |
| Norte concluído e chegada ao deserto | 1.296 | 30,033632 s | 43,16 imagens/s |

Os três agentes dividiram a revisão por percurso, com amostras regulares de intervalo máximo de 0,25 s e pares adjacentes dos maiores saltos de luminância. No leste, foram inspecionadas 157 amostras, intervalo máximo de 0,221977 s, os oito maiores pares e detalhes dos portais/pintura em resolução integral; contatos e índices estão em `review_leste_regular_0..4.jpg`, `review_leste_adjacent_luma.jpg` e `review_leste_temporal.json` na pasta da captura. **Não foi identificado flicker involuntário de fontes ou pintura na cobertura revisada dessas três sequências.** Clarões exteriores observados são compatíveis com o relâmpago autorado de `StormPresentation`: envelope de 0,57 s, modulação explícita de sol/ambiente e cancelamento em abrigo. Essa atribuição é uma inferência fundamentada no código e na sequência visual; o runner não registrou o contador de relâmpagos para correlação individual de cada clarão.

As sete luminárias do vão leste mantiveram registro válido, visibilidade local/na árvore, alcance de 17 m e energia aproximadamente 1,4 em todas as amostras. Portanto, a escuridão exterior não foi causada por perda de registro ou energia zerada nessa captura. O conector em X=440 está fora do alcance do primeiro poste em X=460; o vão em X=508 está dentro do alcance dos postes vizinhos, mas a apresentação permanece escura. Não houve ajuste de luzes para ocultar esse resultado. O leste confirmou chuva interrompida em X≈578,133 e retomada em X≈631,303, nos portais; pesos de montanha/deserto permaneceram zero e `cold_visible=false` em todos os três percursos. A saída mantém o respiro de pintura sem duplicação.

No leste, `get_image` consumiu em média 6,447 ms e a gravação JPEG 9,660 ms, total 16,107 ms por imagem; o maior intervalo entre timestamps foi 64,257 ms. A redução de compressão melhorou a aquisição em relação ao PNG. **Cadência de imagens e tempos de aquisição não são FPS de gameplay ou benchmark.** O jogador foi interpolado pela fixture com física suspensa apenas nas sequências; câmera, streaming, clima e demais sistemas produtivos continuaram ativos. Essa evidência não substitui os percursos físicos, não certifica todas as horas/climas/áreas do jogo e não elimina a fragmentação distante de pintura observada no panorama com near=0,05.

## Falhas e pendências bloqueantes

- **Limite da aprovação visual/temporal:** acabamento diurno com obra fechada e noturno com chuva possui evidência estática; as três sequências finais de cerca de 30 s sustentam somente a revisão temporal de noite/chuva com obra concluída descrita acima. Não há aprovação global para todo clima/horário, nem nova sequência diurna equivalente. A fragmentação fina distante com near=0,05 e a apresentação exterior escura permanecem registradas.
- **Performance comparativa não aprovada:** há uma baseline válida, mas não há A/B release comparável concluído. Contadores das capturas, PNG/readback e testes com GPU/CPU concorrentes não são benchmark. Medir primeira visita e revisita no mesmo export, renderer, resolução, clima e carga; relatar frame time p50/p95/p99/máximo e quadros acima dos limites. Meta HOW-TO-DEVELOP: p50 ≤16,7 ms e nenhum quadro >33 ms após jogável; regressão superior a 5% em p95/p99 pede confirmação finita equivalente.

Houve uma medição inicial válida e isolada de baseline, PID 146096, entre 16:58:42 e 17:00:57, iniciada por uma shell que permaneceu ativa após o cancelamento de seu processo pai. O resultado bruto foi preservado em `trunk-before-first-observed.json`: 8.692 frames, 54,405701 s medidos, média de 159,76 FPS, frame time p50=5,27 ms, p95=11,28 ms, p99=15,02 ms e máximo=67,56 ms; três frames acima de 33 ms e um acima de 66,7 ms. Esses números descrevem somente a baseline; o pico acima da meta permanece registrado e não representa aprovação de performance do conjunto reconstruído.

O lote 27102 repetiu o caso anterior com PID 150536 às 17:01:12, mas outra sessão iniciou `measure_lightning_storm` (PID 2272) às 17:02:18 durante a medição. A raiz encerrou somente o PID 150536 de sua tarefa; o lote terminou com exit 127, sem executar o caso posterior. A interferência está registrada em `benchmark-interference.json`. **A segunda medição cancelada não é um resultado e não há comparação A/B concluída ou performance aprovada.** O arquivo anterior em AppData (`antes1`) permanece correspondente à primeira medição válida, preservada também no bruto observado. O usuário escolheu explicitamente “Entregue a ponte com FPS pendente”. As medições desta tarefa foram encerradas, sem deixar novas execuções próprias na fila. Não há aprovação de FPS ou ausência de regressão de performance.
- Logs de campanha, MainDrive e capturas incluem avisos/erros de liberação de recursos no encerramento; não ocultados nem interpretados como uma sessão limpa. Falhas de fixture não autorizam ignorar esses diagnósticos.

## Trabalho concorrente e preservação

O repositório já tinha alterações de várias sessões. Não houve limpeza, restauração destrutiva ou substituição do mapa salvo por esta tarefa. NativeRegion, CityChunkDressing e outros arquivos compartilhados receberam integrações locais, preservadas por snapshots e comparação dos trechos. A ferrovia e seus trabalhos concorrentes permaneceram intactos.

O recorte de `HarborUrbanSurface3D` no working tree depende da estrutura concorrente `_rounded_parts`/`group.polygons`, introduzida por outra sessão. `HarborUrbanSurface.own.patch` registra somente o recorte desta tarefa e integra o registro versionado sem incorporar a reforma alheia; não é um patch autossuficiente aplicável ao HEAD sem essa estrutura. O código do recorte permanece preservado no working tree. As propostas `NativeRegion.HEAD-proposed.patch` e `CityChunkDressing.HEAD-proposed.patch` foram preparadas separadamente para permitir integração com o HEAD sem capturar mudanças concorrentes. O commit funcional registra os hunks próprios separáveis e esses artefatos; não inclui a reforma concorrente. Não houve push.

O mapa salvo foi alterado externamente durante o trabalho: hash inicial observado `353c18c7803af7e2f68b6b0db9f5c46b03f7f1a595b4388a2a05d26b20385fa4`; após abertura do editor por outra sessão, `29b7e5bf90b6d9c0a0829f911d3d6553922f38720884ef989baf0c79298fcb5f`, conferido novamente nesta revisão. Essa alteração foi preservada.

As execuções desta tarefa foram serializadas. A fila ficou ocupada por jogos, previews e testes externos; somente processos especificamente autorizados pelo usuário foram encerrados. Depois de nova autorização direta, testes funcionais próprios puderam executar com uma janela externa preservada, mantendo um único motor desta tarefa por vez. Essa exceção não autoriza concluir desempenho em ambiente concorrente. Não houve autorização para push.

## Estado da entrega

Reconstrução implementada; contratos geométricos, os quatro percursos produtivos do Main em duas execuções, campanha integrada com 73 checks, obra/save/restauração e embarque nativo estão funcionalmente cobertos nos cenários descritos. O acabamento posterior de pintura foi conferido nas capturas finais; a revisão temporal de noite/chuva cobre os três percursos de cerca de 30 s, com limites explícitos. **Performance continua pendente, assim como os erros de encerramento e a cobertura visual fora dos cenários exercitados; a ponte inteira ainda não está aprovada em todas as dimensões.** O registro funcional preserva a separação do trabalho concorrente e as limitações desta entrega.


Entrega autorizada em 16/10/2026: reconstrução e validações funcionais/visuais entregues com FPS pendente por escolha explícita do usuário. Nenhum push. O registro Git inclui somente código próprio, hunks próprios de NativeRegion/CityChunkDressing e o patch de integração HarborUrbanSurface com sua dependência concorrente documentada; o acabamento validado completo permanece no working tree compartilhado, preservando a reforma alheia.
