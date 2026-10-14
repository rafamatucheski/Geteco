# Identidade visual por clima — implementação e limites

Estado em 13/10/2026: A/B/C ligados ao clima de Harbor, com validação funcional e capturas reais. **A semelhança com os conceitos gerados ainda não está aprovada.** As imagens da proposta também reinterpretaram materiais e arquitetura; não eram demonstrações de recursos funcionando no motor.

**Pausa solicitada pelo usuário em 13/10/2026:** implementação salva; testes e registro de performance passam a ser feitos pelo usuário. A execução `final-route` foi interrompida a pedido, sem concluir o percurso; não é evidência de aprovação integrada. O último passe também deixa de reclassificar malhas dinâmicas ocultas, atualizando-as antes da captura quando reaparecem. `final-visible-only/report.json` contém a última medição (67,41 FPS seco; 65,51 chuva; 42,80 noite chuvosa), com oscilações e foco da janela registrado: não certifica 60 FPS estáveis nem ganho causal sobre a base. Não foram descartadas alterações locais ou modificados saves pessoais.

## Fechamento: medição isolada e ciclo de vida

O pedido final de concluir o pacote iniciou a etapa de desempenho anteriormente adiada. O teste de moto de outra sessão (PIDs 67996/74288) foi encerrado **somente após autorização explícita do usuário**. A base `final-baseline/` rodou sem outro Godot, com inventário de processos em `final-baseline-processes.json`: Godot 4.7.2 .NET/Mobile, RTX 4060 Laptop, 1280×720, MSAA 2×, escala 100%, sombras altas/atlas 8192, VSync ligado e limite 144. Mantidos cena Main, população/tráfego normais, seed 13102026, posição (66, .15, 129), câmera 48. Cada clima tem 8 s de aquecimento e 30 s de medição sem leitura de imagem; PNG somente depois da janela.

| Base antes da otimização final | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| A, seco | 31,41 | 29,93 | 60,78 | 97,79 | 164,23 |
| C, chuva | 41,57 | 20,76 | 38,87 | 51,45 | 191,90 |
| Noite chuvosa | 37,23 | 22,43 | 49,70 | 93,79 | 154,94 |

O JSON contém amostras, quadros longos e tempos CPU/GPU por viewport. As medianas de GPU da vista principal ficaram em 2–3 ms; as capturas, abaixo de 1 ms. Esses tempos assíncronos não incluem todo o custo da aplicação nem devem ser simplesmente somados ao tempo de CPU. O regime da base já está abaixo da meta provisória de 60 FPS, e a população normal evolui entre os climas (16/21/23 NPCs no fechamento das janelas).

O perfil da mesma sessão (`20261013-165219-003-102356-e2c64db6`, depois de 100 s) atribui em média 10,87 ms/quadro à física completa, contendo 4,17 ms de `vehicle.physics` e 1,68 ms de `actor.physics`; são tempos inclusivos. Profiler e logger somam aproximadamente 1 ms/quadro. No quadro 3250, `stream.harbor.dressing_step` durou 130,434 ms dentro de um quadro de 191,89 ms. Esse registro não tem span próprio do gerente costeiro, portanto não demonstra sozinho quanto ele custa. Os picos após captura PNG ficam fora das janelas de benchmark.

O passe final preserva as resoluções/cadências e reduz o trabalho do gerente: atribui layers somente quando mudam, substitui oito projeções dos cantos por centro/extensões equivalentes, enfileira apenas malhas e suspende a captura da fachada fora do frustum com margem de 1 m. Mantém a seleção e os subsets enquanto estão fora da tela; a reentrada força captura imediata. O descarte oculta e retira as layers dos proxies antes de restaurar as câmeras, evitando cópias visíveis por um quadro.

Subsets de MultiMesh agora acompanham transformações, cores, custom data e quantidade visível da fonte. Somente os subsets existentes comparam o buffer nativo; reconstrução ocorre quando os dados mudam. Os proxies não recebem uma segunda interpolação física. `final-planar-interpolation.log` passou com três poses de projeção, descarte, frustum, alterações imediatas em fonte sem interpolação e alterações após renderização em fonte interpolada; stderr vazio. As primeiras tentativas do teste exigiam leitura imediata de setters interpolados e falharam. O diagnóstico mostrou que até a fonte ainda retornava o valor anterior, comportamento explicado pelo [código do motor 4.7](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/storage/mesh_storage.cpp): setters interpolados escrevem o próximo estado, enquanto getters acessam o estado renderizado. A versão corrigida comprova primeiro a atualização real da fonte, sem desligar a interpolação do jogo.

As seções seguintes preservam as etapas anteriores; suas pendências e números históricos não substituem este comparativo final.

## O que está no jogo

- Tempo aberto: sol quente, acentuado na tarde, com sombras mais frias. Céu parcialmente encoberto: sol marfim e preenchimento de maresia. Chuva: luz fria, saturação menor e acionamento gradual das luminárias existentes.
- Umidade compartilhada pelo asfalto e pelas poças: enche em 45 segundos, seca em 120 segundos e persiste no save. O tempo da cidade continua enquanto Dante está em outra área.
- Céu compartilhado para reflexos de ambiente em vidro/lataria, sem atualização por objeto. Vidros escuros deixam de receber o acabamento fosco de reboco.
- Chuva com 1.000 partículas máximas no emissor existente, respeitando intensidade, abrigos e regiões. Garoa e tempestade continuam distintas.
- Reflexos planares da geometria real no asfalto e nas poças, com filme molhado variável e desfoque contínuo. O lobo artificial das luminárias foi removido; os quads mantêm somente a iluminação difusa existente e a correção de neblina.
- Fachada da delegacia com panos de vidro entre as pilastras existentes, em duas malhas. Uma captura vertical compartilhada reflete o entorno da fachada selecionada; as demais superfícies continuam com o ambiente do céu.
- Material de asfalto compartilhado; continuidade do acabamento na ligação com a estrada rural. Geometria viária e colisões produtivas não foram alteradas.

A troca Harbor → pista de arrancada → Harbor → garagem também foi corrigida: cada sistema restaura o céu anterior, evitando reflexos costeiros presos no interior.

O usuário identificou placas retangulares claras no chão durante o teste de reflexos. A causa foi o shader aditivo das luminárias recebendo novamente a cor da neblina: até texels sem luz adicionavam essa cor ao piso. `fog_disabled` foi aplicado somente nesse shader de apresentação; a neblina do cenário e a luz do efeito permanecem. O teste renderizado `test_lamp_pool_fog.gd` compara piso sem efeito, versão defeituosa e correção, verificando cantos transparentes e preservação da luz. Sua primeira execução revelou um erro do próprio teste ao misturar coordenadas do viewport lógico e da imagem; a conversão foi corrigida antes da repetição.

## O que os conceitos mostram além disso

Os panos altos entre pilastras eram paredes azuis de concreto. A implementação agora acrescenta o envidraçamento, preservando pilastras, portas e colisão. A câmera elevada vê principalmente reflexos da rua numa fachada vertical; o gradiente de céu idealizado do conceito não é automaticamente reproduzido por um reflexo geométrico correto.

Os conceitos apresentam reflexos de geometria e um acabamento de pavimento/arquitetura que o tratamento de céu sozinho não reproduz. Por isso não é correto chamar o resultado atual de igual ou muito próximo.

Os helpers antigos em `tests/capture/`, `CoastalFacadeTrial.gd` e `CoastalReflectionProbeTrial.gd`, continuam exclusivamente experimentais. **A probe não foi promovida.** O runtime usa `CoastalPlanarReflections.gd` e `CoastalFacadeFinish.gd`, com câmeras espelhadas no plano físico do chão e do vidro.

## Implementação planar e limites de custo

O pedido posterior adiou explicitamente benchmark e otimização para a etapa final. Não foi feita nova certificação de FPS nesta etapa. As decisões estruturais já limitam o trabalho: dois SubViewports compartilhados (640 e 512 pixels de largura), materiais compartilhados, registro incremental de até 128 nós por frame e acompanhamento do descarregamento. Piso seco e interiores suspendem a captura correspondente. Câmera parada atualiza até 20 Hz; em movimento acompanha cada quadro para evitar reflexo preso à tela.

Após ver a direção funcionando, o usuário pediu moderação sobretudo na rua. A contribuição refletida do asfalto e da ligação rural foi reduzida em 50% (incluindo a parcela angular), mantendo a variação suave do filme. Poças e vidros mantêm resposta mais forte, para que o reflexo seja um detalhe localizado e não o assunto dominante de toda a cidade.

A intensidade reduzida foi conferida em `planar-restrained/c-rain.png` e `planar-restrained/night-rain.png`, capturadas no jogo real a 1920×1080. Shader compilado e sessão encerrada sem erros. Os contadores instantâneos de FPS nas imagens não são benchmark nem aprovação de desempenho.

Na continuação, a seletividade passou a ser também espacial: fora de bacias largas e irregulares o asfalto tem reflexão planar zero, em vez de uma reflexão fraca cobrindo a rua inteira. O teste renderizado `test_coastal_surface_selectivity.gd`, usando uma captura branca para revelar o efeito, mediu 22,44% dos pixels amostrados afetados no piso totalmente molhado e diferença zero no piso seco. A transição é suave e fixa no mundo; o teste não afirma que toda rua terá exatamente essa cobertura.

O agregado do asfalto reaproveita a textura e os mipmaps existentes, com carvão mais claro, menor dominante azul e contraste limitado. Vidros receberam azul mais presente, menor metalicidade (.48), rugosidade .20–.225 e variação discreta entre panos; concreto e juntas continuam foscos. A luz de preenchimento extra na chuva caiu de .14 para .065 para recuperar volume, preservando a iluminação noturna existente. Não foram adicionadas fontes de luz, câmeras de captura, emissores ou texturas de grão.

### Refinamento de fachadas e sombras

Os panos superiores da delegacia receberam revelos laterais de 4,5 cm, lintel e peitoril contidos na projeção das pilastras existentes. Essas faces têm iluminação pela sua orientação real; o vidro recebe oclusão suave somente nos 13 cm junto ao perímetro (até 22%, influência de 10% na luz direta). Juntas e revelos são foscos e compartilham a mesma malha, com cores por vértice. Continuam duas malhas no acabamento; portas, janelas térreas e colisão não foram alteradas. A força dos reflexos e a máscara seletiva da rua permanecem iguais.

No litoral, a opacidade da sombra solar passa de 0,82 no aberto para 0,72 na maresia e 0,42 na chuva; a largura do filtro PCF acompanha esses estados com 1,25/1,45/1,65. A alteração usa a luz existente, preserva seu ângulo e a resolução do mapa de sombras, e restaura os valores anteriores à noite e ao sair da região/entrar em interiores. Não ativa PCSS nem muda o renderer. A [documentação do Light3D](https://docs.godotengine.org/en/4.7/classes/class_light3d.html#class-light3d-property-shadow-blur) recomenda manter esse filtro próximo do padrão para evitar granulação; a faixa escolhida é moderada e exige conferência renderizada.

O passe seguinte corrige a escala desse filtro pela resolução escolhida pelo jogador: os valores acima são a referência para 2048 pixels; em qualidade alta, o atlas atual tem 8192 pixels, exigindo quatro vezes o deslocamento em texels para manter a mesma largura. O código Mobile do motor multiplica o deslocamento pelo tamanho de um texel do atlas ([fonte oficial](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl)). Não foram alteradas as opções de qualidade, quantidade de amostras nem tamanho do atlas; as opções que usam filtro duro continuam respeitadas. O estado noturno/interior continua restaurado.

As paredes principais da delegacia receberam material local `CoastalPoliceMatteMasonry`: tom azul original, juntas com contraste reduzido e normal calculada a partir da altura de juntas/grão, separada da variação de cor. Duas texturas 256×256 com mipmaps e material único em cache substituem os mapas genéricos nesses corpos; rugosidade 0,92, metal zero e especular 0,16. A aplicação acontece na construção, sem atualização por frame ou geometria adicional.

A primeira versão (`masonry-shadow-scale/`) reduziu as juntas a 7% e perdeu a leitura das placas na distância de gameplay, sendo reprovada nesse aspecto. O acabamento seguinte usa placas de 2×1,33 m, variação individual até 3,5% e juntas com até 22% de escurecimento, em vez dos 35% originais. A máscara e a intensidade dos reflexos permanecem inalteradas.

No vidro, a rugosidade agora também afeta a amostragem da captura planar: quatro amostras bilineares próximas suavizam a imagem, com pesos somando 1 e tratamento do alpha nas silhuetas. O material antes ajustava a rugosidade da iluminação, mas lia essa captura com uma única amostra. Não há nova câmera, textura ou passe de captura. A força continua 0,8. Variações fixas de tonalidade (até 3,5%) e rugosidade diferenciam as folhas entre as molduras; o espaçamento vertical é o mesmo da geometria, sem ruído animado ou faixas claras pintadas.

As texturas são HDR linear, com fundo transparente, sem uma segunda aplicação de fog, glow ou ajuste de cor. Os bits de renderização 16/17 ficam reservados ao sistema; 18/19 continuam pertencendo aos túneis, espelho residencial e vegetação. A silhueta de auxílio do jogador não entra no reflexo. Lotes estáticos que cruzam o plano da fachada recebem subconjuntos somente de captura, compartilhando malha e materiais, sem duplicar luzes ou colisões. Carros e pedestres atualizam a classificação do lado do plano enquanto se movem.

Limites: uma fachada selecionada por vez, atualmente autorada na delegacia; plano de chão da rua costeira, sem promover o reflexo às pontes elevadas. Fachadas e geometria que atravessam o plano são tratadas conservadoramente; isto não equivale a ray tracing ou reflexo correto em todas as superfícies do mapa.

O uso de ReflectionProbe com captura única e projeção em caixa segue as capacidades descritas na [documentação oficial](https://docs.godotengine.org/en/stable/classes/class_reflectionprobe.html). Isso demonstra suporte do recurso, não equivalência visual nem performance aprovada neste projeto.

## Validação

Ambiente utilizado: Godot 4.7.2 .NET, Vulkan/Mobile, RTX 4060 Laptop. `Harbor.csproj` compilado com sucesso, sem warnings ou erros. Execuções com `--no-save`; contratos de persistência usam arquivo de teste próprio.

| Verificação | Resultado |
| --- | --- |
| Contratos costeiros, persistência, restauração do céu/filtro de sombras e materiais de vidro | 129 checks aprovados |
| Luminárias locais, incluindo chuva diurna no pool existente | 29 checks aprovados |
| Integração real de clima, garagem, montanha, túnel e pista | 30 checks aprovados, stderr vazio |
| Paridade funcional de iluminação | Aprovada |
| Atmosfera regional | 25 checks aprovados |
| Poças e interações existentes | Aprovadas; fixture registrou aviso de recursos no encerramento |
| Regressão renderizada dos retângulos de neblina | Aprovada: diferença nos cantos defeituosos 0,216; após correção 0; luz útil preservada 0,224 |
| Semelhança com os conceitos | Pendente; diferenças visíveis identificadas |
| Performance final e estabilidade temporal | Não aprovadas; medições abaixo da meta e interferência de sessões concorrentes |

A primeira integração realizada enquanto fontes de um agente mudavam gerou erro de preload e foi descartada como evidência. A integração posterior, com fontes estáveis, passou. Uma captura experimental inicial com probe também registrou aviso de sete RIDs de textura no encerramento; não foi considerada implementação pronta.

## Evidências e comparação

### Etapa planar produtiva

- `glass-finish-final/`: filtro e variação entre folhas do vidro em Main real a 1280×720, Godot 4.7.2 .NET/Mobile/RTX 4060 Laptop. A/B/C e noite chuvosa capturados; sequências de 30 s no sol e à noite com 458/359 frames e nenhuma perda contabilizada. Inspecionadas amostras estáticas, rotação e retorno: reflexão discreta, sem novo contorno duplicado evidente. Entrada/saída da garagem e desligamento no seco com `errors=[]`; stderr vazio, build sem avisos/erros e processo encerrado. As cadências com leitura do framebuffer não certificam estabilidade de um único frame em velocidade normal, nem performance. Contratos de clima e projeção anteriores seguem como evidência dos caminhos não alterados; não foram repetidos para esta mudança de material.

- `masonry-finish-final/`: acabamento atual das paredes e escala corrigida do filtro. A/B/C e noite chuvosa em Main real, 1280×720, Godot 4.7.2 .NET/Mobile/RTX 4060 Laptop. Qualidade de sombras alta (atlas configurado de 8192), blur medido 4,60 no A, 5,32 no B, 6,60 no C e restauração a 1,0 à noite. Sequência diurna de 30 s com 573 frames e nenhuma perda contabilizada; amostras durante rotação e retorno mostram placas legíveis e bordas de sombra sem novo defeito evidente. Transições da garagem e secagem com `errors=[]`, stderr vazio, processo encerrado. Build sem erros; 129 contratos costeiros aprovados. A sequência de chuva com o mesmo filtro em `masonry-shadow-scale/` tem 444 frames/30 s sem perdas, mas antecede o reajuste do contraste das juntas. Não certifica flicker em velocidade normal nem opções de sombras baixa/média; benchmark segue adiado pelo usuário.

- `facade-shadow-finish/`: captura atual após os revelos e o filtro de sombras, Main real em Godot 4.7.2 .NET/Mobile, RTX 4060 Laptop, 1280×720. Quatro estados (A, B, C e noite chuvosa), mais sequências contínuas de 30 segundos no sol e na chuva, com 448/339 frames, sem perdas contabilizadas. Inspecionadas amostras estáticas, rotação e retorno: molduras mais definidas e alteração discreta nas sombras; continuam diferenças claras para a penumbra e os reflexos idealizados dos conceitos. `transitions.json` sem erros; stderr vazio e processo encerrado. Build sem avisos/erros. Sem benchmark nesta etapa, conforme pedido; cadência com readback não certifica flicker em velocidade normal.

- `selective-finish/`: acabamento seletivo atual nos seis estados (seco, maresia, chuva, tempestade, noite chuvosa e secagem), a 1280×720. Sequências de 30 segundos de chuva e noite com 295/273 frames e nenhuma perda contabilizada; transições de garagem e piso seco com `errors=[]`. O log registrou duas mensagens de eixo não normalizado na cadeia de despacho de veículos, fora das alterações desta etapa, e um aviso de interpolação da câmera de reflexo, corrigido na sequência.
- `selectivity-test.log`: teste renderizado de cobertura com 22,44% dos pixels afetados e diferença zero no piso seco. A máscara mantém áreas realmente foscas, além da redução anterior de intensidade.
- `selective-camera-final/`: nova execução após corrigir a interpolação, 392 frames de chuva em aproximadamente 30 segundos, sem perdas contabilizadas. Conferidos frames durante rotação e retorno; entrada/saída da garagem, restrição de armas, retomada da captura e desligamento no piso seco com `errors=[]`. As duas câmeras foram verificadas com interpolação física desativada. `selective-camera-final.err` vazio e processo encerrado; o erro de despacho da execução anterior não reapareceu nesta cobertura.

As câmeras de reflexão passaram a desativar a interpolação física: copiam em `_process` a pose já exibida pela câmera principal, que também faz seu acompanhamento manualmente. Isso evita interpolar novamente a captura e elimina o aviso na troca de ambiente. As sequências usam leitura do framebuffer e não aprovam FPS nem ausência de flicker em alta frequência.

- `planar-final/`: A seco, B maresia, C chuva e noite, em Main real a 1920×1080. Inclui as duas texturas de captura para distinguir geometria refletida de brilho de material. Nenhum erro de runtime no encerramento. O filtro foi posteriormente ajustado de cinco amostras espaçadas para nove amostras contíguas, eliminando contornos múltiplos.
- `planar-motion/motion-final.png`: imagem real depois desse último ajuste, com a câmera rodada, a 1280×720.
- `planar-motion/transitions.json`: captura molhada ativa em Harbor, seleção da delegacia, layers reservadas, suspensão na garagem, proteção de armas, retorno à rua e desligamento no piso seco; `errors=[]`.
- `planar-test-final.log`: projeção/alpha em três posições de câmera e subconjunto de MultiMesh preservando instância visível, cor, custom data e malha compartilhada; sem erros.
- `lamp-fog-planar.log`: regressão dos quadrados, delta nos cantos corrigidos 0, reprodução defeituosa 0,215686 e luz preservada 0,215686; sem erros.
- Contrato climático repetido após integração: 127 verificações, sem erros. Build .NET: zero avisos/erros.

O vídeo externo `planar-motion/motion.mp4` é **inválido como evidência visual**: a captura GDI retornou uma cor uniforme no lugar da imagem Vulkan. O jogo executou o roteiro e as transições, mas esse vídeo não comprova estabilidade. A imagem acima veio do framebuffer do motor.

`planar-temporal/` registra a alternativa pelo framebuffer: 318 frames/30,06 s diurnos e 327 frames/30,07 s noturnos, sem frames renderizados perdidos, com câmera parada, rotação e retorno. A umidade vai de 0 a 0,64 no primeiro trecho e de 0,65 a 1 no segundo. Amostras das posições 100/200/final de cada trecho mostram reflexos acompanhando a geometria, sem as antigas placas brancas. A cadência de gravação (~10,6/10,9 FPS), afetada por readback e concorrência, não certifica ausência de flicker em velocidade normal e não é benchmark. Esse registro precede apenas a redução escalar de 50% solicitada para a rua; `planar-restrained/` contém o acabamento com a intensidade final.

Arquivos em `evidence/coastal-weather-20261013/`:

- `visual-refined/`: capturas reais A/B/C e noite antes do ajuste final dos reflexos das luminárias.
- `reflection-trial/`: primeiro experimento de fachada/probe, reprovado visualmente por brilho excessivo e distorções. Mantido como diagnóstico.
- `reflection-measure/`: comparação pareada entre materiais atuais e experimento com geometria refletida; inclui amostras de frame time e screenshots.
- `temporal-final/`: tentativa interrompida após identificação dos retângulos; não serve como validação.
- `temporal-fixed/`: nova sequência de chuva diurna e noturna após a correção dos retângulos, câmera parada e em rotação, timestamps e contagem de frames perdidos. A gravação usa limite de 30 FPS e leitura de imagem; não serve como benchmark. `frame-times.json` é uma janela separada antes da gravação, sem esse limite adicional/readback.
- `lamp-fog-regression/`: reprodução renderizada isolada das placas e correção.
- `contracts-final.log`, `local-light-final.log`, `integration-final.log`: resultados funcionais.

As medições iniciais `before/` e `after/` não permitem aprovar ou atribuir regressão à versão final: houve ajustes posteriores de material, mudança concorrente no comportamento de enquadramento e outros processos Godot ativos. Os snapshots de processos acompanham as novas medições. Não foram encerradas sessões de outras tarefas. A meta provisória continua 60 FPS/16,67 ms; ausência de comparação isolada e equivalente deixa a aprovação de performance pendente.

A comparação pareada experimental, em 1280×720 e com janela estável de 30 segundos por condição, registrou os números abaixo. Foi feita antes da correção dos retângulos. Há processos Godot de outras sessões ativos; portanto a variação não deve ser atribuída exclusivamente à probe. Ainda assim, estes resultados **reprovam a adoção do experimento como solução pronta**, juntamente com brilho excessivo e projeções visivelmente inadequadas.

| Cenário | FPS médio | p95 (ms) | p99 (ms) |
| --- | ---: | ---: | ---: |
| Chuva, tratamento atual | 30,65 | 79,91 | 94,25 |
| Chuva, experimento de geometria refletida | 8,28 | 187,42 | 202,25 |
| Noite chuvosa, tratamento atual | 12,49 | 154,58 | 997,44 |
| Noite chuvosa, experimento de geometria refletida | 10,02 | 190,52 | 203,69 |

As amostras, p50, máximos, contagem de frames longos e aquecimento estão no JSON original. Não se conclui causa CPU/GPU a partir desses intervalos. A probe e a fachada experimental permanecem fora do runtime normal.

Depois da correção dos retângulos, a janela separada de chuva diurna em 1920×1080 registrou 689 frames/30,05 s, 22,93 FPS, p50 30,93 ms, p95 151,44 ms, p99 178,65 ms, máximo 230,95 ms; 284 frames acima de 33,3 ms e 84 acima de 66,7 ms. VSync ligado, limite normal 144 FPS e câmera 48. A meta continua não atendida nesta execução. A telemetria da comparação anterior registrou mudanças de foco, além da concorrência já mencionada; sem isolar essas condições, não se atribui o custo integral ao efeito.

A captura posterior confirmou visualmente a ausência das placas na esquina, de dia e à noite. Foram gravados todos os frames renderizados durante 31,29 s diurnos (140 frames) e 30,19 s noturnos (200 frames), sem perdas contabilizadas, com câmera estática/rotação/retorno. A leitura e gravação de imagens reduziu a cadência para 4,47/6,63 FPS: a estabilidade visual em velocidade normal permanece inconclusiva. O maior candidato a alteração na fachada noturna foi inspecionado nos frames 5–7, próximo da mudança forçada de horário; não houve reaparecimento dos retângulos. `analysis.json` registra essa cobertura e limitações.

Os números acima são históricos, anteriores ao sistema planar. Não foram aprovados reflexos em todas as fachadas, movimento rápido/streaming amplo ou iluminação de outros mapas. A aprovação de desempenho permanece pendente para a etapa solicitada pelo usuário.
