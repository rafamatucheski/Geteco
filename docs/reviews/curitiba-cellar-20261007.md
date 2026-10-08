# Curitiba Cellar — implementação e validação de 07/10/2026

Loja autorada em Harbor: centro `(136.5, 0.12, 10.5)`, frente para sul/+Z, entre Union e Fuel. Planta de 14 × 11 m, câmera ortográfica alinhada, adegas laterais e traseiras, balcão de degustação e escritório financeiro de Luísa. Nelson atende no balcão e conversa sobre a Grécia. Fachada somente com o nome próprio. O acesso usa o marcador compacto e o fluxo de transferência de salas do `FullSession`.

O parcel foi conferido contra os prédios originais e os edits vigentes: Union acaba em X=125.3125, Fuel começa em X=146.5625; a nova fachada ocupa X=129.5…143.5. O prédio editado atrás termina em Z=4, enquanto a loja começa em Z=5. A Foundry Avenue começa em Z=21.25; a fachada termina em Z=16 e o acesso fica antes da pista. Essa conferência de bounds não substitui a caminhada integrada e não certifica toda a malha viária.

## Contratos jogáveis

- Oito rótulos de Grécia, Brasil, Portugal e Chile; comprar guarda três taças e debita a carteira uma vez. Preços, cura e álcool são regras fictícias do jogo.
- Beber consome uma taça, recupera somente a vida faltante e aumenta embriaguez mesmo com vida cheia. Intervalo entre goles, limite de álcool e capacidade evitam consumo/compra duplicados.
- Álcool, estoque e presente único sobrevivem ao save. Recuperação remove embriaguez sem apagar garrafas. Compra remota, morte, estoque vazio, saldo insuficiente e saves inválidos são rejeitados.
- NPCs nativos e volumes sólidos compartilham profundidade com Dante; sem passes de render por ator. Decoração repetida usa MultiMeshes. Duas fontes locais estáveis complementam as luminárias.

As conversas são diálogos textuais funcionais. Não foram produzidas gravações ou dublagem de Nelson/Luísa; os avisos `Missing pt_BR dialogue recording` dos logs correspondem às falas novas ainda sem áudio. Não considerar dublagem entregue.

## Evidência e cobertura

| Verificação | Resultado atual | Evidência |
|---|---|---|
| Física da loja | **150/150 aprovadas**: inventário de sólidos, cápsulas reais Dante/visitante, varreduras longas, spawn, interações e suporte do piso | `evidence/cellar-physics-final.log` |
| Profundidade renderizada | **26/26 aprovadas**, câmera final, entrada e atores antes/atrás/ao lado dos móveis, controles positivos sem ocultar atores | `evidence/curitiba-cellar-depth-110020-5750585/report.json` |
| Estado vinho/economia | **71/71 aprovadas**, incluindo recibos, quatro origens, cura, álcool, pausa da lógica por delta inválido, limite de estoque, presente e saves inválidos | `evidence/cellar-wine-final.log` |
| Regressões selecionadas | Controles **13/13**, câmera aprovada, garagem **47/47**, inventário **11/11**; fixture legada da garagem emitiu dois avisos ObjectDB | `evidence/cellar-controls.log`, `cellar-camera-regression.log`, `cellar-garage-regression.log`, `cellar-inventory-regression.log` |
| Cena Main: entrada/saída, UI, conversas, bebida, reentrada, save frio, pausa e resgate real | **61/61 aprovadas**; ressalva de hash do arquivo compartilhado abaixo | `evidence/curitiba-cellar-session-119372-5797896/report.json` |
| Luísa: digitação, ameaça, cadeira, retorno e descarregamento | **24/24 aprovadas**, Actor/Place e reação produtivos, colisão da cadeira vazia e contato real dos dedos com o teclado | `evidence/curitiba-cellar-luisa-51592-5602394/report.json`, `evidence/cellar-luisa-final.log` |
| Luz temporal interior | **901 frames/30,005 s**, zero frames renderizados omitidos e nenhuma oscilação indevida encontrada na análise delimitada abaixo | `evidence/curitiba-cellar-session-119372-5797896/temporal/` |
| Performance depois | Exterior antes/depois sem regressão medida; interior final e configuração normal medidos. **Pendente comparação equivalente do custo do álcool**, por população variável e interferência externa na confirmação | `evidence/curitiba-cellar-after-all-116712-5944566/report.json`, `evidence/curitiba-cellar-after-confirm-153652-5791859/report.json` |

No teste de profundidade, os controles continham 837–943 pixels por ator. Entrada/frente/lateral preservaram 100%; atrás do balcão permaneceram 85,2% de Dante e 86,7% do visitante; atrás da adega restaram 2,3%/2,5%. Isso comprova oclusão geométrica nesses pontos, sem fingir profundidade por ordem de desenho. A fixture isolada de profundidade não comprova FPS nem animação dos moradores na sessão completa.

A primeira rodada Main (`curitiba-cellar-session-82804-6052485`, **55/56**) teve somente uma falha de expectativa: comprar disparou o salvamento normal e concedeu a conquista `first_grand` de R$ 50; saldo final R$ 2435 = R$ 2500 − R$ 115 + R$ 50. Recibo e três taças estavam corretos. A fixture agora resolve conquistas após financiar a carteira e só depois captura o saldo inicial; mantém asserções exatas de débito, recibo e quantidade. Não houve correção da economia para satisfazer o teste. A rodada final passou essa asserção, pausa de 0,5 s com álcool/cooldown congelados e dano fatal seguido do resgate produtivo completo: saúde, posição exterior livre, controle, física, remoção do efeito e preservação das garrafas.

A sequência final, após afastar a luminária do rosto de Luísa, contém 901 JPEGs válidos/30,004776 s, nenhum frame renderizado omitido, intervalo máximo de 39,014 ms e p99 de 37,923 ms sob limite temporário de 30 FPS. Análise em todos os frames: regiões estáticas do balcão `(575,295)-(610,312)`, piso `(477,390)-(558,410)` e ilha `(790,409)-(840,447)` apresentaram diferença média absoluta RGB zero; parede do escritório `(835,135)-(940,195)` atingiu somente 0,012593/255. A sala inteira, excluindo as regiões de atores e suas sombras móveis, atingiu máximo de 0,000592/255. Inspeção visual dos frames com os maiores deltas (`00326.jpg`, `00704.jpg`) e das fotos finais não encontrou piscadas. Cobertura: interior diurno seco, câmera final fixa e caminhada lenta pelo corredor central, ida/volta; não certifica outras regiões, noite/chuva exteriores. O comparativo de FPS usa outro runner, sem capturar JPEG durante a amostra.

Ressalva de rastreabilidade da rodada Main final: seu campo bruto `source_stable=false` registra somente `runtime/FullSession.gd` (`39ee3ba6…` → `d711fb38…`). Não foi possível atribuir essa edição concorrente exclusivamente a um bloco por reconstrução em memória. Os 61 comportamentos acima foram observados no código carregado pelo processo. Não interpretar a rodada como verificação automática de alterações posteriores. O benchmark subsequente usou os fontes atuais, com `source_stable=true`, e repetiu admissão, consumo e retorno; não repetiu toda a matriz de 61 checks.

A revisão posterior encontrou dois ajustes locais necessários em Luísa: os alvos originais de digitação excediam o alcance dos braços, e a cadeira acompanhava o recuo da moradora sob ameaça. A correção aproxima teclado/mãos e fixa a cadeira no posto ao levantar, com corpo físico próprio que bloqueia visitantes e uma exceção somente para a ocupante. A fixture específica passou 24 checks: contato dos dedos, digitação, sinal real de ameaça, recuo de pé, cadeira imóvel, varredura contra o assento vazio, retorno físico e postura sentada, restauração da digitação, visibilidade, cancelamento na morte e limpeza ao descarregar. As fotos `01-seated-final-camera.png`, `03-standing-retreat-chair-fixed.png` e `04-returned-to-work.png` dessa execução foram inspecionadas. O closeup corrigido de câmera `evidence/curitiba-cellar-luisa-155424-5399948/02-seated-hand-contact.png` confirma mãos sobre o teclado e rosto livre. Essa rodada cobre o ajuste local posterior; não é uma repetição dos 61 checks Main.

## Baseline renderizado

Godot **4.7.2 .NET**, `Harbor.csproj` compilado e backend de rotas C# confirmado. Main real, GPU NVIDIA GeForce RTX 4060 Laptop, CPU Intel i7-13650HX, renderer Mobile, 1280×720, população solicitada 40, dia `.45`, seco, VSync desligado e sem limitador somente no processo de diagnóstico. Posição exterior `(136.5, .20, 18.3)`; 10 s de aquecimento e 30 s estáveis, sem benchmark concorrente. Meta provisória: 60 FPS/16,67 ms; aumento >5% em p95/p99 exige confirmação finita equivalente.

| Cenário | Frames / duração | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Exterior antes da implementação | 5056 / 30,003 s | 168,51 | 4,570 | 10,754 | 13,518 | 32,148 | 0 / 0 |
| Exterior depois | 5179 / 29,999 s | 172,64 | 4,423 | 10,641 | 13,345 | 24,608 | 0 / 0 |
| Interior novo | 8381 / 30,006 s | 279,31 | 2,941 | 6,698 | 9,619 | 13,923 | 0 / 0 |
| Exterior com embriaguez | 3882 / 30,005 s | 129,38 | 5,665 | 13,253 | 15,982 | 20,582 | 0 / 0 |

Evidência: `evidence/curitiba-cellar-before-exterior-156308-6042214/report.json`, intervalos brutos e `exterior.png`. O campo bruto `source_stable=false` decorreu **somente** da edição do arquivo novo `CuritibaCellarInterior.gd`, ainda não integrado/carregado durante essa execução; todas as dependências produtivas e a DLL permaneceram iguais. A alteração foi o ajuste da aproximação de Luísa para evitar interseção com a mesa. Portanto o baseline exterior é utilizável com essa ressalva explícita. No aquecimento houve um frame de 67,175 ms, separado da janela estável.

Interior e embriaguez são cenários novos sem equivalente anterior à implementação. Sua medição é absoluta; o custo adicional do efeito alcoólico pode ser comparado ao exterior sóbrio na mesma posição/configuração. Captura de JPEG e screenshot acontecem fora das janelas de benchmark; sequência visual não é prova de FPS.

Depois: `evidence/curitiba-cellar-after-all-116712-5944566/report.json`, fontes estáveis. Exterior apresentou p95 −1,05% e p99 −1,28% em relação ao baseline. Os três cenários ficaram abaixo de 16,67 ms no p99 e sem frames acima de 33,3 ms. Exterior bêbado apresentou p95 +24,5% em relação à amostra sóbria da mesma rodada; a população mudou de 31 para 40 pessoas e de 35 para 44 veículos, com draw calls de 361 para 409. Como ocorre após visita ao interior e evolução do tráfego, esse dado não isola o custo do shader.

Foi realizada uma confirmação finita no mesmo ponto e câmera: interior final, quatro doses reais, exterior bêbado, recuperação sem nova entrada/teleporte e configuração normal. `evidence/curitiba-cellar-after-confirm-153652-5791859/report.json` terminou com código zero e `source_stable=true`. Cada linha tem 10 s de aquecimento e 30 s de amostra, com capturas fora da janela.

| Confirmação | Frames / duração | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Interior final, sem outro motor | 13614 / 29,999 s | 453,81 | 1,916 | 3,985 | 5,205 | 9,661 | 0 / 0 |
| Exterior bêbado, interferência externa | 4369 / 30,001 s | 145,63 | 5,178 | 12,117 | 14,526 | 22,939 | 0 / 0 |
| Exterior recuperado, interferência externa | 3483 / 30,007 s | 116,07 | 9,713 | 14,014 | 16,237 | 29,858 | 0 / 0 |
| Recuperado, limite normal de 60 FPS/VSync 1 | 1801 / 30,017 s | 60,00 | 16,687 | 19,567 | 20,840 | 31,086 | 0 / 0 |

O monitor externo `evidence/cellar-confirm-processes.jsonl` registrou o início de um teste `test_fishing_session.gd` de outra conversa durante esta execução. Os registros conservadores delimitam a possível interferência entre 19:33:59,558 e 19:34:43,966. Cruzando `context_start/end.ticks_usec` com o início do processo (19:32:03,759; margem de 1 s para inicialização do relógio), as janelas foram aproximadamente: interior 19:33:02–19:33:32, bêbado 19:33:51–19:34:21, recuperado 19:34:31–19:35:01 e normal 19:35:11–19:35:41. Logo interior e configuração normal ficaram fora dessa sobreposição; **o par bêbado/recuperado teve interferência e não certifica o custo relativo do efeito**. O benchmark de pesca seguinte iniciou às 19:35:43,491, depois da última janela.

A população também não ficou equivalente nesse par: bêbado 21→35 pessoas/30→36 carros/366→426 draw calls; recuperado 38→40 pessoas/38→41 carros/461→421 draw calls. A configuração normal manteve 40 pessoas e 41→43 carros, sem mudar posição ou câmera. Sua média de 60 FPS e p99 de 20,840 ms registram o comportamento absoluto com limitador/VSync, sem comprovar que todos os frames cumprem 16,67 ms. O contexto do interior final manteve contagem de 9 pessoas/22 veículos e 271 draw calls; a foto `confirm-interior.png` mostra a sala final.

Picos do aquecimento da confirmação, separados das amostras estáveis: chegada exterior 86,484 ms (4 frames >33,3 ms, 1 >66,7), recuperação 47,749 ms (1 >33,3) e retorno ao limitador/VSync 78,129 ms (2 >33,3, 1 >66,7). Não foram ocultados nem atribuídos automaticamente ao álcool. Não ocorreu queda sustentada a 12–15 FPS nas janelas observadas. A validação funcional está concluída; o checklist mantém **um interior em validação**, sem certificação integral de performance enquanto faltar uma comparação do álcool com carga equivalente e sem outro motor. Não foi feita repetição indefinida nem degradada a apresentação para obter números melhores.

## Referências públicas

A marca e a seleção boutique foram pesquisadas no [site oficial da Curitiba Cellar](https://www.curitibacellar.com.br/) e na página [Sobre](https://www.curitibacellar.com.br/sobre). A loja de Harbor é uma interpretação autorada; planta, fachada do jogo, NPCs, preços e efeitos não são apresentados como reprodução documental do estabelecimento real. Características de Nelson e Luísa seguem o pedido do usuário, sem pesquisar dados pessoais adicionais.

Os rótulos remetem às páginas oficiais: [Zacharias Nemea](https://www.curitibacellar.com.br/product-page/zacharias-nemea-2022), [Zacharias Malagousia](https://www.curitibacellar.com.br/product-page/zacharias-malagousia-2022), [AG Chardonnay Carvalho](https://www.curitibacellar.com.br/product-page/ag-chardonnay-carvalho), [AG Espumante Festividad](https://www.curitibacellar.com.br/product-page/ag-espumante-festividad), [Medeiros Private Selection](https://www.curitibacellar.com.br/product-page/medeirosprivate-selection), [Medeiros Regional Rosé](https://www.curitibacellar.com.br/product-page/medeiros-regional-ros%C3%A9), [ANCLA Reserva Cabernet Sauvignon](https://www.curitibacellar.com.br/product-page/ancla-reserva-cabernet-sauvignon) e [ANCLA Gran Reserva Merlot](https://www.curitibacellar.com.br/product-page/ancla-gran-reserva-merlot). O jogo usa valores e benefícios próprios.

As conversas de Nelson são diálogos originais. Referências históricas: reunião com vinho, conversa e música em [The Symposium in Ancient Greece — The Met](https://www.metmuseum.org/essays/the-symposium-in-ancient-greece); recipiente de mistura de vinho e água na [cratera atribuída a Lydos, objeto 253349](https://www.metmuseum.org/art/collection/search/253349); representação de Dioniso na [ânfora atribuída ao Affecter, objeto 250679](https://www.metmuseum.org/art/collection/search/250679). Consulta em 07/10/2026, sem copiar passagens dos textos.

## Reprodução

Compilar `Harbor.csproj` antes e usar exclusivamente o executável `_console.exe` da instalação .NET indicada no `AGENTS.md`. Isolar dados de usuário e executar um motor por vez.

```text
--path D:/geteco/game --headless --script res://tests/test_curitiba_cellar_wine.gd
--path D:/geteco/game --headless --script res://tests/test_curitiba_cellar_physics.gd
--path D:/geteco/game --script res://tests/test_curitiba_cellar_depth.gd
--path D:/geteco/game --script res://tests/test_curitiba_cellar_luisa.gd
--path D:/geteco/game --script res://tests/capture/capture_curitiba_cellar.gd -- --no-save
--path D:/geteco/game --script res://tests/measure/measure_curitiba_cellar.gd -- --no-save --benchmark --phase=after --scenario=all
--path D:/geteco/game --script res://tests/measure/measure_curitiba_cellar.gd -- --no-save --benchmark --phase=after --scenario=confirm
```

Os dois primeiros comandos não aprovam visual/FPS. Os runners Main escrevem fixtures e evidências em pastas exclusivas; não usam saves pessoais. As janelas de performance mantêm câmera normal; a captura de 30 s limita somente seu próprio processo a 30 FPS para registrar cada frame renderizado e deve ser inspecionada visualmente. O checklist permanece em validação pela pendência comparativa de performance explicitada acima; não contar o interior como certificado enquanto esse gate estiver pendente.
