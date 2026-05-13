# gemini-cli

A Neovim plugin to seamlessly integrate the Gemini CLI.

<https://github.com/user-attachments/assets/a40b8bab-9a9c-4654-878e-c6f03577585c>

## Features

- Toggle the Gemini CLI in a split window (vertical or horizontal).
- Pass arbitrary flags to the Gemini CLI (e.g., `:GeminiToggle --temp 0.9`).
- Send code/text selections or line ranges directly to the CLI.
- Automatically checks if the `gemini` CLI is installed on startup and shows a warning if missing.
- Utility buffers are hidden from buffer lists.
- Sets the `EDITOR` environment variable to `nvim` for the Gemini CLI session.

## Requirements

- Neovim >= 0.7.0
- [Node.js and npm](https://nodejs.org/) (for the Gemini CLI)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jonroosevelt/gemini-cli.nvim",
  config = function()
    require("gemini").setup({
      split_direction = "horizontal", -- optional: "vertical" (default) or "horizontal"
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "jonroosevelt/gemini-cli.nvim",
  config = function()
    require("gemini").setup({
      split_direction = "horizontal", -- optional: "vertical" (default) or "horizontal"
    })
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'jonroosevelt/gemini-cli.nvim'
```

And then in your `init.lua`:

```lua
require('gemini').setup()
```

## Configuration

The plugin can be configured with the following options:

```lua
require('gemini').setup({
  split_direction = "horizontal", -- "vertical" (default) or "horizontal"
})
```

### Configuration Options

- `split_direction`: Controls how the Gemini CLI window opens
  - `"vertical"` (default): Opens in a vertical split (side by side)
  - `"horizontal"`: Opens in a horizontal split (top and bottom)

### Examples

#### Vertical Split (Default)
```lua
require('gemini').setup() -- or
require('gemini').setup({
  split_direction = "vertical"
})
```

#### Horizontal Split
```lua
require('gemini').setup({
  split_direction = "horizontal"
})
```

## Usage

This plugin provides the following user commands:

- `:GeminiToggle [args]` - Opens or closes the Gemini CLI window. You can pass arguments, for example: `:GeminiToggle --temp 0.7 --model gemini-1.5-flash`.
- `:GeminiSend` - Sends the selected text to the Gemini CLI. Works with Visual Mode or line ranges (e.g., `:10,20GeminiSend`).
- `:GeminiChatFocus` - Focuses the Gemini CLI window and enters Insert mode. **Note:** This command must be triggered from Normal mode.

### Recommended Keybindings

Since this plugin does not set default keybindings, you should add your own to your `init.lua`:

```lua
-- Toggle Gemini CLI
vim.keymap.set("n", "<leader>gt", "<cmd>GeminiToggle<CR>", { desc = "Toggle Gemini" })

-- Send selection to Gemini (Visual Mode)
vim.keymap.set("v", "<leader>gs", ":GeminiSend<CR>", { desc = "Send selection to Gemini" })

-- Focus Gemini Chat
vim.keymap.set("n", "<leader>gc", "<cmd>GeminiChatFocus<CR>", { desc = "Focus Gemini Chat" })
```

## Troubleshooting

When you run the plugin, it will check if you have the `gemini` CLI installed. If it's missing, you will see a warning message. You can install it manually with:

```bash
npm install -g @google/gemini-cli
```
