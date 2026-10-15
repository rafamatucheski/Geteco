# Sons gerados no Adobe Firefly (15/10/2026)

Gerados com o recurso "Gerar efeitos sonoros" do Firefly (conta do desenvolvedor),
um prompt por som, 4 variações por geração, 10 créditos por geração. Os originais (48 kHz
estéreo) ficam em `evidence/firefly_originais_20261015/` (fora do Git); o que está em
`audio/` foi tratado por `tools/audio/process_firefly_sfx.py` (mono, corte de silêncio e
de ruído, fade, volume casado com os sons que o jogo já tinha, loops sem emenda).
O tratamento é repetível: rodar o script de novo parte sempre dos originais.

## Onde cada som entra

Tudo passa por `audio/FireflyBank.gd` (carrega sob demanda, escolhe a tomada sem repetir,
faz o loop, toca posicional). Se um arquivo não estiver importado o jogo segue com o som
que já existia.

| Pasta / nome | Prompt | Usado em |
|---|---|---|
| `weapons_fire/pistol_*`, `shotgun_*` | single pistol gunshot outdoors, short echo / shotgun blast outdoors | `gameplay/CombatAudio.gd`: entram no sorteio dos 5 takes do V1 (pistola, escopeta) |
| `weapons_fire/rifle_shot_*` | assault rifle burst of three shots outdoors | fatiados da rajada em tiros únicos; sorteio do ak47 e m4a1 |
| `weapons_fire/distant_shot_0` | distant gunshot echo across a valley | `audio/WorldAudio.gd`: estalo de tiro de NPC/polícia entre 37,5 e 160 m |
| `vehicle_fx/door_open_*`, `door_close_*` | car door opening / closing | `scripts/Vehicle.gd` `animate_driver_door`: no instante da folha |
| `vehicle_fx/ignition_*`, `engine_off_*` | car engine starting / switching off | `scripts/Driving.gd`: ao sentar e ao começar a descer |
| `vehicle_fx/handbrake_*` | car handbrake lever ratchet pull | `scripts/Vehicle.gd`: puxada do freio de mão pelo botão |
| `vehicle_fx/car_horn_*`, `service_vehicles/horn_*` | passenger car horn / truck air horn | `gameplay/VehicleEquipmentAudio.gd`: buzina por família (moto segue sintética) |
| `service_vehicles/siren_loop.wav` | fire truck siren wailing | `VehicleEquipmentAudio.siren_stream()` |
| `service_vehicles/reverse_beep_loop.wav` | truck reverse beeping alarm | `WorldAudio`: caminhão, ônibus e bombeiro andando de ré |
| `vehicle_fx/wastegate_*`, `diesel_turbo_*` | turbo wastegate / heavy diesel turbo | entram nas listas cíclicas de alívio e de troca de marcha do `WorldAudio` |
| `vehicle_fx/turbo_spool_*`, `turbo_spooldown_*`, `turbo_flutter_*`, `backfire_*` | turbo spooling / spooling down / compressor surge flutter / exhaust backfire | `WorldAudio._update_firefly_foley`: ao pisar fundo, aliviar e estourar o escapamento |
| `vehicle_fx/supercharger_loop.wav` | supercharger whine on a V8 muscle car | `WorldAudio`: camada que sobe com o giro, só na família muscle |
| `desert_ambience/wind_*` | dry desert wind, steady ambience | `DesertAmbience`: rajada longa a qualquer hora |
| `wildlife/coyote_*`, `crickets_*` | coyote howling at night / desert night crickets | `DesertAmbience`: só à noite |
| `mining/drip_*`, `machinery_*` | water dripping in a cave / creaking metal and machinery in a mine tunnel | `MiningAmbience`: caverna e britador |

## Menu e carregamento (15/10/2026)

Música pelo gerador de música do Firefly (20 créditos por faixa, 60 s, 48 kHz estéreo).
Tratamento em `tools/audio/process_menu_audio.py`: o final se funde com o começo (loop sem
emenda), volume casado com a música do menu que já existia (rms ~0,05) e saída em Ogg Vorbis
(~0,7 MB por faixa em vez de 11 MB de WAV). Originais em `evidence/firefly_originais_20261015/menu`.

| Arquivo | Prompt (tags) | Usado em |
|---|---|---|
| `audio/menu/menu_music_0.ogg` | calm nostalgic and dreamy, warm / synthwave, ambient / vlog; tempo lento, energia baixa | `ui/MenuAudio.get_music_stream()`: uma das duas faixas por abertura do jogo |
| `audio/menu/menu_music_1.ogg` | mesmas, trocando ambient por lofi | idem |
| `audio/menu/loading_music.ogg` | warm, playful / synthwave / vlog | `ui/LoadingMusic.gd`, ligado em `runtime/StartupCurtain.gd` (entra com a cobertura, sai com o fade) |
| `audio/menu/hover_*`, `click_*`, `back_*`, `start_*` | soft synth tick / click / descending note / warm chord swell | `ui/MenuAudio.gd`; botão cujo texto tem voltar/cancelar/fechar/sair toca `back` |

O tema original da V1 (`harbor_night_menu.wav`) e os sons sintéticos continuam como reserva
se os arquivos novos não estiverem importados.

## Não ligado (e por quê)

- `vehicle_fx/turn_signal_*`: o jogo não tem pisca-pisca; faltaria a mecânica e as luzes.
- Recarga de pistola: a geração saiu sem eventos claros (a pancada principal ficava no
  fim do clipe), então não entrou. O tratamento descarta a recarga.
- Tomadas com volume original abaixo de 0,12 (ruído de fundo) foram descartadas:
  `supercharger_1..3`, `distant_shot_1..3`, `engine_off_2..3`, `ignition_3`, `backfire_3`.
- Reverso e sirene só no veículo do jogador / equipamento; os veículos de serviço da IA
  (`ServiceVehicleAudio`) continuam só com motor.

## Verificação

`tests/test_firefly_sounds.gd` (existem, importados, sorteio de tiros, loops, camada posicional)
e `tests/test_firefly_engine_layers.gd` (turbo, compressor, ré no mixer real). A qualidade
do som é de ouvido; nenhum teste mede isso.
