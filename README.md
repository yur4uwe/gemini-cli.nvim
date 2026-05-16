# gemini-cli

A Neovim plugin to seamlessly integrate the Gemini CLI.

<https://github.com/user-attachments/assets/a40b8bab-9a9c-4654-878e-c6f03577585c>

## Features

- Open the Gemini CLI in the current window or a split (vertical or horizontal).
- Background process: Send code/text selections to the CLI even when the chat window is closed.
- Multiline paste: Automatically compresses pasted text in the Gemini input.
- Pass arbitrary flags to the Gemini CLI (e.g., `:GeminiOpen --temp 0.9`).
- Automatically checks if the `gemini` CLI is installed on startup.
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
      split_direction = "current", -- optional: "current" (default), "vertical" or "horizontal"
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
      split_direction = "current", -- optional: "current" (default), "vertical" or "horizontal"
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
  split_direction = "current", -- "current" (default), "vertical" or "horizontal"
})
```

### Configuration Options

- `split_direction`: Controls how the Gemini CLI window opens
  - `"current"` (default): Replaces the current buffer in the active window.
  - `"vertical"`: Opens in a vertical split (side by side).
  - `"horizontal"`: Opens in a horizontal split (top and bottom).

## Usage

This plugin provides the following user commands:

- `:GeminiOpen [args]` - Starts the Gemini process (if not running) and opens the chat window. You can pass arguments like `:GeminiOpen --model gemini-1.5-flash`.
- `:GeminiClose` - Stops the Gemini process and wipes the buffer.
- `:GeminiSend` - Sends the selected text to the Gemini CLI as a "pasted" block. Works even if the chat window is closed (provided the process is running).
- `:GeminiChatFocus` - Focuses the Gemini CLI window and enters Insert mode.

### Recommended Keybindings

```lua
-- Open Gemini CLI
vim.keymap.set("n", "<leader>go", "<cmd>GeminiOpen<CR>", { desc = "Open Gemini" })

-- Close Gemini CLI
vim.keymap.set("n", "<leader>gc", "<cmd>GeminiClose<CR>", { desc = "Stop Gemini" })

-- Send selection to Gemini (Visual Mode)
vim.keymap.set("v", "<leader>gs", "<cmd>GeminiSend<CR>", { desc = "Send to Gemini" })

-- Focus Gemini Chat
vim.keymap.set("n", "<leader>gf", "<cmd>GeminiChatFocus<CR>", { desc = "Focus Gemini" })
```

## Troubleshooting

When you run the plugin, it will check if you have the `gemini` CLI installed. If it's missing, you will see a warning message. You can install it manually with:

```bash
npm install -g @google/gemini-cli
```
