if [[ $DESKTOP_SESSION != 'unity' ]]; then
  return 0
fi

# with qt-style-plugins ensure QT apps now pickup a GTK+2 theme
export QT_QPA_PLATFORMTHEME=gtk2
