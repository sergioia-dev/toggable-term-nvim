--- Shared plumbing for the two terminal sidebars: the terminal registry, the
--- focus helpers, the single window-close path and the focus-loss autocmd.
---
--- The vertical and horizontal terminals are separate modules that both register
--- themselves here, so the autocmd can find out which one owns the window that is
--- being left without knowing anything about them.
local M = {}

local config = require("toggable_term.config")

--- Registered terminal modules, filled by `toggable_term.init`.
local terminals = {}

--- True while a terminal is being closed, or focus is moved on purpose, so the
--- focus-loss autocmd never fights the toggle workflow.
local suppressed = false

--- Register a terminal module. A module provided here has to expose
--- `open/close/close_window/is_open/window/owns_window/tracked_window`.
--- @param mod table
function M.register(mod)
	terminals[#terminals + 1] = mod
end

--- True when the window exists and currently hosts a terminal buffer.
--- @param win integer|nil
--- @return boolean
function M.win_is_terminal(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
end

--- True when the window exists and is floating rather than a split.
--- @param win integer|nil
--- @return boolean
function M.win_is_float(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	return vim.api.nvim_win_get_config(win).relative ~= ""
end

--- True when the window is a floating window hosting a terminal buffer.
--- @param win integer|nil
--- @return boolean
function M.win_is_float_terminal(win)
	return M.win_is_float(win) and M.win_is_terminal(win)
end

--- Resolve a size option into a number of editor cells.
---
--- `size` is either a number of cells (`30` → 30 columns or lines) or a
--- percentage of `total` given as a string (`"30%"`). `nil` and `false` fall
--- back to `ratio`, the share-of-total option (`width_ratio` and friends). The
--- result is clamped to at least 1 cell and at most `total`.
--- @param size number|string|boolean|nil
--- @param total integer
--- @param ratio number
--- @return integer
function M.resolve_size(size, total, ratio)
	local value = nil

	if type(size) == "number" then
		value = size
	elseif type(size) == "string" then
		local percent = tonumber(size:match("^(%d+%.?%d*)%%$"))
		if percent then
			value = total * percent / 100
		else
			vim.notify_once(
				'toggable-term-nvim: expected a size in cells or as a percentage, e.g. 30 or "30%", got ' .. size,
				vim.log.levels.WARN
			)
		end
	elseif size ~= nil and size ~= false then
		vim.notify_once(
			'toggable-term-nvim: expected a size in cells or as a percentage, e.g. 30 or "30%"',
			vim.log.levels.WARN
		)
	end

	if not value then
		value = total * ratio
	end
	return math.max(1, math.min(total, math.floor(value)))
end

--- True when `win` is tracked by a registered terminal other than `mod`.
--- @param win integer|nil
--- @param mod table
--- @return boolean
function M.tracked_by_other(win, mod)
	if not win then
		return false
	end
	for _, other in ipairs(terminals) do
		if other ~= mod and other.tracked_window() == win then
			return true
		end
	end
	return false
end

--- The registered terminal module owning `win`, or nil when `win` is not one of
--- our terminals.
--- @param win integer|nil
--- @return table|nil
function M.owner_of_window(win)
	if not M.win_is_terminal(win) then
		return nil
	end
	for _, mod in ipairs(terminals) do
		if mod.owns_window(win) then
			return mod
		end
	end
	return nil
end

--- Focus a window that is neither floating nor a terminal. Floating windows are
--- skipped so a split is never anchored to mini.files' floating explorer or
--- another overlay.
function M.focus_non_terminal_window()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
		local buf = vim.api.nvim_win_get_buf(win)
		if not is_float and vim.bo[buf].buftype ~= "terminal" then
			vim.api.nvim_set_current_win(win)
			return
		end
	end
end

--- Run `fn` with focus-loss closing suppressed, so the autocmd does not react to
--- the window change the call itself causes.
--- @param fn function
function M.without_focus_close(fn)
	local previous = suppressed
	suppressed = true
	local ok, err = pcall(fn)
	suppressed = previous
	if not ok then
		vim.notify("toggable-term-nvim: " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- True when a terminal should be closed after losing focus.
--- @return boolean
function M.close_on_focus_loss()
	return config.options.close_on_focus_loss and not suppressed
end

--- Close a terminal window without the focus-loss autocmd reacting to it.
--- @param win integer
function M.close_window(win)
	if not M.win_is_terminal(win) then
		return
	end
	M.without_focus_close(function()
		pcall(vim.api.nvim_win_close, win, true)
	end)
end

--- Type `command` into the terminal whose job is `job`, followed by a newline, so a
--- freshly created terminal can start a program (see the `*_init` options). Called
--- once per terminal buffer, right when that buffer is created.
--- @param command string|nil
--- @param job integer|nil
--- @return boolean sent
function M.run_init_command(command, job)
	if type(command) ~= "string" or command == "" then
		return false
	end
	if type(job) ~= "number" then
		vim.notify("toggable-term-nvim: no terminal job for the init command", vim.log.levels.WARN)
		return false
	end

	local ok, sent = pcall(vim.fn.chansend, job, command .. "\n")
	if not ok then
		vim.notify("toggable-term-nvim: init command failed: " .. tostring(sent), vim.log.levels.ERROR)
		return false
	end
	if sent == 0 then
		vim.notify("toggable-term-nvim: the terminal refused the init command", vim.log.levels.WARN)
		return false
	end
	return true
end

--- Register the `WinLeave` autocmd that closes a terminal once focus leaves it.
---
--- The close is deferred with `vim.schedule` because at `WinLeave` time the
--- current window is still the one being left, so closing it from the callback
--- would abort the pending focus change.
function M.setup_autocmd()
	vim.api.nvim_create_autocmd("WinLeave", {
		group = vim.api.nvim_create_augroup("toggable_term_focus_close", { clear = true }),
		callback = function()
			if not M.close_on_focus_loss() then
				return
			end

			local left = vim.api.nvim_get_current_win()
			local owner = M.owner_of_window(left)
			if not owner then
				return
			end

			vim.schedule(function()
				if not M.close_on_focus_loss() then
					return
				end
				-- The toggle path may have closed it already, or the user may
				-- have moved back into it before this callback ran.
				if not M.win_is_terminal(left) then
					return
				end
				if vim.api.nvim_get_current_win() == left then
					return
				end
				owner.close_window(left)
			end)
		end,
	})
end

return M
