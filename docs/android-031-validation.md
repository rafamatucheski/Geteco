# APK Android 0.3.1 — 28/09/2026

Fonte do APK: commit `12eb559`, checkout isolado em `builds/android-031-source`.
Alterações simultâneas de outras sessões no checkout principal não foram incorporadas pela metade.

## Entrega

- `builds/android/harbor-0.3.1-debug.apk`, 141.371.610 bytes, ARM64.
- SHA-256: `c448739bd8762cd5dae4cc7960b65cbbf14c573e4c636c526151cfbb97c337d2`.
- Pacote `com.geteco.harbor`, código 301, mínimo API 24, alvo API 36.
- Assinaturas v2/v3 e alinhamento de 16 KB verificados. Mesmo certificado da 0.3.0; instalar como atualização, preservando dados.
- Godot 4.7.2 oficial, templates correspondentes, JDK 17, Android build-tools 36.0.0.
- Exportação concluída. Aviso herdado: projeto sem ícone próprio; o aapt2 também avisa da referência de ícone temático do template. Instalação física ainda não verificada.

## Comportamento

- Analógico esquerdo: andar no curso interno, correr na borda, com histerese; mira e ataque continuam simultâneos. Soltar/cancelar limpa a corrida.
- Opções secundárias não soltam os dedos de direção/aceleração. Rádio tem anterior, próxima e liga/desliga direto, retomando a estação anterior.
- Novo jogo começa só com dois bolsos. Abrir o porta-malas da Monaliza conquistada entrega uma mochila, uma vez por save; acesso remoto não permite recolhê-la. Removidas as bagagens gratuitas das lojas/montanha. Bagagens e conteúdos de saves anteriores permanecem preservados.
- Criação de pedestre, carro e dois equipamentos de tráfego distribuída entre quatro quadros, mantendo alvos de população e os equipamentos. Cada criação individual ainda pode custar um quadro longo.
- Contador opcional mostra o pico real de frame time a cada segundo. Android mantém registro limitado de travadas e o grava somente ao sair da jogabilidade para menu/pausa/segundo plano; `--no-save` não grava esse arquivo.

## Validação funcional

Oito testes passaram no checkout exato do APK: `test_android_controls`, `test_full_save`, `test_inventory_field`, `test_inventory_migration_world`, `test_inventory_panel`, `test_mouse_wheel_weapon_radio`, `test_settings_menu`, `test_traffic_headlights`.

Relatório local: `builds/android-031-source/evidence/test-suite/suite-2026-09-28_2204.json`.
O teste de campo cobre a persistência completa, coleta única, acesso físico, soltar/recuperar bagagem, transferência e proteção de armas/personagens na garagem.

## Performance: pendente no Galaxy Z Fold

O usuário confirmou travadas no Galaxy Z Fold. Nenhum aparelho foi detectado pelo ADB nesta entrega. Os dados abaixo são diagnóstico **desktop**, não comprovação da causa nem da correção no telefone.

Cena Main renderizada, jogador parado em `(132, 0.15, 72)`, população solicitada 8, clima diurno fixo, câmera 38, controles de toque; 8 s de aquecimento + 30 s medidos. RTX 4060 Laptop, Mobile/Vulkan, 1920×1080, VSync desligado, limite 144. Havia editor e outra sessão Godot ativos; a variação é material.

| Amostra | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Antes | 58,27 | 15,338 | 29,110 | 121,475 | 160,888 | 57 | 28 |
| Antes, instrumentada | 65,93 | 15,857 | 18,781 | 27,602 | 34,256 | 2 | 0 |
| Depois, fonte isolada | 66,48 | 15,488 | 18,400 | 27,755 | 195,676 | 5 | 1 |

O p99 não mudou materialmente contra a amostra instrumentada; o orçamento de 16,67 ms não foi atingido em todos os quadros e continuou existindo uma pausa longa. **Performance não aprovada.** A distribuição de trabalho não demonstrou eliminar o problema. No quadro longo, os monitores de CPU/física disponíveis indicavam 11,988/8,764 ms; isso não identifica o restante do intervalo como GPU. Houve também criação de moto com 17,6 ms, que permanece indivisível.

Dados brutos antes: `evidence/ui-refactor-20260928/stutter-before/closed.json` e `stutter-trace/{closed,trace}.json`. Depois e captura revisada: `builds/android-031-source/evidence/ui-refactor-20260928/stutter-after/`.

Próximo diagnóstico necessário: reproduzir no Fold e ler `user://frame-stalls.json` após pausar, correlacionando com perfil no dispositivo. Renderização desktop, teste headless e assinatura do APK não substituem essa medição. Permanecem avisos de liberação de RIDs/ObjectDB no encerramento da cena, já presentes antes.
