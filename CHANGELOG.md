# CHANGELOG

Todas as alterações relevantes deste projeto são registradas neste arquivo.

## 2026-08-20 — Exceções opcionais para Sticky Notes Flatpak

### Adicionado

- Acrescentado ao `picom.conf` um bloco de regras opcionais para o aplicativo **Sticky Notes** distribuído via Flatpak.
- O aplicativo é identificado no X11 por `WM_CLASS = com.vixalien.sticky` e `_GTK_APPLICATION_ID = com.vixalien.sticky`.
- As regras disponíveis no bloco são:
  - `shadow-exclude`;
  - `rounded-corners-exclude`;
  - `blur-background-exclude`;
  - `focus-exclude`.

### Escopo obrigatório

Este bloco **não é uma configuração genérica para Flatpak**. Ele se aplica **somente ao aplicativo Flatpak Sticky Notes (`com.vixalien.sticky`)**.

As exceções foram usadas para corrigir artefatos gráficos observados nesse aplicativo quando executado em XFCE/X11 com Picom e decoração GTK/CSD/ARGB. A correção foi validada para esse caso específico.

### Estado padrão

Todo o bloco foi incluído **inteiramente comentado** no `picom.conf` e permanece **desabilitado por padrão**. Dessa forma, ele não altera o comportamento de outros aplicativos nem a configuração normal do compositor.

Quem utilizar o Sticky Notes Flatpak e reproduzir o mesmo tipo de artefato pode descomentar manualmente apenas esse bloco no `picom.conf`.
