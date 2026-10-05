# toggable-term-nvim

Focus-aware terminal sidebars for Neovim: one **vertical** terminal on the right,
one **horizontal** terminal at the bottom and one **floating** terminal in the
centre of the editor.

Each keeps its buffer cached, so closing the window — by toggling it off or by
losing focus — never kills the shell. The next toggle brings back the same
session, with its scrollback.

## Install

`plugin/toggable_term.lua` registers the `:Term*` commands as soon as the plugin is on
the runtimepath, so nothing has to be required for them to exist. Calling `setup()`
is optional and only changes the defaults (see [Options](#options)). The plugin has
no dependencies and no build step, and is tested against Neovim 0.12.4; it uses
stable APIs only (`vim.api.nvim_create_user_command`, floating windows, `WinLeave`).

### lazy.nvim

```lua
{
	"sergioia-dev/toggable-term-nvim",
	-- `opts` is passed to require("toggable_term").setup().
	opts = {
		close_on_focus_loss = true,
		vertical_size = 30,
		horizontal_size = 30,
		float_width = 50,
		float_height = 50,
		horizontal_init = "opencode",
	},
	keys = {
		{ "<C-w>%", function() require("toggable_term").toggle_right_terminal() end, mode = { "n", "t" }, desc = "Toggle right terminal" },
		{ '<C-w>"', function() require("toggable_term").toggle_bottom_terminal() end, mode = { "n", "t" }, desc = "Toggle bottom terminal" },
		{ "<F2>", function() require("toggable_term").toggle_floating_terminal() end, mode = { "n", "t" }, desc = "Toggle floating terminal" },
	},
}
```

The plugin is not lazy-loaded by default, so this spec loads it at startup, which
is what makes the commands and the keymaps available immediately. LazyVim users
put the same spec in `lua/plugins/toggable-term.lua` (or any file under `lua/plugins/`).
If you prefer an explicit call, use `config = function() require("toggable_term").setup({ ... }) end`
instead of `opts`; both work.

### vim-plug

```vim
call plug#begin()
Plug 'sergioia-dev/toggable-term-nvim'
call plug#end()

lua << EOF
require("toggable_term").setup({ close_on_focus_loss = true })
EOF
```

### packer.nvim

```lua
use({
	"sergioia-dev/toggable-term-nvim",
	config = function()
		require("toggable_term").setup({ close_on_focus_loss = true })
	end,
})
```

### mini.deps

```lua
local add = MiniDeps.add
add({ source = "sergioia-dev/toggable-term-nvim" })
require("toggable_term").setup({ close_on_focus_loss = true })
```

### No plugin manager

```sh
git clone https://github.com/sergioia-dev/toggable-term-nvim \
	"${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start/toggable-term-nvim"
```

Neovim sources `plugin/` from every `pack/*/start/*` directory at startup, so the
`:Term*` commands exist after a restart. This is also the way to test a local
checkout: clone it anywhere and add that directory to the runtimepath with
`vim.opt.rtp:prepend("/path/to/toggable-term-nvim")`.

### Nix

```nix
toggable-term-nvim = pkgs.vimUtils.buildVimPlugin {
  pname = "toggable-term-nvim";
  version = "0.1.0";
  src = pkgs.fetchFromGitHub {
    owner = "sergioia-dev";
    repo = "toggable-term-nvim";
    rev = "6c8f4f3eb070d990bcec37cbf4bd1d31329abc4a";
    hash = "sha256-l8EuEPk1qam2OROHGBtweRn8BylOANDeQrOWCPIn+ws=";
  };
  doCheck = false;
};
```

Add the resulting derivation to `programs.neovim.configure.packages` or to the
`vimPlugins` list of your Neovim overlay; `plugin/toggable_term.lua` is sourced from
the packpath, so the commands exist with no `require` in your configuration.

## Options

```lua
require("toggable_term").setup({
	-- Close a terminal as soon as it loses focus (the buffer is cached, so the
	-- shell survives and the next toggle restores it).
	close_on_focus_loss = true,
	-- `close_on_focus` is accepted as an alias for the same option.

	-- When another plugin (fzf-lua, telescope, oil, ...) opens a file in the
	-- window that hosts one of these terminals, show the file in the principal
	-- window and put the terminal buffer back into its window. With no
	-- principal window left (a tab holding only the terminal) the file lands in
	-- that window, as it does with the option off.
	protect_terminal_windows = true,

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

Every key is optional and only the keys you pass are changed. Pass the table to
`opts` in a lazy.nvim spec (as above), to `config` in packer, or call
`require("toggable_term").setup({ ... })` yourself once the plugin is loaded.

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
terminal.vertical.tracked_buffer()         -- terminal buffer, even when hidden
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
- **A file opened by another plugin never replaces a terminal window**
  (`protect_terminal_windows`, on by default). Pickers load their selection into
  the window that was current, which may be one of ours, so the buffer is moved to
  the *principal* window — the last usable non-terminal window entered, then the
  alternate window, then any split of the current tab — and the terminal buffer is
  put back into its own window, so the shell session stays where it was. Focus
  follows the file. When the tab holds nothing but the terminal there is no
  principal window, and the file lands in the terminal window exactly as it does
  with the option off: the guard never cancels the edit.
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
