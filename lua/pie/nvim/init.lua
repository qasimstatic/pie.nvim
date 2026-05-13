local M = {}

M.config = {
    -- The pi binary
    cmd = "pi",
    -- Extra args passed to pi (e.g. {"--provider", "anthropic", "--model", "sonnet"})
    extra_args = {},
    -- Keymap to trigger inline edit (also toggles the float closed)
    keymap = "<leader>ai",
    -- Keymap to abort a running request
    abort_keymap = "<C-c>",
    -- Width of the floating input window
    float_width = 60,
    -- Height of the floating input window
    float_height = 3,
    -- Border style
    border = "single",
    -- System prompt for inline edits
    system_prompt = [[You are a code editing assistant. The user will provide a file with a marked selection and an instruction.
Return ONLY the replacement code for the selection. Preserve the original indentation. No explanations, no markdown fences, no commentary.]],
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    vim.keymap.set("v", M.config.keymap, function()
        require("pie.nvim.edit").request()
    end, { desc = "pie: inline edit selection" })

    vim.keymap.set("n", M.config.keymap, function()
        require("pie.nvim.edit").request()
    end, { desc = "pie: inline edit current line" })

    vim.keymap.set({ "n", "v" }, M.config.abort_keymap, function()
        require("pie.nvim.edit").abort()
    end, { desc = "pie: abort request" })

    vim.api.nvim_create_user_command("PieEdit", function()
        require("pie.nvim.edit").request()
    end, { desc = "pie: inline edit" })

    vim.api.nvim_create_user_command("PieAbort", function()
        require("pie.nvim.edit").abort()
    end, { desc = "pie: abort request" })

    -- Check that pi is available
    if vim.fn.executable(M.config.cmd) ~= 1 then
        vim.notify(
            "[pie] '"
                .. M.config.cmd
                .. "' not found in PATH.\n"
                .. "Install pi: https://github.com/earendil-works/pi-coding-agent\n"
                .. "Or set cmd in setup: { cmd = '/path/to/pi' }",
            vim.log.levels.WARN
        )
    end
end

return M
