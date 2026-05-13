# pie.nvim

**PI Edits** — inline AI edits in Neovim, powered by [pi](https://github.com/earendil-works/pi-coding-agent).

Select code → press `<leader>ai` → type an instruction → the selection gets replaced by the LLM's response.

## Requirements

- [pi](https://github.com/earendil-works/pi-coding-agent) — the coding agent CLI
- Neovim ≥ 0.10 (for `vim.system` and `virt_lines`)
- (Optional) [conform.nvim](https://github.com/stevearc/conform.nvim) for formatting edits in-place

## Installing pi

```bash
# With bun
bun install -g @earendil-works/pi-coding-agent

# Verify
pi --version
```

Then configure pi with a provider and model:

```bash
pi config set defaultProvider github-copilot
pi config set defaultModel gemini-3-flash-preview
pi config set defaultThinkingLevel off
```

See the [pi documentation](https://github.com/earendil-works/pi-coding-agent) for all supported providers.

## Installation

**[lazy.nvim](https://lazy.folke.io)**

```lua
{
    "qasimstatic/pie.nvim",
    keys = {
        { "<leader>ai", mode = { "n", "v" } },
    },
    cmd = { "PieEdit", "PieAbort" },
    opts = {},
}
```

**[packer.nvim](https://github.com/wbthomason/packer.nvim)**

```lua
use {
    "qasimstatic/pie.nvim",
    config = function()
        require("pie").setup()
    end,
}
```

## Configuration

Default values shown:

```lua
require("pie.nvim").setup({
    -- Path to the pi binary (must be in PATH or set explicitly)
    cmd = "pi",

    -- Extra args passed to pi
    -- example: { "--provider", "anthropic", "--model", "sonnet" }
    extra_args = {},

    -- Keymap to trigger inline edit (also toggles the float closed)
    keymap = "<leader>ai",

    -- Keymap to abort a running request (global, not inside the float)
    abort_keymap = "<C-c>",

    -- Floating input window dimensions
    float_width = 60,
    float_height = 3,

    -- Border style ("single", "double", "rounded", "solid", "shadow", "none")
    border = "single",

    -- System prompt sent to the model
    system_prompt = [[You are a code editing assistant. The user will provide a file with a marked selection and an instruction.
Return ONLY the replacement code for the selection. Preserve the original indentation. No explanations, no markdown fences, no commentary.]],
})
```

### Custom highlights

pie.nvim defines two highlight groups that link to `Keyword` by default. Override them in your colorscheme config:

```lua
vim.api.nvim_set_hl(0, "PiePromptIcon", { fg = "#cba6f7" })
vim.api.nvim_set_hl(0, "PieSpinner", { fg = "#cba6f7" })
```

## Usage

1. Select code in visual mode (or stay on a line in normal mode)
2. Press `<leader>ai` — the floating prompt opens in insert mode
3. Type your instruction — full vim editing works inside the prompt (Enter adds new lines, Esc goes to normal mode, etc.)
4. Submit with `<C-s>` (from any mode) or `<CR>` (from normal mode)
5. The selection is replaced with the LLM's response and auto-formatted

### Inside the prompt

| Key | Action |
|-----|--------|
| `<C-s>` | Submit (from any mode) |
| `<CR>` (normal) | Submit |
| `<CR>` (insert) | New line |
| `<Esc>` | Switch to normal mode |
| `<C-c>` | Clear the buffer; press again to close |

### Outside the prompt

| Key | Action |
|-----|--------|
| `<leader>ai` | Open prompt / toggle closed |
| `<C-c>` | Abort a running request |

A braille spinner appears above the selection while the request is running.

### Commands

- `:PieEdit` — trigger inline edit for current selection/line
- `:PieAbort` — abort a running request
- `:checkhealth pie` — verify pi is installed and configured

## How it works

1. The selected code and full file context are sent to `pi -p` (print mode, one-shot, no session)
2. The response replaces the selection in-place
3. After replacement, the edited range is automatically formatted using the first available method:
   - **conform.nvim** (if configured for the filetype)
   - **LSP range formatting** (if an LSP is attached)
   - **Neovim's built-in reindent** (`==`)

Extmarks are placed above and below the selection to track its position, so the replacement lands correctly even if the buffer shifts during the request.

## Credits

This plugin would not exist without:

- [zed-industries/zed](https://github.com/zed-industries/zed) — Tried Zed in 2023 and Inline Assist was my favourite feature. Had been dying to make something similar for Neovim ever since.
- [ThePrimeagen/99](https://github.com/ThePrimeagen/99) — I got this idea either simultaneously or after he started working on it. But I am glad that this parallel approach of AI assisted development exists without having to vibe on everything!
- [avante.nvim](https://github.com/yetone/avante.nvim) — very polished AI driven IDE like experience in Neovim, a lot to learn from.
- [opencode.nvim](https://github.com/nickjvandyke/opencode.nvim) — a complete package of somewhat similar approach but in an opencode way.

## License

MIT
