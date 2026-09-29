# Harbor no Android

Alvo inicial: Galaxy Z Fold7. APK ARM64, pacote `com.geteco.harbor`, versão 0.3.0.

## Instalar

1. Copie `builds/android/harbor-0.3.0-debug.apk` para o celular.
2. Abra o arquivo no aplicativo Meus Arquivos e permita a instalação por esse
   aplicativo quando o Android solicitar.
3. Abra Harbor. Jogue em paisagem; a interface se adapta ao tamanho disponível.

É um APK de teste assinado com a chave de depuração local. Uma atualização com
outra chave exige um procedimento de migração; preserve os saves antes de
desinstalar. Não é uma publicação na Play Store.

## Controles

- Analógico esquerdo: andar ou virar o veículo. Segure Correr para correr.
- Analógico direito: mirar. Atacar dispara ou executa o ataque equipado.
- Ação: interagir; Entrar/Sair: veículo. Recarregar e Arma fazem as ações indicadas.
- Dirigindo: Acelerar, Frear/Ré e Freio mão, com direção simultânea.
- Pausa, Mapa e Mochila ficam no alto. `•••` abre comandos secundários, incluindo
  câmera, bagagem, diário, lanterna, rendição e os acessórios dos veículos.
- Inventário: toque no item e nos botões de ação ou arraste para mover.
- Mapa: arraste para mover, use `+`/`−` para zoom e toque para selecionar.
- Gazua: setas ajustam o ângulo; segure Girar. Cofre/viatura: toque em Travar.
- Voltar fecha menus. A perda de foco no Android libera os toques e pausa a
  jogabilidade quando ela está ativa. Redimensionar a tela também libera toques.

A garagem preserva suas restrições: não há ataque ou troca de arma disponível.

## Build reproduzível

Use Godot 4.7.2 e seus templates oficiais, Java 17 e Android SDK configurado no
editor. As texturas também são importadas em ETC2/ASTC para Android.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_android.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_android.ps1
```

O script gera o APK em `builds/android/` e informa SHA-256. APKs e chaves não
entram no Git. Para revisar os controles no desktop, inicie com `--touch-controls`.

Validação física no Fold7 (instalação, multitarefa, dobrar/desdobrar, aquecimento,
autonomia e FPS) depende do aparelho. A validação desktop não substitui essa etapa.
