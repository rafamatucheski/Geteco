# Geteco V2 — migração por trechos completos

Projeto Godot independente em `geteco_v2`, iniciado em 21/09/2026 a partir do mundo 3D aprovado. O jogo anterior e `prototypes/world3d` continuam preservados. A primeira entrega é uma base jogável, não a migração completa da campanha.

## Decisões

- Mundo, personagens, veículos, colisões e profundidade em 3D nativo no mesmo World3D. Interface e diálogos continuam em controles 2D, apropriados para tela.
- Modelos originais são reutilizados quando independentes. Comportamentos presos a coordenadas/projeção 2D são reimplementados com física 3D.
- Dados de missão e inventário não dependem das cenas. Lugares e etapas possuem IDs estáveis. Saves V1 não são importados implicitamente.
- Cada trecho só recebe status concluído após funcionar de ponta a ponta, com imagens reais, colisões e oclusão verificadas separadamente e medição renderizada comparável.
- Um mundo pequeno funcionando é a referência para crescer. Aumentar bairros/população requer medição; trocar 2D por 3D não garante desempenho por si só.

## Etapas e critérios de saída

| Etapa | Entrega concreta | Critério | Estado |
|---|---|---|---|
| 1. Base independente | Cidade pequena, Dante, carro dirigível, tráfego, pedestres, câmera e pausa | Jogar a pé e de carro; sem dependências de execução V1 | Implementada, herdada do protótipo aprovado |
| 2. Primeiro trecho Maciota | Fachada/interior original, personagens, interação, tarefa curta, save próprio | Entrar, conversar, coletar, entregar, sair e retomar progresso sem duplicação | Implementado e validado; aguarda avaliação do usuário |
| 3. Bairro de referência | Ruas e pontos de interesse reais, navegação de pedestres, acesso consistente aos interiores | Uma rota real completa, tráfego sem bloqueios permanentes e carga mensurada | Planejada |
| 4. Sistemas de jogo | Inventário apresentado, combate 3D, dano, reações, polícia, veículos com estados persistentes | Fluxo completo de ação/consequência/save; regras da garagem invioláveis | Planejada |
| 5. Campanha | Missões e diálogos completos, progressão, transições entre regiões | Uma missão inteira por entrega, revisada contra dados originais | Planejada |
| 6. Expansão e substituição | Streaming por região, densidade, variedade, áudio, opções e distribuição | Paridade definida, desempenho na máquina alvo e revisão visual | Planejada |

## Reaproveitamento e reconstrução

| Conteúdo | Tratamento V2 |
|---|---|
| Dante GLB, Coupe, modelos de civis | Cópias dos recursos originais; movimento/animação em mundo 3D |
| Fachada, oficina, detalhes e personagens Maciota | Geometria original isolada dos scripts antigos; colisões 3D e câmera próprias |
| Saudação de Maciota | Texto original; demais falas conectam uma tarefa curta adaptada |
| Missão completa de chegada | Ainda não migrada; a tarefa V2 não equivale à campanha V1 |
| Save, inventário e restrições de zona | Novo contrato independente, esquema versionado e backup; sem conversão de save V1 |
| Movimento/colisão 2D, projeção e composição por SubViewport | Substituídos por corpo/câmera/colisão 3D nativos |
| Mapas restantes, armas, combate, polícia, lojas, áudio e missões | Inventariar e migrar por etapa, sem declarar suporte antecipado |

## Organização

- `scripts/World.gd`: composição da cena; `V2Session.gd`: interação, checkpoints e interface.
- `world/maciota`: ambiente e contrato de posições físicas.
- `assets/maciota`: arte adaptada e rastreada em `maciota-migration.md`.
- `systems/Progression.gd` e `data/GarageSequence.gd`: estado puro e conteúdo.
- `tests`: verificações repetíveis; `evidence`: saídas reais, fora da importação do editor.
- `--sandbox`: preserva o percurso experimental de carro para regressão. A campanha inicial usa Maciota.

## Limitações assumidas

Pedestres ainda seguem circuitos fixos; não existe navegação urbana geral. Carros não têm dano, suspensão ou áudio completos. O save registra etapa/inventário/localização por checkpoint, não posição exata nem estado de cada carro/civil. Armas têm somente contrato de bloqueio; combate ainda não existe. Os demais edifícios continuam sendo volumes de referência. A escala total será decidida por medições com mais regiões, não pelo FPS de uma praça.
