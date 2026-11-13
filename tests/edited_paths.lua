local parse = require("gemini.edited_paths").parse

local cases = {
    { "● Edited 1 file (notes/meeting notes.md)", { "notes/meeting notes.md" } },
    { "Edited 2 files (a.lua, docs/my notes.md)", { "a.lua", "docs/my notes.md" } },
    { '\27[32mEdited "notes/my file.md"\27[0m', { "notes/my file.md" } },
    { "Edited 'notes/my file.md.'", { "notes/my file.md." } },
    { "Edited lua/init.lua:", { "lua/init.lua" } },
    { "Edited 1 file (   )", {} },
    { "Reading notes.md", {} },
}

for _, case in ipairs(cases) do
    local actual = parse(case[1])
    assert(vim.deep_equal(actual, case[2]), vim.inspect({ line = case[1], actual = actual, expected = case[2] }))
end
