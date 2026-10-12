# Produção de dublagem dirigida — estado verificável

## Produção integral autorizada em 12 de outubro

O catálogo final desta etapa contém **565 falas, 95 identidades e 1.130 gravações PT-BR/EN planejadas**. As contagens de 504/1.008 abaixo documentam a etapa anterior. A produção integral usa `tools/build_voice_bank.py`; `progress.json`, `anchors.json` e `cloned-production.json` registram somente o que efetivamente terminou. Um plano completo não significa áudio completo.

Foi baixado o modelo oficial Base 0.6B, revisão `5d83992436eae1d760afd27aff78a71d676296fc`, e instalado `bitsandbytes==0.50.2` no ambiente existente, sem atualizar PyTorch. O Base 1.7B também está em cache para diagnóstico/correções, revisão `fd4b254389122332181a7c3db7f27e918eec64e3`.

Cada ator recebe uma referência fictícia autorada de 80–150 caracteres, com intenção e linguagem próprias. O VoiceDesign 1.7B usa NF4 somente nas grandes projeções; codec de áudio, preditor dos códigos, encoder de identidade e cabeças ficam sem essa quantização. Jessica reutiliza a referência portuguesa revisada após o pedido de urgência. Os mesmos bytes de referência e embedding identificam o ator nos dois idiomas.

O Base 0.6B usa referência acústica/textual para português e somente o embedding da identidade para inglês. Na amostra inglesa de Jessica, remover os códigos/texto portugueses da referência corrigiu os alertas lexicais observados pelo ASR: a versão com embedding recuperou integralmente a frase esperada. Isso não equivale a aprovação artística. As instruções de interpretação continuam presentes em `instruct_ids`; o core instalado aceita esse campo juntamente com a referência, mas a documentação pública do Base não promete controle por instrução. Essa capacidade continua identificada como `experimental_text` nos metadados.

O lote de oito faz a geração autoregressiva em conjunto, mas decodifica cada WAV separadamente. Essa separação corrigiu um estouro de memória do decoder ao processar oito formas de onda simultâneas. O primeiro lote corrigido produziu oito arquivos em **14,625 segundos**, com 29,078 segundos de áudio somados e pico CUDA de **2.759,3 MiB**. São medições dessa execução, sujeitas aos demais processos gráficos da máquina. [Evidência do benchmark](../audio/mission_voices/directed/benchmarks/baff80bd910aca04/benchmark.json).

O primeiro grupo de quatro referências VoiceDesign levou 64,953 segundos, gerando Dente de Ouro, Detetive Ribeiro, Digo e Dona Cida. Referências, gravações e avaliações lexicais são retomáveis; nenhum arquivo anterior é substituído silenciosamente. As primeiras verificações do lote de oito encontraram um possível desvio lexical de Cida em uma réplica; ASR é usado para localizar correções, sem mudar o roteiro para coincidir com uma gravação errada.

Comandos de produção:

```powershell
python tools/build_voice_bank.py plan
& 'D:/geteco/tools/opening_voice_design/Scripts/python.exe' tools/build_voice_bank.py anchors --timeout-seconds 7200
& 'D:/geteco/tools/opening_voice_design/Scripts/python.exe' tools/build_voice_bank.py render --batch-size 8 --resume-requests evidence/voice-direction-20261012/production-resume-short-reactions-v1.json --stop-file evidence/voice-direction-20261012/pause-production.request --timeout-seconds 14400
python tools/mix_directed_voices.py --manifest audio/mission_voices/directed/cloned-production.json
python tools/build_voice_bank.py publish --batch-size 8 --audit evidence/voice-direction-20261012/production-asr.json --content-decisions evidence/voice-direction-20261012/production-content-decisions.json --require-audit
```

`--limit` restringe o número de lotes da execução, sem impor teto à produção completa. A geração preserva reserva física de 3 GiB e reserva inicial de VRAM de 768 MiB, com limite privado e watchdog. Ela nunca encerra editores, capturas ou benchmarks de outras sessões.

`--character` na síntese seleciona lotes completos que contêm o personagem, preservando a composição e a semente assinadas do plano global. Portanto também pode gerar os vizinhos desse lote. Na publicação, a opção seleciona apenas entradas do personagem, mantendo 1.130 como cobertura global esperada.

`runtime.json` é separado de `approved.json`: registra `status: generated`, verificações técnicas objetivas e `artistic_review: pending`. Seu cabeçalho guarda os hashes atuais de elenco/direção; cada entrada guarda texto, personagem, gênero autorado, referência, configuração efetiva e hash do WAV. Cobertura parcial nunca recebe `complete: true`, inclusive ao publicar somente personagens selecionados. ASR e semelhança de embedding, quando presentes, não certificam gênero percebido ou atuação.

O auditor separado, em CPU, evita disputar a GPU de síntese e reutiliza a evidência pelo hash dos bytes:

```powershell
& 'D:/geteco/tools/opening_voice_design/Scripts/python.exe' tools/audit_directed_voices.py --manifest audio/mission_voices/directed/cloned-production.json --output evidence/voice-direction-20261012/production-asr.json --asr-max 100 --selection all --deadline-seconds 900
```

As medições de volume ficam em `mix.json`, por hash do áudio, sem modificar WAVs ou referências. O ganho linear busca −20 LUFS, respeita pico verdadeiro de −1,5 dB e limita a correção a ±12 dB. Interjeições curtas sem LUFS mensurável usam política explícita de pico a −6 dB. Não há compressor. O runtime aplica `playback_gain_db` e dispensa a atenuação legada adicional de inglês.

O publicador combina ASR exclusivamente pelo trio hash do áudio, idioma e texto esperado. Alertas ficam fora do manifesto até correção ou decisão lexical explícita em `--content-decisions`; essa decisão precisa registrar o trio exato e um motivo. `--require-audit` também exclui entradas ainda não auditadas. Reconhecimento automático sem alerta continua sendo evidência lexical, sem afirmar aprovação artística.

Retakes seletivos são imutáveis e retomáveis:

```powershell
& 'D:/geteco/tools/opening_voice_design/Scripts/python.exe' tools/build_voice_bank.py repair --repair-requests evidence/voice-direction-20261012/bank-repairs.json
& 'D:/geteco/tools/opening_voice_design/Scripts/python.exe' tools/build_voice_bank.py reanchor --repair-requests evidence/voice-direction-20261012/digo-anchor-retake.json
```

O pedido de fala usa `repairs: [{source_key, language, seed, variant, reason}]`. Somente o slot indicado ganha nova assinatura e WAV; `repair-selections.json` escolhe a alternativa, preservando o histórico. `--repair-model base_large` usa Base 1.7B NF4 em uma hipótese pontual registrada. O pedido de referência usa `anchors: [{character_id, seed, variant, reason, direction_suffix, supersedes_audio_sha256}]`; preserva a referência anterior em `anchor-history.json` e exige o SHA anterior correto. Trocar uma referência invalida apenas as gravações condicionadas por seus bytes e os lotes assinados afetados, sem fingir que mantêm a mesma entrada acústica.

Referências alternativas podem ser agrupadas com `batch_size: 4` e `batch_seed` no cabeçalho do pedido. Os seeds individuais precisam corresponder a essa semente compartilhada; composição, posição e tamanho efetivo entram em cada assinatura. Uma retomada parcial preserva os arquivos completos do grupo e apenas grava os que faltam.

Retakes de falas usam o mesmo contrato de semente compartilhada, com até `batch_size: 8`; somente as solicitações explícitas entram no lote. A semente declarada em cada item deve ser igual a `batch_seed`. `repair-selections.json` mantém as correções anteriores que não pertencem ao novo pedido.

Após 224 gravações, sete das 22 interjeições de dor excederam dois segundos, contrariando a direção de uma reação breve. A produção foi pausada no checkpoint, os 224 arquivos foram verificados por SHA e a retomada isolou somente as reações ausentes em lotes com orçamento de 48 códigos. Os 128 vizinhos ainda não gravados desses lotes receberam novas composições assinadas; 213 tomadas completas permanecem idênticas e onze alternativas pontuais foram planejadas por evidência. Nenhuma referência mudou. A projeção anterior à correção era cerca de 1h50 de síntese restante; o benchmark curto de oito amostras não representa esse banco inteiro.

O plano congelado de retomada é `production-resume-short-reactions-v1.json`. Receitas `requires_missing` recusam substituir áudio completo; `supersedes_audio_sha256` exige o arquivo realmente diagnosticado. O renderer registra o EOS observado nos tokens originais: áudio que chega ao limite sem EOS natural fica preservado para diagnóstico, mas é excluído da seleção/publicação. Janela cinematográfica é conferida pela duração do WAV completo, sem cortar palavras ou acelerar a gravação. Alternativas válidas são selecionadas a cada checkpoint, permitindo auditoria e publicação enquanto os demais lotes prosseguem.

O arquivo indicado por `--stop-file`, quando existir, pausa as próximas execuções entre lotes completos. Antes de retomar, remova apenas esse pedido de pausa. A escrita JSON usa renomeação atômica com retry finito para bloqueios transitórios do Windows; falha persistente conserva o arquivo `.pending`. A recuperação real do primeiro checkpoint de 40 tomadas está documentada em `production-checkpoint-recovery.json`.

Os contratos adicionais de referência fixa, configurações assinadas, lotes determinísticos, retakes, mistura e publicação passaram em **32 testes**: `python -m unittest discover -s tests -p test_voice_bank.py`. Os contratos de direção e escrita atômica passaram em **25 testes**: `python -m unittest discover -s tests -p test_voice_direction.py`. O preflight completo retornou 565 falas, 1.130 takes e 95 atores.

## Registro da primeira etapa

Esta ferramenta prepara e gera audições locais em português brasileiro e inglês. **Ainda não redubla o jogo em execução.** O banco legado permanece intacto; `audio/mission_voices/directed/approved.json` não foi publicado nem integrado ao runtime nesta etapa.

O inventário ampliado contém 504 falas canônicas, 86 rótulos e 91 identidades dramáticas: 345 falas do inventário legado e 159 falas adicionais que hoje são somente texto. Há 1.008 takes planejados para os dois idiomas. Vocalizações sem texto são inventariadas separadamente e não são tratadas como diálogo dublado.

## Arquivos e contrato

- `data/dialogue/voice-cast.json`: identidade, gênero com evidência, personalidade, direção por idioma, homônimos e bloqueios de vínculo visual.
- `data/dialogue/voice-line-direction.json`: texto original, versões faladas PT/EN e intenção/interpretação por fala.
- `tools/directed_voice_inventory.py`: inventário ampliado; preserva o inventário legado sem reescrevê-lo.
- `tools/voice_direction.py`: resolve personagem, valida direção e cria assinaturas de produção.
- `tools/build_directed_voices.py`: plano sem custo, síntese local incremental e manifestação de revisões.
- `audio/mission_voices/directed/production.json`: proveniência e arquivos efetivamente gerados, com estado de revisão.

A chave original é `sha256(persona.lower() + "|" + source)`. O take acrescenta personagem, gênero, idioma, texto falado, instrução efetiva, modelo/revisão, precisão numérica, dispositivo, semente e pós-processamento. Mudanças apenas de biografia/fontes não invalidam o áudio. Uma mudança na direção inglesa não força uma nova gravação portuguesa.

Personagens homônimos são resolvidos por chave de fala e depois por contexto. Ambiguidade, voz sem identidade, gênero desconhecido, texto ausente ou idioma não autorado interrompem o plano; não existe fallback silencioso para uma voz masculina ou para o outro idioma. Bloqueios de emissor visual e de roteamento de falas textuais acompanham o plano e impedem publicação.

A direção situacional prevalece sobre ritmo, emoção e respiração habituais do perfil. Isso é relevante para Jessica: a fuga exige medo e urgência, mesmo que ela costume manter controle e humor seco. As versões revisadas mantêm o texto, para permitir comparação de atuação.

## Comandos

Planejamento completo, sem carregar o modelo ou gerar áudio:

```powershell
python tools/build_directed_voices.py --plan-out tmp/voice-directed-full-plan.json
```

Audição bilíngue da fala de fuga de Jessica, na configuração que gerou áudio neste computador:

```powershell
& 'D:/geteco/tools/opening_voice_design/Scripts/python.exe' tools/build_directed_voices.py --line-key 2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430 --render --device cpu --dtype bfloat16 --memory-mb 8000 --reserve-mb 3072 --timeout-seconds 900
```

Uma fala de Cida nos dois idiomas:

```powershell
& 'D:/geteco/tools/opening_voice_design/Scripts/python.exe' tools/build_directed_voices.py --speaker cida --limit 1 --render --device cpu --dtype bfloat16 --memory-mb 8000 --reserve-mb 3072 --timeout-seconds 900
```

`--limit` conta falas originais, antes de expandir idiomas. Um lote tem no máximo 12 takes. `--languages pt_BR` ou `--languages en` restringe idioma; `--take-index 1` cria uma variação deliberada de semente. A mesma direção e assinatura reutilizam um WAV existente somente se o hash dos bytes conferir. Arquivos sem proveniência correspondente não são sobrescritos.

O modelo precisa estar previamente disponível no cache local; `--model-path` permite selecionar uma revisão exata. Não há download automático, chamada de TTS pela rede nem uso de credenciais. O renderer usa dois threads, prioridade abaixo da normal, limite de memória privada do Windows e watchdog de tempo/reserva física. Ele não encerra processos do editor, do jogo ou de outras sessões.

## Medições e limites observados

O modelo disponível é Qwen3-TTS-12Hz-1.7B-VoiceDesign, revisão `5ecdb67327fd37bb2e042aab12ff7391903235d3`. Ele aceita instruções expressivas nos dois idiomas. Semente fixa oferece repetibilidade de configuração; **não garante um timbre idêntico em todas as falas**.

Primeira audição, CPU BF16, dois threads:

| Personagem/idioma | Áudio produzido | Tempo de geração |
|---|---:|---:|
| Jessica PT-BR | 6,562 s | 396,640 s |
| Jessica inglês | 4,000 s | 233,141 s |
| Cida PT-BR | 2,640 s | 136,813 s |

O lote atingiu 900 segundos durante Cida em inglês; esse quarto take não foi concluído. A retomada preserva os três arquivos completos. Jessica PT/EN da primeira audição são referências anteriores ao pedido humano de **mais urgência e emoção**, não atuações aprovadas.

Arquivos preservados da primeira audição:

- [Jessica PT-BR, antes da revisão](../audio/mission_voices/directed/pt_BR/2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430_18bf54be801ce782.wav)
- [Jessica inglês, antes da revisão](../audio/mission_voices/directed/en/2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430_67f3881be90a16e6.wav)
- [Cida PT-BR, audição da moradora do esgoto](../audio/mission_voices/directed/pt_BR/a0f159168a801dab0e029c9259fde373c44d1123fcb8aa78ab0bd27a6abf3f40_fc2938c6c77dd73d.wav)

Após o pedido humano de mais urgência e emoção, foram geradas duas novas audições de Jessica, com **os mesmos textos** e direção de perigo imediato, comando firme, respiração curta e medo sob controle:

| Nova audição | Duração do áudio | Tempo de geração |
|---|---:|---:|
| [Jessica PT-BR revisada](../audio/mission_voices/directed/pt_BR/2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430_7d8ae2517fa89f66.wav) | 5,954 s | 491,797 s |
| [Jessica inglês revisada](../audio/mission_voices/directed/en/2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430_33c4e8cdd9fd291b.wav) | 4,320 s | 295,140 s |

O processo terminou com código 0, dentro dos 900 segundos previstos. O tempo somado de geração foi 786,937 segundos; pico privado: 6.701,7 MiB; residente: 5.248,0 MiB. São amostras para comparação, **sem aprovação artística automática**. O manifesto guarda cinco WAVs completos: as três audições iniciais e estas duas revisões. Cida em inglês continua pendente.

O pico privado medido na primeira Jessica foi 6.835,5 MiB, com 5.323,1 MiB residentes. O limite inicial de 6.000 MiB era insuficiente para este ambiente: os imports já consumiam aproximadamente 2,45 GB privados e os pesos BF16 somam aproximadamente 4,52 GB com o tokenizer. O lote que produziu áudio usou teto de 8.000 MiB.

Este CPU informa AVX2. No diagnóstico finito de multiplicação de matrizes, BF16 levou 7,987 ms e FP32 0,150 ms para `1×1024 @ 1024×3072`; para 32 linhas, 298,770 ms e 1,034 ms. FP16 também foi lento, 9,083 ms no caso de uma linha. Isso explica um gargalo de precisão numérica, mas **não comprova throughput do modelo inteiro em FP32**.

Uma tentativa FP32 respeitou teto privado de 12 GiB e reserva física de 3 GiB. Ela carregou o modelo, mas falhou no primeiro forward ao tentar alocar 7.028.736 bytes sob esse teto. Não produziu take, não foi repetida com o mesmo orçamento e não prova falta de RAM total do computador. A segunda audição de Jessica usa a configuração BF16 que já produziu áudio.

Produção integral em CPU BF16 não é razoável com os tempos observados: somente o par curto de Jessica levou aproximadamente 10,5 minutos. Não se deve tratar o plano de 1.008 takes como 1.008 gravações já prontas.

## Identidade persistente e próximos lotes

O fluxo oficial [Voice Design then Clone](https://github.com/QwenLM/Qwen3-TTS#voice-design-then-clone) usa uma referência fictícia criada por VoiceDesign e um prompt de voz reutilizável no modelo Base. Isso é mais apropriado para manter uma identidade em várias falas do que confiar apenas na semente. O Base não está instalado nesta máquina e não foi baixado nesta tarefa.

Os repositórios oficiais indicam aproximadamente [2,52 GB para Base 0.6B](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base/tree/main) e [4,54 GB para Base 1.7B](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base/tree/main). Esses são tamanhos de download, não estimativas de RAM. O Base usa referência de voz; ele não oferece o mesmo campo livre de direção `instruct` do VoiceDesign. A combinação de identidade, mudança de emoção e equivalência PT-BR/EN ainda precisa de prova auditiva antes de escalar.

## Revisão e publicação de metadados

Uma revisão pode reunir decisões de um lote. Para cada take aprovado, informe `signature`, `decision: "approved"`, `reviewer` e checks verdadeiros para `transcript`, `language`, `gender`, `identity`, `delivery` e `technical_quality`. Checks representam evidência de qualidade; não devem ser preenchidos automaticamente só porque existe um arquivo WAV. A autorização do usuário para trabalhar já existe; esse registro não é uma nova solicitação de permissão.

```powershell
python tools/build_directed_voices.py --publish-review tmp/voice-reviews.json
```

A publicação verifica bytes SHA-256, direção/elenco atuais e bloqueios de emissor. `reviews.json` preserva decisões anteriores; novas gravações aprovadas substituem o mesmo slot, rejeições explícitas removem aprovação e assinaturas antigas ficam marcadas como obsoletas. `approved.json` é um manifesto de dados; **ainda não há integração dele com o jogo**. ASR e formato correto não comprovam atuação, identidade, gênero percebido nem ausência de problemas de pronúncia.

## Validação do código

Foram executados **23 testes**, todos aprovados:

```powershell
python -m unittest discover -s tests -p test_voice_direction.py
```

Cobrem ausência de fallback de gênero/idioma, homônimos, assinatura por insumos audíveis, notas documentais, preservação de WAV concorrente, retomada sem carregar modelo, bytes alterados, revisões incrementais/obsoletas e bloqueios de personagens ainda sem vínculo ao emissor. Essa validação offline não certifica apresentação no Godot, sincronização de legendas, performance do jogo ou qualidade artística de todos os takes.

A [conferência das duas novas tomadas de Jessica](../evidence/voice-direction-20261011/auditions-jessica-revised-asr.json) confirmou correspondência com o plano atual, hashes dos arquivos e áudio mono PCM16 a 24 kHz sem saturação. O reconhecimento recuperou integralmente o inglês. Em português, escreveu “Sinto” no lugar de “Cinto”, palavras homófonas; essa diferença de escrita não comprova erro audível. “Dante” e o restante da frase foram reconhecidos. A atuação segue aberta à escuta, sem aprovação artística automática.
