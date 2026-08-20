# compton-settings-nvidia-1660

Automação em **Shell POSIX (`/bin/sh`)** para substituir apenas o compositor interno do `xfwm4` pelo **Picom** em uma sessão **XFCE/X11** no **Arch Linux**, mantendo o `xfwm4` como gerenciador de janelas.

O objetivo é obter uma composição simples e previsível em hardware NVIDIA: backend GLX, VSync, sincronização X Sync Fence, cantos arredondados, sombras discretas e transparência leve, sem animações de fading.

## Escopo técnico

A arquitetura resultante é:

```text
Xorg / X11
 ├─ xfwm4
 │   ├─ foco
 │   ├─ decoração
 │   ├─ mover/redimensionar
 │   ├─ atalhos e workspaces
 │   └─ compositor interno: DESATIVADO
 │
 └─ Picom
     ├─ backend GLX
     ├─ VSync
     ├─ X Sync Fence para NVIDIA
     ├─ use-damage
     ├─ cantos arredondados
     ├─ sombras
     └─ transparência leve
```

## Hardware e validação

O repositório é direcionado ao perfil **NVIDIA GeForce GTX 1660 (Turing)**.

Por precisão técnica, a validação reproduzida durante a construção deste script foi realizada em uma **NVIDIA GeForce GTX 1650**, também Turing, utilizando **NVIDIA UNIX Open Kernel Module 610.57.04**, Xorg/X11, XFCE 4.20 e Picom 13. O script não declara teste direto em GTX 1660 até que ele seja efetivamente executado nessa placa.

O Picom detectou corretamente:

- GLX disponível;
- vendor GLX/GL: NVIDIA Corporation;
- renderização pela GPU NVIDIA;
- `xrender-sync-fence` para a pilha NVIDIA;
- scheduler de VBlank `sgi_video_sync` no ambiente de validação.

## O que `script.sh` faz

1. Exige execução como usuário normal dentro da sessão XFCE/X11.
2. Confirma que `pacman` está disponível.
3. Solicita credenciais `sudo` apenas para as operações administrativas.
4. Instala/garante os pacotes `picom` e `xfconf` com `pacman -S --needed`.
5. Coleta informações básicas da GPU/driver NVIDIA quando `nvidia-smi` está disponível.
6. Cria backup das configurações existentes antes de modificá-las.
7. Desativa **somente** `/general/use_compositing` do `xfwm4`.
8. Cria `~/.config/picom.conf` com a configuração deste repositório.
9. Cria `~/.config/autostart/picom.desktop` para iniciar o Picom automaticamente na sessão XFCE após boot/login.
10. Encerra uma instância anterior do Picom, inicia a nova configuração e verifica se o processo permaneceu ativo.
11. Se o teste falhar, reativa o compositor interno do `xfwm4` e não reinicia a máquina.
12. Se tudo estiver correto, reinicia o computador automaticamente após uma contagem de 10 segundos.

## Por que XDG Autostart e não um serviço systemd?

O Picom é um **compositor da sessão gráfica X11**. Ele depende do display X, da sessão do usuário e do ambiente gráfico. Por isso, iniciar Picom como serviço de sistema no boot, antes da sessão gráfica, seria arquiteturalmente incorreto.

O script habilita a inicialização automática através de:

```text
~/.config/autostart/picom.desktop
```

Assim, após o boot e o login na sessão XFCE/X11, o Picom inicia automaticamente com a configuração correta.

## Configuração aplicada

Os principais parâmetros são:

```ini
backend = "glx";
vsync = true;
xrender-sync-fence = true;
use-damage = true;

corner-radius = 8;

shadow = true;
shadow-radius = 8;
shadow-opacity = 0.18;
shadow-offset-x = -4;
shadow-offset-y = -4;

detect-client-opacity = true;

fading = false;
blur-background = true;
unredir-if-possible = false;

inactive-opacity = 0.97;
active-opacity = 1.0;
inactive-opacity-override = false;
```

### Observação sobre blur

O arquivo fornecido para este projeto contém simultaneamente o comentário `# Não usar blur` e o valor:

```ini
blur-background = true;
```

O script **preserva o valor solicitado (`true`) sem corrigi-lo silenciosamente**. Caso o objetivo seja realmente desabilitar blur, altere-o para:

```ini
blur-background = false;
```

## Instalação

Baixe `script.sh`, torne-o executável e rode-o como usuário normal dentro do XFCE/X11:

```sh
chmod +x script.sh
./script.sh
```

**Não execute:**

```sh
sudo ./script.sh
```

O próprio instalador usa `sudo` apenas onde necessário.

## Reinicialização

Por padrão, ao terminar com sucesso, o script aguarda 10 segundos e executa:

```sh
sudo reboot
```

Para executar um teste sem reiniciar automaticamente:

```sh
NO_REBOOT=1 ./script.sh
```

## Backups

Antes de alterar a configuração, o script cria uma pasta semelhante a:

```text
~/.local/state/compton-settings-nvidia-1660/backups/AAAAMMDD_HHMMSS/
```

Ela pode conter:

- `picom.conf.before`;
- `picom.desktop.before`;
- `xfwm4.xml.before`;
- `environment.txt`.

## Segurança e rollback

Se o Picom não permanecer ativo durante o teste final, o script tenta restaurar imediatamente:

```text
xfwm4 /general/use_compositing = true
```

Nesse cenário o reboot é cancelado.

Para rollback manual durante uma sessão:

```sh
pkill picom
xfconf-query -c xfwm4 -p /general/use_compositing -s true
```

Também é possível restaurar os arquivos salvos no diretório de backup.

## Requisitos

- Arch Linux ou sistema compatível com `pacman`;
- XFCE com `xfwm4`;
- sessão X11;
- `sudo` funcional;
- driver NVIDIA devidamente instalado para o perfil NVIDIA;
- conexão de rede caso o pacote Picom ainda precise ser instalado.

## Notas

- Este projeto não substitui o `xfwm4` como window manager; substitui apenas sua função de composição.
- Não altera arquivos do driver NVIDIA, `xorg.conf`, `ForceCompositionPipeline`, `ForceFullCompositionPipeline` ou `TripleBuffer`.
- O backend configurado é GLX. XRender pode ser usado manualmente como fallback de diagnóstico caso uma máquina específica apresente artefatos.
- O fading fica desativado porque, no ambiente de validação, ele gerou artefatos visuais no `xfce4-docklike-plugin`.
