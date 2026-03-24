local config = require("smart-translate.config")

local cmd = {}

--- Get terminal command definitions from config
---@return table<string, SmartTranslate.Config.Translator.Engine.TerminalCommand>
function cmd.get_commands()
    local commands = {}

    if config.translator.terminal_commands then
        for _, cmd_def in ipairs(config.translator.terminal_commands) do
            commands[cmd_def.name] = cmd_def
        end
    end

    return commands
end

--- Create translate function for a terminal command
---@param command_def SmartTranslate.Config.Translator.Engine.TerminalCommand
---@return fun(source: string, target: string, original: string[], callback: fun(err: string|nil, translation: string[]))
function cmd.create_translate_fn(command_def)
    -- Validate command contains {text} placeholder
    if not command_def.command:find("{text}") then
        error(("Terminal command must contain {text} placeholder: %s"):format(command_def.command))
    end

    return function(source, target, original, callback)
        local timeout = (command_def.timeout or config.timeout) * 1000
        local text = table.concat(original, "\n")
        local escaped_text = vim.fn.shellescape(text)
        local final_command = command_def.command:gsub("{text}", escaped_text)

        -- Use shell to execute the command to handle complex commands properly
        vim.system(
            { "sh", "-c", final_command },
            { text = true, timeout = timeout },
            vim.schedule_wrap(function(result)
                local stdout = result.stdout or ""
                local stderr = result.stderr or ""

                -- Check exit code
                if result.code ~= 0 then
                    callback(
                        ("Exit code %d: %s"):format(result.code, stderr or "Unknown error"),
                        {}
                    )
                    return
                end

                -- Custom success check if provided
                if command_def.success_check then
                    local success = command_def.success_check(stdout, stderr)
                    if not success then
                        callback("Custom success check failed", {})
                        return
                    end
                else
                    -- Default: check stdout is not empty/whitespace-only
                    if vim.trim(stdout) == "" then
                        callback("Command returned empty output", {})
                        return
                    end
                end

                -- Split into lines (preserve empty lines for line count matching)
                local translation = vim.split(stdout, "\n", { trimempty = false })

                -- Remove trailing empty line if present (common from shell commands)
                if #translation > 0 and translation[#translation] == "" then
                    table.remove(translation)
                end

                callback(nil, translation)
            end)
        )
    end
end

return cmd
