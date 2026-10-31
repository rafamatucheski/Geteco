# Roteiros — as quatro gravações do Arquivo de Vicente (31/10/2026)

Texto para o card "Quatro gravações do Arquivo de Vicente". O estado, os ícones e os rótulos
("Gravação 01" a "04", `ui/SecretFilePanel.gd`) já existem, mas nenhum stream foi ligado:
`SecretFileRuntime._audio_toggled` responde "A gravação está danificada." e desliga o botão.
Este documento traz **só o texto**. Nenhum áudio foi gerado e nenhum código foi alterado.

Fontes lidas: `runtime/SecretFileRuntime.gd`, `runtime/SecretNetworkProgression.gd`,
`docs/secret-headquarters.md`, `docs/story-act2-vicente-20261020.md`,
`docs/voice-cast-direction.md`, `docs/voice-dialogue-review.md`,
`gameplay/urban_v1/TruckersVillageSecretPassage.gd`, `gameplay/urban_v1/SecretTunnelDecor.gd`,
`audio/mission_voices/directed/elevenlabs.json` e `anchors.json`.

## Cânone e restrições

- **Setor lacrado ambíguo.** Maca, soro, frascos, vidro quebrado, arranhões e cadeira tombada
  sugerem experiência ou contaminação; nada confirma origem sobrenatural nem criatura. As falas
  abaixo descrevem só o que alguém poderia ver, ouvir ou medir, e Vicente admite não saber.
- **A pasta chega por Maciota** depois de `cobra_finale`. Vicente gravou antes do reencontro do
  ato 2; ele não sabe se Dante vai ouvir. Nada aqui revela quem armou a operação de oito anos
  atrás (isso é do ato 3) nem antecipa o perdão: Vicente segura a mágoa ("evidência nova não
  produz perdão automático", `voice-dialogue-review.md`).
- **Código do cofre 3194.** A fita 04 é a única pista de áudio com dígito (o 4) e tem texto
  fixado no jogo: *"...a última porta... o quarto número é 4. Depois disso, não volte."* O
  roteiro mantém essa frase literal.
- Só a fita 04 tem ponto de coleta no mundo hoje (`VAULT_DIGITS`, "Ouvir fita rotulada").
  As outras três são citadas pela cenografia (mesa do gravador com uma fita por registro;
  quadro de turnos ligado a `audio_maintenance_shift`), mas ainda não têm onde ser achadas.
  O contexto de cada uma abaixo é **proposta**.

## Voz

Todas as quatro são de **Vicente**, sozinho, gravando num gravador portátil de fita.

| Campo | Valor registrado no projeto |
|---|---|
| `character_id` | `vicente` |
| ElevenLabs `voice_id` | `sNOgqySaECh2Vh5sDQNY` ("Dantas \| Deep, Warm & Slightly Raspy"), 12 tomadas em `audio/mission_voices/directed/elevenlabs.json` |
| Modelo do registro | `eleven_v4` |
| Âncora local | `res://audio/mission_voices/directed/anchors/vicente_e4c949fb4ab9dae5.wav` (Qwen3 VoiceDesign, `anchors.json`) |
| Direção (`voice-cast-direction.md`) | voz masculina média-grave, mais densa e áspera que a de Dante, volume nivelado, respostas atrasadas, finais secos; a mágoa só aparece na última palavra |

Sem vozes novas: o colega de turno e o supervisor citados nas fitas 02 e 03 são lembrados por
Vicente, não falam. Ruído de fita, chiado e ambiente entram na **mixagem** (camada separada),
não no texto da síntese. As indicações entre colchetes do roteiro são para direção e mixagem;
o bloco "texto para síntese" é o que vai ao TTS. Mantive só os rótulos curtos de intenção no
começo, no mesmo formato `[intenção]` dos prompts já registrados.

---

## Gravação 01 — `audio_vicente_field`

- **Quem fala:** Vicente.
- **Onde se acha (proposta):** a primeira fita da mesa do gravador no QG, junto à cama de
  campanha. É a apresentação: Vicente descobrindo o lugar e decidindo usar o gravador como diário.
- **Duração alvo:** ~45 s.
- **Mixagem:** clique de REC no início, chiado de fita leve, goteira e eco úmido do túnel,
  passos em pedra entre as frases. Clique de STOP no fim.

### Roteiro

> [clique do gravador. Respiração. Passos param.]
> Teste. Tá gravando.
> [pausa]
> Se você tá ouvindo isso, o Maciota cumpriu a palavra. Pelo menos alguém cumpriu.
> [voz baixa, sem pressa]
> Achei esse buraco embaixo da Vila. Ninguém mora aqui faz tempo. Tem cama, tem mapa na parede,
> tem fio puxado até um quadro que ainda funciona. Alguém trabalhou aqui. E saiu com pressa.
> [pausa longa. Uma goteira.]
> Eu vou gravar o que eu achar. Papel some. Papel volta "destinatário desconhecido".
> [seco]
> Fita, pelo menos, fala com a minha voz.
> [respira]
> Não vim aqui pra você, Dante. Vim porque cansei de perguntar e ninguém responder.
> [clique]

### Texto para síntese

```
[registrar com cuidado] Teste. Tá gravando. Se você tá ouvindo isso, o Maciota cumpriu a palavra. Pelo menos alguém cumpriu. Achei esse buraco embaixo da Vila. Ninguém mora aqui faz tempo. Tem cama, tem mapa na parede, tem fio puxado até um quadro que ainda funciona. Alguém trabalhou aqui. E saiu com pressa. Eu vou gravar o que eu achar. Papel some. Papel volta "destinatário desconhecido". Fita, pelo menos, fala com a minha voz. Não vim aqui pra você, Dante. Vim porque cansei de perguntar e ninguém responder.
```

---

## Gravação 02 — `audio_maintenance_shift`

- **Quem fala:** Vicente.
- **Onde se acha (proposta):** na galeria longa, presa no quadro de turnos da manutenção (o
  quadro de giz cujos traços param antes da última linha, `SecretTunnelDecor._shift_board`),
  ao lado do vagonete.
- **Duração alvo:** ~50 s.
- **Mixagem:** galeria mais aberta (reverb maior), rangido de trilho, giz riscando quadro uma
  vez, chiado de fita.

### Roteiro

> [clique. Ele está perto do quadro; a voz bate na parede.]
> Galeria comprida. Tem trilho, tem vagonete, tem um quadro de turno na parede.
> [lendo, devagar]
> Três turmas. Quatro tracinhos e um risco por semana. Igual cadeia: a gente conta dia assim.
> [pausa. Meio riso sem graça.]
> Aqui eles contavam também.
> [tom muda, mais atento]
> Só que a última linha não fecha. Dois grupos, e o segundo para no meio. Ninguém riscou a semana.
> Quem fazia a ronda simplesmente parou de vir.
> [pausa]
> Tem um nome a giz no canto, meio apagado. Dá pra ler "turno da noite" e uma assinatura que eu
> não entendo.
> [baixo]
> Turma não larga quadro pela metade. Não sem ordem. Ou sem motivo.
> [clique]

### Texto para síntese

```
[observar e contar] Galeria comprida. Tem trilho, tem vagonete, tem um quadro de turno na parede. Três turmas. Quatro tracinhos e um risco por semana. Igual cadeia: a gente conta dia assim. Aqui eles contavam também. Só que a última linha não fecha. Dois grupos, e o segundo para no meio. Ninguém riscou a semana. Quem fazia a ronda simplesmente parou de vir. Tem um nome a giz no canto, meio apagado. Dá pra ler "turno da noite" e uma assinatura que eu não entendo. Turma não larga quadro pela metade. Não sem ordem. Ou sem motivo.
```

---

## Gravação 03 — `audio_blackout`

- **Quem fala:** Vicente.
- **Onde se acha (proposta):** no quadro de disjuntores com três faróis (`power_*`), perto do
  relatório de energia (`lab_power_report`). Gravada no escuro; liga com a ação de restaurar
  energia (`power_main`).
- **Duração alvo:** ~55 s.
- **Mixagem:** começa quase sem luz no som: zumbido elétrico morto, respiração mais próxima do
  microfone. Na metade, estalo de disjuntor e zumbido de lâmpada subindo. Nenhum som
  não-identificável: o barulho do fim é metal e água, e deve soar como cano ou estrutura.

### Roteiro

> [clique. Escuro. Ele fala baixo, perto demais do microfone.]
> Caiu tudo. Eu tava no QG e apagou de uma vez. Não piscou. Apagou.
> [respira. Mão tateando metal.]
> Tô no quadro. Tem três chaves. A do meio tá derretida na borda, preta. Alguém forçou isso aqui
> com carga demais.
> [pausa]
> O relatório que tá do lado fala de "pico no setor lacrado" e "desligamento manual". Data rasgada.
> Mesmo dia que o quadro de turno para.
> [estalo de disjuntor. Zumbido de lâmpada subindo. Ele solta o ar.]
> Pronto. Voltou.
> [pausa. Ao longe, um baque metálico e água correndo.]
> [mais baixo, segurando]
> Cano. Deve ser cano. Pressão voltando.
> [pausa longa]
> Eu não sei o que eles ligavam lá dentro. Sei que, quando deu errado, quem tava aqui desligou tudo
> e foi embora. E não voltou pra buscar nem a cadeira.
> [clique]

### Texto para síntese

```
[falar baixo no escuro] Caiu tudo. Eu tava no QG e apagou de uma vez. Não piscou. Apagou. Tô no quadro. Tem três chaves. A do meio tá derretida na borda, preta. Alguém forçou isso aqui com carga demais. O relatório que tá do lado fala de "pico no setor lacrado" e "desligamento manual". Data rasgada. Mesmo dia que o quadro de turno para. [aliviado, contido] Pronto. Voltou. [desconfiar sem admitir medo] Cano. Deve ser cano. Pressão voltando. Eu não sei o que eles ligavam lá dentro. Sei que, quando deu errado, quem tava aqui desligou tudo e foi embora. E não voltou pra buscar nem a cadeira.
```

---

## Gravação 04 — `audio_sealed_sector`

- **Quem fala:** Vicente.
- **Onde se acha (canônico):** a "fita rotulada" dentro do setor lacrado
  (`VAULT_DIGITS[3]`, `local = (3.4, 0.04, -4.1)`, ação "Ouvir fita rotulada"). É o quarto
  dígito do cofre (4). Hoje o jogo mostra só o texto curto dela.
- **Duração alvo:** ~50 s.
- **Mixagem:** a fita mais danificada: chiado forte, dois cortes de fita (dropouts de ~0,3 s)
  **exatamente** onde estão as reticências da frase canônica, para a legenda atual continuar
  verdadeira. Luz de emergência zumbindo, vidro sob a bota.

### Roteiro

> [clique. Chiado alto. Vidro estala sob a bota.]
> Entrei no setor. Tem maca, tem suporte de soro, frasco na prateleira com rótulo arrancado.
> O vidro tá quebrado de dentro pra fora. Ou de fora pra dentro. Daqui não dá pra dizer.
> [pausa]
> Tem marca de unha na parede. Pode ser gente tentando sair. Pode ser gente tentando entrar.
> Eu não vou inventar o resto.
> [respira; o tom fica mais firme, de instrução]
> No fundo tem uma porta redonda, de cofre, com teclado. Os números eu deixei espalhados no QG,
> que nem a mãe guardava dinheiro: um em cada gaveta.
> [chiado sobe — corte] ...a última porta... [corte] o quarto número é 4.
> [pausa. A voz desce, quase pessoal.]
> Depois disso, não volte.
> [mais baixo ainda, o mais perto que ele chega de falar com o irmão]
> Não é pedido, Dante. É o que eu faria se ainda confiasse em alguém.
> [clique]

### Texto para síntese

```
[descrever sem concluir] Entrei no setor. Tem maca, tem suporte de soro, frasco na prateleira com rótulo arrancado. O vidro tá quebrado de dentro pra fora. Ou de fora pra dentro. Daqui não dá pra dizer. Tem marca de unha na parede. Pode ser gente tentando sair. Pode ser gente tentando entrar. Eu não vou inventar o resto. [instruir com firmeza] No fundo tem uma porta redonda, de cofre, com teclado. Os números eu deixei espalhados no QG, que nem a mãe guardava dinheiro: um em cada gaveta. A última porta. O quarto número é 4. Depois disso, não volte. [mágoa no fim] Não é pedido, Dante. É o que eu faria se ainda confiasse em alguém.
```

Nota: na síntese a frase canônica vai com pontos ("A última porta. O quarto número é 4.") para
o TTS não inventar hesitação; as reticências da legenda vêm dos cortes de fita na mixagem.

---

## Como ligar no `SecretFileRuntime` (sem alterar código agora)

**Chave:** o próprio id de `SecretNetworkProgression.AUDIO_IDS` (o mesmo que
`SecretFilePanel.audio_toggled` emite): `audio_vicente_field`, `audio_maintenance_shift`,
`audio_blackout`, `audio_sealed_sector`.

**Caminho esperado (proposta):**

```
res://audio/secret_file/pt_BR/audio_vicente_field.ogg
res://audio/secret_file/pt_BR/audio_maintenance_shift.ogg
res://audio/secret_file/pt_BR/audio_blackout.ogg
res://audio/secret_file/pt_BR/audio_sealed_sector.ogg
```

Ogg Vorbis mono, mixado com fita/ambiente já embutidos, na política de mix do diretório
dirigido (`directed_linear_lufs_v1`: −20 LUFS, pico real ≤ −1,5 dB). Uma versão `en/` pode
seguir o mesmo nome em `res://audio/secret_file/en/`. Se preferirem manter tudo no pipeline
dirigido, a alternativa é registrar as quatro como `source_key` no manifest de
`audio/mission_voices/directed/` com `character_id: vicente` e resolver o caminho por lá.

**Ponto de ligação:** `SecretFileRuntime._audio_toggled(id, playing)`. Hoje ele força
`ui.set_audio_playing(id, false)` e mostra "A gravação está danificada.". Quando houver arquivo:

1. Um único `AudioStreamPlayer` filho do runtime (bus de voz/UI), criado em `configure()`.
2. `playing == true` e o arquivo existe → tocar; `playing == false` → parar.
3. No `finished` do player → `ui.set_audio_playing(id, false)` para o botão voltar.
4. Arquivo ausente → manter o comportamento atual (mensagem de fita danificada), para a UI
   continuar honesta.
5. Fechar o painel (`dismiss`/`close`) para a fita.
6. Regra de desempenho do projeto: não fazer `load()` síncrono no clique. Carregar com
   `ResourceLoader.load_threaded_request` ao abrir a pasta (só as gravações já descobertas),
   ou pré-carregar sob a cortina.
7. Opcional: legenda com o roteiro durante a reprodução; a fita 04 já tem a frase canônica em
   `TruckersVillageSecretPassage.VAULT_DIGITS`.

Faltam para as fitas 01–03 pontos de coleta no mundo; isso é trabalho de gameplay à parte.
