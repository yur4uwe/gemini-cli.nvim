local M = {}

-- Reopening the window when :q is used reloads gemini

-- Default configuration
local default_config = {
	split_location = "current", -- "current", "vertical" or "horizontal"
	cmd = "agy",
	autoreload = true,
}

local config = vim.deepcopy(default_config)

local state = {
	bufnr = nil,
	chan_id = nil,
}

local function ensure_job(args)
	if vim.fn.executable(config.cmd) ~= 1 then
		vim.notify("Antigravity CLI not found. Please install it to use this plugin.", vim.log.levels.WARN)
		return false
	end

	if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and state.chan_id then
		return true
	end

	state.bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.bufnr, "gemini_cli")

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		buffer = state.bufnr,
		callback = function()
			vim.cmd("setlocal nonumber norelativenumber signcolumn=no foldcolumn=0")
		end,
	})

	vim.api.nvim_buf_call(state.bufnr, function()
		vim.cmd("setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted")

		-- Map Esc to exit terminal mode in the Gemini buffer if altscreen is disabled
		vim.api.nvim_buf_set_keymap(state.bufnr, "t", "<Esc><Esc>", "<C-\\><C-n>", { noremap = true, silent = true })

		local cmd = { config.cmd }
		if args and args ~= "" then
			for word in string.gmatch(args, "%S+") do
				table.insert(cmd, word)
			end
		end

		---@diagnostic disable-next-line: deprecated
		state.chan_id = vim.fn.termopen(cmd, {
			env = { ["EDITOR"] = "nvim" },
			on_exit = function()
				state.bufnr = nil
				state.chan_id = nil
				vim.api.nvim_exec_autocmds("User", { pattern = "GeminiStopped" })
			end,
		})
	end)

	if config.autoreload then
		vim.opt.autoread = true
		local attached_bufnr = state.bufnr
		vim.api.nvim_buf_attach(state.bufnr, false, {
			on_lines = function(_, _, _, firstline, lastline, _)
				if state.bufnr ~= attached_bufnr then
					return true -- Detach listener if we've stopped/recreated the buffer
				end

				local lines = vim.api.nvim_buf_get_lines(state.bufnr, firstline, lastline, false)
				for _, line in ipairs(lines) do
					-- Detect file edit tool call logs (e.g. "Edit(...)")
					if line:find("Edit%(") then
						vim.schedule(function()
							vim.cmd("checktime")
						end)
						break
					end
				end
			end,
		})
	end

	vim.api.nvim_exec_autocmds("User", { pattern = "GeminiStarted" })
	return true
end

function M.close_chat()
	if state.chan_id then
		vim.fn.jobstop(state.chan_id)
	end
	if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
		vim.api.nvim_buf_delete(state.bufnr, { force = true })
	end
	state.bufnr = nil
	state.chan_id = nil
end

function M.focus_chat(opts)
	local args = (opts and opts.args) or ""
	if not ensure_job(args) then
		return
	end

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == state.bufnr then
			vim.api.nvim_set_current_win(win)
			vim.cmd("startinsert")
			return
		end
	end

	if config.split_location == "horizontal" then
		vim.cmd("split")
	elseif config.split_location == "vertical" then
		vim.cmd("vsplit")
	end

	vim.api.nvim_win_set_buf(0, state.bufnr)
	vim.cmd("startinsert")
end

local function show_floating_message(message)
	local width = #message + 4
	local height = 1

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  " .. message .. "  " })

	local win_config = {
		relative = "cursor",
		anchor = "NW",
		width = width,
		height = height,
		row = 1,
		col = 0,
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

function M.paste_selection_to_chat(opts)
	if not state.chan_id then
		show_floating_message("Gemini CLI is not running. Please open it with :GeminiOpen first.")
		return
	end

	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" or mode == "V" or mode == "\22" then -- \22 for visual block mode
		vim.cmd([[execute "normal! \<ESC>"]])
	end

	local lines
	if opts and opts.range > 0 then
		-- Use the range provided by the command (:1,5GeminiSend)
		lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
	else
		-- For visual selections, use vim.fn.getregion if available (Neovim 0.10+)
		if vim.fn.getregion then
			local start_pos = vim.fn.getpos("'<")
			local end_pos = vim.fn.getpos("'>")
			local visual_mode = vim.fn.visualmode()
			lines = vim.fn.getregion(start_pos, end_pos, { type = visual_mode })
		else
			-- Fallback for Neovim < 0.10
			local start_pos = vim.fn.getpos("'<")
			local end_pos = vim.fn.getpos("'>")
			local start_line, start_col = start_pos[2], start_pos[3]
			local end_line, end_col = end_pos[2], end_pos[3]

			if start_line == 0 or end_line == 0 then
				show_floating_message("No text selected.")
				return
			end

			lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
      if #lines == 1 then
        lines[1] = string.sub(lines[1], start_col, end_col)
      elseif #lines > 0 then
        lines[#lines] = string.sub(lines[#lines], 1, end_col)
        lines[1] = string.sub(lines[1], start_col)
      end
		end
	end

	if not lines or #lines == 0 then
		show_floating_message("No text selected.")
		return
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

	vim.api.nvim_create_user_command("GeminiOpen", M.focus_chat, { desc = "Open the Gemini CLI chat", nargs = "*" })
	vim.api.nvim_create_user_command("GeminiClose", M.close_chat, { desc = "Close the Gemini CLI chat process" })
	vim.api.nvim_create_user_command(
		"GeminiSend",
		M.paste_selection_to_chat,
		{ desc = "Send selection to Gemini", range = true }
	)
	vim.api.nvim_create_user_command(
		"GeminiChatFocus",
		M.focus_chat,
		{ desc = "Focus on Gemini's opened chat", nargs = "*" }
	)
end

return M

