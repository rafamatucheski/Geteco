# Validação e pendências

Data: 21/09/2026. Aplicadas as orientações de `performance-do-jogo` e `testes-com-criterio`. O usuário proibiu executar Godot/benchmarks sem coordenação com o integrador; nenhuma execução ocorreu.

## Revisão realizada

- Leitura de FullSession.gd, configuração do projeto V2, Settings.gd e contratos de GameInput.gd, além dos catálogos utilizados pela demo.
- Escritas limitadas a arquivos novos em `geteco_v2/ui/menu_presentation/`; alterações preexistentes de outras sessões foram preservadas.
- Inspeção das referências relativas, textos funcionais, limites/step do slider, ciclo de foco, remoção de filhos antigos e ausência de acesso de escrita a saves/settings/InputMap nos componentes/demo.
- Theme aplicado localmente; sem classe global, autoload novo, alteração de projeto, fontes novas ou dependências de rede.
- Nenhum teste Godot foi executado. Revisão de fonte não equivale a compilação ou teste funcional.
- Verificação com Python/stdlib: todas as referências preload/ext_resource locais existem; nenhuma chamada de gravação de configurações/arquivos, alteração de InputMap ou callback por frame nos scripts entregues. Resultado: passou. A inspeção HTML identificou os quatro painéis; nenhum recurso externo é carregado. Isso não valida layout renderizado nem tipos/API GDScript.
- Contraste sRGB calculado (cores sólidas, não captura): texto/fundo da ação 12,93:1; texto secundário/painel 10,26:1; foco/fundo da ação 8,50:1; texto/pressionado 8,03:1. Legibilidade real e renderização da fonte permanecem pendentes.

## Matriz para o integrador (todos os itens pendentes)

| Cenário | Critério |
| --- | --- |
| Importar os scripts e abrir Demo.tscn | Zero erros de parser, tipos, recursos e runtime |
| 1280×720, 1920×1080, 1600×1000, 2560×1080 | Título, textos, foco, volume e Voltar legíveis; margens preservadas; sem rolagem horizontal |
| Área lógica 640×360 e resize contínuo | Quebra de linha sem texto cortado; corpo rolável e rodapé acessível; conferir mínimos dos containers |
| Conteúdo longo | Objetivo completo de Primeiro Giro e todos os bindings; foco acompanha rolagem; nomes/hints longos não aumentam largura do painel |
| Mouse, teclado e controle real | Hover/pressionado/foco distintos; Tab e Shift+Tab ciclam; cima/baixo percorrem; Enter/A acionam uma vez; slider ajusta em 0,05 com esquerda/direita |
| Esc/B/Start e remapeamento | Mesmo destino de Voltar por página; sem fechamento duplicado; captura cancela/valida/salva como antes; teclas reservadas e conflitos preservados |
| Reconstrução de página | Preservar ação focada ao alternar configuração; foco inicial ao mudar página; retorno ao dono anterior no fechamento; nenhum foco em nó removido |
| Inventário e missões reais | Só itens possuídos e ações disponíveis; condições de cura, missão e guincho inalteradas; caso sem missões permanece navegável |
| Modal durante gameplay/pausa | Sem ataque, movimento ou input de veículo vazando; desbloqueio original preservado ao fechar; não alterar fluxo de diálogo/mapa/loja/resgate |
| Save/configuração | Aplicação e persistência exatamente uma vez por ação real; demo sem gravação |

Sem cobertura de garagem/combatente nesta entrega: nenhuma lógica de combate ou transição foi alterada. Se a integração tocar esses fluxos, executar também o teste obrigatório `tests/test_garage_weapon_restrictions.gd` no projeto correspondente, com coordenação.

## Performance: não medida

Risco esperado: construção/medição de texto ao abrir ou redimensionar, desenho de Controls e preenchimento do overlay transparente. Não há `_process`, polling, shader, blur ou viewport extra. Isso reduz trabalho previsto, mas não comprova FPS nem ausência de regressão.

Antes da integração, registrar baseline dos menus atuais no V2 renderizado. Comparar depois na mesma máquina/GPU, versão, renderer, resolução, qualidade, save/cenário, VSync e limite de FPS, sem benchmarks simultâneos. Incluir abertura fria e navegação/rolagem do menu de controles com o mundo real ao fundo. Janela finita de pelo menos 30 segundos por cenário; separar aquecimento. Guardar número de frames, duração, frame time p50/p95/p99, máximo e contagens acima de 33,3 e 66,7 ms. Meta provisória: 60 FPS/16,67 ms; hardware ainda não definido. Aumento de mais de 5% em p95/p99 pede confirmação equivalente, não aprovação automática. Não aprovar regressão confirmada nem queda reproduzível para 12–15 FPS.

Estado final: pronto para revisão e conexão pelo integrador; aprovação visual, funcional e de desempenho pendente. Nenhuma captura do motor ou medição foi produzida.
