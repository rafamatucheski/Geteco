# Boa Praça — implementação e validação

Novo supermercado na fileira comercial de Harbor, no antigo prédio sem interior `NorthFrontage1`, entre North Pier e Ammu-Nation. Identificador persistente: `harbor_supermarket`. Fachada em `(61.875, 0, 8.75)`; porta de correr abre por proximidade, entrada/saída a pé pelo controlador existente. Não redesenha ruas.

**Lote: 1 lugar físico / 1 interior distinto novo; 0 certificados integralmente / 1 em validação / 0 não iniciados.** Acrescenta um acesso e um interior ao inventário existente. A referência anterior do checklist era 32 acessos / 30 interiores; com este acréscimo, 33 / 31, sem recertificar os demais lugares.

## Conteúdo

- Sala 18 × 14 m, câmera ortográfica alinhada, quatro gôndolas com quatro níveis, seis bancas de hortifruti, três módulos de padaria, quatro refrigeradores, dois caixas com esteira/leitor/cartão, cestas e armário de coletes.
- 1.224 produtos de cenário: caixas, garrafas, latas, pacotes, frutas e pães. Geometria repetida agrupada em MultiMesh por formato/material. Sala e população criadas somente na entrada e liberadas na saída.
- Dois funcionários e quatro clientes físicos com escolha de produtos, cesta, espera pelo caixa, pagamento, saída e retorno. Controle exclusivo do caixa dos clientes evita atendimento simultâneo. Jogador usa o outro caixa.
- Oito compras para o inventário: maçã, água, suco, iogurte, pão, cereal, sanduíche e primeiros socorros. Cura usa o fluxo existente do inventário. Colete custa R$ 500 e equipa 100 de proteção. Espaço, saldo e recibos pertencem à Economy; não existe inventário paralelo.
- Um kit de primeiros socorros como recompensa inicial persistente. Regras de armas/Maciota preservadas.
- UI lateral própria: ícones distintos, categorias, preço, recuperação, unidades guardadas, saldo, vida/proteção, feedback local e foco por grade. Compra direta sem confirmação adicional. Falta de dinheiro, espaço e proteção cheia recebem resposta explícita.

## Evidência executada

Godot **4.7.2 .NET**, `dotnet build Harbor.csproj --no-restore` aprovado. Renderização **Mobile/Vulkan**, **RTX 4060 Laptop**, captura Main **1280 × 720**, saves pessoais preservados.

| Verificação | Resultado |
|---|---|
| `tests/test_supermarket.gd` | 93 checks aprovados: economia, recibos, capacidade, colete, cápsulas reais de jogador/NPC, varreduras longas e diagonais, corredores, spawns, caixa e portas |
| `tests/test_supermarket_customers.gd` | Quatro clientes completam pelo menos duas compras em 150 s simulados; pausa/recuperação por ameaça, chão/colisões e liberação de atores aprovados |
| `tests/test_supermarket_depth.gd` | 24 checks Mobile aprovados, com máscaras dos atores e controles positivos; frente, trás e lado das gôndolas e caixas |
| `tests/test_supermarket_save.gd` | 6 checks de save/load em arquivo isolado: local, checkpoint, item, saldo e recibo sem duplicação |
| `tests/test_supermarket_ui.gd` | Painel e Voltar dentro da tela em 1280×720, 960×540 e 640×480; rolagem dos produtos nas menores resoluções |
| `tests/measure/review_supermarket.gd` | 20 checks aprovados em Main: aproximação e travessia da porta, caixa, UI, foco por controle, compra, consumo/vida 50→58, colete, saída, limpeza, compra remota rejeitada e reentrada |
| Regressão `test_campaign_economy.gd` / `test_inventory_grid.gd` | 162 / 36 checks aprovados |

A verificação de clientes inicialmente usou retângulos expandidos, que rejeitavam indevidamente cápsulas circulares nos cantos. Foi substituída pela distância círculo/caixa com o raio real de 0,30 m, preservando o requisito de não interseção. A oclusão encontrou a luminária sobre o corredor central e a parede frontal escondendo atores: luminárias realinhadas sobre gôndolas e recorte visual frontal corrigido, mantendo o corpo físico da parede.

## Fotos e movimento reais

- [Fachada](../../evidence/supermarket-20261002/final/exterior.png)
- [Interior e clientes](../../evidence/supermarket-20261002/final/interior.png)
- [UI anterior, lista genérica](../../evidence/supermarket-20261002/integration/checkout.png)
- [UI nova e compra confirmada](../../evidence/supermarket-20261002/final/purchase-feedback.png)
- [Colete](../../evidence/supermarket-20261002/final/armor.png)
- [Vídeo contínuo](../../evidence/supermarket-20261002/final/market-motion.mp4)
- [Integração](../../evidence/supermarket-20261002/final/integration.json), [profundidade](../../evidence/supermarket-20261002/depth/results.json), [análise temporal](../../evidence/supermarket-20261002/final/temporal-analysis.json)

Sequência de 30 segundos de Main, 899 frames consecutivos, sem lacunas no contador de frames desenhados; captura limitada a 30 FPS. A parede posterior permaneceu estável em todos os frames da região analisada. Maior variação no piso de entrada em 28,16 s corresponde a um cliente e sua sombra atravessando a região (frames 843/844 inspecionados). Isto não certifica todos os horários, movimentos de câmera ou reflexos. Nenhum FPS da captura é usado como benchmark.

## Pendências e limites

- **Performance inconclusiva:** não há baseline renderizado anterior válido. As primeiras tentativas de gravação foram impedidas por acesso ao diretório e a captura inicial ficou na introdução. Durante a validação, outras sessões executavam medições/capturas e alteravam dependências compartilhadas. Não foi feito benchmark concorrente do supermercado nem foi deduzido desempenho pelo contador da tela. Meta provisória permanece 60 FPS/16,67 ms; comparativo exterior/interior de pelo menos 30 s, p50/p95/p99 e hitches ainda necessário em ambiente controlado.
- O processo Main termina com avisos de recursos/RIDs ainda em uso (5 meshes, 3 materiais, 1 shader e 16 ObjectDB). Os checks funcionais terminam com código 0, mas isso **não** aprova o encerramento global. A origem desses avisos não foi isolada; testes isolados do mercado/UI/profundidade não os reproduziram. Há também aviso Ogg do zoológico durante o carregamento, fora deste escopo.
- Antes/depois disponível para a UI e para o refinamento do interior. Não há fotografia válida do prédio anterior à substituição; não foi fabricada uma imagem para suprir essa evidência.
- Save/load em disco cobre a localização e os itens/recibos; restauração completa de combate durante um conflito no mercado não foi exercitada. Ameaça/recuperação de clientes tem teste dirigido, não uma campanha completa de combate, incêndio ou resgate.
- Nenhuma certificação global de interiores ou de iluminação do jogo é atribuída a este lote.
