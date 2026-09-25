# Revisão visual funcional — 24/09/2026

Capturas de `Main.tscn` real, Godot 4.7.2 / Mobile / NVIDIA GeForce RTX 4060 Laptop GPU. **Não são benchmark nem aprovação de FPS.** O jogo preexistente do usuário continuou aberto; não foi encerrado. O fixture solicitou 8 pedestres, desativou despacho externo e usou `--no-save`. Não gravou configurações nem saves.

## Primeira rodada — resultado inspecionado

Executada por `tests/capture/video_review_interiors.gd`. Concluiu com 20 imagens, `failures: []` em `interior-captures.json` e stderr vazio. A finalidade era examinar a apresentação após o lote inicial, antes do ajuste final de HUD/prompt e do último ajuste de zoom.

| Caso | Evidência | Observação visual |
| --- | --- | --- |
| Duas entradas e saídas de carro | `vehicle-0-*`, `vehicle-1-*` | Dante retorna com corpo visível; `visual_position=(0,0,0)` após ambos os ciclos. O coupé usado não apresenta placas laterais soltas quando fechado. |
| Roubo e saída da moto | `motorcycle-before-theft.png`, `motorcycle-after-theft-dante-mounted.png`, `motorcycle-after-dismount.png` | Há ocupante controlado visível e texto “Sair da moto”. Uma vista mais próxima foi solicitada para inspecionar o encaixe da pose. |
| Loja após carro e moto | `ammunation-spawn-after-two-car-cycles.png` | Pernas e pés aparecem completos em piso livre. Não há chuva dentro; o registro do primeiro render também mostra emissores ocultos/desativados. |
| Banco após carro e moto | `bank-walking-armed-guards.png`, `bank-standing-armed-guards.png` | Dante tem pernas/pés completos andando e parado. Guardas seguram as armas orientadas para o jogador; o guarda à esquerda aponta para baixo/direita e o da direita para baixo/esquerda. |
| Retorno ao exterior | `harbor_ammunation-exit-first-render.png` | A primeira imagem solicitada após a saída já contém cenário externo e Dante inteiro; não ficou somente o fundo uniforme. Esse caso chama `FullSession.leave_place` diretamente, portanto não prova o zoom do acesso automático. |
| Chuva na garagem | `maciota-first-render-rain-outside.png`, `maciota-settled-rain-outside.png` | Partículas de chuva ausentes desde o primeiro render. Os NPCs permanecem visíveis. |

A primeira rodada encontrou dois resíduos reais no primeiro render da garagem: texto **“E Entrar”** e pistola no HUD/pose ainda persistiam brevemente, mesmo com o estado de armas já bloqueado. Foram enviados ao coordenador e originaram a atualização síncrona de apresentação em `FullSession`/`ClassicGameplayHUD`. As imagens iniciais foram preservadas como evidência anterior a esse ajuste.

## Segunda rodada e diagnóstico causal

`tests/capture/video_review_final.gd` produziu 15 imagens, sem falhas do fixture nem erros no stderr. A imagem `final-garage-first-render.png` já apresenta punho, mão sem pistola e nenhum “E Entrar” residual. A caminhada até o balcão termina em `final-ammo-counter-service.png` com “Falar com Vance”. `final-ammo-zoom-00..04.png` registra o afastamento real do helper: câmera size 11,60 → 15,17 → 18,59 → 20,03. Esses valores descrevem enquadramento, não FPS.

Essa rodada identificou um problema adicional na camada de silhueta: `final-bank-occlusion-behind.png` mostra pés transparentes desenhados sobre o tampo quando o personagem está fisicamente atrás; `final-motorcycle-after-theft-dante-mounted.png` mostra uma mancha clara na cabeça/costas do piloto. O efeito foi investigado antes de aprovar a aparência.

`tests/capture/video_review_silhouette.gd` removeu **somente o material de silhueta**, por uma imagem, e depois o restaurou, mantendo personagem, pose, veículo, câmera e cena. `CityLook` ficou suspenso durante essa única comparação para não reinstalar o overlay. O resultado confirmou a causa: a mancha some na moto e os pés ficam corretamente ocultos atrás do balcão. O controle positivo externo usou Dante atrás da fachada real do Maciota: com overlay o contorno é visível; sem overlay ele fica inteiramente oculto.

Evidências: `ablation-motorcycle-after-theft-dante-mounted.png` / `ablation-motorcycle-without-silhouette.png`; `ablation-bank-occlusion-behind.png` / `ablation-bank-behind-without-silhouette.png`; `ablation-exterior-behind-building.png` / `ablation-exterior-behind-building-without-silhouette.png`. O JSON registra uma malha de silhueta no jogador antes e zero durante a ablação.

Limitações da execução diagnóstica: o primeiro lançamento revelou um erro de inferência de tipo no próprio script de captura (`city`), corrigido para `Node` e validado pelo parser. Na execução completa, a posição frontal escolhida para o banco estava ocupada por um guarda; o fixture não atravessou esse sólido e registrou a falha. A comparação causal atrás do balcão e o controle externo foram concluídos. Para a confirmação seguinte, o fixture passa a aguardar a admissão dos guardas e tenta outras posições livres, mantendo a mesma consulta de cápsula. Os logs da tentativa anterior foram preservados.

## Confirmação do primeiro ajuste de silhueta

A execução `depth-fixed` concluiu 11 imagens com `failures: []` e stderr vazio. O banco foi confirmado por inspeção: `depth-fixed-bank-first-render.png` não tem overlay desde a primeira imagem; `depth-fixed-bank-occlusion-front.png` mostra o corpo em área livre e `depth-fixed-bank-occlusion-behind.png` oculta corretamente pernas/pés atrás do balcão. O controle exterior `depth-fixed-exterior-behind-building.png` preserva o contorno através da fachada, e a ablação correspondente oculta Dante completamente. Ao retornar ao exterior, o JSON registra novamente uma malha com o material.

**O primeiro ajuste não resolveu a moto.** Mesmo compartilhando a caixa do conjunto jogador/veículo, `depth-fixed-motorcycle-after-theft-dante-mounted.png` ainda contém a mancha branca. `depth-fixed-motorcycle-without-silhouette.png` continua limpa. Portanto, o teste lógico de caixas e `failures: []` do fixture não aprovam essa aparência. A rodada seguinte separa o overlay da moto e o do jogador para definir o menor ajuste causal.

A rodada `layers` acrescentou oito imagens e um dump das caixas/materiais, sem erros. Nessa inicialização, a imagem original **já estava limpa com ambos os overlays**, antes das ablações separadas. Remover o overlay do jogador ou da moto também produziu imagens limpas, portanto essa rodada não permite atribuir causalidade a um deles. O dado levou à investigação da janela de atualização: durante o embarque o personagem é temporariamente oculto e fica fora do cálculo de limites; ao reaparecer, a caixa podia continuar sendo a da moto por até o próximo refresh de 4 Hz. O par `layers-mounted-behind-building.png` / `layers-mounted-behind-building-without-silhouette.png` confirma que o auxílio visual montado aparece através da fachada real e desaparece durante a ablação. Essa posição é um fixture fixo de renderização; não certifica circulação ou colisão da moto atrás da fachada.

## Confirmação final da moto

O ajuste final de `CityLook` reconhece mudança de visibilidade e conclusão da transição corporal, atualizando a caixa do conjunto imediatamente. O teste lógico de escopo reproduziu a falha antes e passou após o ajuste; a validação renderizada foi feita separadamente pelo fixture `tests/capture/video_review_motorcycle_layers.gd`.

A execução `temporal-final` gerou 11 PNGs, `failures: []` e stderr vazio. Para evitar que um refresh periódico favorável escondesse a falha, o fixture executou `_refresh_silhouette` enquanto Dante estava oculto no fim do embarque e reiniciou somente o relógio periódico até o embarque terminar. Os hooks de contexto permaneceram ativos. As três imagens foram coletadas em memória e gravadas depois da sequência, evitando o custo de codificar PNG entre elas.

| Evidência | Resultado inspecionado |
| --- | --- |
| `temporal-final-mounted-frame-000.png` | Primeiro render solicitado após concluir o embarque, aos 4,711 ms: cabeça/costas normais, sem mancha; caixa já engloba a malha do jogador. |
| `temporal-final-mounted-frame-100.png` | Aos 114,179 ms, aparência correta e caixa válida. |
| `temporal-final-mounted-frame-300.png` | Aos 304,070 ms, aparência correta e caixa válida. |
| `temporal-final-motorcycle-after-theft-dante-mounted.png` | Dante permanece visível montado, sem piloto antigo nem mancha de silhueta. |
| `temporal-final-mounted-behind-building.png` | Contorno do conjunto piloto/moto continua visível através da fachada real. |
| `temporal-final-mounted-behind-building-without-silhouette.png` | Mesmo conjunto fica totalmente oculto sem o material, confirmando o controle positivo. |

O JSON registra `box_encloses_mounted_mesh=true` nas três amostras e o corpo visual permanece na origem após desmontar. Esses tempos identificam quando as imagens foram coletadas; **não são amostras de benchmark nem demonstram FPS**. O defeito de silhueta da moto está validado nos casos acima, assim como a oclusão específica do balcão do banco. Não equivale à aprovação completa de movimentação, interiores ou performance.

Reprodução funcional: executar Godot renderizado com `--path D:/geteco/game --script res://tests/capture/video_review_motorcycle_layers.gd -- --no-save --skip-arrival --population=8 --capture-prefix=novo- --capture-report=novo-captures.json`. Usar um log distinto, esperar o término e inspecionar as imagens, mantendo apenas um teste nosso ativo. O script não grava saves/configurações; a física da moto do fixture continua suspensa.

## Fase 2 — armamento policial por equipe

Captura executada em Main real pelo script `tests/capture/video_phase2_police.gd`, com `--no-save --skip-arrival --population=8`. Console PID 33500 encerrado normalmente; cinco PNGs produzidos, `phase2-police-captures.json` com `failures: []` e stderr vazio. Godot 4.7.2 / Mobile / RTX 4060 Laptop GPU; PNGs de 2560×1440. O tamanho da janela informado pelo viewport foi 3440×1440, portanto não se trata de resolução controlada para benchmark.

As equipes foram criadas por `DispatchController.spawn_officer`, com seis estrelas atuais e identidades de despacho diferentes. O fixture posiciona os agentes em piso consultado por raio e cápsula, suspende IA/veículos e usa câmera próxima com a inclinação exterior para inspecionar as armas. Não reproduz a perseguição completa; o desembarque/roubo real foi verificado separadamente no headless de 93 checks.

| Imagem inspecionada | Constatação |
| --- | --- |
| `phase2-police-lineup-aiming.png` | Três policiais com fardas e armas distintas, todos apresentados simultaneamente com seis estrelas atuais. |
| `phase2-police-pistol-aiming.png` | Patrulheiro de azul mantém pistola curta, com as mãos junto ao cabo. |
| `phase2-police-smg-aiming.png` | Interceptor de sobretudo marrom apresenta a SMG, com coronha, carregador e corpo diferentes da pistola. |
| `phase2-police-m4a1-aiming.png` | Equipe tática escura apresenta M4A1, distinguível pelo guarda-mão/cano e corpo do fuzil. |
| `phase2-police-lineup-relaxed.png` | As três famílias continuam distintas com armas baixadas, sem trocar o loadout ao mudar a pose. |

O escopo é **três famílias existentes**: patrulha/pistola, interceptor/SMG e equipes especiais/M4A1. SWAT, FBI e exército mantêm a mesma família de fuzil; não foi criada uma arma exclusiva para cada estrela. Patrulhas comuns enviadas como apoio continuam com pistola mesmo em seis estrelas. O JSON confirma que tier/weapon do agente e do modelo coincidem nos três casos. A rodada aprova essa diferenciação visual específica; não aprova FPS, animação completa de combate ou todos os biotipos.

## Limites de aprovação

- Raios de apoio registrados no JSON apenas complementam a fotografia. Não substituem cápsula, varredura de movimento, spawn e testes de colisão.
- As duas primeiras capturas do banco mostram piso livre; sozinhas não comprovam oclusão por mobiliário. A rodada final acrescenta posições admitidas diante e atrás do balcão, com a mesma câmera.
- A parte traseira do balcão da Ammu-Nation não comporta a cápsula do jogador sem invadir os sólidos: `StaffOnly` termina em z=-3,15 e `ServiceCounter` começa em z=-2,8, deixando 0,35 m. Não foi colocado personagem dentro desses sólidos para fabricar uma imagem de oclusão. Cobertura completa de oclusão da loja continua pendente.
- A moto do fixture usa o ponto de apoio já admitido para o carro, com sua física suspensa. A imagem examina ocupante e pose; não valida direção em movimento, salto, streaming nem estabilidade do veículo.
- O menu/configuração de fullscreen do usuário prevaleceu sobre a primeira opção CLI de resolução. As imagens e registros refletem a execução real; não se declara ensaio controlado em 1280×720.
- Estes casos não constituem migração visual completa dos interiores. Layout, materiais, corredor de acesso, todos os móveis, reação de funcionários ao fogo e o conteúdo do porto ainda exigem o trabalho planejado correspondente.
