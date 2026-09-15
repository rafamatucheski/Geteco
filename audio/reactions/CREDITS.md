# Reações de personagens — 10/09/2026

Gravações por Iwan “qubodup” Gabovitch, licença CC0:

- [15 vocal male strain/hurt/pain/jump sounds](https://opengameart.org/content/15-vocal-male-strainhurtpainjump-sounds): `slightscreams.7z`, voz humana gravada. A página informa CC0 desde 30/08/2024.
- [Punch](https://opengameart.org/content/punch): `qubodupPunch.7z`, cinco impactos; usados em `../combat/flesh_*.wav`.
- [Licença CC0](https://creativecommons.org/publicdomain/zero/1.0/).

Edição: mono, 32 kHz, remoção de silêncio, filtro de rumble/agudos e fades nas bordas. Sem mudança artificial de altura nas fontes. Cinco takes por evento, sem repetição consecutiva. Impacto corporal agora é somente contato seco; a voz de queda vem dos getters de reação existentes. Mortes de pedestres, policiais e socorristas usam takes mais longos que a reação de dor.

Fontes locais: `D:/geteco/assets/audio-sources/character-reactions`.
Reconstrução: `python D:/geteco/tools/build_character_audio.py`.
O gerador geral de combate também usa a gravação de impacto, para não restaurar o antigo timbre sintetizado.

Validação técnica não substitui avaliação auditiva: a seleção usa a descrição das gravações e a duração dos takes; o agente não realizou escuta direta.

## Verificação

- `tests/test_hurt_audio.gd`: passou nos sete tipos de ator, dano inválido, proteção de respawn e agrupamento de chumbos.
- `tests/test_combat_audio.gd -- combat-only`: passou (materiais, projéteis e armas). O teste completo também verifica chuva e falha numa expectativa antiga de até 620 partículas; essa parte não foi alterada nesta revisão.
- `tests/test_character_reaction_audio.gd -- record`: passou. Exercita dano letal real em pedestre, policial, paramédico e bombeiro; confere uma voz de morte no SFX, sem voz simultânea de pânico no golpe letal.
- Quinze vozes mono sem clipping e com bordas suavizadas; os cinco impactos também passam na checagem PCM do banco de combate.
- Captura atual do SFX via WASAPI: `D:/geteco/artifacts/character-sounds-0910/preview.wav`, 7,83 segundos, pico 0,231. Primeiro três contatos secos, depois quatro mortes. Não representa todas as combinações possíveis de sons da campanha.
- Logs em `D:/geteco/artifacts/character-sounds-0910/`. Os autoloads também emitem avisos preexistentes de ações `weapon_slot_*` ausentes ao carregar configurações pessoais.
