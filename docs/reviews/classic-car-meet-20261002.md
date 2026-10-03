# Encontro de antigos — Aurora

## Implementação

Novo exterior em Harbor, na chegada aos Cobras: âncora `(420, 0, 124)`, lote X409–431/Z109–139 e entrada de 8 m pela rua existente. O documento de ruas não foi alterado. A árvore em `(427.5, 119.375)` permanece numa ilha. A fachada exibe apenas **Aurora**; este local não adiciona um interior acessível.

Terça, quinta e sábado, das **19h à 1h**, no calendário do jogo: dois Gol, duas Parati e dois Passat com cores distintas, três capôs abertos e motores modelados, dois neons e seis pessoas conversando/observando os carros. A madrugada pertence à noite anterior. De dia, dois carros comuns e dois clientes percorrem o estacionamento. Nas demais noites, apenas um carro permanece.

A agenda lê `Weather.moon_day()` e `time_of_day`, já persistidos pelo jogo. O encontro não depende do relógio real. O controlador conserva identidades ao hibernar longe do jogador, desativa física/apresentação e impede reativação sobre ocupantes. Mortes são preservadas durante a mesma noite em `classic_meet_absences`; a próxima edição renova a população. Atores usam os corpos e reações a perigo existentes.

Geometria estática dos carros/cenário agrupada por material. Três focos do estacionamento/fachada e um foco adicional do encontro, cordão de vinte luminárias e dois neons. Os focos próprios substituem a disputa anterior pelo pool dos postes. A separação entre focos e luzes omnidirecionais respeita os limites documentados do [renderer Mobile do Godot 4.7](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html).

## Validação e evidências

Ambiente: Godot **4.7.2 .NET**, Mobile/Vulkan, RTX 4060 Laptop, 1280×720. `dotnet build Harbor.csproj --no-restore`: aprovado. Todas as execuções usam `--no-save`; o teste de persistência usa arquivo isolado.

Evidências desta sessão em `C:/Users/rafae/.codex/visualizations/2026/10/03/01a0ff9a-976f-7cd3-81c4-9f9c1fa186e5/classic-meet/`.

| Cenário | Resultado |
|---|---|
| Agenda, três noites/semana, início, fim e madrugada | `test_classic_meet_schedule.gd`: aprovado |
| Corpos reais jogador/NPC, seis vagas, rotas dos clientes e entrada | `test_classic_meet_site.gd`: 50 verificações aprovadas |
| Focos próprios: orientação, alternância, idempotência e ausência de duplicação | `test_classic_meet_site.gd -- --lighting-only`: 25 verificações aprovadas; `lighting-idempotent.log` |
| Oclusão pelos carros com controles positivos de jogador/NPC à frente, atrás e ao lado | `test_classic_meet_depth.gd`: 12 verificações aprovadas; pasta `depth/` |
| Integração real dia/noite | Capturas `final/day.png`, `final/night.png` e `final/night-front.png` |
| Retorno, sobreposição, save, ameaça/recuperação, troca da agenda | 39 verificações integradas aprovadas em `final/`, roteador C# real inicializado; `failures=[]` |
| Estabilidade temporal com câmera em movimento | Última captura sem repetição nos pontos monitorados; aprovação permanece pendente, conforme limites abaixo |
| Comparação de desempenho | Pendente: execuções concorrentes impedem comparação equivalente |

Meta provisória: 60 FPS/16,67 ms; diferença superior a 5% em p95/p99 exige confirmação finita, sem mudar o critério depois da medição. A primeira coleta anterior à integração (`baseline/`) teve 30 s por fase, mas população ainda crescendo e outra execução do jogo disputando GPU. É diagnóstico, não comprovação de regressão: dia 152,2 FPS/p95 10,19 ms/p99 11,69 ms; noite 123,5 FPS/p95 13,33 ms/p99 19,41 ms. O roteador C# é inicializado explicitamente nas coletas seguintes, antes do aquecimento; na primeira estava apenas ainda não solicitado.

O teste integrado percorre fisicamente a entrada, verifica sólidos com jogador/NPC, hiberna e reativa as mesmas entidades, bloqueia reativação sobre o jogador, atravessa meia-noite/fim do evento e restaura ausências após morte usando save isolado. O fixture converte índices numéricos carregados de JSON para inteiro antes de comparar, assim como o controlador. A câmera verifica oclusão separadamente das colisões.

## Iluminação: evidência e limite

A captura `final/` registrou 885 imagens consecutivas em 30,024 s, sem saltos no contador de frames renderizados. Houve escurecida de um frame em contribuição ampla da cena, incluindo telhado e área externa, em aproximadamente 0,50 s e 3,48 s. Os centros dos postes permaneciam acesos; a causa não ficou demonstrada. O controle `temporal-without/`, sem o encontro, não repetiu o efeito nos quatro pontos monitorados durante 30,015 s/957 imagens.

Foi removido o reenvio redundante de energia/visibilidade das luzes a cada atualização do controlador: agora os parâmetros mudam somente na transição de estado. O teste de alternância/idempotência passou. Após esse ajuste, `temporal-stable-fixed/` capturou 843 imagens consecutivas em 30,021 s; os quatro pontos de piso não repetiram a escurecida. Os dois candidatos automáticos correspondem à mudança inicial da câmera e variação durante movimento. A captura inclui oito segundos de câmera parada e movimento posterior.

Essa última execução registrou erro de parse em `ZooAdmission.gd`, de edição concorrente, durante carregamento de outra área. O arquivo já estava corrigido pela outra sessão ao inspecioná-lo depois. Portanto, a captura é evidência local limitada, não uma aprovação final de estabilidade do mundo nem prova da causa/correção definitiva da oscilação anterior. Preservar essa pendência; não certificar toda a iluminação por essa amostra.

## Performance e trabalho concorrente

Uma tentativa posterior de comparação controlada foi interrompida ao detectar benchmarks simultâneos de outras sessões. O jogo do usuário também estava aberto. Não há comparação antes/depois com cargas equivalentes e não há aprovação de FPS. Os intervalos de captura de JPEG incluem leitura da GPU e escrita de imagem; não são benchmark de gameplay.

Foram observados avisos de recursos/RIDs ao encerrar tanto com quanto sem o encontro. Não se atribuiu vazamento novo a esta implementação, nem se certificou limpeza global de recursos.

Edições concorrentes também interromperam carregamentos temporariamente. Foram feitas somente anotações explícitas de tipo em três expressões que impediam compilação: `SupermarketPlace.gd` (`reaction: Node`), `SupermarketFacade.gd` (`x: float`) e `MountainZoo.gd` (`path: String`), preservando conteúdo e comportamento. O parse principal passou depois dessas correções, antes da edição posterior de `ZooAdmission.gd`. Nenhuma alteração local foi descartada. `git diff --check` passou para os dois arquivos versionados de integração do encontro.

Implementação e verificações funcionais locais concluídas. Permanecem pendentes a confirmação temporal em uma execução integrada sem erros concorrentes e a comparação de frame time antes/depois em condições equivalentes.
