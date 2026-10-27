# Variações de pistolas, SMGs e escopetas

O arsenal passa a oferecer três opções em cada uma dessas categorias. Os cinco IDs existentes permanecem; quatro armas novas foram acrescentadas. Dano e capacidade abaixo são valores básicos, antes de acessórios. Dano de escopeta é por chumbo: acertar o leque inteiro exige curta distância.

| Categoria | Arma | Dano | Intervalo | Capacidade | Recarga | Preço |
|---|---|---:|---:|---:|---:|---:|
| Pistola | 9 mm | 34 | 0,26 s | 12 | 1,69 s | inicial |
| Pistola | Magnum .44 | 70 | 0,58 s | 6 | 2,53 s | 800 |
| Pistola | 9 mm silenciada | 28 | 0,30 s | 15 | 1,50 s | 2.200 |
| SMG | MP5 | 25 | 0,11 s | 30 | 1,48 s | 1.200 + descoberta |
| SMG | Compacta | 19 | 0,075 s | 24 | 1,30 s | 1.400 |
| SMG | Tática | 29 | 0,135 s | 24 | 2,00 s | 2.600 |
| Escopeta | Pump | 18 × 8 | 0,78 s | 6 | 2,83 s | 1.800 |
| Escopeta | Serrada | 18 × 10 | 0,44 s | 2 | 2,63 s | 1.600 |
| Escopeta | Semiautomática | 13 × 7 | 0,38 s | 8 | 3,30 s | 2.800 |

## Decisões de jogabilidade

- A silenciada ganha carregador de 15 e recarga rápida, mas perde dano, alcance e velocidade de repetição. Reduz alcance de audição e reação ao disparo; pessoas próximas e agressões continuam provocando consequências.
- A compacta favorece distância curta e deslocamento. Rajadas longas aumentam sua dispersão; parar de atirar recupera precisão, e trocar de arma não zera esse estado.
- A tática tem maior alcance e controle, mas dispara e recarrega mais devagar. A MP5 mantém a vantagem do carregador de 30 e sua descoberta no avião dos Cobras.
- A semiautomática exige um clique por disparo. Repete tiros mais rapidamente, causa menos dano por cartucho e tem recarga mais longa; seu mecanismo e cartuchos não imitam o bombeamento da pump.
- Mirar e parar ajudam a controlar armas. Mirar não transforma o leque físico da escopeta em um único projétil. Acessórios continuam compondo os valores finais.

## Seleção e aquisição

Segurar Q abre a roda no teclado; rolagem ou ←/→ alternam a variante do setor. No controle, L1/LB abre a roda, analógico direito escolhe setor, D-pad ←/→ alterna a variante e soltar confirma. Cancelar preserva a arma equipada. Configurações personalizadas são preservadas na migração.

A loja mostra todas as variantes, preços e valores funcionais. As novas armas também aparecem em equipamentos e drops dos encontros autorados dos Cobras: compacta no encontro com residentes, silenciada e semiautomática nos suprimentos, tática no encontro final. O modelo carregado, o disparo e a arma coletada usam o mesmo ID.

Munição permanece separada por arma, preservando a estrutura dos saves existentes. Uma compra inclui reserva inicial; um drop concede somente a munição registrada naquele item. Coletar uma arma já possuída acrescenta munição sem duplicar a arma. Compras e coletas recusadas por capacidade não consomem recursos. A arma na mochila pode ser selecionada pela roda, respeitando as regras de espaço e da mala de mão.

Garagem, pausa, transição, morte e outros bloqueios continuam passando pelas verificações comuns de combate e equipamento. Maciota e seu mecânico não receberam rotinas de dano.

## Apresentação e áudio

Quatro modelos próprios, poses e ícones distinguem as novas armas. Supressor, comprimento de cano, coronhas, carregadores e acabamento mudam suas silhuetas. Clarões, recuo, ejeção de cápsulas e cartuchos reutilizam os recursos e limites existentes. Carregadores e ferrolhos das novas SMGs se movem; a semiautomática usa guarda-mão fixo e movimento de ferrolho.

O áudio temporário está ligado ao jogo; o pacote definitivo tem **32 WAVs**, especificados em [weapon-variant-audio-brief.md](weapon-variant-audio-brief.md). Os bancos são carregados antes do jogo e substituídos automaticamente quando os arquivos finais são importados.

## Validação

Resultados funcionais e evidências renderizadas ficam em [`artifacts/weapon-variants-20261027/`](../artifacts/weapon-variants-20261027/). Godot 4.7.2 .NET, com `Harbor.csproj` compilado; última compilação sem erros nem avisos. A aprovação de funcionamento, apresentação e desempenho é separada.

| Verificação | Resultado | Evidência |
|---|---|---|
| Balanceamento, cadência, dispersão, recuperação e acessórios | 70 verificações, zero falhas | `balance-final.log` |
| Combate em Main: nove armas, dano, munição, paredes, gatilho, recarga, NPCs e proteção da garagem | 84 verificações, zero falhas e nenhum erro de script na rodada final | `combat-final.log` |
| Compra, capacidade, drops, duplicatas, migração e SaveStore | 142 verificações, zero falhas | `economy-after-review.log` |
| Economia da campanha e inventário existente | 180 + 36 + 30 verificações, zero falhas | `test_campaign_economy.log`, `test_inventory_grid.log`, `test_inventory_limits.log` |
| Roda na sessão real, variantes e teclado/controle | 81 verificações, zero falhas | `wheel-integration.log` |
| Modelos, poses, recarga, cápsulas e limites dos efeitos | 49 verificações, zero falhas | `test_weapon_variant_presentation.log` |
| Consistência dos modelos usados na loja e no jogo | 258 verificações, zero falhas | `test_weapon_model_catalog_consistency.log` |
| Preparação dos sons antes dos disparos | 169 verificações, zero falhas | `test_combat_audio_prewarm.log` |

O teste de combate usa a sessão Main e a física real, com alvo inerte numa faixa elevada isolada. Ele encontrou um cano longo atravessando a parede: a nova verificação do trajeto entre o peito e a boca do cano bloqueia o tiro e o indicador de mira nessa situação. Não equivale a um playthrough das missões dos Cobras. O caso de vidro de veículo atrás de parede foi revisado no código, mas não exercitado contra veículo real nesta rodada. Os logs de tentativas anteriores foram preservados, inclusive o erro corrigido na preparação do inventário do próprio teste.

As regras comuns de garagem e invulnerabilidade foram verificadas. Não foi feita auditoria global da garagem, dos mapas ou dos demais sistemas. A última correção de tradução de `PUNHO` para `FISTS` em inglês foi confirmada na captura final do catálogo; ela ocorreu depois da rodada de 81 verificações da roda.

### Apresentação renderizada

Os quatro modelos foram conferidos no componente real da loja sobre Main: [`after-catalog/`](../artifacts/weapon-variants-20261027/after-catalog/). Essa captura isola o catálogo e oculta o HUD externo; não simula uma caminhada até o balcão. A roda foi conferida em português e em tamanhos de janela distintos: [`after/wheel-pt.png`](../artifacts/weapon-variants-20261027/after/wheel-pt.png) e `wheel/`.

Há uma [sequência noturna sem áudio](../artifacts/weapon-variants-20261027/after/weapon-variants-night.mp4), com 511 quadros em 30 segundos, registrada após a medição. Os quadros e tempos originais estão em `after/sequence/`. A inspeção por amostragem mostra clarões, traçantes e leques de escopeta; a silenciada não acende a luz local do disparo. A leitura de imagem e gravação de JPEG reduzem a cadência desta captura: **seu contador de FPS não é um benchmark**. A sequência não certifica ausência de flickering em todos os quadros na cadência normal de jogo, nem toda a iluminação da cidade.

### Desempenho: não aprovado

Medição renderizada de Main, RTX 4060 Laptop, Forward+, 1280 × 720, VSync desligado, limite de 144 FPS, MSAA 2×. Cada cenário tem 8 segundos de aquecimento e 30 segundos de amostra. O medidor registra disparos realmente executados, saúde e posição; usa invulnerabilidade e arsenal infinito somente na fixture, mantendo os diretores do mundo ativos. As hashes dos arquivos acompanhados ficaram iguais do carregamento ao término da rodada final (`after/provenance.json`).

| Cenário | FPS médio | p95 do quadro | p99 do quadro | Disparos válidos, incluindo aquecimento |
|---|---:|---:|---:|---:|
| Parado | 80,0 | 17,1 ms | 20,5 ms | — |
| MP5 existente | 49,1 | 32,2 ms | 39,4 ms | 232 |
| Pump existente | 48,3 | 30,2 ms | 33,8 ms | 31 |
| Pistola silenciada | 43,8 | 31,9 ms | 38,2 ms | 90 |
| SMG compacta | 57,1 | 25,5 ms | 29,1 ms | 280 |
| SMG tática | 54,2 | 28,8 ms | 33,6 ms | 168 |
| Escopeta semiautomática | 47,7 | 30,5 ms | 33,7 ms | 48 |
| Roda aberta | 62,8 | 21,6 ms | 31,0 ms | — |

O combate ficou abaixo da meta de 60 FPS com armas antigas e novas. Houve ainda um quadro de 1.223,8 ms na amostra da silenciada, sem causa isolada; não é correto atribuí-lo à arma apenas pela coincidência temporal. Os JSONs preservam os tempos individuais e os aquecimentos.

A primeira captura (`before/`) não contava disparos válidos e sofreu mudança de estado durante combate. Além disso, outros trabalhos alteraram tráfego e veículos entre as rodadas. Portanto, o antes/depois é **inconclusivo**. A rodada final também não é uma comparação causal entre armas: os cenários são sequenciais e a população/reação do mundo evolui. Ela diagnostica desempenho absoluto nesta cena, sem certificar ausência de regressão, todos os mapas ou um export de release.

As execuções Main renderizadas deixaram aviso de 11–12 objetos no encerramento, também observado na linha de base; o teste final headless de combate deixou um objeto. A origem não foi isolada nesta tarefa. Não se declara encerramento livre de vazamentos.

Pendências: comparação de desempenho entre builds isoladas e investigação das quedas; playthrough dos encontros autorados para ajuste fino da dificuldade; avaliação temporal na cadência normal; entrega e audição dos sons definitivos no jogo e no exportado.
