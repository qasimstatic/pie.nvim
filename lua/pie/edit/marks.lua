local format = require("pie.edit.format")
local ns = vim.api.nvim_create_namespace("pie")

local M = {}

---@class PieMarks
---@field top_mark number
---@field bottom_mark number

---Place extmarks above and below the selection to track it resiliently
---@param buf number
---@param selection PieSelection
---@return PieMarks
function M.place_marks(buf, selection)
    local top_mark

    if selection.start_line <= 1 then
        -- Selection starts at line 1: place top mark at row 0, col 0
        -- In replace, we use top_pos[1] directly (no +1) since it IS the selection start
        top_mark = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {})
    else
        -- Place top mark at end of the line ABOVE the selection
        local above_line = selection.start_line - 1
        local line_text = vim.fn.getline(above_line)
        top_mark = vim.api.nvim_buf_set_extmark(buf, ns, above_line - 1, #line_text, {})
    end

    -- Bottom mark: end of the last line of selection
    local last_line = vim.fn.getline(selection.end_line)
    local bottom_mark = vim.api.nvim_buf_set_extmark(buf, ns, selection.end_line - 1, #last_line, {})

    return {
        top_mark = top_mark,
        bottom_mark = bottom_mark,
    }
end

---Clear the selection tracking marks
---@param buf number
---@param marks PieMarks
function M.clear_marks(buf, marks)
    if not marks then return end
    if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, marks.top_mark)
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, marks.bottom_mark)
    end
end

---Replace text between marks and apply formatting
---@param buf number
---@param selection PieSelection
---@param marks PieMarks
---@param replacement string
function M.replace_between_marks(buf, selection, marks, replacement)
    local replacement_lines = vim.split(replacement, "\n")

    local top_pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, marks.top_mark, {})
    local bottom_pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, marks.bottom_mark, {})

    local start_row, end_row
    if #top_pos == 0 or #bottom_pos == 0 then
        -- Marks missing/invalid, fallback to original indices
        start_row = selection.start_line - 1
        end_row = selection.end_line
    else
        if selection.start_line <= 1 then
            -- Top mark is ON the first line, so it IS the start row
            start_row = top_pos[1]
        else
            -- Top mark is on the line ABOVE, so start row is one below it
            start_row = top_pos[1] + 1
        end
        end_row = bottom_pos[1] + 1
    end

    -- Replace lines
    vim.api.nvim_buf_set_lines(buf, start_row, end_row, false, replacement_lines)

    -- Format the inserted range
    local new_end = start_row + #replacement_lines
    format.try_format(buf, start_row, new_end)
end

return M
