# omarchy_clipboard

Omarchy shell plugin. Replaces the stock clipboard overlay with pins, boards, snippets, type chips, and a stack.

Enabling it takes over `omarchy.clipboard`, so **Super+Ctrl+V** keeps working.

## Install

```bash
omarchy plugin add https://github.com/0-CYBERDYNE-SYSTEMS-0/omarchy_clipboard.git --enable
```

Review the code before you enable it. Plugins run unsandboxed inside `omarchy-shell`.

Optional extra hotkey in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + V", "Clipboard history", "omarchy-shell shell toggle omarchy.clipboard")
```

## Overlay

| Key | Action |
|---|---|
| Type | Search |
| Enter | Insert into the focused window |
| Shift+Enter | Copy only |
| Alt+Enter | Open |
| Ctrl+P | Pin / unpin |
| Ctrl+S | Save / clear snippet |
| Ctrl+B | Assign to current board |
| Ctrl+N | New board |
| Ctrl+Space | Add / remove from stack |
| Ctrl+Enter | Insert the whole stack |
| Ctrl+[ / ] | Cycle type chips |
| Ctrl+Tab | Cycle boards |
| Delete | Remove one clip |
| Shift+Delete | Clear unpinned history (pins and snippets stay) |

## CLI

The plugin ships `bin/omarchy-clips`. Symlink it onto your PATH if you want:

```bash
ln -s ~/.config/omarchy/plugins/cyberdyne.clipboard/bin/omarchy-clips ~/.local/bin/omarchy-clips
```

```bash
omarchy-clips search token
omarchy-clips list --pinned
omarchy-clips pin 1
omarchy-clips snippet <id>
omarchy-clips board 1 Work
omarchy-clips paste 1
omarchy-clips stack add 1
omarchy-clips stack paste
```

Indexes are 1-based from the current list. Ids are stable and better for scripts.

## Store

- History: `~/.local/state/omarchy/clipboard-history.json`
- Boards / stack: `~/.local/state/omarchy/clipboard-extras.json`
- Images: `~/.local/state/omarchy/clipboard-images/`

Stock helpers still work. Extra fields (`id`, `kind`, `pinned`, `snippet`, `board`, `capturedAt`) are additive.

## Remove

```bash
omarchy plugin remove cyberdyne.clipboard
```

That restores the stock clipboard overlay.
