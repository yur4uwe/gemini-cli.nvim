local M = {}

-- Reopening the window when :q is used reloads gemini

-- Default configuration
local default_config = {
    split_location = "current", -- "current", "vertical" or "horizontal"
    cmd = "agy",
    autoreload = true,
    notify_style = "float", -- "float", "notify", "auto", or "none"
}

local config = vim.deepcopy(default_config)

local state = {
    bufnr = nil,
    chan_id = nil,
    reload_timer = nil,
    pending_buffers = {},
    has_custom_notify = nil,
}

local function debounced_checktime(target_bufs)
    for _, b in ipairs(target_bufs) do
        state.pending_buffers[b] = true
    end

    if state.reload_timer and not state.reload_timer:is_closing() then
        state.reload_timer:close()
        state.reload_timer = nil
    end

    state.reload_timer = vim.defer_fn(function()
        state.reload_timer = nil
        local bufs_to_check = vim.tbl_keys(state.pending_buffers)
        state.pending_buffers = {}
        vim.schedule(function()
            for _, b in ipairs(bufs_to_check) do
                if vim.api.nvim_buf_is_valid(b) then
                    vim.cmd("checktime " .. b)
                end
            end
        end)
    end, 200)
end

local function find_buffers_by_name(target_name)
    local matched = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if not vim.api.nvim_buf_is_loaded(buf) then
            goto continue
        end

        local buf_path = vim.api.nvim_buf_get_name(buf)
        if buf_path == "" then
            goto continue
        end

        local basename = vim.fs and
            vim.fs.basename and
            vim.fs.basename(buf_path) or
            vim.fn.fnamemodify(buf_path, ":t")
        if buf_path:sub(- #target_name) == target_name or basename == target_name then
            table.insert(matched, buf)
        end
        ::continue::
    end
    return matched
end

--- @param lines string[]
--- @return table
local function get_buffers_to_reload(lines)
    local to_reload = {}
    for _, raw_line in ipairs(lines) do
        -- Strip ANSI escape sequences for reliable matching
        local line = raw_line:gsub("\27%[[%d;]*%a", "")
        -- Match lines like: ● Edited 1 file (lab-work-2.md) or Edited 2 files (a.lua, b.lua)
        local files_str = line:match("Edited%s+%d+%s+files?%s+%(([^)]+)%)")
        if files_str then
            for edited_file in files_str:gmatch("[^,]+") do
                edited_file = vim.trim(edited_file)
                local matched_bufs = find_buffers_by_name(edited_file)
                for _, b in ipairs(matched_bufs) do
                    to_reload[b] = true
                end
            end
        else
            -- Fallback for direct "Edited path/file" formats
            local edited_file = line:match('Edited%s+"([^"]+)"')
                or line:match("Edited%s+'([^']+)'")
                or line:match("Edited%s+(%S+)")

            if edited_file then
                edited_file = edited_file:gsub("[:.,]+$", "")
                local matched_bufs = find_buffers_by_name(edited_file)
                for _, b in ipairs(matched_bufs) do
                    to_reload[b] = true
                end
            end
        end
    end
    return to_reload
end

local function ensure_job(args)
    if vim.fn.executable(config.cmd) ~= 1 then
        vim.notify("Antigravity CLI not found. Please install it to use this plugin.", vim.log.levels.WARN)
        return false
    end

    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and state.chan_id then
        return true
    end

    -- Clean up any stale buffer with the same name to prevent E95 error
    local old_bufnr = vim.fn.bufnr("^gemini_cli$")
    if old_bufnr ~= -1 and vim.api.nvim_buf_is_valid(old_bufnr) then
        pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })
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

        state.chan_id = vim.fn.jobstart(cmd, {
            term = true,
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
        state.reload_timer = nil
        state.pending_buffers = {}

        vim.api.nvim_buf_attach(state.bufnr, false, {
            on_lines = function(_, _, _, firstline, _, new_lastline)
                if state.bufnr ~= attached_bufnr then
                    return true -- Detach listener if we've stopped/recreated the buffer
                end

                local lines = vim.api.nvim_buf_get_lines(state.bufnr, firstline, new_lastline, false)
                local to_reload = get_buffers_to_reload(lines)

                local target_bufs = vim.tbl_keys(to_reload)
                if #target_bufs > 0 then
                    debounced_checktime(target_bufs)
                end
            end,
            on_detach = function()
                if state.reload_timer and not state.reload_timer:is_closing() then
                    state.reload_timer:close()
                    state.reload_timer = nil
                end
                state.pending_buffers = {}
            end,
        })
    end

    vim.api.nvim_exec_autocmds("User", { pattern = "GeminiStarted" })
    return true
end

function M.close_chat()
    if state.chan_id then
        pcall(vim.fn.jobstop, state.chan_id)
    end

    if state.reload_timer and not state.reload_timer:is_closing() then
        state.reload_timer:close()
        state.reload_timer = nil
    end
    state.pending_buffers = {}

    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
        pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true })
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

local function has_custom_notify()
    if state.has_custom_notify ~= nil then
        return state.has_custom_notify
    end

    local info = debug.getinfo(vim.notify)
    local is_stock = info and (info.source:match("vim/_editor%.lua$") or info.source:match("vim/shared%.lua$"))

    if not is_stock then
        state.has_custom_notify = true
        return true
    end

    return false
end

local function show_floating_message(message, level)
    local width = #message + 4
    local height = 1

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
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

    local ok, win = pcall(vim.api.nvim_open_win, buf, false, win_config)
    if not ok then
        vim.notify(message, level or vim.log.levels.INFO)
        return
    end

    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, 3000)
end

local function notify(message, level)
    level = level or vim.log.levels.INFO
    local style = config.notify_style

    if style == "none" then
        return
    end

    if style == "auto" then
        style = has_custom_notify() and "notify" or "float"
    end

    if style == "notify" then
        vim.notify(message, level)
    else
        show_floating_message(message, level)
    end
end

function M.paste_selection_to_chat(opts)
    if not state.chan_id then
        notify("Gemini CLI is not running. Please open it with :GeminiOpen first.", vim.log.levels.WARN)
        return
    end

    local mode = vim.api.nvim_get_mode().mode
    local is_visual = mode == "v" or mode == "V" or mode == "\22"
    if is_visual then
        vim.cmd([[execute "normal! \<ESC>"]])
    end

    local lines
    local visual_mode = vim.fn.visualmode()

    -- If called from visual selection mode or visual range was passed
    if is_visual or (opts and opts.range > 0 and opts.line1 == vim.fn.line("'<") and opts.line2 == vim.fn.line("'>")) then
        if vim.fn.getregion then
            local start_pos = vim.fn.getpos("'<")
            local end_pos = vim.fn.getpos("'>")
            lines = vim.fn.getregion(start_pos, end_pos, { type = visual_mode })
        else
            -- Fallback for Neovim < 0.10
            local start_pos = vim.fn.getpos("'<")
            local end_pos = vim.fn.getpos("'>")
            local start_line, start_col = start_pos[2], start_pos[3]
            local end_line, end_col = end_pos[2], end_pos[3]

            if start_line ~= 0 and end_line ~= 0 then
                lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
                if #lines == 1 then
                    lines[1] = string.sub(lines[1], start_col, end_col)
                elseif #lines > 0 then
                    lines[#lines] = string.sub(lines[#lines], 1, end_col)
                    lines[1] = string.sub(lines[1], start_col)
                end
            end
        end
    elseif opts and opts.range > 0 then
        -- Explicit line range provided (e.g. :1,5GeminiSend)
        lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
    end

    if not lines or #lines == 0 then
        notify("No text selected.", vim.log.levels.WARN)
        return
    end

    local text = table.concat(lines, "\n")

    if text and #text > 0 then
        vim.fn.chansend(state.chan_id, "\27[200~" .. text .. "\27[201~\n")
        notify("Sent to Gemini", vim.log.levels.INFO)
    else
        notify("No text selected.", vim.log.levels.WARN)
    end
end

function M.setup(opts)
    -- Merge user config with defaults
    config = vim.tbl_deep_extend("force", default_config, opts or {})

    if config.notify_style == "auto" then
        vim.api.nvim_create_autocmd("User", {
            pattern = "VeryLazy",
            once = true,
            callback = function()
                local info = debug.getinfo(vim.notify)
                local is_stock = info and
                    (info.source:match("vim/_editor%.lua$") or info.source:match("vim/shared%.lua$"))
                state.has_custom_notify = not is_stock
            end,
        })
    end

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
