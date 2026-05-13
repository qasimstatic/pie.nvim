local M = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local ns = vim.api.nvim_create_namespace("pie")

-- Get visual selection info
local function get_visual_selection()
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

-- State
local state = {
    handle = nil,
    float = nil,
    spinner_timer = nil,
    spinner_extmark = nil,
    spinner_buf = nil,
    top_mark = nil,
    bottom_mark = nil,
    selection = nil,
    file_lines = nil,
    source_buf = nil,
    ctrl_c_count = 0,
    ctrl_c_timer = nil,
}

local function close_float()
    if state.float then
        if vim.api.nvim_win_is_valid(state.float.win) then
            vim.api.nvim_win_close(state.float.win, true)
        end
        state.float = nil
    end
end

local function clear_spinner()
    if state.spinner_timer then
        state.spinner_timer:stop()
        state.spinner_timer:close()
        state.spinner_timer = nil
    end
    if state.spinner_extmark and state.spinner_buf and vim.api.nvim_buf_is_valid(state.spinner_buf) then
        pcall(vim.api.nvim_buf_del_extmark, state.spinner_buf, ns, state.spinner_extmark)
    end
    state.spinner_extmark = nil
    state.spinner_buf = nil
end

local function clear_marks()
    if state.spinner_buf and vim.api.nvim_buf_is_valid(state.spinner_buf) then
        if state.top_mark then
            pcall(vim.api.nvim_buf_del_extmark, state.spinner_buf, ns, state.top_mark)
        end
        if state.bottom_mark then
            pcall(vim.api.nvim_buf_del_extmark, state.spinner_buf, ns, state.bottom_mark)
        end
    end
    state.top_mark = nil
    state.bottom_mark = nil
end

local function reset_state()
    state.selection = nil
    state.file_lines = nil
    state.source_buf = nil
    state.ctrl_c_count = 0
    if state.ctrl_c_timer then
        state.ctrl_c_timer:stop()
        state.ctrl_c_timer:close()
        state.ctrl_c_timer = nil
    end
end

-- Place extmarks above and below the selection to track its boundaries
local function place_marks(buf, selection)
    local top_line = math.max(0, selection.start_line - 2)
    if top_line == selection.start_line - 1 then
        state.top_mark = vim.api.nvim_buf_set_extmark(buf, ns, top_line, 0, {})
    else
        local line_text = vim.fn.getline(selection.start_line - 1)
        state.top_mark = vim.api.nvim_buf_set_extmark(buf, ns, top_line, #line_text, {})
    end

    local last_line = vim.fn.getline(selection.end_line)
    state.bottom_mark = vim.api.nvim_buf_set_extmark(buf, ns, selection.end_line - 1, #last_line, {})
end

-- Show spinner as virt_lines on the line above the selection
local function show_spinner(buf, selection)
    state.spinner_buf = buf
    local frame = 1

    local top_line = math.max(0, selection.start_line - 2)
    state.spinner_extmark = vim.api.nvim_buf_set_extmark(buf, ns, top_line, 0, {
        virt_lines = { { { spinner_frames[frame] .. " pie thinking...", "PieSpinner" } } },
    })

    state.spinner_timer = vim.uv.new_timer()
    state.spinner_timer:start(0, 80, vim.schedule_wrap(function()
        if not (state.spinner_buf and vim.api.nvim_buf_is_valid(state.spinner_buf)) then
            clear_spinner()
            return
        end
        frame = (frame % #spinner_frames) + 1
        if state.spinner_extmark then
            pcall(vim.api.nvim_buf_del_extmark, state.spinner_buf, ns, state.spinner_extmark)
        end
        local top_pos = state.top_mark and vim.api.nvim_buf_get_extmark_by_id(buf, ns, state.top_mark, {})
        local row = top_pos and top_pos[1] or top_line
        state.spinner_extmark = vim.api.nvim_buf_set_extmark(state.spinner_buf, ns, row, 0, {
            virt_lines = { { { spinner_frames[frame] .. " pie thinking...", "PieSpinner" } } },
        })
    end))
end

-- Try to format a range: conform -> LSP -> reindent
local function try_format(buf, start_row, end_row)
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

    pcall(function()
        local end_line = end_row + 1
        vim.cmd(string.format("silent! %d,%dnormal! ==", start_row + 1, end_line))
    end)

    return false
end

-- Replace text between the two marks with the replacement
local function replace_between_marks(buf, selection, replacement)
    local replacement_lines = vim.split(replacement, "\n")

    local top_pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, state.top_mark, {})
    local bottom_pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, state.bottom_mark, {})

    local start_row, end_row
    if #top_pos == 0 or #bottom_pos == 0 then
        start_row = selection.start_line - 1
        end_row = selection.end_line
    else
        start_row = top_pos[1] + 1
        end_row = bottom_pos[1] + 1
    end

    vim.api.nvim_buf_set_lines(buf, start_row, end_row, false, replacement_lines)

    local new_end = start_row + #replacement_lines
    try_format(buf, start_row, new_end)
end

-- Build the prompt and submit the edit request
local function submit_edit()
    if not state.float then return end

    local float_buf = state.float.buf
    local selection = state.selection
    local file_lines = state.file_lines
    local buf = state.source_buf

    local lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
    local input = table.concat(lines, "\n")
    if input:match("^%s*$") then
        close_float()
        clear_marks()
        reset_state()
        return
    end

    close_float()

    -- Mark the selection lines with >>> for the model
    local marked_lines = {}
    for i, line in ipairs(file_lines) do
        if i >= selection.start_line and i <= selection.end_line then
            table.insert(marked_lines, "  >>> " .. line)
        else
            table.insert(marked_lines, "      " .. line)
        end
    end

    local filename = vim.api.nvim_buf_get_name(buf)
    local filetype = vim.bo[buf].filetype

    local prompt = string.format(
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
        selection.text,
        input
    )

    show_spinner(buf, selection)

    state.handle = require("pie.nvim.client").run(
        prompt,
        require("pie.nvim").config.system_prompt,
        function(result)
            vim.schedule(function()
                clear_spinner()
                if result and result ~= "" then
                    replace_between_marks(buf, selection, result)
                end
                clear_marks()
                reset_state()
                state.handle = nil
            end)
        end,
        function(err)
            vim.schedule(function()
                clear_spinner()
                clear_marks()
                reset_state()
                vim.notify("pie error: " .. err, vim.log.levels.ERROR)
                state.handle = nil
            end)
        end
    )
end

-- Create the floating input window
local function create_edit_float()
    local cfg = require("pie.nvim").config
    local width = cfg.float_width
    local height = cfg.float_height

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        border = cfg.border,
        style = "minimal",
        title = " pie edit ",
        title_pos = "center",
    })
    vim.api.nvim_win_set_option(win, "winhl", "Normal:NormalFloat")
    vim.api.nvim_win_set_option(win, "wrap", false)
    vim.api.nvim_win_set_option(win, "signcolumn", "no")
    vim.api.nvim_win_set_option(win, "number", false)
    vim.api.nvim_win_set_option(win, "relativenumber", false)

    -- Prompt icon on first line
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
        virt_text = { { "> ", "PiePromptIcon" } },
        virt_text_pos = "overlay",
    })

    -- Submit: <C-s> from any mode, or <CR> from normal mode
    vim.keymap.set({ "i", "n", "v" }, "<C-s>", function()
        vim.cmd("stopinsert")
        vim.schedule(submit_edit)
    end, { buffer = buf, desc = "pie: submit edit" })

    vim.keymap.set("n", "<CR>", submit_edit, { buffer = buf, desc = "pie: submit edit" })

    -- <C-c>: clear buffer, twice exits
    vim.keymap.set({ "i", "n" }, "<C-c>", function()
        local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local has_content = false
        for _, line in ipairs(current_lines) do
            if line:match("%S") then
                has_content = true
                break
            end
        end

        if has_content then
            -- First <C-c>: clear the buffer
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
            state.ctrl_c_count = 1
            -- Reset count after 1 second
            if state.ctrl_c_timer then
                state.ctrl_c_timer:stop()
                state.ctrl_c_timer:close()
            end
            state.ctrl_c_timer = vim.uv.new_timer()
            state.ctrl_c_timer:start(1000, 0, function()
                state.ctrl_c_count = 0
                state.ctrl_c_timer:stop()
                state.ctrl_c_timer:close()
                state.ctrl_c_timer = nil
            end)
            vim.cmd("startinsert!")
        else
            -- Empty buffer: first or second <C-c>
            state.ctrl_c_count = state.ctrl_c_count + 1
            if state.ctrl_c_count >= 2 then
                vim.cmd("stopinsert")
                close_float()
                clear_marks()
                reset_state()
            end
        end
    end, { buffer = buf, desc = "pie: clear / close" })

    return { buf = buf, win = win }
end

-- Is the float currently open?
function M.is_open()
    return state.float ~= nil
        and state.float.win ~= nil
        and vim.api.nvim_win_is_valid(state.float.win)
end

-- Toggle the float closed (called when keymap is hit while float is open)
local function toggle_close()
    vim.cmd("stopinsert")
    close_float()
    clear_marks()
    reset_state()
end

-- Main entry point
function M.request()
    -- Toggle: if float is open, close it
    if M.is_open() then
        toggle_close()
        return
    end

    -- If a request is in-flight, don't open a new float
    if state.handle then
        vim.notify("pie: request in progress, use :PieAbort to cancel", vim.log.levels.WARN)
        return
    end

    local mode = vim.fn.mode()
    local selection
    if mode == "v" or mode == "V" or mode == "\22" then
        selection = get_visual_selection()
    else
        local lnum = vim.fn.line(".")
        local line = vim.fn.getline(lnum)
        selection = {
            text = line,
            start_line = lnum,
            end_line = lnum,
            start_col = 1,
            end_col = #line,
        }
    end

    local buf = vim.api.nvim_get_current_buf()
    local file_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    place_marks(buf, selection)

    -- Save context for submit
    state.selection = selection
    state.file_lines = file_lines
    state.source_buf = buf
    state.ctrl_c_count = 0

    local float = create_edit_float()
    state.float = float

    vim.cmd("startinsert!")
end

function M.abort()
    if state.handle then
        state.handle:kill(9)
        state.handle = nil
    end
    clear_spinner()
    clear_marks()
    close_float()
    reset_state()
end

return M
