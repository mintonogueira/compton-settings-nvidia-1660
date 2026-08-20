#!/bin/sh
# ==============================================================================
# compton-settings-nvidia-1660 - Instalador Picom para XFCE/X11 + NVIDIA
# ==============================================================================
#
# Objetivo:
#   Automatizar a substituição do compositor interno do xfwm4 pelo Picom em uma
#   sessão XFCE sobre X11, com foco em GPUs NVIDIA e uma configuração visual
#   simples: GLX, VSync, X Sync Fence, cantos arredondados, sombras discretas,
#   transparência leve e sem fading.
#
# Ambiente de referência:
#   - Arch Linux
#   - XFCE 4.20 / xfwm4
#   - X11
#   - Picom 13
#   - NVIDIA Open Kernel Module 610.57.04
#   - GPU Turing
#
# IMPORTANTE:
#   * Este script deve ser executado pelo USUÁRIO NORMAL dentro da sessão XFCE.
#   * NÃO execute com "sudo ./script.sh". O próprio script usa sudo apenas nas
#     operações que realmente precisam de privilégios administrativos.
#   * O Picom é um compositor da sessão gráfica. Por isso sua inicialização
#     automática é configurada via XDG Autostart do XFCE, e não como serviço
#     systemd de sistema.
#   * Ao final, por padrão, o computador será reiniciado automaticamente.
#     Para testar sem reiniciar, execute: NO_REBOOT=1 ./script.sh
#
# Compatibilidade do shell:
#   Escrito deliberadamente em Shell POSIX (/bin/sh): sem arrays, [[ ]], local,
#   process substitution, funções específicas do Bash ou outras extensões.
# ==============================================================================

set -eu

PROGRAM_NAME='compton-settings-nvidia-1660'
PICOM_CONF="$HOME/.config/picom.conf"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/picom.desktop"
XFWM_XML="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
STAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_DIR="$HOME/.local/state/$PROGRAM_NAME/backups/$STAMP"

say()
{
    printf '%s\n' "$*"
}

warn()
{
    printf 'AVISO: %s\n' "$*" >&2
}

fail()
{
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

have()
{
    command -v "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# 1. Validações iniciais
# ------------------------------------------------------------------------------

say '============================================================'
say ' Picom para XFCE/X11 + NVIDIA'
say '============================================================'
say ''

# A configuração é de usuário e depende da sessão gráfica/xfconf desse usuário.
# Rodar o programa inteiro como root faria os arquivos serem gravados no HOME de
# root e normalmente perderia acesso correto à sessão XFCE.
if [ "$(id -u)" -eq 0 ]; then
    fail 'execute este script como usuário normal, sem prefixar o comando com sudo.'
fi

# O procedimento foi construído para Arch Linux/pacman.
if ! have pacman; then
    fail 'pacman não foi encontrado. Este instalador foi preparado para Arch Linux.'
fi

# Picom é compositor X11. Em Wayland esta arquitetura não se aplica.
if [ "${XDG_SESSION_TYPE:-}" != 'x11' ]; then
    fail 'a sessão atual não é X11. Entre em uma sessão XFCE/X11 e execute novamente.'
fi

if [ -z "${DISPLAY:-}" ]; then
    fail 'DISPLAY não está definido; execute o script dentro da sessão gráfica XFCE.'
fi

# Precisaremos de sudo em dois pontos: instalação de pacotes e reboot final.
if ! have sudo; then
    fail 'sudo não foi encontrado.'
fi

say '[1/9] Validando privilégios sudo...'
sudo -v

# ------------------------------------------------------------------------------
# 2. Instalação dos pacotes necessários
# ------------------------------------------------------------------------------

say '[2/9] Instalando/confirmando Picom e xfconf...'
# --needed evita reinstalar pacotes já presentes. Não fazemos upgrade completo do
# sistema aqui; o script altera apenas o necessário para esta configuração.
sudo pacman -S --needed picom xfconf

have picom || fail 'picom não ficou disponível após a instalação.'
have xfconf-query || fail 'xfconf-query não ficou disponível após a instalação.'

# ------------------------------------------------------------------------------
# 3. Diagnóstico informativo da NVIDIA
# ------------------------------------------------------------------------------

say '[3/9] Identificando a pilha gráfica...'
if have nvidia-smi; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sed -n '1p' || true)
    if [ -n "$GPU_NAME" ]; then
        say "      GPU detectada: $GPU_NAME"
        case "$GPU_NAME" in
            *NVIDIA*|*GeForce*) : ;;
            *) warn 'a GPU detectada não corresponde ao perfil NVIDIA esperado.' ;;
        esac
    fi
else
    warn 'nvidia-smi não foi encontrado; o script continuará, mas não validará a GPU.'
fi

if [ -r /proc/driver/nvidia/version ]; then
    sed -n '1,2p' /proc/driver/nvidia/version | sed 's/^/      /'
else
    warn '/proc/driver/nvidia/version não está disponível.'
fi

# ------------------------------------------------------------------------------
# 4. Backup reversível das configurações existentes
# ------------------------------------------------------------------------------

say "[4/9] Criando backup em: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -f "$PICOM_CONF" ]; then
    cp -p "$PICOM_CONF" "$BACKUP_DIR/picom.conf.before"
fi

if [ -f "$AUTOSTART_FILE" ]; then
    cp -p "$AUTOSTART_FILE" "$BACKUP_DIR/picom.desktop.before"
fi

if [ -f "$XFWM_XML" ]; then
    cp -p "$XFWM_XML" "$BACKUP_DIR/xfwm4.xml.before"
fi

# Guardamos também um pequeno retrato do ambiente para facilitar diagnóstico e
# eventual restauração futura.
{
    printf 'date=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf 'user=%s\n' "$(id -un)"
    printf 'session_type=%s\n' "${XDG_SESSION_TYPE:-unknown}"
    printf 'display=%s\n' "${DISPLAY:-unknown}"
    printf 'picom_version='
    picom --version 2>/dev/null || true
    printf 'xfwm_compositing_before='
    xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || printf 'unknown\n'
    if have nvidia-smi; then
        printf 'gpu='
        nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sed -n '1p' || true
    fi
} > "$BACKUP_DIR/environment.txt"

# ------------------------------------------------------------------------------
# 5. Desativação APENAS do compositor interno do xfwm4
# ------------------------------------------------------------------------------

say '[5/9] Desativando a composição interna do xfwm4...'
# xfwm4 continua responsável por foco, decoração, movimentação, resize,
# workspaces etc. Desligamos somente a composição de exibição.
if xfconf-query -c xfwm4 -p /general/use_compositing >/dev/null 2>&1; then
    xfconf-query -c xfwm4 -p /general/use_compositing -s false
else
    xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false
fi

XFWM_STATE=$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || true)
if [ "$XFWM_STATE" != 'false' ]; then
    fail 'não foi possível confirmar a desativação do compositor do xfwm4.'
fi

# ------------------------------------------------------------------------------
# 6. Criação do ~/.config/picom.conf solicitado
# ------------------------------------------------------------------------------

say "[6/9] Gravando configuração: $PICOM_CONF"
mkdir -p "$HOME/.config"

cat > "$PICOM_CONF" <<'PICOM_EOF'
# ============================================================
# Picom - configuração simples para XFCE + NVIDIA
# ============================================================

# Renderização via OpenGL
backend = "glx";

# Sincronização vertical
vsync = true;

# Importante para sincronização com drivers NVIDIA
xrender-sync-fence = true;

# Redesenhar somente regiões alteradas
use-damage = true;

# ------------------------------------------------------------
# Cantos
# ------------------------------------------------------------

corner-radius = 8;

# ------------------------------------------------------------
# Sombras
# ------------------------------------------------------------

shadow = true;
shadow-radius = 8;
shadow-opacity = 0.18;
shadow-offset-x = -4;
shadow-offset-y = -4;

# ------------------------------------------------------------
# Transparência
# ------------------------------------------------------------

# Nesta primeira fase NÃO aplicaremos transparência global.
# Primeiro vamos comprovar estabilidade.

detect-client-opacity = true;

# ------------------------------------------------------------
# Efeitos
# ------------------------------------------------------------

fading = false;

#fade-in-step = 0.05;
#fade-out-step = 0.04;
#fade-delta = 15;

# Não usar blur
blur-background = true;

# Não fazer unredirect inicialmente.
# Priorizamos previsibilidade com NVIDIA.
unredir-if-possible = false;

# Transparência leve em janelas inativas
inactive-opacity = 0.97;
active-opacity = 1.0;
inactive-opacity-override = false;
PICOM_EOF

chmod 600 "$PICOM_CONF"

# ------------------------------------------------------------------------------
# 7. Autostart correto para um compositor de sessão X11
# ------------------------------------------------------------------------------

say '[7/9] Habilitando inicialização automática do Picom na sessão XFCE...'
mkdir -p "$AUTOSTART_DIR"

# O Arch instala /etc/xdg/autostart/picom.desktop. Criamos uma entrada com o
# mesmo nome no escopo do usuário para que esta configuração específica tenha
# precedência e use explicitamente ~/.config/picom.conf.
cat > "$AUTOSTART_FILE" <<AUTOSTART_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Picom
GenericName=X compositor
Comment=Picom GLX para XFCE/X11 + NVIDIA
TryExec=picom
Exec=picom --config "$PICOM_CONF" --log-level=WARN
OnlyShowIn=XFCE;
StartupNotify=false
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

chmod 600 "$AUTOSTART_FILE"

# ------------------------------------------------------------------------------
# 8. Teste controlado antes do reboot
# ------------------------------------------------------------------------------

say '[8/9] Reiniciando o Picom para validar a configuração...'
# Encerra somente instâncias anteriores do Picom; não mexe em outros processos.
pkill -x picom >/dev/null 2>&1 || true
sleep 1

# A opção --daemon permite testar a configuração ainda nesta sessão.
picom --config "$PICOM_CONF" --log-level=WARN --daemon
sleep 2

if pgrep -x picom >/dev/null 2>&1; then
    say '      Picom iniciado com sucesso.'
else
    warn 'o Picom não permaneceu em execução.'
    warn 'reativando o compositor do xfwm4 como rollback de segurança.'
    xfconf-query -c xfwm4 -p /general/use_compositing -s true >/dev/null 2>&1 || true
    fail 'teste do Picom falhou; o computador NÃO será reiniciado.'
fi

say '      Estado do xfwm4: compositor interno desativado.'
say '      Picom: ativo.'
say "      Backup: $BACKUP_DIR"

# ------------------------------------------------------------------------------
# 9. Reinicialização final
# ------------------------------------------------------------------------------

say '[9/9] Configuração concluída.'
say ''
say 'Após o próximo login XFCE/X11, o Picom será iniciado automaticamente.'
say ''

# Mantém uma saída de emergência útil para testes/empacotamento, mas o
# comportamento padrão solicitado pelo projeto é reiniciar o computador.
if [ "${NO_REBOOT:-0}" = '1' ]; then
    say 'NO_REBOOT=1 detectado: reinicialização automática ignorada.'
    exit 0
fi

say 'O computador será reiniciado automaticamente em 10 segundos.'
say 'Pressione Ctrl+C agora se precisar cancelar o reboot.'
sleep 10

sudo reboot
