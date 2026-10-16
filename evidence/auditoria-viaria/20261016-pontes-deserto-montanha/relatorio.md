# Diagnóstico das pontes — 16/10/2026

Pedido: três agentes, identificar a divisão entre cidade inicial, deserto e montanha de gelo e propor unidade visual antes de implementar. Inspeção por três agentes, código atual e capturas históricas. Nenhuma alteração de gameplay, geometria ou materiais.

## Base da proposta

Foram lidos AGENTS.md, CLAUDE.md, docs/HOW-TO-DEVELOP.md e as skills auditoria-viaria, guardiao-do-jogo, testes-com-criterio e performance-do-jogo. A proposta respeita materiais cacheados, malhas compartilhadas, pré-aquecimento de shaders sob a cortina, trabalho de montagem com orçamento e execução serial de Godot pela fila. Medição futura será em release, A/B equivalente na mesma máquina e dia; não usar FPS de screenshots como benchmark.

## Inventário e contagem

São dois braços distintos: norte/deserto e leste/montanha. Não há uma única ponte linear que atravesse deserto e depois gelo.

### Leste — WorldConnection3D.gd

Cinco trechos construtivos no eixo z=-285, antes da estrada da serra:

| ID | Trecho | Intervalo X (m) |
| --- | --- | --- |
| L1 | Encontro com a cidade | 393,75–405 |
| L2 | Conector | 405–456,25 |
| L3 | Ponte principal | 456,25–559,375 |
| L4 | Encontro com a serra | 559,375–578,125 |
| L5 | Túnel | 578,125–631,25 |

O acabamento é agrupado em três lotes longitudinais (conector, primeiro vão, segundo vão), com cortes X=456,25 e 508. São lotes de renderização, não três pontes. BridgeLookMesh.gd registra que os cortes distribuem a influência das luzes no renderer Mobile. Também existem agrupamentos por material; três lotes não significam três MeshInstance3D no total.

### Norte — NorthGatewayLayout.gd / NorthGatewayScenery.gd

Uma ponte autorada por outro gerador: entrada (364,55; 0,032; -254), curva/rampa até (342,5; 2,4; -280), continuação até Z=-373,5 e encontro com Route 66.

O eixo tem 62 pontos e 61 segmentos geométricos: 24 de curva e 37 de continuação. Cinco segmentos cobrem o vão de 13 m entre Z=-309,5 e -322,5, completado pela campanha. Os três grupos PermanentBridge, CompletedSpan e ConstructionSite representam componentes/estados, não três trechos consecutivos de estrada. Assim, não se deve somar os 61 segmentos aos cinco volumes do leste como se fossem a mesma unidade.

## Achados

| ID | Prioridade | Local e observado | Causa e proposta |
| --- | --- | --- | --- |
| V1 | P3 | Conector leste L2: cunha central mais escura e emenda evidente na captura de 14/10 | HarborRoadGeometry3D usa coastal_wet_asphalt; HarborConnectorGapAsphalt usa StandardMaterial3D separado. Compartilhar material, escala e coordenadas de textura, inclusive resposta à chuva. |
| V2 | P3 | Cidade/ponte/túnel: passeios e concreto mudam de família | Cidade e túnel usam HarborPaving; ponte usa bridge_concrete e cores próprias. Definir acabamento comum e transições geométricas coerentes. |
| V3 | P3 | Norte, junção (342,5; 2,4; -373,5): asfalto cinza passa a marrom/bege | Ponte usa WorldGroundFactory; DesertRoadGeometry usa base 706d61 e outro tratamento. Uniformizar pista do corredor e fazer transição intencional para areia/cascalho fora da pista. |
| V4 | P3 | Os dois braços usam desenhos diferentes de guarda, parede e passeio | Norte usa base de concreto com trilhos; leste usa outro conjunto de guarda e fáscia. Compartilhar perfis e paleta, preservando larguras, curvas, apoios e função de cada trecho. |

As diferenças de implementação foram verificadas no código. As observações visuais são históricas, não renderização da revisão atual. Não foi demonstrada falha funcional de trânsito nesta inspeção.

## Evidência examinada

- ../../mountain-bridge-look/cima_conector_depois3_12h.png — 14/10, cunha e emenda do conector.
- ../../mountain-bridge-look/cima_vao_ajuste_12h.png — 14/10, acabamento do vão principal.
- ../../desert-entrance-43352-7163839/temporal/bridge_toll_drive.png — 12/10, ponte norte e troca de asfalto na chegada.

## Proposta de construção posterior

1. Criar especificação compartilhada de asfalto, concreto, meio-fio, passeio e metal; cor, textura, escala e chuva devem ser consistentes em cidade/conector/ponte/encontros.
2. Aplicar aos geradores existentes e eliminar os tapa-vãos com tratamento visual diferente. Manter segmentação interna necessária para streaming, iluminação e colisão; aparência contínua não depende de uma malha gigante.
3. Harmonizar perfil dos passeios, paredes, guardas e juntas. Fazer mudanças de largura com transição intencional. Preservar os dois braços, o acesso leste disponível e o bloqueio/obra ao norte até a missão final.
4. Reutilizar e reter materiais; pré-aquecer variantes. Evitar geração pesada na primeira visita, novas luzes fora de LightBudget ou loops de manutenção por frame.
5. Validar depois da implementação: build C#, quatro checks estruturais do CLAUDE.md, casos pertinentes de emenda/campanha/acesso, travessia física e observação renderizada nas duas direções, dia/noite/chuva e retorno de streaming. Performance release A/B nas rotas ponte/travessia/deserto/serra afetadas, métricas em ms e cobertura explícita. Meta do HOW-TO-DEVELOP: p50 ≤16,7 ms e nenhum quadro >33 ms após jogável; registrar qualquer pendência real.

## Cobertura e limites

Inventariados dois geradores de ponte, cinco trechos construtivos leste e 61 segmentos geométricos norte; materiais dos encontros e das vias regionais relacionados. Três capturas históricas examinadas. Nenhuma travessia nova, teste funcional, captura atual, benchmark, revisão de grafo ou validação física realizada. Havia importação, teste de táxi e medição de tráfego de outras sessões ativos; não foram iniciadas instâncias concorrentes nem encerrados processos alheios.

Conclusão: divergências de acabamento confirmadas no código e ilustradas em evidência histórica. Aparência atual completa, física e performance permanecem não verificadas. O mapa salvo não foi editado; SHA256 lido durante a inspeção: 353c18c7803af7e2f68b6b0db9f5c46b03f7f1a595b4388a2a05d26b20385fa4. Esta entrega é diagnóstico/proposta, não aprovação da reforma.
