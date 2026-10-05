# Engasgos de 105–121 ms antes da física (SDL/DirectInput) — 05/10/2026

Escopo: a família de quadros de cauda da captura WPR rec2 (f17284/85, 17299, 17384/85,
17399; READY +120,28..122,00 s) em que 80–94 ms ficaram entre `post_draw` e o primeiro
callback físico, com stacks em `PeekMessage` e `dinput8 → RegOpenKeyExW/NtOpenKeyEx`.
Contexto anterior: [auditoria rec2](../../evidence/stalls-1709-20261005/wpr-rec2-causal-audit.md),
[síntese nativa rec2](../../evidence/stalls-1709-20261005/wpr-rec2-native-summary.md),
[handoff](handoff-claude-20261005.md).

**Resultado curto:** nenhuma mudança no jogo. A família é rara (apareceu em 1 de 47
capturas com detalhe feitas antes de desligar o Bluetooth, ~1,7 h de gameplay+cauda) e não
reproduziu em 8 capturas com Bluetooth desligado (2 minhas + 6 do outro agente) — o que, dada
essa raridade, **não discrimina** a hipótese. O mecanismo
no SDL vendorizado está identificado no código-fonte. A única alavanca sem rebuild do motor
(`SDL_JOYSTICK_DIRECTINPUT=0`) desabilita controles só-DirectInput e não pôde ser verificada
por módulo carregado; por isso **não foi aplicada**.

## 1. Quando e quanto a família aparece

Varredura offline de todas as capturas `evidence/intermittent-stalls-20261004/*/<label>.json`
(script `evidence/stalls-1709-20261005/sdl-input/scan_gap.py` e `scan_big.py`). Métrica:
intervalo `draw_post_usec → physics_ticks[0].start_usec` dentro do mesmo intervalo retido.
Os detalhes só são retidos em janelas ao redor de quadros ≥ 25 ms; como um gap ≥ 25 ms torna
o próprio quadro ≥ 25 ms, a cobertura é completa para gaps desse tamanho (salvo perda de
ring, que foi zero nas capturas auditadas), mas **não** para gaps pequenos.

| Conjunto | Capturas | Gap ≥ 30 ms fora do loading | Gap ≥ 8 ms fora do loading |
|---|---:|---|---|
| 04/10 (baseline, blood, coach, cpu-box, shader-cache, startup-box…) | 40 com detalhe + 3 observer-off sem detalhe | 1: `residual-stage2-01` f6578, retorno, +38,77 s, quadro 72,7 ms, gap 45,9 ms — **no exato quadro de uma troca de foco** | +2 quadros de 8,7 e 11,2 ms (2 capturas) |
| 05/10 D1/D2/wide1/memory-a1/a2 | 5 | 0 | 2 (10,0/11,1 ms em D1) |
| WPR rec2 | 1 | **6** (80,2–94,0 ms, todos na cauda) | 9, de +119,77 a +122,69 s |
| WPR rec3 | 1 | 0 (máx 0,946 ms) | 0 |

Total varrido antes do Bluetooth desligado: 50 capturas (47 com detalhe), ~6.000 s
não-loading. Nos quadros ≥ 60 ms o segmento dominante é física, draw ou processamento —
`post_draw → primeiro físico` só domina nos seis da rec2 e no f6578 da `residual-stage2-01`.
O estado do Bluetooth não foi registrado nessas capturas; presume-se ligado (o usuário só o
desligou hoje).

Observações:

- Há também um gap recorrente de 40–161 ms nesse mesmo trecho **durante o loading**, perto
  de READY −0,7 s (f≈460), em ~19 das capturas. Não foi investigado aqui; sem stack não se
  sabe se é SDL, mensagem de janela ou trabalho de input do jogo. Não somar à família.
- Troca de foco da janela também abre esse gap (mensagens de ativação no message pump):
  todos os gaps de 8,9–45,9 ms encontrados em capturas com perda/retomada de foco caem
  **exatamente** no quadro da transição. Os da rec2 não têm nenhuma transição de foco
  (a captura inteira ficou focada), então não são isso.
- A família não depende do WPR em si (a rec3 também tinha WPR e deu zero), e só a rec2 a
  mostrou. Ela coincidiu com a cauda após uma prisão/respawn, mas isso não demonstra relação.
- Os StallLogs de jogo normal (`evidence/stall-logs/`, 3.242 registros de 01–03/10) não têm
  marcadores de draw/física; mostram 44 quadros ≥ 60 ms com resíduo não explicado pelos
  monitores (de 60 ms a 1,8 s). Esse resíduo inclui o tempo de `process_events` do SO, mas
  também outras coisas; **não** dá para atribuí-los ao SDL com esses dados.

A sequência temporal da rec2 é compatível com o desenho do SDL descrito abaixo (enumeração
imediata + temporizadores de 300 ms e 2 s): +119,77 → +120,07 (≈ +0,30 s) e +120,666 →
+122,690 (≈ +2,02 s). É compatibilidade, não prova; o gatilho (qual dispositivo, se algum)
não foi observado.

## 2. Medição com Bluetooth desligado

Estado verificado antes de medir (somente leitura): rádio Bluetooth `Off` via
`Windows.Devices.Radios`; adaptador Intel presente, filhos (inclusive "DualSense Wireless
Controller") não presentes. 35 dispositivos HIDClass presentes.

Mesmo runner e mesmas condições nominais das rec2/rec3, sem WPR:
`tests/measure/RunIntermittentStalls.ps1 -Observer on -ExternalTelemetry
-Project evidence/intermittent-stalls-20261004/stall1709-project` (projeto congelado, mesmo
de rec2/rec3; cache ShaderRD frio; física 60 Hz / teto 3; C# compilado, 0 erros). Lock
`godot-run.lock` adquirido para cada execução, coordenando com o outro agente.

| Captura | Validade | Quadros GP | p50 / p95 / p99 / máx ms | >33,3 | >66,7 | Cauda máx ms | Gap post_draw→físico máx ms |
|---|---|---:|---|---:|---:|---:|---:|
| rec2 (BT ligado, WPR) | ok | 16.657 | 5,603 / 12,988 / 14,627 / 83,432 | 9 | 3 | 121,6 | **93,984** |
| rec3 (BT ligado, WPR) | ok | 15.582 | 6,199 / 14,028 / 15,738 / 94,667 | 13 | 4 | 16,3 | 0,946 |
| sdl-bt-off-01 | **inválida (lost_focus)** | 11.621 | 10,006 / 18,011 / 30,924 / 185,094 | 69 | 5 | 20,3 | 4,392 |
| sdl-bt-off-02 | ok, focada | 16.080 | 5,937 / 13,205 / 14,686 / 472,381 | 9 | 5 | 14,1 | 1,446 |

Capturas do outro agente feitas hoje com o Bluetooth já desligado (snapshot
`first-draw-snapshot`, objetivo diferente — draws de 55–60 ms; contam apenas como amostras
adicionais da métrica de gap): `first-draw-diag-01`, `-diag-02`, `-a1`, `-a2`, `-b1`, `-b2`.
Zero gaps ≥ 8 ms fora de transições de foco; os cinco gaps de 8,9–30,4 ms (a1/a2/b1, que
perderam foco no meio) coincidem cada um com o quadro de uma troca de foco. Seus máximos de
1,5–1,8 s não foram analisados aqui (escopo do outro agente).

- `sdl-bt-off-01` nunca recebeu foco (o Windows negou trazer a janela à frente); os tempos
  de quadro não são comparáveis e ela vale apenas como mais uma amostra negativa da métrica
  de gap, sob condição diferente.
- `sdl-bt-off-02`: zero gaps ≥ 8 ms; C# ativo (router nativo `true` no fim e em 4.601
  contextos). O máximo de 472,381 ms é **outra família**: f2124, +9,995 s, dentro do primeiro
  callback físico, com `dispatch.service.plan` 462,951 ms (primeira resposta de despacho,
  instante em que `router_native` vira `true`). Nenhuma outra captura retida tem esse span
  ≥ 1 ms. Fica registrado como pendência separada, não relacionada a SDL.

**Conclusão honesta da medição:** a família tem taxa-base de ~1 em 47 capturas com Bluetooth
(presumidamente) ligado. Mesmo que o Bluetooth não tivesse efeito algum, a chance de 8
capturas não a mostrarem seria de ~84% (≈ 96% para as duas minhas no projeto congelado). A ausência nas duas rodadas é **inconclusiva**; não confirma
nem refuta a hipótese do DualSense/Bluetooth. Discriminar exigiria um gatilho controlado
(ex.: conectar/desconectar um dispositivo HID durante a captura, com WPR), o que não foi feito.

## 3. Mecanismo no motor (Godot 4.7.2 `ed1daf0bf`, SDL3 vendorizado)

Fontes lidas no commit exato:

- `platform/windows/display_server_windows.cpp:4424` — `process_events()` chama
  `joypad_sdl->process_events()` antes do message pump, sempre na thread principal e
  independentemente de foco. Esse é o trecho `post_draw → primeiro físico`.
- `drivers/sdl/joypad_sdl.cpp:63` — define só `SDL_HINT_JOYSTICK_THREAD=1` e
  `SDL_HINT_NO_SIGNAL_HANDLERS=1` com prioridade normal; não há project setting de SDL/joypad.
  Os drivers XInput, DirectInput, RawInput, HIDAPI (PS3/4/5, Switch, Xbox, Steam…) e
  Windows.Gaming.Input são compilados (`drivers/sdl/SCsub`).
- `thirdparty/sdl/core/windows/SDL_hid.c:179` — `CM_Register_Notification` com filtro
  `GUID_DEVINTERFACE_HID`: **qualquer** chegada/remoção de interface HID (não só controles)
  atualiza `s_LastDeviceNotification`.
- `thirdparty/sdl/joystick/windows/SDL_windowsjoystick.c:96` — a thread de joystick só
  *sinaliza*: em `WM_DEVICECHANGE` arma temporizadores de 300 ms e 2 s que forçam nova
  varredura. `WINDOWS_JoystickDetect()` (linha 389), chamado a cada `SDL_PollEvent` na thread
  principal, executa `SDL_DINPUT_JoystickDetect` → `IDirectInput8::EnumDevices(GAMECTRL,
  ATTACHEDONLY)` sempre que houve notificação. O próprio SDL comenta que essa enumeração pode
  demorar muito "even with no controllers". Ou seja, `SDL_HINT_JOYSTICK_THREAD=1` não move a
  enumeração para fora da thread principal — só a detecção do evento.
- `thirdparty/sdl/SDL_hints.c:105/258` — variável de ambiente tem precedência sobre hint de
  prioridade normal; é lida do ambiente do processo, então só funciona se definida **antes**
  de iniciar o Godot (launcher), não por script do jogo.

Isso explica a localização e o padrão (rajadas com repetição em ~0,3 s/2 s), e é consistente
com notificações HID do Bluetooth, mas também com qualquer outra mudança HID (USB, receptor,
dispositivos virtuais).

## 4. Alavancas sem rebuild e por que nada foi aplicado

| Opção | Efeito | Custo para controles |
|---|---|---|
| `SDL_JOYSTICK_DIRECTINPUT=0` no `Jogar.cmd` | `SDL_DINPUT_JoystickInit` deixa `dinput=NULL`; `EnumDevices` deixa de rodar | XInput (Xbox) e HIDAPI (DualSense/DualShock/Switch/Xbox HID) continuam; **controles genéricos só-DirectInput** (gamepads USB sem driver HIDAPI, volantes, manches) deixam de funcionar. Force feedback via DirectInput também. |
| `SDL_JOYSTICK_RAWINPUT=1` | adiciona driver RawInput | não remove a enumeração DirectInput; não ajuda |
| `SDL_JOYSTICK_THREAD` | já é `1` | nenhum |
| Desligar Bluetooth / desparear o DualSense | elimina uma fonte possível de notificações | decisão do usuário, não do jogo; outras fontes HID continuam |

Tentativa de verificação do mecanismo do env: um projeto mínimo (sonda
`evidence/stalls-1709-20261005/sdl-input/sdl_probe.gd`) foi aberto 2× com e 2× sem
`SDL_JOYSTICK_DIRECTINPUT=0`. Em todos os quatro, `dinput8.dll` estava carregado (também
`xinput1_4`, `hid`, `setupapi`, `cfgmgr32`), e `Input.get_connected_joypads()` = `[]`.
Presença de módulo, portanto, **não** prova se o hint foi aceito; e sem disparar uma mudança
HID sob perfil não há como mostrar que a enumeração some. Como a mudança também desligaria
uma classe de controles, ela **não foi aplicada** — conforme o critério da tarefa.

Se o usuário quiser aceitar o trade-off, o experimento discriminante seria: braço A/B por
variável de ambiente no lançamento (sem trocar arquivos), mesmo runner, WPR com
CSwitch/SampledProfile, e um gatilho HID controlado durante a cauda (ex.: plugar/desplugar um
dispositivo USB HID), verificando ausência de `dinput8!…EnumDevices` na thread principal no
braço B e controles XInput/HIDAPI funcionando.

## O que foi e o que não foi medido

- Medido: varredura offline de 56 capturas pré-existentes/concorrentes; duas capturas novas com Bluetooth desligado
  (uma inválida por foco); leitura do código SDL/Godot no commit exato; sonda de módulos.
- Não medido: reprodução da família sob gatilho controlado; WPR com Bluetooth desligado;
  efeito real do env `SDL_JOYSTICK_DIRECTINPUT=0` no custo; jogo normal via `Jogar.cmd`
  com marcadores; o gap de loading de ~40–160 ms; a causa do `dispatch.service.plan` de
  463 ms; a pausa histórica de 1,7 s (localização diferente: depois do último físico).
- Verificação mínima do CLAUDE.md não foi executada: este trabalho não alterou código nem
  estrutura, apenas adiciona este relatório.

Evidência local (fora do Git): `evidence/intermittent-stalls-20261004/sdl-bt-off-01/`,
`sdl-bt-off-02/`, `evidence/stalls-1709-20261005/sdl-input/` (scripts e `summary.txt`).
