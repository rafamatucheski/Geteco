# Impactos nos objetos da montanha

Aplicado o sistema existente do deserto aos pinheiros da montanha (inclusive registros do editor), aos três pinheiros e três blocos rochosos da aproximação da caverna e aos postes MountainRoadLamp. Bancos já registrados continuam usando o sistema compartilhado. Construções, terreno e estruturas de progressão não foram cadastrados como objetos frágeis.

Os impactos reutilizam os limiares, fragmentos físicos, dano, arrasto e descarte do sistema existente. O registro aceita raio opcional para respeitar o tamanho das pedras e a escala dos pinheiros editados. O proxy visual oculto da colisão do tronco é removido antes da fratura, preservando o corpo físico. Atualizações noturnas ignoram luzes destruídas.

## Validação

- Godot 4.7.2 .NET; `dotnet build Harbor.csproj --no-restore`: aprovado, sem avisos ou erros.
- `tests/test_mountain_breakables.gd -- --no-save`, headless: 166 checks, nenhuma falha ou erro no log final. Exercita geometria real pelo adaptador de produção, colisão antes/depois, contato lento, varredura a 42 m/s, fragmentos, impacto repetido, escala, oito variantes de pinheiro, luz destruída e descarregamento. É teste de integração dirigido, não percurso jogado.
- `tests/test_vehicle_contact_release.gd -- --no-save`, headless: 36 checks aprovados. O runner também emitiu avisos de objetos/recursos ainda vivos ao encerrar; não equivale a encerramento sem diagnóstico.
- Logs: `D:/geteco/mountain-breakables-test-production-final.log` e `D:/geteco/mountain-breakables-regression.log`.

## Performance e apresentação: pendentes

O medidor existente `tests/measure/measure_terrain3d_mountain.gd` completou a amostra anterior às mudanças: RTX 4060 Laptop, Vulkan Mobile, 1280×720, 30,003 s, 4074 frames, 135,79 FPS, p50 6,981 ms, p95 10,259 ms, p99 13,812 ms, máximo 33,527 ms. Um frame acima de 33,3 ms e nenhum acima de 66,7 ms. Dados brutos em `evidence/terrain3d-mountain/after-39876/report.json`; o nome `after` é fixado pelo medidor de terreno, mas esta execução precedeu a integração dos objetos. Outras sessões de Godot estavam abertas, portanto esta amostra não é uma referência isolada.

A tentativa de comparação foi interrompida ao identificar outros dois benchmarks renderizados concorrentes. Apenas os processos desta tarefa foram encerrados. Não há aprovação de performance nem comparação válida antes/depois. A rota do medidor é a pé e também não mede o pico de fratura durante colisões.

Faltam percurso renderizado com impactos e destroços, observação temporal dos postes destruídos durante o ciclo de iluminação e comparação isolada de frame time incluindo impactos sucessivos e recuperação. Meta provisória: 60 FPS / 16,67 ms; aumentos superiores a 5% em p95/p99 exigem confirmação equivalente. Preservar os saves e processos de outras sessões.
