---@class PieSelection
---@field text string
---@field start_line number
---@field end_line number
---@field start_col number
---@field end_col number

local M = {}

---Get the current visual selection or current line
---@return PieSelection
function M.get_visual_selection()
    local mode = vim.fn.mode()
    
    -- If in normal mode, just return current line
    if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
        local lnum = vim.fn.line(".")
        local line = vim.fn.getline(lnum)
        return {
            text = line,
            start_line = lnum,
            end_line = lnum,
            start_col = 1,
            end_col = #line,
        }
    end

    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")

    local start_line = math.min(start_pos[2], end_pos[2])
    local end_line = math.max(start_pos[2], end_pos[2])
    local start_col = math.min(start_pos[3], end_pos[3])
    local end_col = math.max(start_pos[3], end_pos[3])

    local lines
    if start_line == end_line then
        local line = vim.fn.getline(start_line)
        lines = { line:sub(start_col, end_col) }
    else
        lines = vim.fn.getline(start_line, end_line)
        lines[1] = lines[1]:sub(start_col)
        lines[#lines] = lines[#lines]:sub(1, end_col)
    end

    return {
        text = table.concat(lines, "\n"),
        start_line = start_line,
        end_line = end_line,
        start_col = start_col,
        end_col = end_col,
    }
end

return M
