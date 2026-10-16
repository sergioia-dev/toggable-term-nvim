local M = {}

-- Terminal kinds accepted by :TermFocusClose (string keys double as a set).
local focus_close_kinds = { vertical = true, horizontal = true, float = true }

-- :TermVertical - toggle the right-side vertical terminal through toggable-term.
vim.api.nvim_create_user_command("TermVertical", function()
	require("toggable_term").toggle_right_terminal()
end, { desc = "Toggle the vertical (right) terminal" })

-- :TermHorizontal - toggle the bottom terminal through toggable-term.
vim.api.nvim_create_user_command("TermHorizontal", function()
	require("toggable_term").toggle_bottom_terminal()
end, { desc = "Toggle the horizontal (bottom) terminal" })

-- :TermFloat - toggle the floating terminal through toggable-term.
vim.api.nvim_create_user_command("TermFloat", function()
	require("toggable_term").toggle_floating_terminal()
end, { desc = "Toggle the floating terminal" })

-- :TermFocusClose {vertical|horizontal|float} [on|off|toggle] - the per-kind
-- <kind>_close_on_focus_loss option.
vim.api.nvim_create_user_command("TermFocusClose", function(args)
	local api = require("toggable_term")
	local kind = args.fargs[1]

	if not focus_close_kinds[kind] then
		vim.notify("toggable-term-nvim: unknown terminal kind: " .. vim.inspect(kind), vim.log.levels.ERROR)
		return
	end
	local action = args.fargs[2] or "toggle"
	local value

	if action == "on" then
		value = true
	elseif action == "off" then
		value = false
	elseif action ~= "toggle" then
		vim.notify("toggable-term-nvim: expected on, off or toggle", vim.log.levels.ERROR)
		return
	end

	local enabled = api.set_close_on_focus_loss(kind, value)
	vim.notify("toggable-term-nvim: " .. kind .. "_close_on_focus_loss = " .. tostring(enabled))
end, {
	nargs = "+",
	complete = function(arg_lead, cmd_line)
		local args = vim.split(cmd_line, "%s+")
		local choices = #args > 2 and { "on", "off", "toggle" } or { "vertical", "horizontal", "float" }
		return vim.tbl_filter(function(choice)
			return choice:find(arg_lead, 1, true) == 1
		end, choices)
	end,
	desc = "Close (or keep) a terminal kind when it loses focus",
})

return M
