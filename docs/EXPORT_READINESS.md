# Prontidão de exportação do Geteco V2 para Windows

Data da verificação: 2026-09-21  
Godot usado: `4.7.2.stable.official.ed1daf0bf`  
Preset: `Geteco V2 Windows`

## Conclusão

A árvore de origem possui os recursos dinâmicos inventariados e o preset produz um PCK que cobre os JSONs, catálogos, cenas, modelos, imagens e áudios por `ResourceLoader`. A distribuição Windows ainda **não está pronta para ser declarada funcional** por dois bloqueios independentes:

1. os templates Windows compatíveis com Godot 4.7.2 não estão instalados, portanto nenhum `.exe` foi produzido;
2. 99 WAVs de combate são carregados em produção por `FileAccess` + `AudioStreamWAV.load_from_file()`. No PCK eles existem apenas como recursos importados: `ResourceLoader` os encontra, mas `FileAccess.file_exists()` não encontra os caminhos `.wav` originais.

O segundo ponto é um defeito do carregador de produção e ficou somente documentado, conforme o limite de escopo. O filtro explícito do preset para os WAVs não muda o resultado. A documentação do Godot recomenda `ResourceLoader` para recursos exportados ou o modo de importação *Keep File* quando `FileAccess` for obrigatório: <https://docs.godotengine.org/en/stable/classes/class_fileaccess.html>.

## Preset Windows

`export_presets.cfg` contém um único preset novo, `Geteco V2 Windows`, com:

- `export_filter="all_resources"` para os recursos reconhecidos pelo Godot;
- inclusão explícita dos nove JSONs de runtime;
- filtros explícitos dos WAVs de combate e recarga, mantidos como defesa documental mesmo que o importador WAV continue substituindo o arquivo bruto no PCK;
- exclusão de `tests/**`, `tools/**`, `docs/**` e `evidence/**`;
- PCK separado do executável (`binary_format/embed_pck=false`);
- assinatura desativada e nenhuma credencial lida ou registrada.

Nenhum preset anterior existia no V2 no início desta tarefa.

### Limitação de versionamento

O `.gitignore` da raiz do workspace contém a regra global `export_presets.cfg`. Por isso, o preset existe em `geteco_v2/export_presets.cfg`, é aceito pelo Godot e foi usado nos PCKs desta verificação, mas fica ignorado pelo Git e não aparece em uma adição normal de arquivos. Alterar o `.gitignore` estava fora do escopo exclusivo desta tarefa, e nenhum commit foi feito. Antes da integração, o responsável deve permitir explicitamente esse arquivo no controle de versão ou adicioná-lo de forma intencional apesar da regra.

## Inventário coberto

O manifesto gerado contém 523 entradas de cobertura, distribuídas assim. Um mesmo caminho pode aparecer em mais de uma categoria quando cumpre dois contratos (por exemplo, gravação de voz e áudio dinâmico):

| Categoria | Caminhos | Resultado na árvore | Resultado no PCK |
|---|---:|---|---|
| JSONs de runtime | 9 | presentes e parseáveis | presentes e parseáveis |
| Cenas da frota | 49 | presentes e carregáveis como `PackedScene` | presentes e carregáveis como `PackedScene` |
| Modelos de moradores | 2 | presentes | presentes |
| Gravações apontadas pelo manifesto de voz | 20 | presentes | presentes como `AudioStream` |
| Áudios dinâmicos | 326 | presentes e carregáveis | presentes como `AudioStream`; 99 WAVs não são visíveis ao carregador por arquivo bruto |
| Modelos dinâmicos de regiões/interiores | 31 | presentes | presentes |
| Demais recursos de regiões/interiores | 84 | presentes | presentes |
| Outros recursos dinâmicos | 2 | presentes | presentes |

Os nove JSONs são:

- `assets/fleet/catalog.json`;
- `runtime/VehiclePaintSources.json`;
- `world/places/OriginalResidentData.json`;
- `world/regions/OriginalLakeData.json`;
- `world/regions/OriginalWorldData.json`;
- `data/campaign/campaign_v1.json`;
- `data/campaign/first-favors-dialogue.json`;
- `data/campaign/cobra-dialogue.json`;
- `audio/mission_voices/recordings.json`.

Além dos itens pedidos nominalmente, a cobertura inclui abertura, rádios, motores, passos, ambiência urbana e regional, clima, menu, vozes de missão, cenas de recompensa da garagem, fachadas, modelos de interiores e recursos em `assets/regions/source` usados por caminhos montados em runtime.

Os campos `model_class` da frota e `source` de `VehiclePaintSources.json` são metadados de origem; os carregadores de produção examinados usam `scene` para a frota e dados de cor para pintura. Eles não foram tratados como dependências ativas do runtime.

## Verificações executadas

### 1. Recursos presentes na árvore

Resultado: **aprovado**.

- 1.428 verificações;
- 523 entradas de cobertura inventariadas;
- todos os JSONs parseáveis;
- 49/49 cenas do catálogo da frota carregáveis;
- 8 moradores com 2/2 modelos existentes;
- 20/20 gravações do manifesto de vozes existentes;
- nenhuma dependência inventariada ausente na árvore.

Evidência: `source-validation.json`, `source-validation.log` e `production-resources.json` no diretório de artefatos.

### 2. Recursos incluídos no pacote

Resultado: **parcial, bloqueado pelo carregador de WAV bruto**.

- PCK gerado e montado diretamente pelo Godot, sem usar a árvore do editor como fallback;
- 1.290 verificações no segundo PCK;
- as 523 entradas passaram pelos checks de JSON/`ResourceLoader`;
- os sentinelas de `tests`, `tools`, `docs` e `evidence` não estavam no pacote;
- 99 falhas adicionais e homogêneas: `FileAccess` não vê os WAVs em `assets/gameplay/audio/**` dentro do PCK.

Arquivos responsáveis pelo carregamento incompatível:

- `gameplay/CombatAudio.gd:22`;
- `gameplay/Gameplay.gd:1037-1039`.

O primeiro PCK, sem o filtro WAV explícito, e o segundo, com o filtro, produziram a mesma assinatura de 99 falhas. Não houve terceira repetição equivalente.

### 3. Exportação Windows concluída

Resultado: **não executável / não concluída**.

O editor encontrou o preset, mas recusou produzir o `.exe` porque faltam os templates:

- `C:/Users/rafae/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_debug_x86_64.exe`;
- `C:/Users/rafae/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe`.

Versão necessária: **templates de exportação Godot 4.7.2.stable para Windows x86_64**. Nenhuma ferramenta ou template foi instalado ou baixado.

Foi possível gerar somente um PCK de inspeção. Isso não equivale a uma distribuição Windows completa.

### 4. Executável realmente iniciado

Resultado: **não executado**.

Não existe executável exportado. Nenhum teste de abertura foi tentado e nenhum save normal do usuário foi acessado. Quando os templates estiverem disponíveis, a abertura ainda deverá usar `user://` isolado antes de ser considerada validada.

## Artefatos

Diretório criado exclusivamente para esta tarefa:

`D:/geteco/game/artifacts/geteco-v2-windows-20260921-1732`

PCK final de inspeção:

`D:/geteco/game/artifacts/geteco-v2-windows-20260921-1732/pack-inspection-raw-filter/GetecoV2.pck`

- tamanho: 102.898.168 bytes;
- SHA-256: `E967F4D0767218BA479DC464F870483564E64CED3D2119455327D8342C44B644`.

Logs e relatórios principais:

- `production-resources.json` — manifesto usado nas duas fronteiras;
- `source-validation.json` / `source-validation.log` — árvore de origem;
- `export-release.log` — falha por templates ausentes;
- `export-pack-raw-filter.log` — geração do PCK;
- `package-validation-raw-filter.json` / `.log` — inspeção do PCK e falha dos 99 WAVs brutos.

## Ferramenta de verificação

`tools/export_validation/validate_dynamic_resources.gd` possui dois modos:

- `source`: inventaria catálogos/diretórios, valida a árvore e grava o manifesto;
- `package`: roda com `--main-pack`, lê o mesmo manifesto fora do pacote, verifica recursos, catálogos, exclusões e o caminho real do carregador WAV.

O script emite mensagens no formato `EXPORT_VALIDATION|MISSING|<categoria e caminho>`, para que qualquer recurso ausente seja identificável sem depender de stack trace.

## Pendências para liberação

1. Responsável pelo runtime/áudio: trocar os dois carregamentos de WAV por `ResourceLoader` ou definir/importar esses arquivos como *Keep File*, e repetir a inspeção do PCK.
2. Responsável pelo ambiente de build: instalar externamente os templates oficiais 4.7.2.stable para Windows x86_64.
3. Repetir a exportação em uma pasta nova e vazia.
4. Rodar novamente a verificação do pacote.
5. Só então fazer um teste de abertura com `user://` comprovadamente isolado e registrar separadamente o resultado.


---

## Atualização 2026-09-21 (frente "áudios de combate no PCK")

### Falha reproduzida
PCK de inspeção anterior + validador antigo (cópia fora do PCK, `--path` vazio + `--main-pack`): **99 falhas, todas `[raw-audio-loader] FileAccess não vê WAV`, nenhuma outra**. Causa: o PCK guarda o WAV só como recurso importado; `FileAccess`/`AudioStreamWAV.load_from_file()` só veem o arquivo-fonte.

### Estado dos consumidores (conferido no código atual)
| Consumidor | Exige | Situação |
|---|---|---|
| `gameplay/CombatAudio.gd:wav()` (base de `take`, `reload_take`, `reload_seconds`) | `AudioStream` (só toca e usa `get_length()`; sem `duplicate`/`loop`) | **já usa `ResourceLoader`** no código atual (não há mais `load_from_file` em produção) |
| `gameplay/Gameplay.gd:1074` (`_audio_cache[path] = AUDIO.wav(path)`) e `:598/:868/:1100/:1123/:1154` | `AudioStream` | passam por `CombatAudio.wav`; sem encaixe próprio |
| `audio/service_vehicles`, `vehicle_ambience`, `WorldAudio` | `AudioStreamWAV` (`duplicate()` + `loop_mode`) | `load()` de recurso importado; o importador entrega `AudioStreamWAV`; funciona no PCK |

Restou um único uso de `load_from_file`: o **próprio validador antigo**, que testava o contrato errado. Foi trocado.

### Carregador (`audio/export_compat/ImportedAudioLoader.gd`) — **implementado, NÃO conectado**
`stream(path)` (AudioStream, cacheado), `wav(path)` (exige AudioStreamWAV), `fresh(path)` (cópia para alterar loop), `duration(path)`, `report()`. `ResourceLoader` primeiro; arquivo bruto só se não houver recurso importado (árvore sem importar), registrado em `sources`. Falha nunca vira silêncio: fica em `failures` e sai um `push_error` por caminho.

### Contrato para o Claude (único encaixe; `CombatAudio.gd` e `Gameplay.gd` NÃO foram editados)
Em `gameplay/CombatAudio.gd`, hoje `wav()` memoriza `null` sem avisar quando o recurso não existe. Substituir o corpo por:
```gdscript
const IMPORTED := preload("res://audio/export_compat/ImportedAudioLoader.gd")

static func wav(relative_path: String) -> AudioStream:
	if _wav.has(relative_path): return _wav[relative_path]
	var stream := IMPORTED.stream(AUDIO_DIR + relative_path)
	if stream != null: _wav[relative_path] = stream   # falha não é memorizada: fica em IMPORTED.failures, com diagnóstico
	return stream
```
`Gameplay.gd`: nenhuma alteração. Sem esse encaixe o comportamento **já funciona** no PCK (verificado abaixo); o encaixe só acrescenta diagnóstico. O módulo continua "não conectado" até a troca.

### Resultados
| Ambiente | Resultado |
|---|---|
| Árvore do editor | `PASS checks=1867`: 102 WAVs (99 + 3 `panic_*`) como `AudioStreamWAV`, duração >0, dados/mix_rate, cache com mesma instância, `fresh()` independente, `reload_seconds` de 11 armas igual ao cálculo pelo carregador, `CombatAudio.wav()` real; `raw_fallbacks=0` |
| PCK novo (`artifacts/export-compat-0921/pack/GetecoV2.pck`, 103.105.544 B) | `PASS checks=1828`, 102/102, `raw_file_visible=0`, `raw_fallbacks=0` |
| Validador antigo no PCK novo | 102 falhas (confirma que o arquivo bruto continua ausente: o contrato antigo é inválido, não o PCK) |
| Caminho inexistente | `null` + diagnóstico único, também no PCK |

### Preset
`export_filter=all_resources`; incluí `*/test_*.gd, */validate_*.gd` no `exclude_filter` porque 4 scripts de teste dentro de `activities/` e `audio/` entrariam no pacote (agora 0 no PCK). `tests/`, `tools/`, `docs/`, `evidence/` seguem fora. Os filtros `assets/gameplay/audio/*.wav` continuam só documentais (o PCK guarda o importado). Não incluí árvore inteira.

### Exportação Windows
`export_templates/` existe mas está **vazia**: faltam `windows_debug_x86_64.exe`/`windows_release_x86_64.exe` 4.7.2.stable. Nada foi instalado/baixado; **nenhum `.exe` foi gerado nem iniciado**. O PCK acima não comprova a distribuição funcionando. A abertura futura exige `user://` isolado.
