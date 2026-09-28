# Acabamento e luzes da frota — 28/09/2026

O gerador da V2 (`FleetCatalog.create`) aplica `VehicleFinish` sobre as cenas exportadas. Os arquivos `.scn` e os modelos arquivados da V1 não foram regravados.

- Cabines reconstruídas: Union, Sedan Classic, Metro, Ranch Single, Ranch Pickup, Lumber Pickup, Courier, Polar e transporte policial. Para-brisas inclinados, janelas delimitadas por colunas e vidros expostos na superfície da carroceria. O bloco que cobria o para-brisa do Courier foi substituído.
- Painéis procedurais em caixa ganham bordas chanfradas. Pintura recebe verniz; vidro recebe material separado, brilho e faixas suaves de reflexo estilizado. Essas faixas não são reflexos de objetos da cena. O material continua respondendo às luzes, sem probes ou SubViewports adicionais.
- Superfícies agrupadas preservam caçamba, santantônio, cromados, piscas e rodas. Lanternas traseiras que estavam enterradas são assentadas pela interseção com a geometria da lataria.
- Faróis usam o centro real das lentes, inclusive quando os vértices estão deslocados da origem do nó. Tags `material_role`, `material_key` e suas listas por superfície são reconhecidas.
- Freio funciona nas malhas agrupadas, incluindo Arctic/Desert Jeep, na terceira luz do Metro e no cupê. A lanterna fica forte ao frear, fraca com luzes ligadas e apagada no veículo estacionado ou destruído. Desaceleração do trânsito tem retenção de 150 ms para evitar cintilação entre ticks de física.
- Materiais de luz são individuais por carro. Malhas, vidro e acabamento são compartilhados em cache; as propriedades da lanterna só são atualizadas quando o estado muda.

## Validação funcional e visual

Godot 4.7.2, testes diretos com `--headless --path D:/geteco/game --script res://tests/<arquivo>.gd`:

| Teste | Resultado |
|---|---|
| `test_fleet_finish.gd` | 619 checks; 49 modelos de rua, orientação dos fachos, freio, isolamento entre instâncias, desaceleração, pintura, geração idempotente e exposição de janelas/lanternas |
| `test_traffic_headlights.gd` | 45 checks aprovados |
| `test_vehicle_equipment.gd` | 41 checks aprovados |
| `test_vehicle_damage_look.gd` | 104 checks aprovados |
| `test_fleet_fixups.gd` | aprovado; preservação dos fixups e pivôs das motos |

A empilhadeira não entra no contrato de iluminação rodoviária. Os testes antigos de equipamentos foram atualizados para acessar os registros atuais (`item.material` e `item.lamp`), mantendo as verificações de comportamento.

Capturas: `evidence/fleet-finish-20260928/gallery/`. O script `tests/capture/capture_fleet_finish.gd` captura modelos em cinco ângulos; a opção `--brakes` usa o veículo real com equipamento, nos estados apagado, freio e faróis. Revisados Union, Metro, Ranch, Courier, Arctic, Aurora, Station Wagon e cupê, além das capturas integradas de dia/noite. A galeria não mede FPS.

## Desempenho: pendente de comparação isolada

Cena real `Main.tscn`, cruzamento da delegacia, RTX 4060 Laptop, Mobile/Vulkan, 1280×720, VSync desligado, limite observado de 144 FPS. O harness preserva as configurações locais e usa `--no-save --benchmark`. Cada cenário tem 8 s de aquecimento e pelo menos 30 s de amostras reais. Referência provisória: 60 FPS / 16,67 ms; aumento superior a 5% nos percentis exige investigação.

| Versão/cenário | FPS médio | p95 ms | p99 ms |
|---|---:|---:|---:|
| Antes / dia | 103,83 | 16,44 | 35,53 |
| Primeira revisão / dia | 99,29 | 15,44 | 17,24 |
| Antes / noite e chuva | 64,06 | 18,55 | 26,35 |
| Primeira revisão / noite e chuva | 67,15 | 19,75 | 29,08 |
| Final / dia, carga concorrente | 64,16 | 43,53 | 73,01 |
| Final / noite e chuva, carga concorrente | 40,76 | 46,98 | 143,91 |

Há processos Godot de outras sessões consumindo CPU simultaneamente, variação na população do trânsito e alterações concorrentes no mundo. A primeira revisão apresenta aumento de 6,5% no p95 e 10,4% no p99 noturno. Isso não foi tratado como aprovação. Na confirmação da versão final, após evitar atualizações redundantes de material, houve piora substancial: 143 quadros acima de 33,3 ms de dia e 110 à noite; 30 e 42 quadros acima de 66,7 ms, respectivamente. Os dados estão em `evidence/fleet-finish-20260928/final/`. O orçamento de 60 FPS não foi atendido nessa medição; a causa não está isolada.

Os JSONs em `before/`, `after/` e `final/` guardam todos os intervalos, contagens acima de 33,3/66,7 ms, máximo, aquecimento, GPU, renderer e configuração. Há picos de aquecimento superiores a 1 s já no baseline. As amostras não isoladas não permitem atribuir a variação aos carros, nem certificar ausência de regressão. É necessário repetir a comparação com carga externa estável; nenhum processo de outra sessão foi encerrado.

As execuções headless restritas exibiram avisos de escrita do log/certificados do ambiente. Capturas e benchmarks renderizados também registram avisos de liberação de textura no encerramento, presentes desde o baseline. Esses avisos são distintos dos resultados funcionais.
