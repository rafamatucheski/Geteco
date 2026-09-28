# HUD compacta e câmera diagonal — 25/09/2026

O minimapa passa de 192 para **156 px de largura**, com fundo grafite/violeta,
ruas em marfim, jogador ciano e destino amarelo. O quadrado do mapa mantém essa
largura em diferentes resoluções; abaixo dele ficam navegação, clima, horário e
bússola. O rodapé de navegação só aparece com destino. Sem destino, o conjunto
mede 156 × 180; com destino, 156 × 204 (o mapa continua sendo 156 × 156).

Vida, colete e arma/munição surgem juntos acima do mapa ao mirar, atacar,
recarregar ou receber dano. A entrada dura 240 ms; após cinco segundos sem ação,
o bloco recolhe em 320 ms. Vida entre 1 e 25 permanece visível. O minimapa não
muda de posição durante essa animação. Estrelas aparecem acima do bloco apenas
com nível de procurado maior que zero, sem estrelas vazias; permanecem durante
a busca mesmo quando o combate recolhe. Dinheiro aparece por três segundos após
mudança no saldo e continua consultável no inventário.

A indicação térmica funcional existente foi preservada, assim como o selo do
Neco e o cache multirregional que já estavam em edição no workspace.

## Navegação e custo

O mapa usa desenho vetorial e cache de geografia, sem câmera adicional ou
SubViewport. Posição e direção atualizam até 30 vezes por segundo; parado, sem
mudança visual, não há solicitação de redesenho. O zoom abre gradualmente com a
velocidade do veículo.

O GPS lê o grafo dirigido existente, sem alterá-lo nem construir outro grafo de
interseções. Recalcula após movimento relevante, mudança de destino/região ou
troca de modo a pé/carro, com intervalo de 750 ms para movimento. O traçado segue
ruas conhecidas e respeita mão única. A distância de navegação inclui o trecho
até o acesso ao destino; quando não há rota conhecida, aparece só a distância
direta e o marcador, sem inventar uma ligação atravessando prédios. Os últimos
metros fora da malha viária não recebem uma rota pedestre certificada.

## Testar a câmera

**Esc → Configurações → Vídeo → Câmera → Diagonal (experimental)**. Salvar mantém
a preferência; Cancelar restaura a anterior. Também é possível iniciar uma
sessão de teste com `--camera-preview` após o separador `--` do Godot.

A opção gira o ponto de vista exterior em 45° e usa inclinação aproximada de
37,5°, com transição de meio segundo. A projeção continua ortográfica. O modo
Original permanece como padrão. A câmera bloqueada dos interiores mantém seus
offsets e enquadramentos existentes; nenhum ambiente ou sólido foi reformado.

## Evidência

Arquivos em `evidence/compact-hud-20260925/`. As imagens são capturas reais de
`Main.tscn`, não os conceitos gerados durante a discussão. Todas as execuções
usaram `--no-save --skip-arrival`; nenhuma preferência foi gravada pelo teste.

- `tests/test_compact_hud.gd`: integração real da HUD, GPS, clima/horário,
  câmera, menu, pausa, saúde crítica, perseguição e entrada na garagem.
- `tests/test_camera_rig.gd`: contratos anteriores da câmera aprovados, incluindo
  suavização de altura, mira, troca para veículo e câmera bloqueada.
- `tests/measure/measure_compact_hud.gd`: Main renderizada, semente 25092026,
  população 24, aquecimento de oito segundos e amostra de aproximadamente trinta
  segundos por cenário. Relatórios guardam intervalos de cada frame, p50/p95/p99,
  máximo e contagens acima de 33,3/66,7 ms.

Hardware medido: RTX 4060 Laptop, Godot 4.7.2, Mobile, 1280 × 720, VSync ligado e
limite de 60 FPS. Meta provisória: 60 FPS; tolerância de comparação de p95/p99:
5%, conforme a skill. Não é certificação de todas as regiões ou GPUs. O tráfego
é real e sua contagem pode variar ligeiramente entre amostras.

O cenário noturno de `final/report.json` é **inválido para comparação**: a captura
mostra o jogador fora do carro e em combate. O harness foi corrigido para limpar
bindings apenas no processo de medição e verificar que o motorista continua
embarcado. Os resultados anteriores não foram apagados.

### Comparativo renderizado

| Cenário | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | Frames >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes, caminhada | 59,78 | 16,68 | 17,37 | 17,89 | 97,26 | 2 / 2 |
| Depois, caminhada | 60,00 | 16,67 | 17,50 | 18,13 | 21,23 | 0 / 0 |
| Antes, veículo/noite/chuva | 60,00 | 16,63 | 17,58 | 18,09 | 23,87 | 0 / 0 |
| Depois, veículo/noite/chuva | 60,00 | 16,68 | 17,38 | 17,87 | 22,43 | 0 / 0 |
| Câmera diagonal, caminhada | 60,00 | 16,72 | 17,59 | 18,04 | 19,22 | 0 / 0 |

Fontes: `before/report.json`, `lower-weather/report.json` e
`diagonal/report.json`. O p99 da caminhada aumentou 1,4%; o cenário noturno
melhorou 1,2%. Sem regressão acima de 5% nesses cenários. A câmera diagonal
também manteve o alvo de 60 FPS nesta rua. Isso não significa folga de GPU sem
VSync nem aprovação de trajetos longos por outras regiões.

O aquecimento foi contabilizado separadamente: máximos de 86,0/80,2 ms antes,
39,2/44,7 ms depois (caminhada/veículo), e 38,2 ms na câmera diagonal. A compilação
e o pré-aquecimento inicial das regiões duraram cerca de 8–10 segundos e não
foram misturados ao regime estável. Não se declara ausência de travamentos de
primeira visita. O benchmark da câmera diagonal já inclui a bússola no rodapé;
o de `lower-weather` antecede apenas a transferência do glifo da bússola para o
rodapé, conferida também na validação visual final.

### Regressões

`test_compact_hud.gd`: **53 verificações, zero falhas**, em Main renderizada,
`verified.log`, com cinco capturas. Inclui o rodapé final com clima, horário e
bússola; retirada do destino ao terminar a introdução; GPS real; estados de
combate/perseguição; resoluções 1024 × 768 e 1920 × 1080; seleção e cancelamento
da câmera no menu; proteção da câmera e arma guardada na garagem. A tentativa
`delivery.log` revelou uma preparação incorreta do teste: `intro.stage` é uma
propriedade derivada, e atribuí-la não conclui a introdução. O teste foi corrigido
para restaurar um snapshot validado pela API de progressão; nenhuma asserção
foi removida ou afrouxada.

`test_video_phase3_hud.gd`: **41 verificações, zero falhas**, em headless,
`regression.log`. Verificou embarque/desembarque real, visibilidade do mapa,
pausa/modal, restauração após morte e feedback de salvamento usando arquivo
isolado. O erro de diretório em `regression.err` é a falha de disco provocada
pelo próprio teste; a asserção de tratamento desse erro passou.

Comandos utilizados (executável Godot 4.7.2 local):

```text
--path D:/geteco/game --script res://tests/test_compact_hud.gd -- --no-save --skip-arrival --population=24
--headless --path D:/geteco/game --script res://tests/test_camera_rig.gd
--headless --path D:/geteco/game --script res://tests/test_video_phase3_hud.gd -- --no-save --skip-arrival --output-dir=D:/geteco/game/evidence/compact-hud-20260925 --label=regression
--path D:/geteco/game --script res://tests/measure/measure_compact_hud.gd -- --no-save --skip-arrival --population=24 --variant=lower-weather
--path D:/geteco/game --script res://tests/measure/measure_compact_hud.gd -- --no-save --skip-arrival --population=24 --variant=diagonal --preview
```

Há aviso de liberação de texturas/RIDs ao encerrar o renderer, presente também
no baseline anterior às alterações. Isso não foi tratado como falha nova da HUD
nem como comprovação de ausência de vazamentos.
