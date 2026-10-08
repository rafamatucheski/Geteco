# Rauhz — final das arrancadas

Rauhz entra após Digo, Lívia, Raul, Jessica e Nadir. A vitória contra Nadir libera a final de 800 m; saves antigos com cinco vitórias mantêm o histórico e recebem o novo desafio. Primeira vitória: R$ 9.000. Revanche melhora o recorde sem duplicar recompensa.

O Focus MK1 2002 preto tem modelo próprio: hatch de cinco portas, rodas prateadas de cinco raios, pneus baixos, lanternas nos pilares traseiros, aerofólio discreto e repetidores laterais. Usa pintura, rodas animadas, cabine, colisão, motor e áudio da frota. É exclusivo do rival e não aparece à venda no Digo. A ficha mecânica representa uma preparação de corrida fictícia, não a potência de fábrica nem uma medição do carro real da referência.

Rauhz aparece como contato no encontro e como motorista na final, com cabelo castanho, barba curta e camiseta preta. O retrato de seleção usa a fotografia fornecida como referência. O atlas dos cinco adversários anteriores mantém seus recortes; o sexto retrato é independente.

## Validação

Godot 4.7.2 .NET; `dotnet build Harbor.csproj --no-restore -v quiet`: zero erros e avisos. Saves pessoais preservados; checkpoints e gravações de teste em diretórios exclusivos.

| Cenário | Evidência | Resultado |
|---|---|---|
| Progressão anterior, prêmios e rejeição de dados inválidos | `evidence/rauhz-test_desert_drag_progress.log` | 49 checks aprovados |
| Final bloqueada, save antigo, vitória, revanche, gravação/leitura real, retrato, carro e motorista | `evidence/rauhz-contract-final.log` | 27 checks aprovados |
| Equilíbrio mecânico | `evidence/rauhz-test_desert_drag_rival_balance.log` | 33 checks aprovados; Rauhz 15,117 s, Nadir 15,583 s no simulador de motor de 800 m |
| Seleção e revanche | `evidence/rauhz-test_desert_drag_board.log` | 10 checks aprovados |
| Frota, rodas, pintura, preparação e áudio | `evidence/rauhz-desert_cars_fleet.log` | Aprovado, zero falhas |
| Main com C#, embarque normal, quadro, corrida física, pausa, vitória, pagamento, revanche, cancelamento e limpeza | `evidence/rauhz-session-headless.log`, `evidence/rauhz-session-rendered.log` e `evidence/rauhz-session-final.log` | 24 checks aprovados em cada execução; última execução após o encaixe final das lentes |

A final integrada foi vencida pelo jogador com Mirage e peças disponíveis no catálogo, sem forçar resultado, posição de chegada ou pagamento. O checkpoint monta as cinco vitórias anteriores; não é evidência de ter jogado toda a sequência nesta sessão.

A revisão de perto encontrou lentes parcialmente enterradas no capô. A superfície final é projetada sobre os triângulos reais da carroceria durante a construção do modelo, preservando o encaixe no chanfro sem trabalho por frame. Captura final do carro: `evidence/rauhz-focus-110324-5835250/rauhz_focus_mk1-front-day.png`.

Capturas da cena real:

- `evidence/rauhz-session-133400-5864582/final-board.png`
- `evidence/rauhz-session-133400-5864582/final-grid.png`
- `evidence/rauhz-session-133400-5864582/final-racing.png`
- `evidence/rauhz-session-133400-5864582/final-result.png`

Não houve avaliação auditiva humana nem revisão temporal noturna. Não foi feita auditoria de trânsito ou de iluminação fora desta atividade.

## Desempenho: inconclusivo

Runner existente: `tests/measure/measure_drag_ui.gd`. Main renderizada, RTX 4060 Laptop, Mobile, 1280×720, horário 0,45, VSync e limitador desligados apenas no processo de medição. Alvo provisório: 16,67 ms; variação acima de 5% em p95/p99 exige confirmação comparável.

| Amostra | Frames / segundos | FPS | p50 / p95 / p99 (ms) | Máximo (ms) | >33,3 / >66,7 ms |
|---|---|---|---|---|---|
| Quadro antes | 14.686 / 29,916 | 490,9 | 1,785 / 3,287 / 5,007 | 71,827 | 1 / 1 |
| Quadro depois | 12.426 / 29,909 | 415,5 | 2,254 / 3,877 / 5,314 | 9,616 | 0 / 0 |
| Corrida 1 antes | 8.536 / 20,697 | 412,4 | 2,212 / 3,938 / 5,817 | 12,223 | 0 / 0 |
| Corrida 1 depois | 7.434 / 20,695 | 359,2 | 2,557 / 4,226 / 6,113 | 15,539 | 0 / 0 |
| Corrida 2 antes | 7.812 / 20,690 | 377,6 | 2,434 / 4,405 / 6,197 | 14,483 | 0 / 0 |
| Corrida 2 depois | 6.340 / 20,684 | 306,5 | 2,979 / 5,299 / 7,641 | 23,402 | 0 / 0 |

Métricas brutas: `evidence/drag-ui-179856-5732168/metrics.json` e `evidence/drag-ui-41764-5876564/metrics.json`. O aumento de p95/p99 não foi atribuído a esta implementação: outra sessão iniciou `tests/test_dante_traversal_pose.gd` renderizado durante a medição posterior, e várias dependências compartilhadas receberam trabalho concorrente. A janela do quadro também ficou ligeiramente abaixo de 30 s úteis; as duas corridas são ciclos separados de aproximadamente 20,7 s. O runner usa Digo, portanto tampouco mede especificamente a carga do novo Focus na final. Não há aprovação de regressão ou de FPS da final; falta amostra exclusiva comparável de pelo menos 30 s por cenário crítico. A corrida renderizada da final valida funcionamento e apresentação, não substitui esse benchmark.

## Retrato

Arquivo final: `assets/desert_drag/portraits/rauhz.png`. Gerado pela ferramenta integrada `image_gen`, seguindo a skill imagegen. Referências: fotografia do Rauhz fornecida no pedido e `assets/desert_drag/portraits/roster-cinematic.png` como guia de estilo.

Prompt utilizado:

> Create one cinematic game character selection portrait of Rauhz, matching the identity of the man in reference image 1 (reference only: preserve his facial structure, short swept brown hair, blue-grey eyes, light skin, faint mustache and short stubble). Reference 2 is the style guide only: realistic illustrated cinematic racing-game portrait, charcoal blue dark background, subtle warm rim light, high detail. Single person only, front facing, composed confident neutral expression, black crew-neck t-shirt like reference with small red/cyan graphic mostly below framing. Vertical portrait, head and upper chest, full hair with some top margin, face centered for square thumbnail crops. No letters, no UI, no logos, no border. This is an in-game portrait asset, not a photo of a monitor.
