# flatpak only mounts org.freedesktop.Platform.GL.* extensions listed in FLATPAK_GL_DRIVERS
# (set by switch-flatpak), so also list the vulkan layer extension
if [ -n "$FLATPAK_GL_DRIVERS" ]; then
    case ":$FLATPAK_GL_DRIVERS:" in
        *:VK_LAYER_TEGRA_dc_present:*) ;;
        *) export FLATPAK_GL_DRIVERS="$FLATPAK_GL_DRIVERS:VK_LAYER_TEGRA_dc_present" ;;
    esac
fi
