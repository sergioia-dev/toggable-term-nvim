local M = {}

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

-- :TermFocusClose [on|off|toggle] - the close_on_focus_loss option.
vim.api.nvim_create_user_command("TermFocusClose", function(args)
	local api = require("toggable_term")
	local value

	if args.args == "on" then
		value = true
	elseif args.args == "off" then
		value = false
	elseif args.args ~= "" and args.args ~= "toggle" then
		vim.notify("toggable-term-nvim: expected on, off or toggle", vim.log.levels.ERROR)
		return
	end

	local enabled = api.set_close_on_focus_loss(value)
	vim.notify("toggable-term-nvim: close_on_focus_loss = " .. tostring(enabled))
end, {
	nargs = "?",
	complete = function()
		return { "on", "off", "toggle" }
	end,
	desc = "Close (or keep) terminals when they lose focus",
})

return M
