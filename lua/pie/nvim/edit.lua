local utils = require("pie.nvim.edit.utils")
local marks = require("pie.nvim.edit.marks")
local ui = require("pie.nvim.edit.ui")
local client = require("pie.nvim.client")

local M = {}

---@class PieRequest
---@field source_buf number
---@field selection PieSelection
---@field file_lines string[]
---@field float PieFloat?
---@field marks PieMarks?
---@field spinner PieSpinner?
---@field handle vim.SystemObj?

---@type PieRequest?
local current_request = nil

---Reset the current request state
local function reset_request()
    if not current_request then return end
    
    ui.close_float(current_request.float)
    ui.clear_spinner(current_request.spinner)
    marks.clear_marks(current_request.source_buf, current_request.marks)
    
    if current_request.handle then
        current_request.handle:kill(9)
    end
    
    current_request = nil
end

---Build the prompt for the LLM
---@param req PieRequest
---@param instruction string
---@return string
local function build_prompt(req, instruction)
    local marked_lines = {}
    for i, line in ipairs(req.file_lines) do
        if i >= req.selection.start_line and i <= req.selection.end_line then
            table.insert(marked_lines, "  >>> " .. line)
        else
            table.insert(marked_lines, "      " .. line)
        end
    end

    local filename = vim.api.nvim_buf_get_name(req.source_buf)
    local filetype = vim.bo[req.source_buf].filetype

    return string.format(
        [[File: %s (%s)

Full file (>>> marks the selection):
%s

Selected code:
```
%s
```

Instruction: %s]],
        filename ~= "" and filename or "untitled",
        filetype,
        table.concat(marked_lines, "\n"),
        req.selection.text,
        instruction
    )
end

---Submit the edit request
local function submit_edit()
    if not current_request or not current_request.float then return end
    local req = current_request

    local lines = vim.api.nvim_buf_get_lines(req.float.buf, 0, -1, false)
    local instruction = table.concat(lines, "\n")
    
    if instruction:match("^%s*$") then
        reset_request()
        return
    end

    ui.close_float(req.float)
    req.float = nil -- Prevents double close

    local prompt = build_prompt(req, instruction)
    
    -- Start spinner using the top mark
    if req.marks then
        req.spinner = ui.start_spinner(req.source_buf, req.selection, req.marks.top_mark)
    end

    req.handle = client.run(
        prompt,
        require("pie.nvim").config.system_prompt,
        function(result)
            vim.schedule(function()
                ui.clear_spinner(req.spinner)
                if result and result ~= "" and req.marks then
                    marks.replace_between_marks(req.source_buf, req.selection, req.marks, result)
                end
                reset_request()
            end)
        end,
        function(err)
            vim.schedule(function()
                vim.notify("pie error: " .. err, vim.log.levels.ERROR)
                reset_request()
            end)
        end
    )
end

---Main entry point to start an edit
function M.request()
    -- Toggle off if open
    if current_request and current_request.float then
        vim.cmd("stopinsert")
        reset_request()
        return
    end

    if current_request and current_request.handle then
        vim.notify("pie: request in progress, use :PieAbort to cancel", vim.log.levels.WARN)
        return
    end

    local buf = vim.api.nvim_get_current_buf()
    local selection = utils.get_visual_selection()

    current_request = {
        source_buf = buf,
        selection = selection,
        file_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    }

    current_request.marks = marks.place_marks(buf, selection)
    
    current_request.float = ui.create_float(submit_edit, function()
        reset_request()
    end)

    vim.cmd("startinsert!")
end

---Abort the current edit request
function M.abort()
    reset_request()
end

---Check if the float is open (for tests)
function M.is_open()
    return current_request ~= nil and current_request.float ~= nil
end

return M
