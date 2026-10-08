--- Horizontal (bottom) terminal sidebar.
---
--- Owns one terminal buffer that is kept alive across toggles, so closing the
--- window — by toggling it off or by losing focus — never kills the shell.
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

--- Configured height in lines: `horizontal_size` when set, `height_ratio`
--- otherwise. Currently rendered sizes are not remembered.
--- @return integer
local function height()
	return core.resolve_size(config.options.horizontal_size, vim.o.lines, config.options.height_ratio)
end

--- The window hosting the terminal, or nil when it is not visible.
---
--- The tracked window is trusted first; the size heuristic is only a fallback,
--- for a terminal that was resized or opened outside this module.
--- @return integer|nil
function M.window()
	if core.win_is_terminal(term_win) then
		return term_win
	end
	term_win = nil

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local is_ours = core.win_is_terminal(win)
			and not core.tracked_by_other(win, M)
			and not core.win_is_float(win)
			and vim.api.nvim_win_get_height(win) <= height()
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
	if not core.win_is_terminal(win) then
		return
	end
	core.close_window(win)
	if not core.win_is_terminal(term_win) then
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

--- Create the terminal without a window, so `horizontal_init` is already running
--- when the terminal is first toggled (`horizontal_background_init`).
--- @return boolean started
function M.preload()
	if not core.background_init_enabled("horizontal_background_init") then
		return false
	end
	if M.tracked_buffer() then
		return false
	end
	local buf = core.create_background_terminal(config.options.horizontal_init, vim.o.columns, height())
	if not buf then
		return false
	end
	term_buf = buf
	return true
end

--- Open the terminal at the bottom, reusing the cached buffer when possible.
--- Leaves the cursor in the new terminal window, in insert mode.
function M.open()
	vim.cmd("botright " .. height() .. "split")

	if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
		vim.api.nvim_win_set_buf(0, term_buf)
	else
		vim.cmd("terminal")
		term_buf = vim.api.nvim_get_current_buf()
		-- First creation of this terminal: start its init command, if one is set.
		core.run_init_command(config.options.horizontal_init, vim.b.terminal_job_id)
	end

	term_win = vim.api.nvim_get_current_win()
	-- A terminal created by `M.preload()` kept the size its pseudo-terminal had
	-- while hidden; Neovim does not resize it when the window shows it.
	core.resize_terminal(term_buf, term_win)
	vim.cmd("startinsert")
end

return M
