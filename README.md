# Windscribe for Omarchy

Bar widget for the [Omarchy](https://omarchy.org) Quattro shell. It wraps `windscribe-cli`: connection state in the bar, a keyboard-friendly panel for locations, protocol, firewall, and IP tools.

## Install

Requires [`windscribe-cli`](https://windscribe.com/guides/linux) on `PATH`, already logged in (`windscribe-cli login`).

```sh
omarchy plugin add https://github.com/tuxr/omarchy-windscribe.git --enable
```

Place it if the default right-section slot is not what you want:

```sh
omarchy bar move io.github.dsumpter.windscribe --section right
```

## Usage

- Left click the shield: open or close the panel
- Right click: connect to best / disconnect
- Middle click: refresh
- Escape closes the panel

Inside the panel:

| Key | Action |
| --- | --- |
| `j` / `k` or arrows | move cursor |
| Enter / Space | expand a region, or connect a city |
| `h` / `l` or left/right | collapse / expand region |
| `/` or `s` | focus location search (type normally, including j/k) |
| `t` or `c` | toggle VPN |
| `r` | refresh |
| `f` | toggle firewall |
| `i` | rotate IP (while connected) |
| `p` | pin current IP to favourites |
| `y` | copy VPN IP |

Locations browse like the desktop app: **Best location**, then expandable regions (`US West`, `Japan`, …). Expand a region to see `City  Nickname` rows (e.g. `Seattle  Cobain`). Search filters the tree. **Favs** and **Static** tabs appear when `windscribe-cli` reports any.

## Configure

Widget settings (refresh interval, default connect protocol) live in the Omarchy bar widget editor. Protocol is also on the panel; Auto uses the CLI's last / preferred protocol.

## IPC

```sh
omarchy-shell io.github.dsumpter.windscribe status
omarchy-shell io.github.dsumpter.windscribe connectBest
omarchy-shell io.github.dsumpter.windscribe disconnect
omarchy-shell io.github.dsumpter.windscribe rotateIp
omarchy-shell io.github.dsumpter.windscribe pinIp
omarchy-shell io.github.dsumpter.windscribe refresh
omarchy-shell io.github.dsumpter.windscribe open
omarchy-shell io.github.dsumpter.windscribe close
omarchy-shell io.github.dsumpter.windscribe toggle
```

## Develop

Source of truth is this repository. On a machine you are iterating on, symlink it into the user plugin directory (Omarchy discovers `~/.config/omarchy/plugins/<id>`):

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.dsumpter.windscribe
omarchy plugin validate ~/.config/omarchy/plugins/io.github.dsumpter.windscribe
omarchy plugin enable io.github.dsumpter.windscribe right
omarchy-shell shell rescanPlugins
```

`omarchy plugin validate` must be run against this repository path, not the `~/.config/omarchy/plugins/...` symlink. The validator treats the symlink itself as a forbidden link; the shell still loads symlink installs, and `omarchy plugin remove` knows how to unlink them.

`windscribe-cli` is single-instance. The service serializes every spawn; do not add a second concurrent CLI call.

IPC handler changes need `omarchy-restart-shell`. Manifest and QML edits usually hot-reload after `touch manifest.json` or `omarchy-shell shell rescanPlugins`. Follow live logs with:

```sh
qs -p "$OMARCHY_PATH/shell" log -f
```

## Remove

```sh
omarchy plugin remove io.github.dsumpter.windscribe
```

## License

MIT. See [LICENSE](LICENSE).
