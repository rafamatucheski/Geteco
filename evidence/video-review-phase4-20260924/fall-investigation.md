# Investigação da queda do veículo — fase 4

## Estado

**Queda original de 02:21–02:23 ainda não reproduzida; não declarar corrigida.** Os dois diagnósticos iniciais abaixo não alteraram runtime. Posteriormente, a revisão do frete demonstrou uma causa distinta de snapshot abaixo do chão, documentada ao final. Os patches das fases anteriores permanecem presentes.

## Evidência do vídeo

- A gravação começa em **Continuar**, com uma partida anterior; o estado inicial completo não está disponível no vídeo.
- O sedan azul usado na Ammu-Nation/banco é distinto da silhueta branca vista no embarque após o resgate. O modelo branco é visualmente compatível com um cupê, mas o vídeo não prova seu identificador ou archetype.
- Após morrer no banco, Dante retorna à região do Maciota e aborda um veículo junto de um caminhão na Westgate. A silhueta aparece por baixo/atrás do caminhão; depois, o cenário sobe na tela e o veículo aparece no vazio com velocímetro em zero. Isso é compatível com queda vertical. Não prova, isoladamente, o instante em que o piso foi perdido.
- Reconstrução usa `sport_coupe` em `(26.7, 0.12, 109)` como preparação explícita, aproximada a partir do vídeo. Não é replay determinístico do save gravado.

## Cenário de suporte e transições

`tests/video_phase4_fall_probe.gd` carrega Main real, mantém o cupê físico e conduz outro veículo até a Ammu-Nation. Abre/fecha o interior, volta de ré pela via até o banco, entra, aplica morte pelo Gameplay, aguarda resgate real e embarca no cupê novamente. Setup a pé nas portas usa teleporte explícito; o deslocamento do sedan usa motor, direção e colisão normais. Tráfego e despacho aleatórios estão desligados para isolar a hipótese.

Resultado: **3.327 frames físicos, 12 verificações aprovadas, zero falhas**, `exit 0`. Altura do cupê: mínimo `0.000219 m`, máximo `0.114444 m` no assentamento inicial. Depois de assentado, a posição permaneceu `(26.7, 0.000219, 109)`. Todos os registros de raycast encontraram `HarborNativeRegion/Chunk_0_1/Land`.

Ammu-Nation/banco usam células `(1,0)`/`(0,0)`, e o cupê usa `(0,1)`. A retenção normal de duas células conserva o piso do cupê nesse trajeto. Assim, a hipótese de que **somente** esse ciclo retiraria seu piso não se confirmou no runtime atual.

Arquivos: `fall-route-probe.json` (amostras, estado físico, foco e piso) e `fall-route-probe.log`. A primeira trajetória de teste bloqueou numa curva; `fall-route-fixture-blocked.json` documenta essa preparação inválida, que não vale como resultado do ciclo.

## Cenário de contato com caminhão

`tests/video_phase4_truck_probe.gd` usa o mesmo Main e ponto Westgate. São seis impactos reais: `cargo_flatbed_truck` e `towmaster`, cada um no eixo do cupê e com deslocamento lateral de ±0,9 m. Os corpos começam separados; o caminhão aproxima com motor e velocidade inicial de 11 m/s, colide normalmente e freia após o contato. Não há teleporte para sobreposição nem impulso artificial.

Resultado: **6 impactos confirmados, 18 verificações aprovadas, zero falhas, exit 0**. O caminhão de carga empurrou o cupê cerca de 4,48 m e o guincho cerca de 2,81 m; todos os cupês permaneceram apoiados acima do solo. O contato foi confirmado também pela perda de saúde, de 80 para 75,67/76,48. Não foi reproduzida a sobreposição vertical do vídeo nesses contatos.

Arquivos: `fall-truck-probe.json` e `fall-truck-probe.log`. Para reproduzir, use os mesmos argumentos abaixo, substituindo o script por `res://tests/video_phase4_truck_probe.gd` e o nome do log por `fall-truck-probe.log`.

## Reprodução

Godot 4.7.2; a partir da raiz do projeto:

```text
Godot_v4.7.2-stable_win64_console.exe --headless --path D:/geteco/game --log-file D:/geteco/game/evidence/video-review-phase4-20260924/fall-route-probe.log --script res://tests/video_phase4_fall_probe.gd --fixed-fps 60 --max-fps 0 -- --no-save --no-traffic --population=0
```

`--fixed-fps` acelera o relógio da simulação; **nenhuma métrica de FPS/performance foi coletada ou aprovada**. Saves do usuário não são escritos, e seus processos não são encerrados. Não houve alteração da física para fabricar uma aprovação. Ambos os processos de diagnóstico encerraram; ao final só os processos do usuário 76560/86396 permaneciam. Hashes do código usado estão em `fall-source-hashes.json`.

## Limites

Ainda faltam o save inicial exato, histórico físico anterior à gravação, identidade do veículo branco e contato exato com o caminhão. A reconstrução não reproduz todo o tráfego, ataques policiais ou colisões aleatórias do vídeo. A correção da fase 3 (impulso residual/retomada de IA) resolve causas demonstradas diferentes; não comprova solução da queda abaixo do mapa.

## Novo defeito demonstrado: carro anterior salvo abaixo do chão durante o frete

O checkpoint real `phase4-port-depot-save.json`, na pasta de artefatos da revisão, continha o `player_coupe` anterior em `(46.875, -0.416447, 108.5)`, saúde 80. Esse dado foi produzido durante o fluxo físico de frete, mas sozinho não informava quando o carro perdeu o apoio.

O probe finito `tests/test_video_phase4_port_previous_floor.gd` isolou a ordem responsável em Main real. O cupê inicia sobre piso em Y `0.000219`, continua apoiado enquanto é a seleção do jogador distante, e só perde o piso depois que a seleção muda para um caminhão no porto, a mais de 145 m. `ProductionWorld._update_physical_residency` retira o suporte no frame seguinte; o descarte normal aguarda o relógio de população de 0,25 s. Durante esse intervalo, a gravidade continua agindo. As amostras registram raycast vazio e queda até Y `-0.738670` antes do descarte.

O setup solicita o foco pelo próprio `ProductionWorld`, preservando o suporte da seleção anterior. Não coloca nenhum carro abaixo do piso, não aplica impulso e não chama o descarte diretamente. A troca distante de seleção é uma preparação explícita equivalente ao estado do empréstimo; não é replay do incidente de 02:21.

Comparação causal de snapshot:

- **Ablação da captura anterior:** uma subclasse exclusiva de teste mantém o callback antigo, que copia `FleetState.capture` sem validar apoio. Mesma cena física, 9 verificações, **1 falha esperada**: grava Y `-0.833114`; ID, saúde e equipamento preservados. `previous-floor-legacy.json` / `.log`, exit 1 pela assertion. Não houve reversão de arquivos compartilhados.
- **Runtime corrigido:** `PortFreightDelivery._capture_supported_previous` conserva posição/yaw previamente apoiados quando o raycast não confirma chão e continua copiando saúde/equipamentos atuais. **9/9 verificações aprovadas**, record salvo em Y `0.000219`. `previous-floor-after.json` / `.log`, exit 0. O corpo distante ainda cai brevemente até ser removido; a correção é da persistência, sem reter física longe nem alterar streaming global.

A primeira execução planejada como BEFORE já carregou o patch concorrente; seus arquivos foram corretamente renomeados para AFTER. A baseline causal apresentada é explicitamente a ablação do callback anterior, além do checkpoint histórico `-0.416447`. A execução AFTER emitiu aviso de recursos retidos no encerramento; a ablação terminou sem esse aviso. Ambas encerraram seus processos. Não houve benchmark nem aprovação de FPS.

O teste usa `--headless --fixed-fps 60 --no-save --no-traffic --population=0`; acrescentar `--legacy-capture --label=legacy` reproduz a ablação, e `--label=after` usa o componente atual. A correção do componente pertence à frente do frete. Esta causa nova explica saves de **carros anteriores distantes** contaminados pelo intervalo de descarte; a identidade, partida inicial e queda original do vídeo continuam sem comprovação.
