# Casas compráveis — 28/09/2026

Escopo: Westgate Garden, Quayside e Canal North; três fachadas e três interiores
existentes. A compra continua usando a regra de residência ativa e troca com
crédito de 70%. Nenhuma alteração nas casas dos caminhoneiros.

- Porta física e admissão ficam bloqueadas antes da compra.
- Garagem aberta junto à casa, uma vaga persistente de carro e uma de moto.
  A cobertura se oculta por presença e revela as vagas ocupadas, sem loop por frame.
  Guardar exige parar, caber na vaga e concluir o desembarque real. Retirar
  exige piso e volume livres. Veículos pessoais/de missão protegidos mantêm
  suas restrições; inventário do Maciota não é concedido pela residência.
- Guarda-roupa usa as roupas já possuídas e aplica a aparência ao personagem.
- Geladeira oferece refeição (+35 vida) e suco (+15), limitados pela vida máxima.
  Mantém o serviço doméstico gratuito que já existia; não consome a mochila.
- Mesa com caderno salva manualmente, pelo fluxo de save existente, incluindo
  feedback de falha. Cama e arsenal continuam disponíveis nos próprios móveis.
- Baú físico tem 24 tipos de item, até 99 unidades por tipo, com persistência.
  Fica bloqueado enquanto não houver integração com a mochila desbloqueada.

## Contrato para a mochila em desenvolvimento

Os arquivos `systems/inventory/` do Antigravity foram preservados. O adaptador
da mochila deve registrar seu provedor na sessão:

```gdscript
session.residence_services.storage.bind_inventory(backpack_provider)
```

O provedor implementa:

- `is_backpack_unlocked() -> bool`: consulta o desbloqueio real, não a roupa.
- `storage_items() -> Dictionary`: `{id: {label: String, count: int}}`.
- `remove_storage_item(id, count) -> bool` e `add_storage_item(id, count) -> bool`:
  transações atômicas; `false` não altera o inventário. A mochila decide capacidade,
  identidade e quais itens podem ser transferidos. IDs usam identificadores estáveis.

A mochila deve integrar sua persistência ao mesmo `FullSession.save_game()` antes
de registrar o provedor. O baú só altera seu saldo após uma transferência aceita;
mochila cheia, inexistente ou bloqueada não perde nem cria itens. O teste usa um
provedor controlado para este contrato; isso não certifica a mochila futura.

Saves antigos recebem baú e vaga de moto vazios. Uma moto no slot único legado é
migrada para a vaga correta, mantendo seu estado. `stored_vehicle` continua sendo
a chave compatível do carro; `stored_motorcycle` é a chave adicional.

## Evidências e validação

Pasta: `evidence/residence-living/`. Teste de integração:
`tests/test_residence_living.gd -- --no-save --skip-arrival --population=8`.
Usa a Main real, saves exclusivamente nessa pasta e não lê a partida do usuário.
Sem `--headless`, também produz fotos de profundidade de jogador e NPC.

Medição: `tests/measure/residence_living.gd -- --no-save --skip-arrival --benchmark
--population=40 --label=before|after|final`. Seis cenários (exterior/interior de
cada casa), aquecimento separado e 30 segundos de intervalos reais por cenário.
GPU de referência: RTX 4060 Laptop, Mobile, janela 1280×720. Meta provisória:
60 FPS / 16,67 ms; aumento superior a 5% de p95/p99 exige investigação.

**Implementação funcional verificada; certificação integral pendente.** As outras
instâncias Godot foram preservadas. O estacionamento final fica à esquerda em
Westgate/Quayside e à direita em Canal North, fora da árvore e da rua.

Resultados:

- `functional-fixed.log`: 333 checks aprovados, incluindo compra, passagem,
  cura, save e colisão varrida de jogador/NPC. O desembarque foi corrigido para
  terminar antes de esconder o veículo; foco adiado usa referência fraca.
- `parking-final.log`: 75 checks aprovados nas três casas, incluindo save completo,
  reconstrução de carro/moto e bloqueio de retirada duplicada.
- `verified.log`: 418 checks aprovados na Main renderizada; a única falha foi da
  fixture de migração (moto com vida 100, acima da durabilidade real 55). A fixture
  foi corrigida para 45; `storage-final.log` confirma **11/11**, incluindo migração
  da moto antiga e rejeição de carro no slot de moto. O restante da execução
  renderizada passou, inclusive compra na soleira, roupa possuída/não possuída,
  teto por presença, saves, interação normal e fotos de profundidade.
- Regressões independentes: garagem **47/47**, save completo **PASS**, conversão V1
  **42/42** e profundidade/silhueta **19/19**. Logs nomeados por teste nesta pasta.
- `activities/test_activities.gd`: falhou em requisitos de rotas legadas e numa
  fixture de guincho sem `session.state.campaign`, fora das mudanças residenciais.
  Não foi ajustado nem apresentado como aprovado.
- Uma edição concorrente de `runtime/ProductionWorld.gd`, às 12:51, duplicou
  `CANAL_TUNNEL` nas linhas 6 e 11. A Main passou a falhar no parse. Esse arquivo
  foi preservado e o usuário foi avisado. A regressão adicional de motorista e
  transferência da garagem não foi executada após esse bloqueio. Uma tentativa
  de foto/ajuste posterior foi interrompida; a geometria entregue permanece a
  configuração já verificada em `verified.log`.
- Execuções renderizadas registram retenção de textura no encerramento, também
  presente no baseline; não houve erro de script residencial na Main verificada.

Comparativo diagnóstico (30 s por cenário, RTX 4060 Laptop, Mobile, 1280×720,
40 pedestres solicitados, limite efetivo **144 FPS**, VSync desligado nas duas
execuções por configuração já carregada do usuário):

| Cenário | FPS antes → final | p95 ms antes → final | p99 ms antes → final |
|---|---:|---:|---:|
| Westgate exterior | 138,7 → 142,4 | 12,36 → 12,19 | 14,54 → 13,36 |
| Westgate interior | 141,8 → 144,0 | 12,67 → 12,09 | 13,64 → 12,73 |
| Quayside exterior | 93,3 → 72,8 | 18,09 → 18,84 | 30,84 → 29,00 |
| Quayside interior | 123,1 → 139,8 | 13,70 → 12,94 | 15,80 → 13,92 |
| Canal North exterior | 92,0 → 109,5 | 15,15 → 12,67 | 29,05 → 17,14 |
| Canal North interior | 126,9 → 129,3 | 13,95 → 13,35 | 19,16 → 29,24 |

**Desempenho não aprovado.** Quayside perde FPS médio, Canal North piora p99
interior e registra hitch exterior de 1.139 ms (12 frames >33,3 ms; 8 >66,7 ms).
Outras execuções Godot estavam presentes e variaram durante os comparativos;
não há atribuição causal demonstrada às casas. `before.json`, `after.json` e
`final.json` preservam todas as amostras, duração, frames, p50/p95/p99, máximos e
contagens. O alvo de estabilidade permanece pendente; não se aprovou FPS por foto,
limite de quadros ou teste headless. Primeira visita também não foi certificada.

Fotos reais finais: `final-*-exterior.png`, `final-*-interior.png`, `parked-*.png`,
`menu-*.png` e `depth-*.png`; anteriores: `before-*.png`. As fotos de profundidade
cobrem baú, mesa, armário e cozinha, com controle visual positivo de jogador/NPC;
não certificam todos os ângulos de todos os móveis legados.
