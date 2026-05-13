local M = {}

---Try to format a range: conform -> LSP -> reindent
---@param buf number Buffer ID
---@param start_row number 0-indexed, inclusive
---@param end_row number 0-indexed, exclusive
---@return boolean success Whether formatting was applied
function M.try_format(buf, start_row, end_row)
    -- 1. Try conform.nvim
    local ok, conform = pcall(require, "conform")
    if ok then
        local ft = vim.bo[buf].filetype
        local formatters = conform.formatters_by_ft[ft]
        if formatters then
            local format_ok = pcall(function()
                conform.format({
                    bufnr = buf,
                    range = {
                        start = { start_row + 1, 0 },
                        ["end"] = { end_row + 1, 0 },
                    },
                })
            end)
            if format_ok then return true end
        end
    end

    -- 2. Try LSP range formatting
    local format_ok = pcall(function()
        local clients = vim.lsp.get_clients({ bufnr = buf })
        for _, client in ipairs(clients) do
            if client.server_capabilities.documentFormattingProvider then
                local params = vim.lsp.util.make_range_params()
                params.range = {
                    start = { line = start_row, character = 0 },
                    ["end"] = { line = end_row, character = 0 },
                }
                local result = client.request_sync("textDocument/rangeFormatting", params, 1000, buf)
                if result and result.result then
                    vim.lsp.util.apply_text_edits(result.result, buf, client.offset_encoding)
                    return true
                end
            end
        end
    end)
    if format_ok then return true end

    -- 3. Fallback to Neovim reindent
    pcall(function()
        local end_line = end_row + 1
        -- Save cursor position
        local view = vim.fn.winsaveview()
        vim.cmd(string.format("silent! %d,%dnormal! ==", start_row + 1, end_line))
        -- Restore cursor position
        vim.fn.winrestview(view)
    end)

    return false
end

return M
