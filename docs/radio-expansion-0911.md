# Rádios — 11/09/2026

Sete estações musicais e uma opção desligada. As quatro primeiras continuam na mesma ordem: Porto FM, Porto Noite, Porto Groove e Porto Brisa.

Novas estações, com músicas completas de Zane Little Music publicadas sob CC0:

- Porto Neon — synth rock: [The Way It Is](https://opengameart.org/content/the-way-it-is), 148 s.
- Porto Arcade — chiptune: [The Cool Factor](https://opengameart.org/content/the-cool-factor), 132 s.
- Porto Pesada — metal fusion: [The End](https://opengameart.org/content/the-end-day-30), 242 s.

Arquivos OGG locais, estéreo a 32 kHz, com normalização e fades curtos. Fontes, hashes e métricas estão em `audio/living_city/SOURCES.json`; reprodução offline. Reprocessamento: `python game/tools/expand_radio.py` a partir da raiz do workspace.

Ao dirigir, roda para cima avança e roda para baixo volta. Botões e tecla R continuam disponíveis. O receptor usa eventos não consumidos pela interface e ignora pausa, diálogo e remapeamento. Motocicletas agora inicializam e reproduzem a mesma rádio dos outros veículos ao embarcar.

Validação com Godot 4.7.2 headless:

- `tests/test_radio_controls.gd`: zero falhas; sete faixas com mais de dois minutos, botões, mute, roda nos dois sentidos, retorno circular, pausa e saída.
- `tests/test_motorcycles.gd`: zero falhas; embarque e rádio nas três motos, troca pela roda em sedan e caminhão de carga, parada do som na saída e regressões de motos.

Logs em `D:/geteco/artifacts/radio-expanded-controls.log` e `D:/geteco/artifacts/radio-expanded-vehicles.log`. O importador gerou os recursos de áudio; ao restaurar o layout do editor, também reportou `Busy` em `CarjackedDriver.tscn`. Os dois testes executaram depois com código de saída zero. O teste de controles emitiu avisos de recursos ainda em uso no encerramento. Não foi feita avaliação auditiva manual dentro de uma sessão interativa.
