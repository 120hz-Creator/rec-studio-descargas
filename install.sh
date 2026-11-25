#!/usr/bin/env bash
set -euo pipefail

REPO="120hz-Creator/rec-studio-descargas"
URL="${REC_STUDIO_URL:-https://github.com/$REPO/releases/latest/download/Rec-Studio.AppImage}"

APP_DIR="$HOME/.local/share/rec-studio"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
APPIMAGE="$APP_DIR/Rec-Studio.AppImage"
LINK="$BIN_DIR/rec-studio"
DESKTOP="$APPS_DIR/rec-studio.desktop"
ICON="$ICON_DIR/rec-studio.png"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
  fail "No lo ejecutes con sudo ni como root. El script pide la contraseña solo cuando la necesita."
fi

case "$URL" in
  *TU_USUARIO*) fail "Falta configurar el repositorio en la variable REPO del script." ;;
esac

update_menu() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
  fi
}

uninstall() {
  say "Quitando Rec Studio"
  rm -f "$APPIMAGE" "$LINK" "$DESKTOP" "$ICON"
  rmdir "$APP_DIR" 2>/dev/null || true
  update_menu
  say "Listo. Tus grabaciones no se tocaron."
}

has_fuse() {
  [ -n "${REC_STUDIO_SKIP_DEPS:-}" ] && return 0
  { ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null || true; } | grep -q 'libfuse\.so\.2'
}

install_fuse() {
  if command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm fuse2
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y libfuse2t64 || sudo apt-get install -y libfuse2
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y fuse-libs
  else
    fail "Instala fuse2 (libfuse.so.2) con el gestor de tu distro y vuelve a ejecutar el script."
  fi
}

install_app() {
  command -v curl >/dev/null 2>&1 || fail "Hace falta curl."

  if ! has_fuse; then
    say "Instalando fuse2 (te pedirá la contraseña)"
    install_fuse
  fi

  mkdir -p "$APP_DIR" "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  say "Descargando Rec Studio"
  curl -fL --progress-bar -o "$tmp/Rec-Studio.AppImage" "$URL" || fail "No se pudo descargar $URL"
  [ "$(head -c 4 "$tmp/Rec-Studio.AppImage" | tail -c 3)" = "ELF" ] || fail "El archivo descargado no es un AppImage válido."

  chmod +x "$tmp/Rec-Studio.AppImage"
  mv -f "$tmp/Rec-Studio.AppImage" "$APPIMAGE"
  ln -sf "$APPIMAGE" "$LINK"

  say "Preparando el icono y el acceso directo"
  (cd "$tmp" && "$APPIMAGE" --appimage-extract '*.png' >/dev/null 2>&1) || true
  found=""
  if [ -d "$tmp/squashfs-root" ]; then
    found="$(find "$tmp/squashfs-root" -maxdepth 1 -name '*.png' 2>/dev/null | head -n 1 || true)"
    if [ -z "$found" ]; then
      found="$(find "$tmp/squashfs-root" -path '*512x512*' -name '*.png' 2>/dev/null | head -n 1 || true)"
    fi
  fi
  icon_name="application-x-executable"
  if [ -n "$found" ]; then
    cp -f "$found" "$ICON"
    icon_name="rec-studio"
  fi

  cat > "$DESKTOP" <<DESKTOP_ENTRY
[Desktop Entry]
Type=Application
Name=Rec Studio
Comment=Estudio de grabación con escenas, fuentes y mezclador de audio
Exec="$APPIMAGE"
Icon=$icon_name
Terminal=false
Categories=AudioVideo;Recorder;
StartupWMClass=Rec Studio
DESKTOP_ENTRY
  update_menu

  say "Instalado. Búscalo en el menú como Rec Studio o ejecuta: $LINK"

  if [ -z "${REC_STUDIO_NO_RUN:-}" ]; then
    say "Abriendo Rec Studio"
    nohup "$APPIMAGE" >/dev/null 2>&1 &
    disown || true
  fi
}

case "${1:-}" in
  --uninstall|uninstall) uninstall ;;
  *) install_app ;;
esac
