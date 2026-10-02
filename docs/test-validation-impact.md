# Seleção de testes por impacto

Mapa para os perfis de `tests/Runner.Common.ps1`. Os conjuntos são seleções explícitas; sua duração varia por cenário e ambiente. Verifique a janela de execução antes de iniciar Godot.

| Impacto | Começar pelo caso diretamente afetado | Ampliar quando | Conjunto preparado |
|---|---|---|---|
| Regras, rotas e despacho | `test_dispatch_rules` para regras/grafo; `test_dispatch_lifecycle` para cancelamento, suspensão e limpeza; `test_dispatch_emergency` para atendimento | A alteração atravessa despacho, equipes, incidentes ou perseguição integrada | `dispatch`: 8 casos |
| Geografia, admissão e streaming | `test_regions` e `test_bridge_approach_terrain` para composição/acesso; `test_admission` ou `test_admission_integration` para admissão; `test_region_vehicle_suspension` e `test_persistent_vehicle_support` para suporte de corpos | Mudam residência, colisão, carregamento/liberação ou fronteiras regionais; incluir `test_pursuit_region_seam` se alcançar continuidade da perseguição | `streaming`: 7 casos |
| Condução, carroceria e motorista | `test_native_driving` ou `test_vehicle_floor_contact` para movimento/piso; `test_vehicle_body_transitions`, `test_vehicle_doors` ou `test_seated_driver` para embarque/apresentação | O fluxo chega à transferência da garagem ou modifica contratos compartilhados do veículo/motorista | `vehicles`: 6 casos |
| Garagem e transições | `test_maciota_transition_safety` para proteção/transição; `test_garage_rewards` para recompensas; `test_garage_driver_restore` para restauração; `test_garage_vehicle_transfer` para transferência | A mudança atravessa entrada, saída, motorista, veículo persistente ou regras da garagem | `garage`: 4 casos |

Use o teste ligado à propriedade alterada como primeiro portão. Um conjunto completo é apropriado para uma mudança que alcança várias dessas propriedades. O tamanho do diff, sozinho, não define o impacto.

Exemplos na raiz do projeto, em janela livre:

```powershell
# Regra ou grafo de despacho: um caso, uma execução.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_suite.ps1 -Only test_dispatch_rules

# Fronteira entre piso e veículo: dois casos específicos.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_suite.ps1 -Only 'test_region_vehicle_suspension,test_persistent_vehicle_support'

# Mudança compartilhada de streaming: conjunto de integração preparado.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_suite.ps1 -Impact streaming
```

`-Filter`, `-Only` e `-Impact` se combinam por **interseção**. Para combinar casos de conjuntos diferentes, use uma lista explícita em `-Only`. Não acrescente `-Impact` se ele excluir um caso necessário. Não execute também `tests/dispatch/Run.ps1` sobre os mesmos casos nessa rodada: ambas as entradas compartilham o contrato, e a suíte geral já executa cada caso selecionado uma vez.

Os perfis não abrangem todo o jogo. Mudança de save exige os casos específicos de persistência, como `test_full_save`, além do fluxo afetado. Iluminação, chuva, oclusão, áudio temporal e desempenho exigem validação própria; um perfil funcional aprovado não cobre essas propriedades.

`test_pursuit_region_seam` cobre uma resposta inicialmente preparada e a travessia dirigida de Harbor para Mountain. Não comprova latência natural do despacho nem a volta dirigida. Mudanças que alcançam esses fluxos precisam de casos adicionais com viatura, física, colisão e perseguição produtivas.

## Contratos locais de mundo

`-Impact world-contracts` seleciona somente cinco casos: equivalencia do indice, yield urbano, foco de startup, ownership de caches e variantes de pecas. Eles nao medem FPS, colisao em conducao ou RAM liberada. Para uma correcao local use `-Only` com o caso afetado; amplie para `streaming` quando houver residencia, suporte fisico ou continuidade regional. Nao execute os mesmos casos novamente em outro runner.

Para custo/lifecycle, `tests/measure/measure_region_lifecycle.gd` exige Main renderizado, `--no-save`, `--isolated-save-root=<diretorio novo vazio>` e `--pilot-label=<id unico>`. Mantem fisica, transito, 40 NPCs e saude normal; mede warmup5s/caminhada30s e tres pares de viagens produtivas. O limite externo720s protege os gates80s de startup/recomposicao e15s por viagem; e um teto de seguranca, nao promessa de duracao. Viagem por API mede lifecycle e admissao, nao travessia continua por conducao. WorkingSet opcional e capturado fora das fases com `--pilot-process-ram`; progresso e roteado explicitamente pelo piloto, Settingsautoload ficam normais.

## Parar ou avançar

1. Fixar hipótese, propriedade esperada, fontes/dependências relevantes e seleção antes de executar. Nenhum teste selecionado, nome inexistente ou contrato incompleto reprova o portão.
2. Falha: ler logs e classificar a causa antes de repetir. Alterar o código ou a hipótese diagnóstica; preservar a falha anterior. Após duas falhas equivalentes sem progresso, mudar a investigação.
3. Sucesso: reutilizar a evidência enquanto fontes, dependências e condições relevantes permanecerem compatíveis. `SourceChanged=null` nos metadados significa comparação incompleta; exige conferência das dependências antes de reutilizar a rodada.
4. Avançar para integração apenas se a mudança alcançar outra fronteira. Não repetir os mesmos casos pelo outro runner. Rodada ampla fica para integração acumulada ou entrega, conforme o risco.
5. Alteração de custo em runtime: medir a cena real renderizada em janela livre, com configuração e carga equivalentes, sistemas produtivos ativos e transições pertinentes. Registrar primeira visita/retorno, p95/p99, picos e carga efetiva. Nenhum tempo de execução ou ganho de FPS é prometido por este mapa.

`test_city_streaming_budget` acrescenta o contrato de yield e retomada ao primeiro portão. Exercita o escalonador produtivo com chunk vazio fora da árvore; não mede milissegundos nem substitui piso, perseguição e desempenho.
