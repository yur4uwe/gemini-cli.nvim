local M = {}

-- Default configuration
local default_config = {
	split_direction = "vertical", -- "vertical" or "horizontal"
}

local config = {}

local state = {
	bufnr = nil,
	winnr = nil,
	chan_id = nil,
}

local function close_gemini_window()
	if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
		vim.api.nvim_win_close(state.winnr, true)
	end
	if state.chan_id then
		vim.fn.jobstop(state.chan_id)
	end
	if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
		vim.api.nvim_buf_delete(state.bufnr, { force = true })
	end
	state.winnr = nil
	state.bufnr = nil
	state.chan_id = nil
end

--- Open the Gemini CLI window
--- If window is already open, all flags passed will be ignored.
--- @param args string
--- @return nil
local function open_gemini_window(args)
	-- If the window is already open, just focus it.
	if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
		vim.api.nvim_set_current_win(state.winnr)
		return
	end

	-- Use configured split direction
	if config.split_direction == "horizontal" then
		vim.cmd("split")
	else
		vim.cmd("vsplit")
	end

	state.winnr = vim.api.nvim_get_current_win()

	-- Reuse existing buffer if valid and process is alive
	if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and state.chan_id then
		vim.api.nvim_win_set_buf(state.winnr, state.bufnr)
		return
	end

	vim.cmd("enew")
	vim.cmd("setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted")
	state.bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(state.bufnr, "gemini_cli")

	-- Map Esc to exit terminal mode in the Gemini buffer
	vim.api.nvim_buf_set_keymap(state.bufnr, "t", "<Esc>", "<C-\\><C-n>", { noremap = true, silent = true })

	local cmd = { "gemini" }
	if args and args ~= "" then
		for word in string.gmatch(args, "%S+") do
			table.insert(cmd, word)
		end
	end

	state.chan_id = vim.fn.termopen(cmd, {
		env = { ["EDITOR"] = "nvim" },
		on_exit = function()
			-- Check if the window is still valid before trying to close it
			if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
				local buf_in_win = vim.api.nvim_win_get_buf(state.winnr)
				if buf_in_win == state.bufnr then
					vim.api.nvim_win_close(state.winnr, true)
				end
			end
			state.bufnr = nil
			state.winnr = nil
			state.chan_id = nil
		end,
	})
end

--- Toggle the Gemini CLI window
--- @param opts table
--- @return nil
function M.toggle_gemini_cli(opts)
	local args = (opts and opts.args) or ""

	if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
		close_gemini_window()
	else
		open_gemini_window(args)
	end
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

--- Send the selected text to the Gemini CLI
--- @param opts table
--- @return nil
function M.send_to_gemini(opts)
	-- Check if the Gemini window is open and the channel is available.
	if not (state.winnr and vim.api.nvim_win_is_valid(state.winnr) and state.chan_id) then
		show_floating_message(
			"Gemini CLI is not running. Please open it with :GeminiToggle or specified keybind first."
		)
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
		vim.fn.chansend(state.chan_id, text .. "\n")
		vim.api.nvim_set_current_win(state.winnr)
	else
		show_floating_message("No text selected.")
	end
end

function M.gemini_chat_focus()
	if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
		vim.notify("Gemini CLI is not running. Please open it first.", vim.log.levels.WARN)
		return
	end

	local user_current_win = vim.api.nvim_get_current_win()
	local gemini_win_tab = vim.api.nvim_win_get_tabpage(state.winnr)
	local user_current_tab = vim.api.nvim_get_current_tabpage()

	if gemini_win_tab ~= user_current_tab then
		vim.api.nvim_set_current_tabpage(gemini_win_tab)
	end

	if user_current_win ~= state.winnr then
		vim.api.nvim_set_current_win(state.winnr)
	end

	pcall(vim.cmd, "startinsert")
end

function M.setup(opts)
	-- Merge user config with defaults
	config = vim.tbl_deep_extend("force", default_config, opts or {})

	if vim.fn.executable("gemini") ~= 1 then
		vim.notify("Gemini CLI not found. Please install it to use this plugin.", vim.log.levels.WARN)
		return
	end

	vim.api.nvim_create_user_command(
		"GeminiToggle",
		M.toggle_gemini_cli,
		{ desc = "Toggle the Gemini CLI window", nargs = "*" }
	)
	vim.api.nvim_create_user_command(
		"GeminiSend",
		M.send_to_gemini,
		{ desc = "Send selection to Gemini", range = true }
	)
	vim.api.nvim_create_user_command("GeminiChatFocus", M.gemini_chat_focus, { desc = "Focus on Geminis opened chat" })
end

return M
