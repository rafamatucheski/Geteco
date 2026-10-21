# Protótipo de lataria e peças destacáveis — 21/10/2026

Estado de entrega: protótipo habilitado, testes funcionais e revisão visual dos dois pares concluídos. A pedido do usuário, a execução pendente de desempenho e da checagem final de limpeza foi cancelada; ele fará essas avaliações no jogo. Não há aprovação de performance. A última correção de ordem de liberação dos materiais tem sintaxe validada, mas ainda não foi executada no motor.

## Escopo implementado

Peças destacáveis habilitadas no jogo normal para `sport_coupe`, `monaliza`, `metro_hatch` e `police_cruiser`, independentemente de serem dirigidos pelo jogador ou pelo trânsito. Os demais modelos continuam sem peças destacáveis; aqueles que já aceitam amassados também recebem a intensidade e direção do impacto físico. Não é uma conversão de toda a frota.

- A colisão entrega velocidade de aproximação e normal aos dois veículos. A lataria usa esses dados para amassar localmente; os valores de dano de vida continuam com o balanceamento anterior.
- Capô e para-choques dianteiro/traseiro acumulam dano de fixação. Contato leve mantém as peças; batidas fortes ou repetidas podem arrancá-las. Atingir a traseira não arranca o capô.
- Os quatro modelos são preparados offline, preservando pintura, rodas, vidros, lentes e portas. O capô tem face interna; o vão expõe um compartimento mecânico. Suportes dos para-choques permanecem no carro.
- Cada peça solta conserva sua malha amassada e pintura, herda a velocidade do veículo e cai com um colisor simples. Os fragmentos colidem com o mundo, sem bloquear carros/pedestres nem causar dano ou crime.
- Limite provisório de 18 corpos físicos ativos; duração de 22 segundos, seguida de desaparecimento de 0,45 segundo. Os temporizadores respeitam pausa. Descarregar o carro não remove imediatamente sua peça solta; descarregar o mundo a remove.
- O save guarda o dano/ausência por identificador de peça. Fragmentos no chão são transitórios. Saves antigos continuam válidos. Carregar um carro danificado não reproduz o desprendimento; abrir portas não recompõe o capô; reparar recompõe o veículo e remove seus fragmentos associados.

## Limites desta versão

O casco de colisão dirigível conserva sua forma atual; a deformação é geométrica e visual. Portas, rodas, motor e vidros não se destacam neste protótipo. Lentes e luzes funcionais permanecem no corpo do carro. Não há simulação completa de estrutura deformável nem alteração de dirigibilidade por painel perdido.

A preparação offline gera variantes dos modelos atuais. Quando a arte de um desses carros mudar, regenerar com `tools/fleet_fixups/build_breakaway_prototype.gd` e revisar as três zonas de recorte. `assets/fleet/breakaway/manifest.json` registra origem, conservação de área e contagens de geometria.

| Modelo | Triângulos originais → preparados | Superfícies originais → preparadas |
|---|---:|---:|
| sport_coupe | 4.908 → 13.638 | 17 → 27 |
| monaliza | 9.647 → 18.159 | 34 → 51 |
| metro_hatch | 2.580 → 8.384 | 23 → 36 |
| police_cruiser | 4.418 → 10.620 | 26 → 39 |

Essas contagens vêm do bake e não equivalem a custo de frame medido. Malhas intactas são compartilhadas; deformação cria uma malha própria apenas no carro atingido.

## Validação

Geometria aprovada no teste dedicado dos quatro modelos: três painéis por modelo, pintura independente, rodas/lentes preservadas e erro máximo de conservação de área de `6,37e-7 m²`. Bake e teste terminaram com código 0 e sem erros de script. [Logs e resultados](../../evidence/breakaway-validation-20261021/geometry/runner-exit-extract.log).

| Verificação | Resultado |
|---|---|
| `test_vehicle_panel_geometry.gd` | Aprovado, quatro modelos, zero falhas |
| `test_vehicle_breakaway.gd` | Aprovado, 120 verificações, zero falhas |
| `test_vehicle_body_dents.gd` | Aprovado, cinco modelos, deformação geométrica observada |
| `test_vehicle_body_dents_incremental.gd` | Aprovado, três modelos, diferença máxima 0 entre reconstrução parcial e completa |
| `test_vehicle_crash_damage.gd` | Dez verificações aprovadas antes da correção final de limpeza; três mensagens de material nulo no teardown dummy foram isoladas e corrigidas no código, com reexecução cancelada a pedido do usuário |
| `test_vehicle_impact_momentum.gd` | Aprovado, zero falhas |
| `test_vehicle_panel_momentum.gd` | Aprovado, 26 verificações: velocidade de apresentação após o contato, ordem dos eventos, massas diferentes e direção das peças |
| Colisões na Main renderizada | Dois pares, quatro modelos, dois contatos reais por par; zero falhas funcionais; trajetória corrigida aprovada visualmente |
| Recarga pela Main renderizada | Aprovada: estado, portas, reparo e ausência de repetição do desprendimento |
| Comparativo de frame time | Não executado; usuário optou por avaliar o desempenho pessoalmente |

[Log do lote funcional](../../evidence/breakaway-validation-20261021/regressions.log). A primeira tentativa do teste novo teve quatro falhas de fixture: usava um grupo para invulnerabilidade, enquanto o contrato de `DamageProtection` usa a metadata `invulnerable`. O teste foi corrigido conforme esse contrato e a tentativa inicial permanece registrada. A proteção do produto não foi afrouxada. A rodada aprovada também verifica cópia independente de `material_overlay` nas peças soltas.

Os testes headless comprovam contratos; a aparência, o funcionamento integrado na cidade e a performance têm evidências e critérios separados.

O [probe de materiais](../../evidence/breakaway-validation-20261021/panel-rid-probe.log) reproduziu três erros ao destruir imediatamente peças recém-criadas e zero erros mantendo apenas as referências dos materiais até o quadro seguinte, com o mesmo momento de destruição dos nós. A ordem de destruição do motor pode consultar RIDs depois de liberar essas referências. A correção final em `VehiclePanelDebris._exit_tree` chama `panel_mesh.set_base(RID())` enquanto os materiais ainda existem. Ela não acrescenta timers, caches ou loops por quadro. Sintaxe aprovada; o probe e a regressão após essa correção não executaram, conforme a decisão do usuário. Os contratos de expiração, limite de 18 peças, pausa e reparo já haviam passado nas 120 verificações anteriores; isso não substitui a checagem da última edição.

A primeira captura completa na Main confirmou amassados nos dois participantes, desprendimento dos dois para-choques atingidos e apoio dos fragmentos no piso (distâncias de −8,3 mm e −1,7 mm, ambos em repouso). A segunda aproximação falhou por preparação do teste: reativar o motorista externo não limpava o freio e reposicionar mantinha a reação da colisão anterior. Essa tentativa não valida o capô nem a sequência completa. A fixture foi corrigida para limpar o movimento anterior, rearmar os controles e confirmar apoio no piso antes de cada aproximação. Os limiares do produto permaneceram iguais. [Tentativa preservada](../../evidence/vehicle-breakaway-candidate-capture-96700-8485538/report.json).

As capturas corrigidas de [sport_coupe/metro_hatch](../../evidence/vehicle-breakaway-candidate-capture-99956-10248240/report.json) e [monaliza/police_cruiser](../../evidence/vehicle-breakaway-candidate-capture-92280-10315429/report.json) passaram: dois contatos físicos por par, amassados nos dois participantes, capô e para-choque frontal do atacante e para-choque traseiro do alvo separados. Os seis fragmentos repousaram no chão, com diferenças entre −1,5 e −9,4 mm. Não houve empilhamento. As capturas usaram C# e fontes estáveis, mantendo VSync e limite local de 144 FPS; gravar PNG não constitui medição de FPS.

A revisão visual encontrou trechos do suporte dos faróis no capô solto do esportivo. O recorte foi corrigido para seguir a superfície autorada do capô. O novo bake reduziu a peça de 888 para 516 triângulos; seu ponto mais alto passou de 1,01145 para 0,858658 m. O teste dos quatro modelos passou novamente, e os outros três assets mantiveram hashes idênticos. [Evidência da correção](../../evidence/breakaway-validation-20261021/geometry/bake-sport-fix-summary.json). A captura seguinte confirmou o recorte limpo e os suportes preservados.

A [captura temporal de 37 imagens e 97 amostras físicas](../../evidence/vehicle-breakaway-candidate-capture-92288-20020470/report.json) revelou passagem do capô pela cabine. A peça recebia −3,78 m/s enquanto o carro seguia a 15,40 m/s: o controlador lia a velocidade zerada pelo contato antes de a resolução da colisão repor o movimento. A peça agora recebe a velocidade calculada após a colisão, sem alterar a ordem dos eventos de dano e resposta física. O capô ganha impulso vertical e lateral para afastar-se da cabine; os para-choques caem para fora dos suportes. A regressão de 26 verificações passou.

As capturas finais do [esportivo/hatch](../../evidence/vehicle-breakaway-candidate-capture-112208-10003592/report.json) e da [Monaliza/viatura](../../evidence/vehicle-breakaway-candidate-capture-88652-14117338/report.json) passaram com C# ativo, fontes estáveis e zero falhas funcionais. A revisão temporal por dois agentes confirmou folga visível do capô em relação à cabine e ao alvo, subida/afastamento lateral e queda ao lado do carro. As 96 amostras físicas do esportivo e 97 da Monaliza não sobrepõem a geometria de cabine examinada pelo analisador de transformações reais. Para a Monaliza o envelope é conservador; a aprovação também usa os PNGs. Os três fragmentos de cada par repousaram no chão, com diferenças entre −1,5 e −10,0 mm. Os para-choques ficam parcialmente ocluídos pelos carros em alguns closeups; não se afirma visibilidade integral em todas as vistas. Esta evidência cobre os pares e trajetórias capturados, não todas as velocidades e ângulos possíveis.

A primeira tentativa dessas capturas foi interrompida antes de construir a cidade: uma alteração concorrente de carregamento deixou a variável `usable` sem tipo inferível em `ProductionWorld.gd`. O responsável corrigiu a declaração para `bool`. Não houve imagem útil nem medição nessa tentativa; os testes isolados já concluídos foram preservados.

A [recarga produtiva](../../evidence/vehicle-breakaway-candidate-99472-21727122/reload-report.json) passou com C# ativo e fontes estáveis. O erro anterior da assertion era comparar diretamente `version` inteiro com o número desserializado do JSON; versão, chaves e valores foram confirmados semanticamente. Abrir portas manteve capô e para-choque ausentes; reparar recompôs o veículo. A limpeza explícita da Main removeu os três fragmentos sem vazamentos de Body, Shape, Mesh ou Material. Restou um aviso de `RefCounted` no encerramento, já observado antes do protótipo.

Ambiente: Godot 4.7.2 .NET, `Harbor.csproj` compilado, renderer Forward Plus, RTX 4060 Laptop GPU. As capturas usam viewport 1280×720 e janela fullscreen 3440×1440, VSync ligado e limite local de 144 FPS; população de 23 veículos e 11 pessoas. O comparativo desativa VSync/limitador somente no processo, mantendo a mesma fonte e uma opção de diagnóstico (`--vehicle-damage-baseline`) que seleciona os modelos e a resposta anteriores. Essa opção não desabilita o protótipo no jogo normal.

A tentativa de baseline histórico anterior à integração foi interrompida por concorrência com outro processo de benchmark. Seus arquivos foram preservados, mas não produziram métricas válidas. O comparativo desligado/ligado será registrado separadamente, sem apresentar essa tentativa incompleta como baseline aprovado.

## Como experimentar

Abrir normalmente por `Jogar.cmd`. Usar um dos quatro modelos acima e bater de frente ou de traseira, com velocidade ou impactos repetidos. Verificar o dano nos dois participantes, observar as peças no chão e depois reparar o carro. Contato leve não deve arrancar peças. O hatch do trânsito permite observar o mesmo sistema fora do carro do jogador.

O estudo que orientou o protótipo está em [estudo-danos-carros-20261021.md](../estudo-danos-carros-20261021.md).
