local M = {}

-- Reopening the window when :q is used reloads gemini

-- Default configuration
local default_config = {
	split_direction = "current", -- "current", "vertical" or "horizontal"
}

local config = {}

local state = {
	bufnr = nil,
	chan_id = nil,
}

local function ensure_job(args)
	if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and state.chan_id then
		return
	end

	local cur_win = vim.api.nvim_get_current_win()
	local cur_buf = vim.api.nvim_get_current_buf()

	state.bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.bufnr, "gemini_cli")

	vim.api.nvim_win_set_buf(cur_win, state.bufnr)
	vim.cmd("setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted")

	-- Map Esc to exit terminal mode in the Gemini buffer
	vim.api.nvim_buf_set_keymap(state.bufnr, "t", "<Esc><Esc>", "<C-\\><C-n>", { noremap = true, silent = true })

	local cmd = { "gemini" }
	if args and args ~= "" then
		for word in string.gmatch(args, "%S+") do
			table.insert(cmd, word)
		end
	end

	state.chan_id = vim.fn.termopen(cmd, {
		env = { ["EDITOR"] = "nvim" },
		on_exit = function()
			state.bufnr = nil
			state.chan_id = nil
		end,
	})

	vim.api.nvim_win_set_buf(cur_win, cur_buf)
end

function M.close_gemini_cli()
	if state.chan_id then
		vim.fn.jobstop(state.chan_id)
	end
	if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
		vim.api.nvim_buf_delete(state.bufnr, { force = true })
	end
	state.bufnr = nil
	state.chan_id = nil
end

function M.focus_gemini_cli(opts)
	local args = (opts and opts.args) or ""
	ensure_job(args)

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == state.bufnr then
			vim.api.nvim_set_current_win(win)
			vim.cmd("startinsert")
			return
		end
	end

	if config.split_direction == "horizontal" then
		vim.cmd("split")
	elseif config.split_direction == "vertical" then
		vim.cmd("vsplit")
	end

	vim.api.nvim_win_set_buf(0, state.bufnr)
	vim.cmd("startinsert")
end

local function show_floating_message(message)
	local width = #message + 4
	local height = 1

	local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  " .. message .. "  " })

	local win_config = {
		relative = "win",
		anchor = "NW",
		width = width,
		height = height,
		row = cursor_row - 1,
		col = cursor_col,
		focusable = false,
		style = "minimal",
		border = "rounded",
	}

	local win = vim.api.nvim_open_win(buf, false, win_config)

	vim.defer_fn(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, 3000)
end

function M.send_to_gemini(opts)
	if not state.chan_id then
		show_floating_message("Gemini CLI is not running. Please open it with :GeminiOpen first.")
		return
	end

	local start_line, end_line, start_col, end_col

	if opts and opts.range > 0 then
		-- Use the range provided by the command (:1,5GeminiSend)
		start_line = opts.line1
		end_line = opts.line2
		start_col = 1
		end_col = 2147483647 -- Very large number to include the whole line
	else
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")
		start_line, start_col = start_pos[2], start_pos[3]
		end_line, end_col = end_pos[2], end_pos[3]
	end

	if start_line == 0 or end_line == 0 then
		show_floating_message("No text selected.")
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	if #lines == 0 then
		show_floating_message("No text selected.")
		return
	end

	-- Handle visual selection precisely
	if #lines == 1 then
		lines[1] = string.sub(lines[1], start_col, end_col)
	else
		lines[#lines] = string.sub(lines[#lines], 1, end_col)
		lines[1] = string.sub(lines[1], start_col)
	end

	local text = table.concat(lines, "\n")

	if text and #text > 0 then
		vim.fn.chansend(state.chan_id, "\27[200~" .. text .. "\27[201~\n")
		show_floating_message("Sent to Gemini")
	else
		show_floating_message("No text selected.")
	end
end

function M.setup(opts)
	-- Merge user config with defaults
	config = vim.tbl_deep_extend("force", default_config, opts or {})

	if vim.fn.executable("gemini") ~= 1 then
		vim.notify("Gemini CLI not found. Please install it to use this plugin.", vim.log.levels.WARN)
		return
	end

	vim.api.nvim_create_user_command(
		"GeminiOpen",
		M.focus_gemini_cli,
		{ desc = "Open the Gemini CLI chat", nargs = "*" }
	)
	vim.api.nvim_create_user_command(
		"GeminiClose",
		M.close_gemini_cli,
		{ desc = "Close the Gemini CLI chat process" }
	)
	vim.api.nvim_create_user_command(
		"GeminiSend",
		M.send_to_gemini,
		{ desc = "Send selection to Gemini", range = true }
	)
	vim.api.nvim_create_user_command(
		"GeminiChatFocus",
		M.focus_gemini_cli,
		{ desc = "Focus on Gemini's opened chat", nargs = "*" }
	)
end

return M
