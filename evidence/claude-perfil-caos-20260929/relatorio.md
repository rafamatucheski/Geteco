# Perfil do passo de física no caos (29/09/2026)

Autor: Claude. Cena: roteiro de recuperação do Codex (aquecimento 8 s, normal 30 s, caos 35 s, cessação 60 s;
semente 20260929, `--no-save --skip-arrival --benchmark --population=40`), renderizado, Vulkan/RTX 4060 Laptop,
uma instância de Godot por vez (o editor do usuário ficou aberto, ocioso). Instrumentação só numa **cópia isolada**;
a árvore compartilhada recebeu apenas a otimização final (2 arquivos).

## O que os quadros lentos são

`run1` (sem instrumentação, árvore atual): no caos 196 quadros >26 ms; **186 têm 2 ou mais passos de física**
e GPU/CPU de render pequenas (GPU p99 8 ms, CPU de render p99 4 ms). Na cessação, 278 de 282. Ou seja: o quadro
não cabe em 16,7 ms porque o **passo de física** (scripts + passo nativo) passa de ~12 ms, e o motor roda 2 passos
para alcançar. GPU não é o gargalo neste cenário. A mediana do caos é 16,9 ms (teto do vsync de 60 Hz); a perda para
~54 FPS vem da cauda (~3–10 % dos quadros).

## Onde o passo gasta (cópia instrumentada, médias por passo no caos; o timer infla ~25 %, use proporções)

| Seção | ms/passo | observação |
|---|---:|---|
| `Vehicle._physics_process` (≈45 carros) | 4,3–5,9 | dos quais: |
| — efeitos de veículo (`effects.physics_tick`) | 0,85–1,6 | pneu 0,55–1,2 · escapamento 0,13–0,26 · impacto ~0,05 |
| — direção do trânsito (`_drive_traffic`) | 1,4–1,6 | rota/junção/sensor ≈ 0,7 |
| — `move_and_slide` | 0,7–1,1 | |
| — `StreetPhysics.vehicle_pre_move` | 0,7–1,0 | |
| `Actor._physics_process` (≈41 pessoas) | 1,8–2,5 | |
| passo nativo da física | não medido aqui | |

Picos (ticks com Vehicle+Actor ≥ 9 ms, 587 em ~8000): dominados por `_drive_traffic` (318) e efeitos (267).
Custos de **primeiro uso** raros e altos: `fx.impact` 12,7 ms num único passo (criação do emissor de faíscas),
`fx.tire` 8,5 ms num passo (emissor de fumaça/áudio de derrapagem).

## Otimização aplicada (só apresentação, sem tocar gameplay)

- `gameplay/vehicle_effects/VehicleTireEffects.gd`: validade das marcas checada a cada 0,25 s (e nunca com a lista
  vazia) em vez de todo passo com `filter` + lambda; ao ficar inativo, para emissores e zera contatos **uma vez**, não
  a cada passo (alocava dois dicionários por passo por carro).
- `gameplay/vehicle_effects/VehiclePowertrainEffects.gd`: `_update_exhaust` regravava ~9 propriedades do material de
  partículas a 60 Hz; agora 10 Hz, com atualização imediata no arranque (punch) e na troca marcha-lenta/andando.

Medido na cópia instrumentada (cenário equivalente: 10 unidades, 4 policiais, 6 estrelas, 4 explosões nos dois):

| ms/passo | antes | depois |
|---|---:|---:|
| `fx.tire` | 0,98–1,18 (janelas de 10 s) | 0,47–0,67 |
| `fx.power` | 0,21–0,26 | 0,08–0,11 |
| `Vehicle` total | 5,3–5,9 | 3,5–4,3 |

Sem instrumentação, caos de 35 s (2 execuções depois vs. execuções anteriores da mesma árvore):

| | FPS | p95 | p99 | quadros >33 ms |
|---|---:|---:|---:|---:|
| antes (run1, probe1–3, probe7) | 53,5 / 51,5 / 54,8 / 53,1 / 56,1 | 26,6–31,0 (run1, probe7) | 33–46 | 64 (run1), 33, 17 |
| depois (run2, run3) | 59,0 / 56,8 | 18,6 / 24,5 | 27,2 / 33,9 | 8 / 22 |

Direção consistente (~+4 FPS, p95 −6 a −12 ms), **mas são 2 execuções contra ~5** e a variação entre execuções
da mesma árvore é de ±2 FPS: não trate como ganho medido com precisão. O ganho por passo na cópia instrumentada
(tabela anterior) é o número mais confiável.

## Verificação

`test_vehicle_effects` (40 checagens; uma falhou na 1ª tentativa por eu atrasar a troca marcha-lenta/andando — corrigido),
`test_regions`, `test_bridge_approach_terrain`, `test_native_driving`, `cold/test_admission`: passam.
Não verifiquei visualmente a fumaça de escapamento/derrapagem em jogo.

## O que não foi resolvido

- Um bloqueio de 857 ms na fase normal de `run1` (quadro 1211, 8 passos de física em seguida). Não reproduziu
  em `run2`/`run3`; sem sonda de chunk nessa execução, causa desconhecida (candidatos: build síncrono de chunk do porto).
- Próximos custos por passo, em ordem: direção do trânsito (~1,4 ms), `move_and_slide` + `pre_move` (~1,5 ms; `pre_move`
  percorre todas as pessoas por carro), atores (~2 ms), criação de emissores no primeiro uso (picos de 8–13 ms).
- Não medi o passo nativo da física (colisões/ilhas: ~70 corpos ativos, 300–390 pares); é a fatia que falta para fechar a conta.
