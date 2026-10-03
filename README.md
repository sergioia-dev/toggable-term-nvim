# toggable-term-nvim

Focus-aware terminal sidebars for Neovim: one **vertical** terminal on the right,
one **horizontal** terminal at the bottom and one **floating** terminal in the
centre of the editor.

Each keeps its buffer cached, so closing the window — by toggling it off or by
losing focus — never kills the shell. The next toggle brings back the same
session, with its scrollback.

## Install

The plugin lives in this repo as `plugins/toggable-term` and is installed by the
flake like the other in-tree plugins:

- `derivations/toggable-term-nvim/default.nix` builds it with `vimUtils.buildVimPlugin`
  (a plain directory *is* part of the flake source, so no `fetchFromGitHub`).
- `flake.nix` exposes it as `vimPlugins.toggable-term-nvim` and `neovim.nix` adds it to
  `startPlugins`, so `plugin/toggable_term.lua` is sourced from the packpath and
  the `:Term*` commands exist without any `require` in the configuration.

## Options

```lua
require("toggable_term").setup({
	-- Close a terminal as soon as it loses focus (the buffer is cached, so the
	-- shell survives and the next toggle restores it).
	close_on_focus_loss = true,
	-- `close_on_focus` is accepted as an alias for the same option.

	-- Right-side vertical terminal: share of the total `columns`.
	width_ratio = 0.30,

	-- Bottom horizontal terminal: share of the total `lines`.
	height_ratio = 0.25,

	-- Fixed sizes instead of the ratios: a number of cells (`vertical_size = 30`
	-- → 30 columns wide) or a percentage of the editor (`vertical_size = "30%"`).
	-- These win over the ratios above, which stay the fallback; nil or false
	-- keeps using the ratio.
	vertical_size = nil,
	horizontal_size = nil,

	-- Floating terminal: share of the total `columns` / `lines`, and the border
	-- passed to `nvim_open_win()` ("none", "single", "double", "rounded", ...).
	float_width_ratio = 0.80,
	float_height_ratio = 0.80,
	float_border = "rounded",

	-- Floating terminal: same fixed-size options as above.
	-- `floating_width`/`floating_height` are accepted as aliases.
	float_width = nil,
	float_height = nil,

	-- Command typed into a terminal the first time it is created, e.g. start a
	-- program in the bottom terminal with `horizontal_init = "opencode"`. The
	-- buffer is cached, so it is not run again on later toggles.
	vertical_init = nil,
	horizontal_init = nil,
	float_init = nil,

	before_open = nil 
```

In this configuration the call lives in `configuration/lua/plugins/toggable-term.lua`,
following the one-file-per-plugin convention of `configuration/lua/plugins/` (each file calls
`require(...).setup{...}` and `configuration/lua/plugins/init.lua` requires them all).

`close_on_focus_loss` can also be flipped at runtime, either through the Lua API
or with `:TermFocusClose on|off|toggle`.

## Commands

| Command | Description |
| --- | --- |
| `:TermVertical` | Toggle the vertical (right) terminal |
| `:TermHorizontal` | Toggle the horizontal (bottom) terminal |
| `:TermFloat` | Toggle the floating terminal |
| `:TermFocusClose [on\|off\|toggle]` | Turn closing on focus loss on/off |

## Lua API

```lua
local terminal = require("toggable_term")

terminal.setup(opts)                       -- merge options
terminal.options()                         -- active options table

terminal.toggle_right_terminal()           -- vertical on/off
terminal.toggle_bottom_terminal()          -- horizontal on/off
terminal.toggle_floating_terminal()        -- floating on/off

terminal.close_vertical_terminal()
terminal.close_horizontal_terminal()
terminal.close_floating_terminal()
terminal.close_terminal()                  -- all of them

terminal.close_on_focus_loss()             -- the current value
terminal.set_close_on_focus_loss(true)     -- set it; no argument toggles

terminal.vertical.window()                 -- hosting window id, or nil
terminal.horizontal.is_open()              -- boolean
terminal.floating.is_open()                -- boolean
```

Example keymaps (the ones this repo uses):

```lua
vim.keymap.set({ "n", "t" }, "<C-w>%", require("toggable_term").toggle_right_terminal)
vim.keymap.set({ "n", "t" }, '<C-w>"', require("toggable_term").toggle_bottom_terminal)
```

## Behavior

- **Why a window is closed on focus loss.** A `WinLeave` autocmd registers the
  window that is being left, then closes it from a deferred `vim.schedule`
  callback. The close has to be deferred: at `WinLeave` time the current window is
  *still* the one being left, so closing it from the callback would abort the
  pending focus change. The callback re-checks that the window is still a
  terminal and still unfocused, so the toggle path — which closes the same
  window — can never fight it.
- **Terminal buffers are cached**, and terminal buffers default to
  `'bufhidden' = "hide"`, so closing the window keeps the shell, its job id and
  its scrollback alive. `jobwait([job], 0)` still returns `-1` while the terminal
  is hidden.
- **Sizes.** The `*_ratio` options size a terminal as a share of the editor.
  `vertical_size`, `horizontal_size`, `float_width` and `float_height` override
  them with a fixed size, given either as a number of cells (`vertical_size = 30`)
  or as a percentage of the editor (`horizontal_size = "30%"`); the result is
  clamped to at least one cell and to the editor itself. `nil` or `false` keeps
  using the ratio, and a value that is neither a number nor a `"N%"` string warns
  once and falls back to it.
- **`vertical_init`/`horizontal_init`/`float_init` run once per terminal buffer**,
  right when it is created, so `horizontal_init = "opencode"` starts opencode in
  the bottom terminal. Because the buffer is cached, later toggles return to the
  running session instead of starting a second one; change the option and wipe the
  buffer (`:bd!`) to get a fresh terminal with a new init command.
  Pass `false` to turn an init command off again: `setup({ x = nil })` cannot
  clear an option, because Lua's `pairs()` skips nil values.
- **The floating terminal** is a `relative = "editor"` float, centred and sized by
  `float_width` × `float_height` (or, when those are unset, `float_width_ratio` ×
  `float_height_ratio`) in editor cells, with `float_border`.
  It is opened on a throwaway scratch buffer that `:terminal` immediately replaces,
  so no stray buffer is left behind, and it follows the same focus-loss rules as
  the splits.
- **The tracked window is remembered**, with a size heuristic (≤ the configured
  width in columns / height in lines) only as a fallback, so resizing a split with
  `:vertical resize` does not break detection. Floating windows are excluded from
  the heuristic, so a small float is never mistaken for a sidebar.
- **Only one sidebar at a time**: opening a terminal closes the terminals of the
  other kinds, and `before_open` is where a configuration closes sidebars it owns
  (DBUI, mini.files).
- **`<Esc>` (leaving terminal mode) does not close** the terminal: it stays in the
  same window, so no `WinLeave` fires.
- Switching tab pages closes a focused terminal too, because the tracked window id
  is checked for validity rather than compared against the current tab. The shell
  session survives, so toggling again in any tab restores it.
