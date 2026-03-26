-- author: askfiy

local config = require("smart-translate.config")
local parser = require("smart-translate.core.parser")
local cacher = require("smart-translate.core.cacher")
local complete = require("smart-translate.core.complete")
local Translator = require("smart-translate.core.translator")

-- require("smart-translate.debug")

local M = {}

---@param opts? table<string, any>
function M.setup(opts)
    config.update(opts)
    cacher.load_cache()

    vim.api.nvim_create_user_command("Translate", function(env)
        local translator = Translator.new(env)

        if not vim.tbl_isempty(translator.special) then
            if #translator.special > 1 then
                vim.notify("Many special operations", "ERROR", {
                    annote = "[smart-translate]",
                })
                return
            end

            if not vim.tbl_isempty(translator.original) then
                vim.notify("Unable to translate when special operations are executed", "ERROR", {
                    annote = "[smart-translate]",
                })
                return
            end
        end

        if vim.tbl_contains(translator.special, "--stream") then
            vim.notify("Not implemented", "ERROR", {
                annote = "[smart-translate]",
            })
            return
        end

        if vim.tbl_contains(translator.special, "--cleanup") then
            vim.notify("Cleanup cacher success", "INFO", {
                annote = "[smart-translate]",
            })
            cacher.cleanup()
            return
        end

        if not vim.tbl_isempty(translator.original) then
            translator.original = { table.concat(translator.original, " ") }
        else
            if not vim.tbl_contains(translator.special, "--comment") then
                translator.range, translator.original = unpack(parser.select(translator.mode))
            else
                translator.range, translator.original = unpack(parser.comment(translator.buffer))
            end

            local content = table.concat(translator.original, "\n")
            if #vim.trim(content) == 0 then
                vim.notify("No content", "ERROR", {
                    annote = "[smart-translate]",
                })
                return
            end
            translator.original = vim.split(content, "\n", { trimempty = false })
        end

        -- Check if we're translating from within a translate float window
        -- If so, allow nested translation by skipping the focus check
        local current_win = vim.api.nvim_get_current_win()
        local is_in_translate_window = vim.w[current_win].smart_translate_preview ~= nil

        -- Handle focus behavior for float windows
        if translator.handle == "float" then
            local float_handle = require("smart-translate.core.handle.float")

            if is_in_translate_window then
                -- If in a translate window without any text selection,
                -- focus the topmost existing window instead of creating a new one
                if vim.tbl_isempty(translator.original) then
                    local topmost_win = float_handle.get_topmost_window()
                    if topmost_win and topmost_win ~= current_win then
                        api.nvim_set_current_win(topmost_win)
                        return
                    end
                end
                -- If text is selected, allow creating a new nested window
            else
                -- If not in a translate window, focus the base translate window if it exists
                if float_handle.focus_open("translate") then
                    return
                end
            end
        end

        translator:translate()
    end, {
        nargs = "*",
        range = true,
        complete = complete.get_complete_list,
        desc = "Translate command",
    })
end

return M
