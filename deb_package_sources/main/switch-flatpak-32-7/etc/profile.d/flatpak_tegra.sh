export FLATPAK_GL_DRIVERS=nvidia-tegra-32-7-4
if command -v flatpak > /dev/null && [ -n "$DESKTOP_SESSION" ]; then
    if [ ! -f ~/.local/share/flatpak/overrides/global ]; then
  	    flatpak override --user --device=all --share=network --filesystem=/sys
    elif ! (grep -q "shared=network;" ~/.local/share/flatpak/overrides/global && grep -q "devices=all;" ~/.local/share/flatpak/overrides/global && grep -q "filesystems=/sys;" ~/.local/share/flatpak/overrides/global) ; then
        flatpak override --user --device=all --share=network --filesystem=/sys
    fi
fi
