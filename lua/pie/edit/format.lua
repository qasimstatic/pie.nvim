local M = {}

---Try to format a range: conform -> LSP -> reindent
---@param buf number Buffer ID
---@param start_row number 0-indexed, inclusive
---@param end_row number 0-indexed, exclusive
function M.try_format(buf, start_row, end_row)
    -- 1. Try conform.nvim
    local ok, conform = pcall(require, "conform")
    if ok then
        local ft = vim.bo[buf].filetype
        local formatters = conform.formatters_by_ft[ft]
        if formatters then
            local fmt_ok = pcall(conform.format, {
                bufnr = buf,
                range = {
                    start = { start_row + 1, 0 },
                    ["end"] = { end_row + 1, 0 },
                },
            })
            if fmt_ok then return end
        end
    end

    -- 2. Try LSP range formatting
    pcall(function()
        local clients = vim.lsp.get_clients({ bufnr = buf })
        for _, lsp_client in ipairs(clients) do
            if lsp_client.server_capabilities.documentRangeFormattingProvider then
                local params = vim.lsp.util.make_range_params()
                params.range = {
                    start = { line = start_row, character = 0 },
                    ["end"] = { line = end_row, character = 0 },
                }
                local result = lsp_client.request_sync("textDocument/rangeFormatting", params, 1000, buf)
                if result and result.result then
                    vim.lsp.util.apply_text_edits(result.result, buf, lsp_client.offset_encoding)
                    return
                end
            end
        end
    end)

    -- 3. Fallback to Neovim reindent
    pcall(function()
        local view = vim.fn.winsaveview()
        vim.cmd(string.format("silent! %d,%dnormal! ==", start_row + 1, end_row))
        vim.fn.winrestview(view)
    end)
end

return M
