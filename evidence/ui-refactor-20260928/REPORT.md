# Refactoring de UI/UX — 28/09/2026

A nova interface está implementada no projeto: HUD dividida em componentes,
tema compartilhado, informações contextuais, mochila com roupas, minimapa e
mapa completo. O mapa de dependências e as decisões estão em
[ui-contextual.md](../../docs/ui-contextual.md).

## Evidência visual

Capturas reais do jogo, sem composição externa:

- [HUD 16:9](acceptance/hud-1280x720.png), [16:10](acceptance/hud-1280x800.png), [21:9](acceptance/hud-1680x720.png).
- [Mochila](acceptance/backpack.png), [roupas](acceptance/clothes.png), [mapa](acceptance/map.png).
- [Menu inicial](acceptance/main-menu.png), [configurações](acceptance/settings.png), [pausa](acceptance/pause.png).

Os arquivos `before/` e `after/` contêm capturas dos mesmos cenários usados no
benchmark. `source-before/` preserva as fontes anteriores como texto não executável.
Os antigos caminhos de HUD, mapa e inventário são aliases da implementação única.

## Validação funcional

`tests/test_contextual_ui.gd`: **69 verificações, nenhuma falha**, conforme
[result.json](acceptance/result.json) e `acceptance-complete.log`.

Cobertura: estado real de vida/colete/frio, saldo e alteração temporária, troca de
arma e retirada do carrossel, margens e modais nas três proporções, remapeamento,
alternância teclado/controle, abertura/fechamento da mochila, roupa equipada pelo
sistema existente com atualização do personagem, zoom e seleção no mapa, retorno
dos modais ao tamanho normal e bloqueio/arma guardada na garagem.

**13 scripts adicionais aprovados** (12 regressões existentes e um contrato novo):

| Script | Resultado final |
| --- | --- |
| `tests/cold/test_adapter.gd` | Passou |
| `tests/cold/test_thermal.gd` | Passou; 121 verificações |
| `tests/test_arsenal_input_integration.gd` | Passou |
| `tests/test_compact_hud.gd` | Passou; 49 verificações |
| `tests/test_garage_driver_restore.gd` | Passou |
| `tests/test_garage_rewards.gd` | Passou; 47 verificações |
| `tests/test_garage_vehicle_transfer.gd` | Passou |
| `tests/test_inventory_grid.gd` | Passou; 36 verificações |
| `tests/test_inventory_panel.gd` | Passou; 11 verificações |
| `tests/test_modal_ui_accept_independent.gd` | Passou |
| `tests/test_mouse_wheel_weapon_radio.gd` | Passou |
| `tests/test_settings_menu.gd` | Passou |
| `tests/test_ui_map_contract.gd` | Passou; 4 verificações |

Resultados das execuções:
[1733](../test-suite/suite-2026-09-28_1733.json),
[1734](../test-suite/suite-2026-09-28_1734.json),
[1736](../test-suite/suite-2026-09-28_1736.json),
[1740](../test-suite/suite-2026-09-28_1740.json).

Duas falhas iniciais tiveram causa identificada antes da repetição: o teste de
polícia precisava informar contato real para esperar perseguição em vez de
BUSCA; o simulador do teste de recompensa precisava aceitar o quarto argumento
opcional já recebido pela implementação real. As verificações de comportamento
foram mantidas. Alguns testes headless emitem avisos de recursos do RendererDummy
na saída; aprovação das assertivas não significa ausência desses avisos.

Eventos de controle foram injetados no motor; não houve teste físico em controles
Xbox/PlayStation. Não foram alteradas colisões nem interiores. As proteções da
garagem continuam pertencendo aos sistemas existentes.

## Comparação de performance renderizada

Godot 4.7.2, renderizador Mobile, RTX 4060 Laptop, 1920×1080, VSync desligado,
limite existente de 144 FPS. Cena Main real, seed 28092026, posição/clima/câmera
fixados pelo script, tráfego e NPCs ativos. Aquecimento de 8 s e pelo menos 30 s
por cenário. Amostras brutas e metadados nos JSONs de `before/` e `after/`.

| Cenário | FPS antes → depois | p50 ms antes → depois | p95 ms antes → depois | p99 ms antes → depois |
| --- | ---: | ---: | ---: | ---: |
| HUD | 51,06 → 50,32 | 16,61 → 17,14 | 34,78 → 33,18 | 51,63 → 45,54 |
| Mochila | 18,70 → 41,06 | 31,94 → 18,62 | 148,28 → 37,91 | 184,22 → 117,44 |
| Mapa | 11,66 → 33,42 | 78,06 → 31,09 | 147,73 → 46,41 | 175,01 → 51,59 |

A implementação reduz o custo observado da mochila e do mapa; a HUD tem média
semelhante e percentis menores. O maior frame da HUD depois foi **207,30 ms**
(antes: 90,92 ms), apesar de apenas 5 frames acima de 66,7 ms (antes: 6).
Esse pico não foi ocultado nem atribuído conclusivamente à UI.

**Performance não aprovada para 60 FPS.** Os cenários continuam abaixo da meta,
e processos Godot e edições de outras sessões estavam ativos na máquina. Este
comparativo é diagnóstico e não isola causalidade entre todas as mudanças do
projeto. Aprovação requer medição em estado estável, sem carga concorrente, e
investigação dos custos restantes. Não se usou resultado headless como FPS.

## Estado da compilação e trabalho concorrente

Os testes funcionais e o benchmark acima terminaram antes de novas edições de
outra sessão nos túneis. Durante a captura dos menus, faltavam `_batch_box`,
`_batch_cylinder` e `_flush_batches` em `TruckersVillageSecretPassage.gd`; essas
funções reapareceram às 17:42:43.

Na primeira tentativa de importação final, o bloqueio passou para `SecretTunnel3D.gd`: chamadas a
`_cylinder()` nas linhas 321, 343, 368 e 400 sem definição correspondente,
impedindo a compilação das dependências de `SessionLaunch`. Esses arquivos não
foram editados por este refactoring. O processo terminou com código zero, mas
os erros de script impedem considerar a importação aprovada. Também houve
negação de escrita do sandbox ao log/cache; não foi tratada como falha da UI.

A função reapareceu na edição das 17:45:20. Com essa mudança concreta, foi feita
uma única nova importação, com permissão de escrita para o cache/log: **concluiu
com código zero e sem erros de script ou importação**, conferida às 17:46:55.
Evidência: [final-import.log](final-import.log). O bloqueio transitório está
resolvido no estado verificado. Nenhum trabalho local de outra sessão foi descartado.

## Decisões que preservam a jogabilidade

- As roupas continuam reduzindo a perda térmica conforme o modelo existente;
  não foi criada imunidade ao frio nem simulada estabilização visual falsa.
- Prompts mostram o botão realmente configurado; interação continua em X no
  padrão Xbox. A mochila ganhou vínculo no direcional esquerdo, antes ausente.
- Rádio conserva seus controles e áudio, com indicação temporária da estação.
- As linhas topográficas são tratamento cartográfico visual, sem alegação de
  cotas reais de terreno.
- Não houve alteração de saves pessoais, commit, descarte de arquivos locais
  ou encerramento de processos Godot pertencentes a outras sessões.
