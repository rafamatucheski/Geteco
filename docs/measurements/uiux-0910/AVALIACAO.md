# Avaliação de UI/UX — GETECO — 10/09/2026

**Parecer: há uma direção visual convincente e uma base funcional de jogo de PC, mas o conjunto ainda não entrega acabamento premium consistente.** O menu é o ponto mais forte; configurações, HUD, diário e quadros de missão precisam compartilhar melhor essa identidade. A evolução adequada é consolidar os sistemas existentes, com prioridade para leitura, orientação e controle.

## Escopo e evidências

Foram lidos o README, a arquitetura e o código atual do jogo principal, cuja entrada é `ui/MainMenu.tscn` e cuja partida usa `world/harbor/HarborGame.tscn`. Não foram confundidos os protótipos, o jogo web da raiz ou o legado com a versão principal.

Capturas novas foram feitas com Godot 4.7.2, Vulkan/Forward+, RTX 4060 Laptop, por `capture_review.gd`, com saves e destino de configurações isolados em pasta temporária. A execução terminou com código 0; o log registra um aviso de interpolação de câmera e uma instância residual no encerramento, sem diagnóstico de causa nesta avaliação.

Foram inspecionados visualmente menu, carregar vazio, áudio, vídeo, controles, partida, pausa, diálogo, quadro de serviços e diário. Menu e HUD também foram capturados em viewport 1920×1080. A captura `07_menu_16x10.png` manteve viewport lógico 1280×720; **não comprova layout expandido em 16:10**. Não houve validação em ultrawide, 4K, gamepad ou aparelho mobile.

A abertura foi pulada por flags de revisão. Diálogo, quadro e diário foram abertos por suas funções, e o quadro/diário usaram uma flag de progresso artificial para inspeção visual. Portanto, essas imagens não validam a sequência de campanha, seus estados de bloqueio ou a acessibilidade física dos pontos de interação. Capturas históricas de lojas, arsenal e tutoriais foram usadas apenas como apoio, com confiança menor que as capturas novas.

Não foi feita uma sessão longa de jogo, teste com usuários, avaliação sonora por escuta ou medição de desempenho nesta auditoria. Os arquivos de gameplay existentes não foram alterados.

## O que merece ser preservado

- **Identidade do menu:** porto, pôr do sol, Dante e carro comunicam bem ação urbana e dão personalidade ao GETECO. A seleção em laranja e as transições curtas já criam uma apresentação intencional.
- **Estrutura da partida:** vida/armadura/arma à esquerda, dinheiro/procura à direita e minimapa no canto formam uma organização reconhecível. O centro permanece relativamente livre.
- **Integração com o mundo:** Maciota, oficina, quadro de serviços e arsenal ligado ao carro têm relação com a ficção. Vale desenvolver essa identidade nas interfaces correspondentes.
- **Base de usabilidade:** existem foco visual, rolagem, configurações persistentes, tradução PT/EN e tratamento de modais. O diálogo tem corpo de texto confortável. O tutorial possui fila e bloqueios para não disputar atenção com combate, direção rápida e outras telas.
- **Custo do minimapa:** usa desenho de geometria em cache, sem outra câmera renderizando a cidade. É uma base apropriada para preservar ao evoluir a navegação.

## Achados e prioridades

| Prioridade | Evidência | Impacto | Ação sugerida | Esforço relativo |
|---|---|---|---|---|
| Alta | Ao abrir Carregar com Enter, o foco permanece em `BtnLoadGame`, atrás do modal; Esc não fecha a janela. Log e captura 02. | O teclado continua apontando para uma ação atrás do modal; fluxo inconsistente com Configurações, onde Esc funciona. | Transferir e conter o foco no modal, bloquear ações ao fundo e restaurar o foco ao fechar. Verificar com saves válidos e com lista vazia. | Baixo |
| Alta | O menu mantém Carregar em primeiro lugar mesmo com todos os slots vazios. Captura 02. | A principal opção leva um jogador novo a uma tela sem ação útil. | Sem save: Novo jogo como ação principal. Com save válido: Continuar, mostrando brevemente onde o jogador parou; Carregar fica como opção secundária. | Baixo/médio |
| Alta | Configurações mostram “AudioServer” e `user://settings.cfg`; Carregar mostra `user://saves/`; quadro mostra “Serviço autorado”. | A linguagem parece voltada a quem desenvolve o jogo. | Reescrever para intenção do jogador: “Nenhuma partida salva”, “Ajuste o volume do jogo” e uma descrição concreta do serviço. | Baixo |
| Alta | Menu usa preto/laranja/creme; pausa e configurações usam borda amarela, sombra e botões distintos; quadro e diário têm outro tratamento. Capturas 01, 03, 09, 10 e 12. | A qualidade da primeira tela não se mantém como um conjunto reconhecível. | Criar tema compartilhado de tipografia, espaçamento, painéis, botões, foco e mensagens. Preservar variações temáticas, como a moldura do quadro. | Médio |
| Alta | O objetivo apresenta “SO / 66 m”; o minimapa atual não desenha destino ativo nem rota de missão. Código de `HarborMinimap.gd` e captura 08. | O jogador precisa converter texto e pontos cardeais em navegação. | Primeiro, marcador do destino e indicação da entrada correta; depois, rota opcional pelas vias. Compartilhar o mesmo destino entre objetivo e mapa. | Médio; rota maior |
| Alta antes do lançamento PC | Controles são labels; mira lê mouse diretamente e vários comandos do carro leem teclas específicas. | Não há remapeamento completo por esta UI; isso também torna gamepad e toque mais trabalhosos. | Centralizar ações de jogar, separar navegação de menus, permitir remapeamento e gerar dicas conforme dispositivo ativo. | Médio/alto |
| Média | Dinheiro em 36 px com oito dígitos e contorno forte; objetivo em 16 px e título em 12 px. HUD mantém dimensões semelhantes em pixels na captura 1080. | A informação de objetivo perde importância visual; resolução maior pode reduzir o conforto relativo de leitura. | Rever hierarquia e oferecer escala independente para interface/texto. Remover zeros à esquerda do dinheiro se não forem uma escolha retro deliberada. | Médio |
| Média | Em inglês, a tela de vídeo ainda mostra “Janela” e “Ativado”. Código também contém “CORPO A CORPO” fixo em PT. | Tradução incompleta enfraquece acabamento e consistência. | Revisar texto visível, inclusive opções, checkboxes e HUD; testar a troca pelo fluxo real da interface. | Baixo/médio |
| Média | Configurações de vídeo oferecem três resoluções 16:9; não há controles de escala de UI, tamanho de legenda ou redução de movimento nesta tela. | Pouca adaptação a preferências e telas de PC. | Ampliar opções de legibilidade e conforto; validar janela, tela cheia, 16:10 e ultrawide. Adicionar confirmação com reversão para troca de vídeo. | Médio |
| Média | Diário apresenta lista longa; o botão de descansar tem destaque mesmo com a explicação de que descanso é opcional. | O jogador pode interpretar descanso como próximo passo obrigatório. | Dar destaque ao objetivo atual e ao próximo local; separar disponíveis e concluídas; descanso como ação secundária contextual. | Médio |
| Média | Diálogo e quadro mantêm partes do HUD e minimapa visíveis, embora o objetivo seja ocultado. | Elementos sem utilidade imediata continuam competindo com a leitura. | Definir uma política comum de visibilidade por estado: exploração, combate, direção, diálogo e menus. | Médio |
| Antes do lançamento | Novo jogo faz fade para preto e troca de cena; não há tela explícita de carregamento nesse caminho. | A espera não informa o que está acontecendo. | Mostrar apresentação de carregamento com feedback que continue atualizando durante a construção da cena. | Médio/alto |

O carregamento merece atenção, mas os números da documentação antiga não devem ser tratados como medição atual. `ARCHITECTURE.md` descreve um pico antigo de aproximadamente 9,2 s; `HarborPreview.gd` já contém esperas entre etapas, e o arquivo de perfil existente registra outro valor. Esta auditoria não confirmou nenhum desses tempos como benchmark da versão atual.

## Direção visual coerente com o projeto

A proposta mais viável é **ação urbana estilizada, com acabamento de indie premium**. A ilustração do menu é compatível com uma partida top-down; o ponto a controlar é a distância entre a riqueza da ilustração e a simplicidade visual da partida. Não é necessário aproximar o jogo de fotorealismo para resolver isso.

Sugestão: superfícies escuras legíveis, texto marfim, laranja para foco/ação e cores funcionais reservadas para vida, armadura, alerta e objetivo. Poucos pesos tipográficos e uma família consistente de ícones. Texturas temáticas leves em lugares específicos, como oficina e quadro, mantendo a mesma linguagem de interação. Evitar que todos os painéis tenham bordas brilhantes e a mesma intensidade de destaque.

O arsenal já possui um bom contexto na Monaliza. A captura histórica mostra uma UI dominada por menus suspensos: uma evolução seria apresentar os quatro espaços de equipamento com ícone, arma selecionada, munição e ação clara de equipar. Isso pode reaproveitar os catálogos e ícones existentes. Deve ser revalidado na implementação atual antes de redesenhar.

## PC primeiro; preparação mobile agora

No PC, priorizar teclado/mouse completos, foco previsível, remapeamento, escala de interface e leitura rápida. Gamepad deve entrar como uma frente explícita; ter foco em botões do menu não prova que a partida inteira seja jogável com controle.

Para mobile, recomendo começar pelo formato horizontal. A experiência precisa de uma composição própria: direção/movimento à esquerda, mira/ataque à direita e uma ação contextual para entrar, conversar ou coletar. Rádio, faróis e inventário podem ficar em acesso secundário, evitando uma coleção de botões permanentes. Durante a direção, trocar o conjunto de controles.

O minimapa ocupa hoje a região inferior esquerda, e dicas de tutorial usam a inferior direita: ambas disputariam espaço com os polegares. Isso exige reorganização específica no mobile. Inventário, missões e configurações devem permitir painéis maiores ou tela cheia, alvos de toque amplos e menos colunas.

Preparar agora: ações independentes de dispositivo, componentes compartilhados, hierarquia de modais, texto escalável e suporte a margens de segurança. Implementar mais tarde, com aparelho real: ergonomia de toque, assistência de mira, direção e comportamento ao suspender/retomar. A documentação Android recomenda alvos de toque de pelo menos 48×48 dp; dp não equivale diretamente aos pixels do viewport Godot. [Android: acessibilidade e alvos de toque](https://developer.android.com/guide/topics/ui/accessibility/views/apps-views?hl=en).

Definir também a política de proporções e escala: aumentar a área visível, preservar proporção ou usar faixas tem efeitos diferentes na câmera e no HUD. A escolha deve ser validada no jogo, conforme a [documentação de múltiplas resoluções do Godot](https://docs.godotengine.org/en/latest/tutorials/rendering/multiple_resolutions.html).

Portar a UI não garante desempenho mobile. A arquitetura mistura física 2D e apresentação 3D com SubViewports e usa Forward+ nesta versão. Será necessária uma avaliação separada em hardware alvo, com orçamento para memória, aquecimento e estabilidade de quadros. Esta avaliação não declara incompatibilidade nem prontidão mobile.

## Sequência recomendada

1. Corrigir foco do modal, entrada sem saves, textos técnicos e tradução incompleta.
2. Definir tema compartilhado e aplicá-lo ao menu, pausa e configurações; depois HUD e diálogos.
3. Melhorar objetivo, marcador no mapa e hierarquia do diário. Padronizar notificações e dicas contextuais.
4. Completar remapeamento, escala de texto/UI, gamepad e validação em formatos de tela do PC.
5. Criar um protótipo jogável no celular para andar, mirar, interagir e dirigir antes de adaptar todos os menus.

Critério de conclusão: uma pessoa nova consegue iniciar/continuar, entender seu próximo destino, realizar uma interação, sair de qualquer tela e ajustar os controles sem depender de explicação externa. Confirmar isso em sessões curtas com jogadores novos; não substituir esse teste por uma suíte de código verde.

## Índice das capturas desta auditoria

- `01_menu_720.png`, `13_menu_1080.png`: menu principal.
- `02_load_empty.png`: carregar sem partidas; foco e Esc registrados em `runtime.log`.
- `03_settings_audio.png`, `04_settings_video.png`, `05_settings_video_en.png`, `06_settings_controls.png`: configurações.
- `07_menu_16x10.png`: tentativa de janela 16:10, com viewport lógico ainda 16:9.
- `08_gameplay_720.png`, `14_gameplay_1080.png`: HUD em dois viewports e contextos distintos; não são comparação de desempenho ou câmera.
- `09_pause.png`: pausa.
- `10_board_current.png`, `11_dialogue_current.png`, `12_journal_current.png`: composição visual dos modais, com estado de revisão.
