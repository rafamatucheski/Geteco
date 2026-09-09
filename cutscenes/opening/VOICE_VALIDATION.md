# Vocalizações V2

Não é dublagem: são sílabas procedurais sem palavras reconhecíveis, junto das
legendas. `ExpressiveVoice.gd` gera uma fala finita por texto, com pausa em
pontuação, intervalos entre palavras e variação determinística de timbre/pitch.
Dante, Maciota e interlocutor telefônico têm perfis diferentes; o último tem
menos grave e harmônicos médios, uma aproximação estilizada de telefone.

Telefone de chegada e CGI usam as novas falas. Maciota reutiliza um único
AudioStreamPlayer SFX; trocar/fechar diálogo interrompe o áudio anterior.
A boca usa o envelope da vocalização na posição de reprodução. Não é lip-sync
fonético e não altera o rig do personagem. Legendas continuam necessárias.

Cache limitado a 32 linhas; falas conhecidas preparadas na configuração/ready.
Novas linhas não cacheadas ainda exigem síntese; não foi medido FPS nesta etapa.
As falas da CGI têm duração ajustada às legendas. Outros NPCs e dublagem completa
não foram migrados. A qualidade perceptiva ainda precisa de revisão ouvindo no jogo.

Testes: `test_expressive_voice.gd`, `test_maciota_character.gd` e
`test_opening_cutscene_runtime.gd`: os três passaram, exit 0 e zero falhas.
Não foi rodada a suíte completa. Permanecem avisos ambientais de logs/certificados
e duas instâncias ObjectDB no encerramento do teste do Maciota.
Sem commits ou alterações em modelos.
