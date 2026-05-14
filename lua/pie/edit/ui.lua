local ns = vim.api.nvim_create_namespace("pie")
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local M = {}

---@class PieFloat
---@field buf number
---@field win number

---Create the floating input window
---@param submit_cb function Callback when user submits
---@param close_cb function Callback when user closes
---@return PieFloat
function M.create_float(submit_cb, close_cb)
    local cfg = require("pie").config
    local width = cfg.float_width
    local height = cfg.float_height

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"

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
    vim.wo[win].winhl = "Normal:NormalFloat"
    vim.wo[win].wrap = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false

    -- Prompt icon on first line (inline so cursor appears after it)
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
        virt_text = { { "> ", "PiePromptIcon" } },
        virt_text_pos = "inline",
    })

    -- Submit keymaps
    local function submit()
        vim.cmd("stopinsert")
        vim.schedule(submit_cb)
    end

    vim.keymap.set({ "i", "n", "v" }, "<C-s>", submit, { buffer = buf, desc = "pie: submit edit" })
    vim.keymap.set("i", "<C-CR>", submit, { buffer = buf, desc = "pie: submit edit" })
    vim.keymap.set("n", "<CR>", submit_cb, { buffer = buf, desc = "pie: submit edit" })

    -- Close/clear keymaps
    local ctrl_c_count = 0
    local ctrl_c_timer = nil

    local function safe_close_timer()
        if ctrl_c_timer and not ctrl_c_timer:is_closing() then
            ctrl_c_timer:stop()
            ctrl_c_timer:close()
        end
        ctrl_c_timer = nil
    end

    vim.keymap.set({ "i", "n" }, "<C-c>", function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local has_content = false
        for _, line in ipairs(lines) do
            if line:match("%S") then
                has_content = true
                break
            end
        end

        if has_content then
            -- First <C-c>: clear the buffer
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
            ctrl_c_count = 1
            safe_close_timer()
            ctrl_c_timer = vim.uv.new_timer()
            ctrl_c_timer:start(1000, 0, function()
                ctrl_c_count = 0
                safe_close_timer()
            end)
            vim.cmd("startinsert!")
        else
            -- Empty buffer: first or second <C-c>
            ctrl_c_count = ctrl_c_count + 1
            if ctrl_c_count >= 2 then
                vim.cmd("stopinsert")
                safe_close_timer()
                close_cb()
            end
        end
    end, { buffer = buf, desc = "pie: clear / close" })

    return { buf = buf, win = win }
end

---Close a float window safely and wipe its buffer
---@param float PieFloat?
function M.close_float(float)
    if not float then return end
    local buf = float.buf
    if float.win and vim.api.nvim_win_is_valid(float.win) then
        vim.api.nvim_win_close(float.win, true)
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
    end
end

---@class PieSpinner
---@field timer userdata
---@field mark number
---@field buf number
---@field stopped boolean

---Show spinner above the selection
---@param buf number
---@param selection PieSelection
---@param top_mark number The extmark tracking the line above
---@return PieSpinner
function M.start_spinner(buf, selection, top_mark)
    local frame = 1
    local top_line = math.max(0, selection.start_line - 2)
    local stopped = false

    local mark = vim.api.nvim_buf_set_extmark(buf, ns, top_line, 0, {
        virt_lines = { { { spinner_frames[frame] .. " pie thinking...", "PieSpinner" } } },
    })

    local timer = vim.uv.new_timer()
    timer:start(0, 80, vim.schedule_wrap(function()
        -- Guard: stop if spinner was cleared or buffer is gone
        if stopped then return end
        if not vim.api.nvim_buf_is_valid(buf) then
            stopped = true
            if not timer:is_closing() then
                timer:stop()
                timer:close()
            end
            return
        end

        frame = (frame % #spinner_frames) + 1
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, mark)

        local top_pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, top_mark, {})
        local row = #top_pos > 0 and top_pos[1] or top_line

        mark = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
            virt_lines = { { { spinner_frames[frame] .. " pie thinking...", "PieSpinner" } } },
        })
    end))

    return {
        timer = timer,
        mark = mark,
        buf = buf,
        stopped = stopped, -- note: this is a reference; we set spinner.stopped = true in clear_spinner
    }
end

---Clear the spinner
---@param spinner PieSpinner?
function M.clear_spinner(spinner)
    if not spinner then return end

    -- Flag prevents scheduled callbacks from running after we stop
    spinner.stopped = true

    if spinner.timer and not spinner.timer:is_closing() then
        spinner.timer:stop()
        spinner.timer:close()
    end

    if vim.api.nvim_buf_is_valid(spinner.buf) then
        pcall(vim.api.nvim_buf_del_extmark, spinner.buf, ns, spinner.mark)
    end
end

return M
