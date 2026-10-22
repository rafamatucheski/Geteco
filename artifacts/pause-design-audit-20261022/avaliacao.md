# Avaliação visual da pausa e das configurações

22/10/2026. Componentes reais de `ui/PauseMenu.tscn`, `ui/PauseMenu.gd`, `ui/SettingsMenu.gd` e `ui/GameStyle.gd`, instanciados em cena isolada no Godot 4.7.2 .NET / Forward+. Fundo composto com captura anterior da cena do jogo. Não representa uma partida integrada nem um redesign.

## Parecer

A paleta grafite/dourado e a fonte Barlow já dão continuidade ao HUD. A composição da pausa é que parece atrasada em relação ao jogo: uma caixa estreita com dez botões muito parecidos, sem agrupamento entre partida, progresso, ajustes e saída. As configurações têm melhor estrutura, porém desperdiçam área vertical e apresentam muita rolagem.

## 1. Pausa — precisa de revisão estrutural

![Pausa em 1280 × 720](02-pausa-1280.png)

- Painel de 360 × 648 em 1280 × 720: estreito, alto e com grandes margens internas. Título e botões estão dentro da mesma rolagem; o foco inicial em Continuar deixa o título fora da área visível nesta montagem.
- Continuar tem foco reconhecível em dourado. Os demais botões têm quase a mesma importância visual, incluindo sair, progresso e ferramentas técnicas.
- Guia do jogo e Desenvolvedor usam texto centralizado e capitalização diferente dos demais botões, que são alinhados à esquerda e em caixa alta.
- A mistura produz a aparência de uma lista de ferramentas, com pouca composição própria de um menu de jogo.
- Recomendo título fixo, agrupamentos claros, maior destaque para retomar e ferramentas de desenvolvimento em acesso separado na versão de desenvolvimento.

![Pausa em 1920 × 1080](08-pausa-1920.png)

Em 1080p, o painel mantém 360 px de largura e ocupa 90% da altura: sobra muito espaço vazio abaixo da lista. O problema de proporção aparece nos dois tamanhos, de maneiras diferentes.

## 2. Vídeo — organizado, mas muito longo

![Vídeo: início](03-video.png)

![Vídeo: final](04-video-final.png)

- Abas, seções, valores e rodapé fixo são pontos fortes.
- Em 720p, o início mostra idioma, perfil, renderizador e modo de tela; a resolução já aparece parcialmente cortada. As opções mais frequentes ficam espalhadas por uma longa página.
- Título e abas ocupam duas faixas; controles têm largura mínima de 330 px. A composição limita o espaço útil para leitura e ajuste.
- Recomendo agrupar Tela, Qualidade e Avançado; colocar idioma em Geral/Idioma; tirar Renderizador da área principal se for somente diagnóstico. Manter descrições técnicas que ajudem o jogador a escolher.

## 3. Áudio — coerente, precisa de melhor densidade

![Áudio](05-audio.png)

- Sliders e valores percentuais são claros, com uma linguagem visual consistente.
- Só quatro volumes aparecem na primeira área, apesar de haver oito canais. Descrições e espaçamento tornam ajustes simples mais demorados.
- Recomendo linhas mais compactas para os canais e explicações sob demanda onde forem necessárias. Manter volume geral em destaque e dublagem em grupo próprio.

## 4. Controles — conteúdo útil com prioridade inadequada

![Controles: entrada](06-controles.png)

![Controles: remapeamento ao final](07-controles-final.png)

- O mapa por contexto ajuda quem joga com controle. A tabela permite tecla principal, secundária e gamepad.
- Mesmo sem controle conectado, o diagrama ocupa quase toda a primeira área. O usuário de teclado precisa rolar para chegar ao remapeamento.
- O desenho combina formato semelhante ao PlayStation com rótulos Xbox, tornando a identificação menos consistente.
- Recomendo seletor Teclado e mouse / Controle, com a configuração do dispositivo ativo primeiro. Grupos por contexto evitariam uma tabela única extensa.

## 5. Ajuda — legível, mas deslocada

![Ajuda](09-ajuda.png)

![Ajuda: final](10-ajuda-final.png)

- Os títulos ajudam a percorrer o texto.
- Ajuda fica dentro de Configurações e há também Guia do jogo na pausa. A arquitetura oferece dois destinos de ajuda sem explicar claramente a diferença.
- A página de leitura herda Cancelar, Salvar e Padrões da aba, ações que não correspondem ao conteúdo apresentado. Recomendo concentrar instruções no guia e usar Voltar em páginas somente de leitura.

## Direção recomendada

Preservar grafite, branco quente, Barlow e dourado moderado. Reorganizar a pausa como navegação de jogo, com título fixo, grupos e seleção bem marcada; reduzir caixas arredondadas repetidas e evitar a coluna estreita ocupando quase toda a altura. Dar continuidade a essa composição nas configurações. A prioridade é hierarquia, proporção e organização, antes de trocar a paleta ou adicionar efeitos.

## Acessibilidade e limites

Foco dourado e valores explícitos são pontos positivos. Textos auxiliares de 14 px, cinza sobre superfície translúcida, merecem conferência de leitura nos fundos claros e escuros. Contraste não foi medido nesta avaliação. Navegação completa por teclado/gamepad, persistência, cancelamento, desempenho e comportamento durante uma partida não foram validados.

Compilação de Harbor.csproj: sucesso, sem avisos e sem erros. Captura final: dez imagens de menus exportadas com sucesso, processo encerrado com código 0 e sem erros no log final. A montagem usa mundo de apoio, valores das preferências carregadas em memória e um fundo estático; disponibilidade real de salvar/carregar e qualidade do cenário não devem ser julgadas por ela. Nenhum código de produção foi alterado por esta avaliação. Arquivos de menu receberam alterações concorrentes durante o trabalho; as imagens refletem o estado carregado na última execução.
