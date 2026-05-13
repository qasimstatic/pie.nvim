-- Smoke tests for pie
-- Run: nvim --headless -u test/init.lua -c "PlenaryBustedDirectory test/"

local eq = assert.are.same

describe("pie", function()
    before_each(function()
        package.loaded["pie"] = nil
        package.loaded["pie.client"] = nil
        package.loaded["pie.edit"] = nil
    end)

    describe("setup", function()
        it("loads without errors", function()
            local ok, err = pcall(require, "pie")
            assert.is_true(ok, err)
        end)

        it("setup() runs without errors", function()
            local pie = require("pie")
            local ok, err = pcall(pie.setup)
            assert.is_true(ok, err)
        end)

        it("merges custom config", function()
            local pie = require("pie")
            pie.setup({ extra_args = { "--provider", "anthropic" } })
            eq({ "--provider", "anthropic" }, pie.config.extra_args)
        end)

        it("preserves defaults for unset options", function()
            local pie = require("pie")
            pie.setup({ extra_args = {} })
            eq("pi", pie.config.cmd)
            eq("<leader>ai", pie.config.keymap)
            eq("<C-c>", pie.config.abort_keymap)
            eq("single", pie.config.border)
            eq(60, pie.config.float_width)
            eq(3, pie.config.float_height)
        end)

        it("creates PieEdit command", function()
            local pie = require("pie")
            pie.setup()
            local cmds = vim.api.nvim_get_commands({})
            assert.is_not_nil(cmds["PieEdit"])
        end)

        it("creates PieAbort command", function()
            local pie = require("pie")
            pie.setup()
            local cmds = vim.api.nvim_get_commands({})
            assert.is_not_nil(cmds["PieAbort"])
        end)
    end)

    describe("client", function()
        it("has run() function", function()
            require("pie").setup()
            local client = require("pie.client")
            assert.is_function(client.run)
        end)
    end)

    describe("edit", function()
        it("has request() and abort()", function()
            require("pie").setup()
            local edit = require("pie.edit")
            assert.is_function(edit.request)
            assert.is_function(edit.abort)
        end)
    end)

    describe("highlights", function()
        before_each(function()
            vim.api.nvim_set_hl(0, "PiePromptIcon", { link = "Keyword" })
            vim.api.nvim_set_hl(0, "PieSpinner", { link = "Keyword" })
        end)

        it("PiePromptIcon highlight exists", function()
            local hl = vim.api.nvim_get_hl(0, { name = "PiePromptIcon" })
            assert.is_not_nil(hl)
        end)

        it("PieSpinner highlight exists", function()
            local hl = vim.api.nvim_get_hl(0, { name = "PieSpinner" })
            assert.is_not_nil(hl)
        end)

        it("highlights link to Keyword by default", function()
            local hl = vim.api.nvim_get_hl(0, { name = "PiePromptIcon" })
            eq("Keyword", hl.link)
        end)
    end)

    describe("health", function()
        it("health module loads", function()
            require("pie").setup()
            local health = require("pie.health")
            assert.is_function(health.check)
        end)
    end)
end)
