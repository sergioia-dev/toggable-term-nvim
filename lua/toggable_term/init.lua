--- Focus-aware terminal sidebars for Neovim: one vertical (right), one horizontal
--- (bottom) and one floating terminal, each caching its buffer so a toggle brings
--- back the same shell session.
---
--- ```lua
--- require("toggable_term").setup({
--- 	close_on_focus_loss = true,
--- 	before_open = function()
--- 		require("plugins.sidebars").close_other_sidebars()
--- 	end,
--- })
---
--- vim.keymap.set({ "n", "t" }, "<C-w>%", require("toggable_term").toggle_right_terminal)
--- vim.keymap.set({ "n", "t" }, '<C-w>"', require("toggable_term").toggle_bottom_terminal)
--- ```
local M = {}

local config = require("toggable_term.config")
local core = require("toggable_term.core")
local horizontal = require("toggable_term.horizontal")
local vertical = require("toggable_term.vertical")
local floating = require("toggable_term.floating")

--- The terminals a `*_background_init` option can start, by the name used in
--- the options (`float` rather than `floating`).
local kinds = {
	vertical = vertical,
	horizontal = horizontal,
	float = floating,
}

--- Option that switches the background start of each kind on.
local background_init_option = {
	vertical = "vertical_background_init",
	horizontal = "horizontal_background_init",
	float = "float_background_init",
}

core.register(vertical)
core.register(horizontal)
core.register(floating)
core.setup_autocmd()
core.setup_buffer_guard()

--- True when at least one `*_background_init` option asks for a background
--- terminal. A value that is neither boolean counts too, so `M.setup()` still
--- hands it to the kind, which warns about it.
--- @return boolean
local function background_init_requested()
	for _, option in pairs(background_init_option) do
		local value = config.options[option]
		if value ~= nil and value ~= false then
			return true
		end
	end
	return false
end

--- True while a background preload is waiting for the event loop.
local preload_scheduled = false

--- Start the terminals whose `*_background_init` option is on, without a window.
---
--- Every kind is asked: it skips itself when its option is off or when it
--- already has a buffer, so preloading twice never starts a second session.
local function preload_background_terminals()
	for _, kind in pairs(kinds) do
		kind.preload()
	end
end

--- Preload the background terminals once the current `setup()` is over.
---
--- Deferred with `vim.schedule()` so `setup()` never spawns a shell while the
--- options are still being merged, and guarded so repeated `setup()` calls (a
--- reload of the plugin spec, for instance) do not preload in parallel. A later
--- `setup()` that switches another kind on still starts that one.
local function schedule_preload()
	if preload_scheduled or not background_init_requested() then
		return
	end
	preload_scheduled = true
	vim.schedule(function()
		preload_scheduled = false
		preload_background_terminals()
	end)
end

--- Merge options (see `toggable_term.config` for the full list, including the
--- `close_on_focus_loss` switch).
--- @param opts table|nil
--- @return table options
function M.setup(opts)
	local options = config.setup(opts)
	schedule_preload()
	return options
end

--- The active options table.
--- @return table
function M.options()
	return config.options
end

--- Whether terminals currently close as soon as they lose focus.
--- @return boolean
function M.close_on_focus_loss()
	return config.options.close_on_focus_loss
end

--- Enable/disable closing on focus loss. Without an argument the current value
--- is toggled.
--- @param value boolean|nil
--- @return boolean enabled
function M.set_close_on_focus_loss(value)
	if value == nil then
		config.options.close_on_focus_loss = not config.options.close_on_focus_loss
	else
		config.options.close_on_focus_loss = not not value
	end
	return config.options.close_on_focus_loss
end

--- Close the vertical terminal window if one is visible.
function M.close_vertical_terminal()
	vertical.close()
end

--- Close the horizontal terminal window if one is visible.
function M.close_horizontal_terminal()
	horizontal.close()
end

--- Close the floating terminal window if one is visible.
function M.close_floating_terminal()
	floating.close()
end

--- Close every terminal window if visible.
function M.close_terminal()
	vertical.close()
	horizontal.close()
	floating.close()
end

--- Toggle the right-side vertical terminal (`width_ratio` wide). Any terminal of
--- another kind and any other sidebar are closed first, so exactly one sidebar is
--- visible at a time.
function M.toggle_right_terminal()
	core.focus_non_terminal_window()

	if vertical.is_open() then
		vertical.close()
		return
	end

	if config.options.before_open then
		config.options.before_open()
	end
	horizontal.close()
	floating.close()

	vertical.open()
end

--- Toggle the bottom horizontal terminal (`height_ratio` tall). Any terminal of
--- another kind and any other sidebar are closed first, so exactly one sidebar is
--- visible at a time.
function M.toggle_bottom_terminal()
	core.focus_non_terminal_window()

	if horizontal.is_open() then
		horizontal.close()
		return
	end

	if config.options.before_open then
		config.options.before_open()
	end
	vertical.close()
	floating.close()

	horizontal.open()
end

--- Toggle the floating terminal (`float_width_ratio` × `float_height_ratio`,
--- centred, `float_border`). Any terminal of another kind and any other sidebar
--- are closed first, so exactly one sidebar is visible at a time.
function M.toggle_floating_terminal()
	core.focus_non_terminal_window()

	if floating.is_open() then
		floating.close()
		return
	end

	if config.options.before_open then
		config.options.before_open()
	end
	vertical.close()
	horizontal.close()

	floating.open()
end

--- The individual terminals, for direct access:
--- `require("toggable_term").vertical.open()`.
M.vertical = vertical
M.horizontal = horizontal
M.floating = floating

return M
