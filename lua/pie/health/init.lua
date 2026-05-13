local M = {}

function M.check()
    vim.health.start("pie")

    local cfg = require("pie").config

    -- Check pi binary
    if vim.fn.executable(cfg.cmd) == 1 then
        vim.health.ok("'" .. cfg.cmd .. "' found in PATH")
        local version = vim.fn.system(cfg.cmd .. " --version"):gsub("\n", "")
        if version ~= "" then
            vim.health.ok("pi version: " .. version)
        end
    else
        vim.health.error(
            "'" .. cfg.cmd .. "' not found in PATH",
            { "Install pi: https://github.com/earendil-works/pi-coding-agent" }
        )
    end

    -- Check Neovim version
    if vim.fn.has("nvim-0.10") == 1 then
        vim.health.ok("Neovim >= 0.10")
    else
        vim.health.error("Neovim >= 0.10 is required for vim.system and virt_lines")
    end

    -- Check conform.nvim
    local ok, _ = pcall(require, "conform")
    if ok then
        vim.health.ok("conform.nvim available for formatting")
    else
        vim.health.info("conform.nvim not found — formatting will fall back to LSP/reindent")
    end

    -- Check keymap conflicts
    local modes = { "n", "v" }
    for _, mode in ipairs(modes) do
        local lhs = vim.fn.maparg(cfg.keymap, mode)
        if lhs ~= "" and not lhs:match("pie") then
            vim.health.warn(
                cfg.keymap .. " is already mapped in " .. mode .. " mode: " .. lhs,
                { "Set a different keymap: require('pie').setup({ keymap = '<leader>e' })" }
            )
        end
    end
end

return M
