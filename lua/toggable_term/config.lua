--- Options for toggable-term. Merged by `require("toggable_term").setup()`; only the
--- keys listed in `M.known` are accepted, any other key is ignored.
---
--- ```lua
--- require("toggable_term").setup({
--- 	close_on_focus_loss = true,
--- 	vertical_size = 30,
--- 	horizontal_size = "30%",
--- 	float_width = 50,
--- 	float_height = 50,
--- 	horizontal_init = "opencode",
--- 	before_open = function()
--- 		require("plugins.sidebars").close_other_sidebars()
--- 	end,
--- })
--- ```
local M = {}

--- Default options.
---
--- `close_on_focus_loss` is the focus-loss switch: while true a terminal closes as
--- soon as focus leaves it, but its buffer (and therefore its shell session and
--- scrollback) is cached, so the next toggle restores the same shell.
---
--- The `*_ratio` options size a terminal as a share of the editor; the `*_size`,
--- `float_width` and `float_height` options override them with a fixed size, given
--- either as a number of cells or as a percentage of the editor (`"30%"`).
---
--- `vertical_init`/`horizontal_init`/`float_init` are commands typed into the
--- terminal the first time it is created, e.g. `horizontal_init = "opencode"`
--- starts opencode in the bottom terminal. The cached buffer keeps the session, so
--- the command is not run again on later toggles.
M.defaults = {
	-- Close a terminal as soon as it loses focus.
	close_on_focus_loss = true,
	-- Right-side vertical terminal: share of the total `columns`.
	width_ratio = 0.30,
	-- Right-side vertical terminal: a fixed width in columns (`30`) or a share of
	-- the editor as a string (`"30%"`). nil/false keeps using `width_ratio`.
	vertical_size = nil,
	-- Bottom horizontal terminal: share of the total `lines`.
	height_ratio = 0.25,
	-- Bottom horizontal terminal: a fixed height in lines (`30`) or a share of the
	-- editor as a string (`"30%"`). nil/false keeps using `height_ratio`.
	horizontal_size = nil,
	-- Command run once in the vertical terminal, when its buffer is created.
	vertical_init = nil,
	-- Command run once in the horizontal terminal, when its buffer is created.
	horizontal_init = nil,
	-- Floating terminal: share of the total `columns`.
	float_width_ratio = 0.80,
	-- Floating terminal: share of the total `lines`.
	float_height_ratio = 0.80,
	-- Floating terminal: a fixed width in columns (`50`) or a share of the editor
	-- as a string (`"50%"`). nil/false keeps using `float_width_ratio`.
	float_width = nil,
	-- Floating terminal: a fixed height in lines (`50`) or a share of the editor
	-- as a string (`"50%"`). nil/false keeps using `float_height_ratio`.
	float_height = nil,
	-- Border of the floating terminal, any `nvim_open_win()` border value.
	float_border = "rounded",
	-- Command run once in the floating terminal, when its buffer is created.
	float_init = nil,
	-- Called right before a terminal opens; use it to close competing sidebars
	-- (DBUI, mini.files, ...) so only one sidebar is ever visible.
	before_open = nil,
}

--- Every option name `M.setup()` accepts. A defaults lookup cannot answer that on
--- its own: a Lua table literal drops keys whose value is nil, so `before_open` and
--- the `*_init` commands would look like unknown options.
M.known = {
	close_on_focus_loss = true,
	width_ratio = true,
	vertical_size = true,
	height_ratio = true,
	horizontal_size = true,
	vertical_init = true,
	horizontal_init = true,
	float_width_ratio = true,
	float_height_ratio = true,
	float_width = true,
	float_height = true,
	float_border = true,
	float_init = true,
	before_open = true,
}

--- Alias names accepted by `M.setup()`: `close_on_focus` is a convenience
--- spelling of `close_on_focus_loss`, `floating_width`/`floating_height` of
--- `float_width`/`float_height`.
M.aliases = {
	close_on_focus = "close_on_focus_loss",
	floating_width = "float_width",
	floating_height = "float_height",
}

--- Active options, seeded from `M.defaults`.
M.options = vim.deepcopy(M.defaults)

--- Merge `opts` into the active options.
---
--- `setup({ an_option = nil })` cannot clear an option: `pairs()` skips nil
--- values, so the key never reaches this function. Pass `false` to disable
--- `before_open` or an `*_init` command again.
--- @param opts table|nil
--- @return table options
function M.setup(opts)
	if type(opts) ~= "table" then
		return M.options
	end
	for key, value in pairs(opts) do
		local name = M.aliases[key] or key
		if M.known[name] then
			M.options[name] = value
		end
	end
	return M.options
end

return M
