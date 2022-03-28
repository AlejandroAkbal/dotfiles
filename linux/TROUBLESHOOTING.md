# Troubleshooting

## Specific

### Firefox

If Firefox is opening under different icons on the desktop, modify this file:

```shell
~/.local/share/applications/firefox_dev.desktop
```

Which should end up looking like this:

```desktop
[Desktop Entry]
Name=Firefox Developer
GenericName=Firefox Developer Edition
Exec=/usr/local/bin/firefox_dev/firefox %u
Terminal=false
Icon=/usr/local/bin/firefox_dev/browser/chrome/icons/default/default128.png
Type=Application
Categories=Application;Network;X-Developer;
Comment=Firefox Developer Edition Web Browser.
StartupWMClass=firefox-aurora
```

If `StartupWMClass` is different, get the current WMClass from `xprop`:

```shell
xprop | grep WM_CLASS
```

Then change the `StartupWMClass` to the current WMClass.
