# Calçadas e integração do vídeo de 22/09/2026

Estado: correção geométrica aplicada; validação visual localizada realizada; desempenho e integração dos quatro problemas **pendentes**.

## Referência e diagnóstico por sintoma

Referência: `C:/Users/rafae/AppData/Local/Packages/Microsoft.ScreenSketch_8wekyb3d8bbwe/TempState/Recordings/20260922-1328-56.2777156.mp4` (38,63 s, 1282 × 734, 30 FPS). O quadro em 26,4 s separa faixas finas no piso à esquerda do braço alongado e de sua sombra sobre o asfalto.

| Sintoma | Evidência e causa | Situação |
| --- | --- | --- |
| Faixas/manchas nas calçadas | `HarborUrbanSurface3D` desenhava piso-base, lotes e acessos sobrepostos em y=0,006. A reprodução mantém faixas mesmo sem sombra solar e com materiais unshaded. Havia 182 pares de fontes sobrepostos na primeira inspeção. | Corrigida a composição de acabamentos; pendem aceite integrado e performance. |
| Dante deformado e sombras alongadas do corpo | O vídeo mostra braços/geometria esticados com sombras correspondentes. É sintoma distinto da coplanaridade do piso. | Agente externo trabalhando. Uma captura externa `after-capture/report.json` informa erro máximo de escala de braço de 2,53e-7 e `first_bad_tick=-1`; isso não aprova a sequência integrada. |
| Policiais com braços para trás | Reportado pelo usuário; depende de pose, orientação e arma. Não atribuído à iluminação. | Agente externo trabalhando; entrega final ainda não recebida. |
| Tiros policiais diferentes da V1 | Requer comparar saída da arma, direção, traço, impacto e efeitos com a referência V1. | Agente externo trabalhando; falta testar os efeitos sobre o piso corrigido. |

Não foi demonstrado que névoa, normais ou precisão entre planos de alturas diferentes sejam a causa destas faixas. A coplanaridade entre acabamentos é demonstrável independentemente delas. Retângulos escuros de acabamento autorado e sombras úteis não foram removidos.

## Alteração delimitada

Alterado apenas `world/urban_detail/HarborUrbanSurface3D.gd` no runtime desta frente. A configuração agora subtrai de cada retângulo as áreas cobertas pelas fontes posteriores, reproduzindo a precedência de pintura da V1. O streaming recebe somente peças visíveis sem sobreposição positiva; a composição ocorre uma vez na configuração, sem novo trabalho por frame.

Preservados materiais, cores, UVs mundiais, altura y=0,006, pontos de acesso e colisões. Não houve alteração de Weather, atmosfera, luz direcional, combate ou ProductionWorld. O recorte concorrente `_RAISED_APRON_HOLES` da garagem, inserido por outra frente durante esta tarefa, foi preservado. Esta mudança não certifica a colisão da laje modificada pela outra frente.

## Evidências e testes

- `evidence/sidewalk-glitches/probe/`: diagnóstico anterior, incluindo normal, sem sombra solar, sem névoa, unshaded e oito posições próximas. Esta rodada teve falhas de carregamento concorrentes em prédios/porta-malas: diagnóstico parcial de piso, não aceite da Main.
- `evidence/sidewalk-glitches/probe-after/`: mesmos controles depois do recorte; execução concluída sem erros no log `evidence/sidewalk-probe-after.log`.
- `evidence/sidewalk-glitches/motion/`: 320 PNGs, 80 por condição (dia nublado 13:12, entardecer 18:00, noite 20:09, chuva 13:12). Cada condição registra parada, caminhada, zoom e rotação. População solicitada 24 e trânsito ativo. Câmera inicial ortográfica 26, posição `(137.5, 0.08, 105)`, na rua entre o hospital e Port Authority. Enquadramento localizado, mais aberto que o trecho ampliado do vídeo original.
- [Vídeo das calçadas](../evidence/sidewalk-glitches/sidewalk-motion.mp4): montagem dos 320 PNGs a 10 FPS. É amostragem visual, **não gravação de frame time real nem vídeo integrado final**. Foram examinados quadros das quatro sequências; isso não prova ausência de qualquer cintilação entre amostras.
- `tests/urban_detail/test_sidewalk_surface_coverage.gd`: antes, 241 falhas de sobreposição/precedência; depois, zero. Inspeciona os retângulos efetivamente enviados à malha, cobertura de pontos e precedência original, inclusive recortes em limites de chunks. Última execução limpa: saída 0.
- `tests/test_regional_atmosphere.gd`: 25 checks, zero falhas.
- `tests/test_weather_lighting_parity.gd -- --no-save --skip-arrival`: **falhou** na igualdade da cor diurna com `HARBOR_SUN_DAY` em t=0,45. Weather conserva o mesmo SHA256 anterior à correção; a divergência entre expectativa fixa e perfil atmosférico atual não foi alterada nesta frente.
- `tests/test_weather_atmosphere_integration.gd`: primeira execução contaminada por erro concorrente de TrunkView; após correção desse arquivo pela outra frente, repetição justificada terminou limpa, saída 0, 20 checks e `errors=[]`. Inclui entrada real na garagem, suspensão da atmosfera exterior e restrição de armas. Log: `evidence/sidewalk-atmosphere-integration.log`. Não substitui o teste integrado de combate.
- `tests/measure_sidewalk_glitches.gd`: sintaxe verificada com `--check-only`; execução de performance ainda não aprovada.

## Performance: não aprovada / sem comparativo válido

Ambiente das capturas: Godot 4.7.2, Mobile/Vulkan, RTX 4060 Laptop, 1280 × 720. Meta provisória: 60 FPS; sinal de regressão: aumento >5% de p95/p99 exige confirmação finita.

O harness prevê quatro cenários, 8 s de aquecimento e 30 s de intervalos reais por cenário, p50/p95/p99/máximo e quadros >33,3/>66,7 ms. Capturas ficam fora da janela de medição. O primeiro baseline terminou sem concluir a inicialização; nenhuma métrica foi produzida. A tentativa posterior foi interrompida por esta frente ao encontrar `TrunkView.gd:89` com erro de inferência de tipo. Execuções concorrentes de Dante, polícia, menus e porta-malas também impediram isolamento em várias janelas. Nenhum processo alheio foi encerrado.

O modo diagnóstico `--legacy-surfaces` reconstrói a lista coplanar anterior apenas no processo do teste, sem reverter arquivos compartilhados. Serve para comparação futura de regime estável; não reconstitui custo anterior de inicialização. Não há p50/p95/p99 aprovado a publicar nesta entrega.

Às 11:05 o erro de TrunkView estava corrigido pela outra frente; a nova tentativa foi impedida pelo guard de concorrência, pois `capture_dante_deformation.gd --dante-label=after-verified --dante-capture` ainda usava a GPU. O guard saiu com código 3 antes de abrir outro jogo. Dependência atual: janela exclusiva e entregas externas estabilizadas.

## Versões registradas

SHA256 do piso inicialmente inspecionado: `9E32D259C1206BDE76020ABEA249FD0FA6A074525D90DD21A10FB3EF0DD35DDB`.
Após o recorte concorrente da garagem, antes desta correção: `53057C194FBB6F1B9BEA621D020A7C8E009EF860246207AA0DE49B76F05423F5`.

| Arquivo | SHA256 após a validação localizada |
| --- | --- |
| HarborUrbanSurface3D.gd | `5410F7B7370FEC78206665390292EEC615C0FA50DDBC7E93C0050EBB686C82F8` |
| HarborRoadGeometry3D.gd | `C654059DB074B27060D0D8B15548F0450FF6326B2AAEF6D66392D3AB1065AEB0` |
| ProductionWorld.gd | `3B85B98C9BF98D1432C4AC6D089539708D2EC28DAEB1F9B0D842AB8209139B30` |
| Weather.gd | `999588F41AF79D265FB4B1AFD0FA05A86D41FA6C7926AA14A70263227FFF7540` |
| RegionalAtmosphere3D.gd | `816514E90640548DBD06BE41922A9B5DCB07C145EE1844B6BC60A023E11411AC` |

Arquivos de combate apenas observados, **não certificados**: Actor `1701CD647AE88A2EDDE3CD39FDE9E61D1106AF9D4F2975E94CD9163E4239D3C2`; Gameplay `6CCD099DE37607B1F7664740F7A0F3D72A6DDAE3E24B9B62563EAE5BD7F065DA`; WeaponRigPose `918246959FF8D073A93723BF0AF87A31205AEED18E09B073B088A1B4FA58DE61`; WeaponPoseData `55A94C815275DC69A56F9EA15A0FB865270751CE62EBBC18F1C430D2B822674C`. Não usar estes hashes como aceite das entregas externas.

## Integração final pendente

Receber relatórios finais de Dante e policiais e congelar as versões durante a janela de validação. Com Main compilando sem erros e GPU reservada, concluir A/B de performance e reproduzir o vídeo com movimento, mira, disparos, recarga e troca de armas sob perseguição. Conferir braços, armas, saída dos tiros, impactos, sombras e piso simultaneamente, incluindo flashes policiais. Revalidar as proteções da garagem e saves; gravar vídeo comparável e registrar novos hashes. Nada desta etapa está marcado como concluído.
