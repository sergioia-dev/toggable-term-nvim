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
--- `open/close/close_window/is_open/window/owns_window/tracked_window/tracked_buffer`.
---
--- `preload()` is optional: it creates the terminal — and runs its `*_init`
--- command — without a window, for the `*_background_init` options.
---
--- `tracked_window()` and `tracked_buffer()` have to be pure getters: the buffer
--- guard calls them for a window that no longer hosts a terminal, while
--- `window()`/`owns_window()` clear a stale tracked window as a side effect.
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

--- True when the buffer exists and is a terminal buffer.
--- @param buf integer|nil
--- @return boolean
function M.buf_is_terminal(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	return vim.bo[buf].buftype == "terminal"
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

--- The module tracking `win`, even when `win` no longer hosts a terminal buffer
--- because a picker replaced it.
---
--- `M.owner_of_window()` cannot answer that: it requires the window to host a
--- terminal today, and `owns_window()` clears a stale tracked window as a side
--- effect. The buffer guard has to recognise the very window it is about to
--- restore, so this uses the pure `tracked_window()` getters only.
--- @param win integer|nil
--- @return table|nil
function M.owner_of_tracked_window(win)
	if type(win) ~= "number" or win <= 0 or not vim.api.nvim_win_is_valid(win) then
		return nil
	end
	for _, mod in ipairs(terminals) do
		if mod.tracked_window() == win then
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

--- Size the pseudo-terminal of `buf` in cells.
--- @param buf integer|nil
--- @param cols integer
--- @param rows integer
--- @return boolean resized
function M.resize_terminal_to(buf, cols, rows)
	if not M.buf_is_terminal(buf) then
		return false
	end
	local job = vim.b[buf].terminal_job_id
	if type(job) ~= "number" or job <= 0 then
		return false
	end
	local width = math.max(1, math.floor(tonumber(cols) or 1))
	local height = math.max(1, math.floor(tonumber(rows) or 1))
	return pcall(vim.fn.jobresize, job, width, height)
end

--- The part of `win` that is left for its buffer, in cells.
---
--- Neovim clamps a displayed terminal to the window's text area, so that is the
--- area the pseudo-terminal has to be sized to: `textoff` columns are kept for
--- `'number'` and friends, `winbar` lines for the winbar. Both are clamped to at
--- least 1, because a pty of 0 cells is not a size.
--- @param win integer|nil
--- @return table|nil area `{ cols = integer, rows = integer }`
function M.win_text_area(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return nil
	end
	local info = vim.fn.getwininfo(win)[1]
	local cols = vim.api.nvim_win_get_width(win) - (info and info.textoff or 0)
	local rows = vim.api.nvim_win_get_height(win) - (info and info.winbar or 0)
	return { cols = math.max(1, cols), rows = math.max(1, rows) }
end

--- Size the pseudo-terminal of `buf` like the text area of the window hosting it.
---
--- The pty gets the cells the window leaves for its buffer, not the whole window,
--- so the number column (see the `*_line_number` options) never hides terminal
--- output and Neovim never has to clamp the display afterwards. A terminal created
--- without a window (see `M.create_background_terminal()`) keeps the size its pty
--- had back then, even once a window shows it, so the size has to be applied again
--- on the first open. A no-op for a terminal that was created in its window the
--- usual way.
---
--- Showing a terminal that Neovim did not create in this window schedules a
--- resize of its pty to the window size Neovim saw before the `*_line_number`
--- options were applied, and that scheduled resize runs after this function
--- returns. The `:redraw` below lets it run first, so the explicit resize is the
--- last word on the size and `textoff` really is taken off the pty.
--- @param buf integer|nil
--- @param win integer|nil
--- @return boolean resized
function M.resize_terminal(buf, win)
	local area = M.win_text_area(win)
	if not area then
		return false
	end
	vim.cmd("redraw")
	return M.resize_terminal_to(buf, area.cols, area.rows)
end

--- Apply the `*_line_number`/`*_relative_line_number` options of `kind` to `win`.
---
--- The values are explicit: `true` turns the option on in that window, `false`
--- (the default) turns it off, so the terminal never inherits the global
--- `'number'`/`'relativenumber'`. Applied on every open, so a recreated window —
--- including the first open of a preloaded terminal — uses the values of the
--- latest `setup()`.
--- @param win integer|nil
--- @param kind string
--- @return boolean applied
function M.apply_line_number_options(win, kind)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	vim.wo[win].number = M.boolean_option(kind .. "_line_number")
	vim.wo[win].relativenumber = M.boolean_option(kind .. "_relative_line_number")
	return true
end

--- Read a strict boolean option.
---
--- Only a real boolean counts: `true` and `false` keep their meaning, while any
--- other value (`"yes"`, `1`) warns once and counts as `false`, so a typo can
--- never switch something on behind the user's back.
--- @param name string
--- @return boolean
function M.boolean_option(name)
	local value = config.options[name]
	if value == nil or value == false then
		return false
	end
	if value ~= true then
		vim.notify_once(
			"toggable-term-nvim: " .. name .. " expects true or false, got " .. vim.inspect(value),
			vim.log.levels.WARN
		)
		return false
	end
	return true
end

--- True when a `*_background_init` option is switched on.
---
--- The strict boolean reading is shared with the `*_line_number` options, so
--- `background_init_enabled(name)` and `boolean_option(name)` behave the same.
--- @param name string
--- @return boolean
function M.background_init_enabled(name)
	return M.boolean_option(name)
end

--- Create the terminal of a kind without any window, so its `*_init` command is
--- already running when the terminal is first toggled (`*_background_init`).
---
--- `cols`/`rows` size the pseudo-terminal right away: without a window the pty
--- would inherit the size of the internal window `nvim_buf_call()` uses, and
--- Neovim does not resize a terminal that was created while hidden when it is
--- shown later. The init command is typed after that resize, so a program that
--- reads the terminal size at startup sees the geometry it will be shown in.
--- @param command string|nil
--- @param cols integer
--- @param rows integer
--- @return integer|nil buf
function M.create_background_terminal(command, cols, rows)
	local buf = vim.api.nvim_create_buf(false, true)
	local ok, err = true, nil
	M.without_focus_close(function()
		ok, err = pcall(vim.api.nvim_buf_call, buf, function()
			vim.fn.termopen(vim.o.shell)
		end)
	end)

	local job = vim.b[buf].terminal_job_id
	if not ok or not M.buf_is_terminal(buf) or type(job) ~= "number" or job <= 0 then
		vim.notify_once(
			"toggable-term-nvim: could not start a terminal in the background: " .. tostring(err),
			vim.log.levels.WARN
		)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		return nil
	end

	-- `:terminal`-style buffers are listed; a background terminal should only
	-- appear in `:ls` once it has been opened.
	vim.bo[buf].buflisted = false
	vim.bo[buf].bufhidden = "hide"
	M.resize_terminal_to(buf, cols, rows)
	M.run_init_command(command, job)
	return buf
end

--- Close `left` when the focus has moved away from it and it still hosts one of
--- our terminals, mirroring the deferred half of the focus-loss autocmd.
--- @param left integer
local function focus_loss_close(left)
	if not M.close_on_focus_loss() then
		return
	end
	-- The toggle path may have closed it already, or the user may have moved
	-- back into it before this callback ran.
	if not M.win_is_terminal(left) then
		return
	end
	if vim.api.nvim_get_current_win() == left then
		return
	end
	local owner = M.owner_of_window(left)
	if not owner then
		return
	end
	owner.close_window(left)
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
				focus_loss_close(left)
			end)
		end,
	})
end

--- Last window seen hosting a normal (non-terminal) buffer, used as the
--- preferred destination for a buffer that has to leave a terminal window.
--- Only a hint: `acceptable_window()` re-checks it before every use, so a window
--- that has since become a terminal is skipped.
local primary_win = nil

--- True while `M.redirect_to_primary()` moves buffers around, so the `BufWinEnter`
--- events it causes cannot re-enter the guard.
local redirecting = false

--- True when `win` may take a buffer that was headed for a terminal window: a
--- valid split of the current tab that hosts neither a terminal nor one of our
--- terminal windows.
---
--- `win <= 0` is checked explicitly: `nvim_win_is_valid(0)` is true, 0 stands
--- for the current window, and `win_getid(winnr("#"))` returns 0 when there is no
--- alternate window.
--- @param win integer|nil
--- @return boolean
local function acceptable_window(win)
	if type(win) ~= "number" or win <= 0 or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	if M.win_is_float(win) or M.win_is_terminal(win) then
		return false
	end
	if M.owner_of_tracked_window(win) then
		return false
	end
	return vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

--- Where a buffer taken out of a terminal window should go: the remembered
--- principal window while it is still usable, then the alternate window
--- (`winnr("#")`), then any window of this tab that can host it. nil when all
--- that is left are terminals or floats.
--- @return integer|nil
function M.primary_window()
	if acceptable_window(primary_win) then
		return primary_win
	end

	local alternate = vim.fn.win_getid(vim.fn.winnr("#"))
	if acceptable_window(alternate) then
		return alternate
	end

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if acceptable_window(win) then
			return win
		end
	end

	return nil
end

--- Move `buf` out of the terminal window `win` into the principal window, and
--- put the terminal's buffer back into `win`.
---
--- This is what stops fzf-lua, telescope and friends from replacing a terminal:
--- they load their selection into the window that was current, which may be one
--- of ours. Without a principal window (`target` would be `win` itself) nothing
--- happens, so the buffer stays where it landed instead of the edit being
--- swallowed.
---
--- The buffers are swapped and the focus is moved right away, so the buffer is
--- already in its final window when the caller continues (telescope positions
--- the cursor last). Because the guard runs inside `BufWinEnter`, that focus
--- change emits no `WinLeave`: the focus-loss policy for `win` is applied
--- explicitly instead.
--- @param win integer
--- @param buf integer
--- @return boolean redirected
function M.redirect_to_primary(win, buf)
	if redirecting then
		return false
	end

	local mod = M.owner_of_tracked_window(win)
	local term_buf = mod and type(mod.tracked_buffer) == "function" and mod.tracked_buffer()
	local target = M.primary_window()

	if not target or target == win or not term_buf then
		return false
	end

	local was_current = vim.api.nvim_get_current_win() == win

	redirecting = true
	local ok, err = pcall(function()
		vim.api.nvim_win_set_buf(target, buf)
		-- Restore the terminal before the focus change: the focus-loss autocmd
		-- only closes a window that still hosts a terminal.
		vim.api.nvim_win_set_buf(win, term_buf)
		vim.api.nvim_set_current_win(target)
	end)
	redirecting = false

	if ok then
		primary_win = target

		-- The buffer swap above is synchronous, so a picker that positions the
		-- cursor right after displaying the buffer (telescope calls
		-- `nvim_win_set_cursor(0, ...)` last) already sees it in its final window.
		-- The focus move may not survive that: `nvim_set_current_buf` on a buffer
		-- that still had to be loaded finishes after this autocmd and puts the
		-- focus back into `win`, so re-assert it once the event loop is free,
		-- unless the user got somewhere else first.
		vim.schedule(function()
			if vim.api.nvim_win_is_valid(target) and vim.api.nvim_get_current_win() == win then
				vim.api.nvim_set_current_win(target)
			end

			-- A window change made from an autocmd emits no `WinLeave`, so the
			-- focus-loss autocmd cannot see the move above; apply its policy for
			-- the terminal window the guard just took the focus away from.
			if was_current then
				focus_loss_close(win)
			end
		end)
	end

	if not ok then
		vim.notify_once(
			"toggable-term-nvim: could not redirect to the principal window: " .. tostring(err),
			vim.log.levels.WARN
		)
	end

	return ok
end

--- Move `buf` to the principal window when a plugin loaded it into one of our
--- terminal windows.
---
--- Called from `BufWinEnter`: it fires for `nvim_set_current_buf`, for `:edit`
--- and for a buffer shown in a window that is not current (where no `WinEnter`
--- is emitted at all). Terminal buffers are skipped, so restoring a terminal
--- never re-enters the guard.
--- @param buf integer|nil
--- @return boolean redirected
local function guard_buffer(buf)
	if redirecting then
		return false
	end
	if type(buf) ~= "number" or buf <= 0 or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.bo[buf].buftype == "terminal" then
		return false
	end

	local redirected = false
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if M.owner_of_tracked_window(win) then
			redirected = M.redirect_to_primary(win, buf) or redirected
		end
	end
	return redirected
end

--- Register the autocmds behind `protect_terminal_windows`: a `WinEnter`
--- recorder for the principal window and a `BufWinEnter` guard that moves a
--- plugin-loaded buffer into it.
---
--- An own augroup keeps a repeated `setup()` or a reloaded config from stacking
--- the autocmds.
function M.setup_buffer_guard()
	local current = vim.api.nvim_get_current_win()
	if acceptable_window(current) then
		primary_win = current
	end

	local group = vim.api.nvim_create_augroup("toggable_term_buffer_guard", { clear = true })

	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			if not config.options.protect_terminal_windows then
				return
			end

			local win = vim.api.nvim_get_current_win()
			if acceptable_window(win) then
				primary_win = win
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = function(args)
			if not config.options.protect_terminal_windows then
				return
			end

			-- A guard bug must never break the edit that triggered it: leave the
			-- buffer where it landed and report the error once.
			local ok, err = pcall(guard_buffer, tonumber(args.buf))
			if not ok then
				vim.notify_once("toggable-term-nvim: buffer guard failed: " .. tostring(err), vim.log.levels.WARN)
			end
		end,
	})
end

return M
