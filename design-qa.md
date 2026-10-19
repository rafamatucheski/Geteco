# Harbor — mapa M (19/10/2026)

final result: passed

Escopo desta aprovação: apresentação e interação do mapa escolhido na opção 1, aplicado a cidade, montanha, deserto e visão do mundo. A aprovação visual não certifica desempenho. O benchmark longo foi encerrado a pedido do usuário por sobrecarregar o computador; não será tratado como validação concluída.

## Referência e comparação

- Fonte escolhida: `evidence/world-map-316608-13675368/concept-1.png`, 1672×941. A marca foi corrigida para **HARBOR**, conforme instrução explícita do usuário.
- Implementação: `evidence/world-map-design-379512-14114868/desert-digo-region.png`, 1280×720. Captura adicional em 800×600, com seleção, destino marcado e filtros abertos nas três regiões.
- Comparação conjunta: `evidence/world-map-design-379512-14114868/comparison.png` (2560×750); fonte normalizada para 1280×720 por reamostragem Lanczos, sem recorte, e implementação em pixels nativos. Comparação de detalhes: `comparison-controls.png`. Godot usa pixels do viewport; CSS/deviceScaleFactor não se aplicam.
- Estado: português, deserto enquadrado, Digo selecionado e filtros recolhidos. As capturas rápidas usam o MapUI de produção e geografia real preparada, sem montar Main; o relatório `capture-index.json` explicita essa limitação. A evidência integrada usa `tests/measure/measure_world_map.gd`.

## Superfícies de fidelidade

- **Tipografia:** Barlow Semi Condensed do projeto, títulos em semibold, hierarquia HARBOR/abas/nome/ações. Textos funcionais legíveis nas duas resoluções verificadas. Uma linha de respiro acomoda os overlays obrigatórios de build e FPS sem sobrepor HARBOR.
- **Layout:** mapa amplo, abas superiores, filtros recolhíveis à esquerda, controles à direita e cartão horizontal de destino. O cartão retorna ao mínimo após mudança de conteúdo; o botão Limpar destino permanece inteiramente no rodapé compacto.
- **Cores:** grafite, marfim, dourado para seleção/ação e ciano para jogador. Escala e norte têm suporte escuro discreto para manter contraste sobre neve e estradas.
- **Imagem:** relevo e curvas obtidos dos dados de produção; material raster mineral gerado a partir da direção escolhida (`assets/ui/map/mineral-relief.png`), com mipmaps. Base contínua e transição exterior eliminam o recorte retangular de apresentação, vazios e espinhos introduzidos nas primeiras passadas. O mapa continua baseado em coordenadas navegáveis reais.
- **Conteúdo:** HARBOR correto, nomes próprios autorados, ações funcionais, sem descrições decorativas. A localização de Digo acompanha sua entrada real; o conceito ilustrado o colocava em outra posição. Ponte bloqueada, descobertas e destinos continuam refletindo o estado do jogo.

## Histórico de correções e evidência

1. `world-map-352996-13481260`: P1 nas bordas retangulares do deserto e no recorte da montanha; P2 no primeiro cartão excessivamente alto, botão de rodapé cortado e escala sem contraste. Corrigidos material, perímetro, dimensionamento dos Containers e contraste.
2. `world-map-design-369032-17483095`: cartões/filtros corrigidos; detectado P1 de separação escura entre bacia e escarpas. Substituído o fade interno por uma base contínua da união das formas.
3. `world-map-design-374948-13957858`: união corrigida; pequenos espinhos nas concavidades do anel exterior classificados P2. Substituído o anel extrudido por uma grade sem sobreposição, com transparência pela distância ao perímetro.
4. `world-map-design-379512-14114868`: revisão conjunta pós-correção. Sem os vazios/espinhos; cartão inicial compacto, filtros abertos legíveis e `desert-marked-compact.png` confirma o rodapé completo. Nenhum P0/P1/P2 de HUD ou artefato de borda ficou aberto nessa cobertura.

Diferenças intencionais: a geografia autorada mantém o centro do deserto mais uniforme e escarpas mais regulares que a ilustração; não se afirma equivalência fotorrealista. Facetas largas do relevo de origem continuam visíveis. Pictogramas são os vetores compartilhados do jogo, preservando significado dos serviços, e o botão Localizar continua disponível no cartão. A faixa de versão alfa não existe no conceito.

## Validação funcional e performance

- `dotnet build Harbor.csproj --no-restore`: passou, zero erros/avisos.
- `tests/test_ui_map_contract.gd`: 42 checks aprovados, incluindo seleção por controle sem alternância infinita, sobreposição de UI, filtros, waypoint e rodapé em 800×600.
- `tests/test_world_map_atlas.gd`: 270 checks aprovados, incluindo coordenadas, acesso norte versus montanha, progressão e reutilização do relevo sem montar regiões. Uma primeira tentativa encontrou erro externo em Gameplay.gd durante edição concorrente; não foi usada como aprovação. A repetição após alteração daquele arquivo passou sem erros de script.
- Primeira integração com Main/C# concluída em `evidence/world-map-352996-13481260/metrics.json`; revisão visual final nas capturas rápidas indicadas acima. As tentativas de comparativo em `world-map-349824-10903834` e `world-map-350736-12984565` foram interrompidas. A última também detectou outro teste renderizado concorrente (`test_firearm_rig.gd`), portanto não fornece comparação válida de frame time. Os processos do benchmark desta tarefa foram encerrados; testes alheios foram preservados. Performance permanece não certificada, conforme a decisão do usuário de manter a validação simples.
- Cache de apresentação limitado ao mundo da sessão e invalidado pela geometria; marcadores e progressão são recolhidos novamente a cada abertura.
- Importações da textura concluíram, mas o editor headless apresentou erros no encerramento (`EditorSettings`/RID) e foi finalizado depois do término da importação. As execuções de jogo e testes posteriores encerraram normalmente.

Limites: navegação de gamepad validada por eventos injetados, não por teste físico de um controle; benchmark não pode ser inferido do contador de FPS nas capturas rápidas.

---

# Revisão anterior preservada — menu centralizado

final result: passed

Escopo: apresentação do menu principal, seleção de saves, novo jogo e configurações. Não certifica o carregamento do mundo ou os demais sistemas do jogo.

## Referência e evidências

- Referência aprovada: `C:/Users/rafae/.codex/generated_images/01a13f3f-db8c-75a0-a2b0-643d252490c6/exec-7b41ef3c-cc47-4778-97eb-28738f5339d6.png` (1672×941).
- Capturas renderizadas: `evidence/centered-title-menu/main.png`, `main-4x3.png`, `saves.png`, `new-game.png`, `settings-0.png`, `settings-1.png`, `settings-2.png`.
- Comparação conjunta da referência e captura principal, mesma proporção 16:9, captura em 1280×720; teste adicional em 1024×768. Estado principal: Continuar selecionado, português.

## Correções após a primeira comparação

- P2: título em Barlow estava fino e pequeno. Substituído por wordmark raster transparente derivado da referência; proporção preservada via AtlasTexture.
- P2: textos do menu estavam compactos. Aplicado espaçamento entre letras e largura da seleção ajustada.
- Nova captura após correções confirmou título, hierarquia, centralização e leitura. Sombra discreta dá suporte aos textos sobre reflexos.

## Superfícies verificadas

- Tipografia: wordmark pesado em marfim; Barlow existente nos controles, com espaçamento ampliado. Sem quebras nas ações verificadas.
- Layout: título e ações centralizados; fundo cobre a tela sem distorção; saves e configurações substituem as ações, preservando a arte.
- Cores: água azul quase preta, marfim e detalhes dourados; foco usa faixa clara com texto escuro.
- Imagens: fundo e wordmark gerados com Image Gen a partir da opção aprovada. Sem personagens ou revelações narrativas.
- Conteúdo: funções existentes preservadas; importação V1 acessível dentro da seleção de saves. Preferência de idioma do usuário continua sendo respeitada (português aplicado só no processo de captura).
- P3 aceitos: ausência do pequeno triângulo decorativo; foco continua explícito pela faixa. Texto funcional existente “Sair do jogo” e aviso de versão alfa preservados. Pequenas diferenças no desgaste do wordmark e fonte dos botões.

## Validação

- `dotnet build Harbor.csproj --no-restore`: 0 erros, 0 avisos.
- `tests/test_centered_title_menu.gd`: PASS. Centralização, abertura/retorno de saves, cancelamento de importação, três abas, restauração de foco e novo jogo sem gravação.
- `tests/test_menu_idle.gd -- --measure`: PASS antes/depois, saves da fixture intactos e nenhum mundo iniciado sem clique.
- Godot 4.7.2 .NET, Forward Mobile, RTX 4060 Laptop, VSync e limite 60 FPS; 30 segundos por amostra. Baseline versus final: p50 16,666→16,666 ms; p95 16,873→16,823 ms; p99 17,979→17,297 ms; máximo 1521,729→1176,289 ms; média incluindo inicialização 56,49→57,32 FPS; 3 frames acima de 33,3 ms e 3 acima de 66,7 ms em ambas. Sem regressão observada neste cenário de menu. Picos de inicialização permanecem; não é certificação global de FPS.
- Relatórios: `evidence/menu-on-demand-20261002/deepwater-before/report.json` e `deepwater-final/report.json`.
- Limite externo: importação do editor detectou erro de inferência em `world/desert/village/DesertVillageDoor.gd:27`, arquivo já alterado por outra sessão. Não modificado aqui. Entrada no mundo não foi revalidada nesta entrega.
