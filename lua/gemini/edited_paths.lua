local M = {}

function M.parse(raw_line)
    local line = raw_line:gsub("\27%[[%d;]*%a", "")
    local files = line:match("Edited%s+%d+%s+files?%s+%(([^)]+)%)")
    if files then
        local paths = {}
        for file in files:gmatch("[^,]+") do
            local path = vim.trim(file)
            if path ~= "" then
                table.insert(paths, path)
            end
        end
        return paths
    end

    local quoted = line:match('Edited%s+"([^"]+)"') or line:match("Edited%s+'([^']+)'")
    if quoted then
        return { quoted }
    end

    local bare = line:match("Edited%s+(%S+)")
    if bare then
        local path = bare:gsub("[:.,]+$", "")
        if path ~= "" then
            return { path }
        end
    end
    return {}
end

return M
