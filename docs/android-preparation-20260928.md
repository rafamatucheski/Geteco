# Consolidação e preparação Android — 28/09/2026

Alvo informado: Samsung Galaxy Z Fold7 com a atualização Android mais recente
disponível no aparelho. A versão exata do sistema ainda não foi coletada.

## Revisão do trabalho recente

O histórico Git e os documentos alterados em 27 e 28/09 mostram estes grupos.
O conjunto local também inclui trabalho anterior ainda não commitado; o checkpoint
preserva esse conjunto, sem atribuir todas as alterações aos dois dias.

- Harbor: identidade, chegada de barco, terminal, passageiros e pescadores.
- Transporte: linha biarticulada, estações, cruzamentos e editores do mundo.
- Veículos: acabamento, faróis, colisões, saída em movimento, áudio, táxis e tanque.
- Polícia: resposta terrestre/aérea, helicóptero e perseguição.
- Porto: Vértice, empilhadeiras, cargas e arrombamento de contêineres.
- Serra: esqui, motocross, vila, residências, base secreta e forte.
- Ambiente: iluminação externa, clima, atmosfera e vegetação.
- Interface: HUD contextual, inventário em grade, mapa, controles e saves.

Fontes: documentos correspondentes em `docs/`, relatórios em `evidence/`,
histórico e diferenças locais. Planos de trem, coletáveis e expansões não
comprovam implementação. Esta revisão não equivale a uma auditoria linha a linha
de todo o jogo ou a uma certificação de estabilidade.

## Preparação entregue

- Preset `Harbor Android`, APK ARM64, pacote `com.geteco.harbor`, versão 0.3.0.
- Filtros de dados do preset Windows preservados; evidências, ferramentas,
  testes, editor de mundo e builds excluídos do pacote Android.
- `tools/build_android.ps1` verifica o template da versão efetiva do motor,
  exporta APK de teste e calcula SHA-256 quando o build termina.
- Builds, chaves, perfil de navegador e cópia local de benchmark não entram
  no commit. Esses arquivos permanecem no disco.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_android.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_android.ps1
```

O ambiente tem Java 17, Android SDK (plataformas 34/35/36) e caminhos configurados
no editor. A pasta de templates estava vazia na inspeção. Instalar templates
compatíveis com a versão efetiva do Godot é pré-requisito para gerar o APK.
Referência: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html

## Pendências para uma versão jogável estável

- Implementar e verificar interface multitoque completa. `touch_move` e
  `touch_aim` existentes não constituem controles Android utilizáveis.
- Verificar menus, inventário e mapa sem teclado/mouse; movimento, mira,
  armas e direção precisam funcionar com toques simultâneos.
- Validar tela interna/externa, áreas seguras e abrir/fechar o Fold7.
- Testar pausa/retomada, áudio, salvamento e restauração no aparelho.
- Medir gameplay renderizado no Fold7, incluindo noite/chuva, trânsito,
  porto e interiores. Resultados no desktop não certificam FPS Android.
- Resolver falhas relevantes dos testes e concluir verificações físicas,
  oclusão e regras da garagem antes de declarar estabilidade.

Nenhum aparelho estava conectado em `adb devices`. APK não gerado nesta etapa.
O checkpoint é uma base de desenvolvimento, não uma release Android aprovada.

## Validação desta consolidação

- Importação do projeto no Godot 4.7.2 concluída sem erros de script na execução
  com acesso aos caches. A primeira tentativa restrita falhou ao gravar caches
  e configurações; não foi usada como evidência de aprovação.
- 10 de 11 testes dirigidos passaram: chegada, integração de comandos/arsenal,
  HUD compacto, save completo, restauração do motorista, recompensas da garagem,
  transferência de veículos, inventário em grade, painel de inventário e
  equipamentos de veículos.
- `test_combat_flow`: 76 verificações, seis falhas na execução com acesso aos
  arquivos temporários. Três relacionadas a crime/denúncias, uma à restauração
  do snapshot na garagem e duas fixtures de equipamento após restauração.
  Causa não confirmada; nenhum contrato ou assertion foi enfraquecido.
- Relatório local da rodada de nove testes:
  `evidence/test-suite/suite-2026-09-28_2025.json`. Chegada e arsenal passaram
  antes dessa rodada, na execução inicial interrompida pela permissão ao mover
  o relatório de combate. A repetição de combate foi motivada por essa limitação
  do ambiente e continuou falhando; não houve terceira tentativa equivalente.
- `build_android.ps1 -CheckOnly` identifica corretamente o template ausente.
  A exportação direta reconhece `Harbor Android` e falha especificamente pela
  ausência de `android_debug.apk` e `android_release.apk` da versão 4.7.2.stable.
- `git diff --check` aponta espaços finais em arquivos existentes do lote
  acumulado e cópias históricas de evidência. Essas fontes não foram reformatadas
  durante a consolidação.
- Não houve benchmark Android, inspeção visual do Fold7 nem suíte integral.
