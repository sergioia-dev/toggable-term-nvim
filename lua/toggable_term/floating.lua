--- Floating terminal.
---
--- Owns one floating terminal buffer that is kept alive across toggles, so closing
--- the window — by toggling it off or by losing focus — never kills the shell.
local M = {}

local config = require("toggable_term.config")
local core = require("toggable_term.core")

--- Cached terminal buffer, reused by every later `open()`.
local term_buf = nil
--- Window currently hosting the terminal.
local term_win = nil

--- The tracked window, even when it is no longer valid.
--- @return integer|nil
function M.tracked_window()
	return term_win
end

--- The cached terminal buffer, even when the window no longer shows it because
--- a plugin replaced it. Terminal buffers keep `'bufhidden' = "hide"`, so the
--- session is intact when the buffer guard puts it back into the window.
--- @return integer|nil
function M.tracked_buffer()
	if type(term_buf) == "number" and vim.api.nvim_buf_is_valid(term_buf) then
		return term_buf
	end
	return nil
end

--- Geometry of the floating window, centred in the editor.
--- @return table
local function geometry()
	-- `float_width`/`float_height` win over the ratios; both are clamped to the editor.
	local width = core.resolve_size(config.options.float_width, vim.o.columns, config.options.float_width_ratio)
	local height = core.resolve_size(config.options.float_height, vim.o.lines, config.options.float_height_ratio)

	return {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		border = config.options.float_border,
		style = "minimal",
	}
end

--- The window hosting the terminal, or nil when it is not visible.
---
--- Only floating windows count here, so a split terminal is never mistaken for
--- this one. The tracked window is trusted first, the scan is only a fallback for
--- a floating terminal opened outside this module.
--- @return integer|nil
function M.window()
	if core.win_is_float_terminal(term_win) then
		return term_win
	end
	term_win = nil

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local is_ours = core.win_is_float_terminal(win) and not core.tracked_by_other(win, M)
		if is_ours then
			return win
		end
	end
	return nil
end

--- True while the terminal is visible.
--- @return boolean
function M.is_open()
	return M.window() ~= nil
end

--- True when `win` is this terminal's window.
--- @param win integer|nil
--- @return boolean
function M.owns_window(win)
	return M.window() == win and not core.tracked_by_other(win, M)
end

--- Close `win` and forget it when it was the tracked window.
--- @param win integer
function M.close_window(win)
	if not core.win_is_float_terminal(win) then
		return
	end
	core.close_window(win)
	if not core.win_is_float_terminal(term_win) then
		term_win = nil
	end
end

--- Close the terminal window if it is visible.
function M.close()
	local win = M.window()
	if win then
		M.close_window(win)
	end
end

--- Open the terminal in a centred floating window, reusing the cached buffer when
--- possible. Leaves the cursor in the floating window, in insert mode.
function M.open()
	local is_new = not (term_buf and vim.api.nvim_buf_is_valid(term_buf))
	-- A placeholder buffer is needed to open the window; `:terminal` replaces it,
	-- and `bufhidden = "wipe"` takes the placeholder with it.
	local buf = is_new and vim.api.nvim_create_buf(false, true) or term_buf
	if is_new then
		vim.bo[buf].bufhidden = "wipe"
	end

	term_win = vim.api.nvim_open_win(buf, true, geometry())

	if is_new then
		vim.cmd("terminal")
		term_buf = vim.api.nvim_get_current_buf()
		-- First creation of this terminal: start its init command, if one is set.
		core.run_init_command(config.options.float_init, vim.b.terminal_job_id)
	end

	vim.cmd("startinsert")
end

return M
