# APK Android — 28/09/2026

## Artefato

- Arquivo local: `builds/android/harbor-0.3.0-debug.apk`.
- Tamanho: 141.363.247 bytes (134,81 MiB).
- SHA-256: `1d9fefae6788e47f0ba83d61eeebf70e9e2d1ca1ca7cff0c37c53b84ed3124ad`.
- Pacote: `com.geteco.harbor`; versão 0.3.0 / código 300; ARM64; target SDK 36.
- Godot 4.7.2 stable, templates oficiais baixados de
  `godotengine/godot-builds/releases/download/4.7.2-stable/` e verificados contra
  `SHA512-SUMS.txt` antes da instalação. Java 17 e build-tools 36.0.0.
- `apksigner verify --verbose`: aprovado, assinaturas v2/v3.
- `zipalign -c -P 16 -v 4`: aprovado (alinhamento de 16 KB).
- Conteúdo ZIP: biblioteca `arm64-v8a`, controles compilados e configuração;
  sem diretórios de evidências, testes, documentação, ferramentas ou addons.

APK de teste com chave de depuração local. Não publicado em loja nem instalado
no aparelho: `adb devices` não lista dispositivos e não há AVD configurado.

## Implementação

- Controles multitoque separados por dedo: movimento, mira, ataque e direção.
- Pedais, freio de mão, interação, veículo, pausa, mapa, inventário e comandos
  secundários, com ações existentes e sem inventário paralelo.
- Gazua, cofre e viaturas trancadas recebem controles próprios.
- Desembarque de passageiros e pilotagem do motocross continuam acessíveis
  mesmo enquanto o corpo do pedestre está bloqueado por essas atividades.
- Mouse emulado desativado durante gameplay para impedir tiros ao tocar no
  analógico; reativado nos menus. Liberação de ações ao mudar contexto/tamanho.
- No Android, perda de foco libera controles e pausa gameplay ativo; o sistema
  controla o tamanho da superfície, sem forçar resolução de janela desktop.
- HUD reposicionada para liberar os cantos dos analógicos. Áreas seguras e
  layout proporcional; orientação paisagem e expansão do canvas no Android.
- Importação ETC2/ASTC habilitada para as texturas Android.

## Testes funcionais

13 scripts distintos aprovados nas rodadas dirigidas:

`test_combat_flow`, `test_full_save`, `test_garage_driver_restore`,
`test_garage_rewards`, `test_garage_vehicle_transfer`, `test_inventory_grid`,
`test_police_crime_contract`, `test_android_controls`, `test_compact_hud`,
`test_inventory_panel`, `test_ui_map_contract`, `test_container_lockpick`,
`test_motocross_session`.

- `test_android_controls`: 30 verificações aprovadas, incluindo dedos
  simultâneos, menus, pedais em veículo real, guarda de armas na garagem,
  layout largo/quase quadrado, gazua, tentativa única no cofre e liberação de
  comandos. Uma revisão anterior passou em 21 verificações renderizadas.
- `test_container_lockpick`: oito verificações do contrato do minijogo.
- `test_motocross_session`: sessão funcional aprovada; 122,9 segundos.
  O custo adicional de leitura do toque no motocross não foi medido separadamente.
- Relatórios locais: `evidence/test-suite/suite-2026-09-28_2053.json`,
  `suite-2026-09-28_2101.json`, `suite-2026-09-28_2109.json` e a rodada final
  de controles/motocross no mesmo diretório.
- As falhas antigas de combate eram incompatibilidades de fixture: o contrato
  policial exige uma testemunha viva completar a chamada de 2,5 s; o cheat não
  concede armas persistentes. O teste agora aguarda a chamada e adquire armas
  reais antes de restaurar o snapshot, sem enfraquecer dano, crime ou garagem.
- A execução inicial do novo teste usava coordenadas de janela como se fossem
  de viewport; foi corrigida com `Viewport.push_input(..., true)`. A fixture
  renderizada também foi afastada do gatilho automático da garagem.
- Persistem avisos de liberação de RIDs/ObjectDB ao encerrar a cena, também
  observados no baseline. Não houve erros de script nas últimas execuções.
- `git diff --check` passou nas alterações desta tarefa.

## Performance e limites

Meta provisória: 60 FPS / 16,67 ms; aumento superior a 5% em p95/p99 exige
confirmação. Cenário: Main real, Harbor, população 8, seed fixa, câmera 38,
dia sem chuva, RTX 4060 Laptop, renderer Mobile. Foram preservadas configurações
de janela, VSync e limite carregadas no desktop; os JSON registram esses valores.
Cada janela tem oito segundos de aquecimento e pelo menos 30 segundos de amostra.

Não há medição no Fold7. Dobrar/desdobrar, suspensão/retomada no Android, instalação,
save no aparelho, autonomia e aquecimento permanecem sem comprovação física.
O APK não deve ser descrito como uma release estável certificada para o Fold7.

As imagens em `evidence/ui-refactor-20260928/android-final/` mostram a HUD,
mochila e mapa. São capturas desktop e não comprovam FPS Android.

### Resultado das medições

Resolução 1920×1080, VSync desativado e limite de 144 FPS, conforme configuração
desktop efetivamente carregada. Não são os padrões de um Android recém-instalado.

| Rodada / cenário | FPS médio | p95 ms | p99 ms | Máximo ms |
| --- | ---: | ---: | ---: | ---: |
| Antes, rua | 66,69 | 17,832 | 24,491 | 43,678 |
| Final, rua | 68,43 | 20,476 | 65,686 | 170,830 |
| Antes, mochila | 63,16 | 18,375 | 26,321 | 33,860 |
| Final, mochila | 67,50 | 17,642 | 22,362 | 35,392 |
| Antes, mapa | 58,52 | 25,900 | 27,910 | 31,676 |
| Final, mapa | 57,77 | 26,194 | 29,950 | 106,540 |
| Confirmação sem controles, rua | 75,17 | 16,869 | 22,118 | 39,498 |
| Confirmação com controles, rua | 68,24 | 18,709 | 27,925 | 44,753 |

O sinal de regressão nos percentis motivou diagnóstico com uma única variável
na mesma sessão: desenhar ou ocultar a sobreposição, mantendo a HUD móvel e o
restante da simulação. Sequência finita, oito segundos de aquecimento e 30 s por
janela:

| Sobreposição | FPS médio | p95 ms | p99 ms | Máximo ms | Frames >66,7 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Oculta | 62,19 | 26,027 | 64,460 | 293,491 | 18 |
| Visível | 58,69 | 25,410 | 28,671 | 43,857 | 0 |
| Oculta novamente | 51,54 | 28,067 | 29,513 | 35,194 | 0 |

A variação também ocorre sem desenhar os controles; a origem dos picos não foi
isolada. Há uma instância Godot preexistente que não foi encerrada. O orçamento
de 16,67 ms não foi atendido de forma consistente: **performance não aprovada**.
Não se atribui a variação exclusivamente à interface nem se usa o diagnóstico
para certificar a estabilidade da cena. Amostras brutas, warm-up, quantidade de
frames e percentis completos em `evidence/ui-refactor-20260928/android-*/`.
A rodada intermediária `android-after` teve atividades de validação concorrentes
e não foi usada como comparação conclusiva.
