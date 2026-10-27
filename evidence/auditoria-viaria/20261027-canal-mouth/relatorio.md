# Saídas do túnel do canal — 27/10/2026

Escopo: bocas oeste/warehouse_way e leste/east_union_avenue, acabamento do túnel, marcador de drift dos armazéns e nomes dos lugares no minimapa. Sem redesenho do mapa.

## Causas e alterações

- O túnel usava `_material(ROAD_COLOR)`, acabamento antigo, enquanto as ruas usam `_coastal_asphalt_material()`. Agora compartilham o acabamento efetivo, agregado e projeção mundial; no modo padrão usam a mesma instância unificada.
- O recorte de calçadas e pintura atendia apenas às rampas abertas. Os acessos em nível mantinham a borda da rua atravessando a entrada. `surface_cuts()` inclui esses acessos; as pontas avançam 25 cm para cobrir toda a borda da rua oblíqua salva.
- O círculo amarelo da imagem era o marcador de drift `harbor_cold_storage`, em (162.5, 65.625), sobre a rampa. Transferido para (124, 59.5), no pátio a oeste da warehouse_way, preservando ID, raio e recompensa. Os colecionáveis foram verificados contra a reserva do túnel e não ocupam esse local.
- Minimap: removidas etiquetas de nomes dos ícones, conservando seleção estável, símbolos e navegação funcional.

## Evidências

Capturas reais de Main.tscn, Godot 4.7.2 .NET, Vulkan Forward+, RTX 4060 Laptop, 3440 × 1440, VSync desligado, limite 144, seed 28092026, foco (145, 63), zoom 40, horário .35 e clima limpo. Saves não gravados (`--no-save`).

- Antes: [captura](../../canal-mouth-20261027/before-mouth.png).
- Depois: [captura](../../canal-mouth-20261027/after-mouth.png).
- Contratos: [log](../../canal-mouth-20261027/contracts.log), `CANAL_MOUTHS PASS`: encaixe na rua salva em ambas as bordas das duas bocas, recorte real de malha, calçada lateral preservada, material atual e atividades fora da reserva.
- Minimap: [log](../../canal-mouth-20261027/minimap.log), 3 checks aprovados; zero piscadas na seleção atual, zero nomes durante todo o percurso sintético.
- `dotnet build Harbor.csproj --no-restore -v quiet`: sucesso, zero avisos/erros.

## Frame time renderizado

Amostras de 30 segundos, após aquecimento, mesma configuração e local. Meta provisória: 60 FPS / 16.67 ms; aumento >5% em p95/p99 exigiria confirmação. Não houve aumento nesta amostra.

| Métrica | Antes | Depois |
|---|---:|---:|
| Frames | 2247 | 2600 |
| Duração (s) | 30.004 | 30.012 |
| FPS (frames/tempo) | 74.89 | 86.63 |
| p50 (ms) | 13.382 | 12.005 |
| p95 (ms) | 18.907 | 15.628 |
| p99 (ms) | 26.429 | 17.823 |
| Máximo (ms) | 35.142 | 27.728 |
| >33.3 ms | 1 | 0 |
| >66.7 ms | 0 | 0 |

Dados brutos: `evidence/canal-mouth-20261027/{before,after}-mouth.png.json`. Há outras sessões executando testes headless; a carga externa não foi isolada. Portanto a diferença não comprova ganho causal de performance. A amostra atual não mostra queda para 12–15 FPS. A captura inicial `before.png` ficou na garagem por usar um critério antigo de prontidão e foi excluída do comparativo; o probe foi corrigido para aguardar restauração e sessão jogável.

## Cobertura e limites

Geometria/dados: duas bocas, aprovados nos contratos. Visual: boca oeste, asfalto, remoção do círculo e minimapa aprovados na captura integrada; a boca leste ainda não tem captura dedicada. Capturas isoladas não certificam estabilidade temporal. Sem auditoria global de trânsito/semáforos, que não foram modificados. Logs de encerramento do probe registram recursos pendentes já presentes no baseline; não foram tratados nesta correção local.

Mapa salvo preservado: SHA256 `B4556AFA538699CBC8A4A568CBDB3A3DD36DAA7D42A8113690C97DC98DD88F6E`.

Passagem física integrada: **aprovada** no [log renderizado](../../canal-mouth-20261027/drive.log), `CANAL_TUNNEL PASS`. O carro real partiu da warehouse_way em x=138.5, atravessou o tubo e saiu pela east_union_avenue em x=345.669; fundo atingido -6.00 m, desvio máximo do piso 0.29 m, zero toques de teto/parede. Rampa máxima 12.5%, nenhum buraco nem teto baixo na inspeção por raios. O mesmo carro cruzou o cais acima sem afundar (mínimo 0.00 m). O teste verificou também grafo do túnel nos dois sentidos e ausência de conexão de vias de superfície com nós subterrâneos. Isso aprova a passagem testada; não certifica condução reversa, todos os tipos de veículo nem todos os comportamentos de tráfego.

Estado final: correção funcional e apresentação oeste aprovadas no escopo observado; estabilidade temporal por gravação contínua e captura dedicada leste não verificadas. Performance comparada sem regressão observada nesta amostra, com a ressalva de carga externa acima. Nenhuma alteração no documento salvo.
