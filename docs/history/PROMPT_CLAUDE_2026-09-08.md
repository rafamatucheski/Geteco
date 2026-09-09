# Tarefa para Claude Code — áudio isolado

Estamos trabalhando em paralelo em D:/geteco/game. Astra e três agentes cuidam de mundo contínuo, estradas, veículos/câmera, polícia, Dante/armas e interiores. Preserve alterações existentes; não faça reset ou commit geral.

Melhore os sons de sirene e conquista, hoje artificiais/desagradáveis, sem alterar regras de perseguição ou disparo de conquista.

Você pode editar `ProceduralAudio.gd` e criar arquivos em `audio/review_0908/` e testes próprios. Antes, identifique as funções públicas existentes para sirenes e conquistas e PRESERVE seus nomes, argumentos, tipo de retorno e duração esperada pelos consumidores.

Sirene: alternância reconhecível, transições contínuas, sem clipping, estalos ou agudos dolorosos. Loop realmente contínuo quando aplicável. Conquista: frase musical curta e satisfatória, com ataque/decay suaves e volume coerente com SFX. Não mudar canais nem configurações do usuário. Cache dos streams: não gerar PCM novamente a cada acionamento.

Também crie módulo independente `audio/review_0908/BearAudio.gd` com sons discretos de respiração, grunhido/alerta e investida, com interface documentada para Astra conectar aos ursos; sem editar os ursos agora. Use apenas áudio original/procedural ou material com licença documentada.

Não edite WantedManager, EmergencyVehicle, PoliceOfficer, Player*, TrafficVehicle, mapas, RegionTravel, SaveManager, UI, Localization ou achievement controllers. A lógica da sirene está com o agente de polícia; sua tarefa é o timbre e qualidade dos streams.

Execute testes de geração, amostras finitas, pico sem clipping, cache e continuidade do loop. Exporte WAVs de comparação para audição. Godot 4.7.2: `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`. Relate honestamente o que executou. Entregue arquivos alterados, funções preservadas e caminhos dos WAVs; não alegue ter validado gameplay se não rodou o jogo.
