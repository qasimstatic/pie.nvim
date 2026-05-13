local M = {}

-- Build pi command args
local function build_cmd(prompt_text, system_prompt)
    local cfg = require("pie.nvim").config
    local args = {
        cfg.cmd,
        "-p",
        "--no-session",
        "--no-tools",
        "--thinking", "off",
        "--system-prompt", system_prompt,
    }
    for _, a in ipairs(cfg.extra_args) do
        table.insert(args, a)
    end
    table.insert(args, prompt_text)
    return args
end

-- Run pi in print mode. Calls on_result(text) on success, on_error(msg) on failure.
function M.run(prompt_text, system_prompt, on_result, on_error)
    local cfg = require("pie.nvim").config

    -- Guard: pi must be executable
    if vim.fn.executable(cfg.cmd) ~= 1 then
        if on_error then
            on_error(
                "'"
                    .. cfg.cmd
                    .. "' not found. Install pi: https://github.com/earendil-works/pi-coding-agent"
            )
        end
        return nil
    end

    local args = build_cmd(prompt_text, system_prompt)
    local output = ""

    local handle
    handle = vim.system(args, {
        stdout = function(err, data)
            if err then
                if on_error then on_error(err) end
                return
            end
            if data then
                output = output .. data
            end
        end,
        stderr = function() end,
    }, function(result)
        if result.code ~= 0 then
            if on_error then
                on_error("pi exited with code " .. result.code .. ": " .. (result.stderr or ""))
            end
            return
        end
        local text = output:gsub("^%s+", ""):gsub("%s+$", "")
        -- Strip markdown code fences if model wrapped the output
        text = text:gsub("^```[%w]*\n", ""):gsub("\n```$", "")
        on_result(text)
    end)

    return handle
end

return M
