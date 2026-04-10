local config = require("smart-translate.config")

local cmd = {}

--- ANSI color code to Neovim highlight group mapping
local ansi_colors = {
    [0] = "Normal",
    [30] = "TranslateAnsiBlack",
    [31] = "TranslateAnsiRed",
    [32] = "TranslateAnsiGreen",
    [33] = "TranslateAnsiYellow",
    [34] = "TranslateAnsiBlue",
    [35] = "TranslateAnsiMagenta",
    [36] = "TranslateAnsiCyan",
    [37] = "TranslateAnsiWhite",
    [90] = "TranslateAnsiBrightBlack",
    [91] = "TranslateAnsiBrightRed",
    [92] = "TranslateAnsiBrightGreen",
    [93] = "TranslateAnsiBrightYellow",
    [94] = "TranslateAnsiBrightBlue",
    [95] = "TranslateAnsiBrightMagenta",
    [96] = "TranslateAnsiBrightCyan",
    [97] = "TranslateAnsiBrightWhite",
}

--- Check if text contains ANSI escape sequences
---@param text string
---@return boolean
function cmd.has_ansi(text)
    return text:find("\27%[") ~= nil
end

--- Parse ANSI escape sequences and return clean lines with highlight info
---@param text string
---@return string[] lines, table[] highlights highlights: {line, col_start, col_end, hl_group}
function cmd.parse_ansi(text)
    local lines = {}
    local highlights = {}
    local current_line = ""
    local col = 0
    local line_num = 0
    local current_fg = nil

    -- Process text character by character, handling ANSI sequences
    local i = 1
    while i <= #text do
        local char = text:sub(i, i)

        -- Check for ESC sequence
        if char == "\27" and text:sub(i + 1, i + 1) == "[" then
            -- Find the end of the sequence (letter)
            local j = i + 2
            while j <= #text and not text:sub(j, j):match("[A-Za-z]") do
                j = j + 1
            end

            local seq_type = text:sub(j, j)
            local params = text:sub(i + 2, j - 1)

            if seq_type == "m" then
                -- SGR (Select Graphic Rendition) sequence
                if params == "" or params == "0" then
                    -- Reset
                    current_fg = nil
                else
                    -- Parse parameters
                    for code_str in params:gmatch("([^;]+)") do
                        local code = tonumber(code_str)
                        if code then
                            if code == 0 then
                                current_fg = nil
                            elseif code >= 30 and code <= 37 then
                                current_fg = code
                            elseif code >= 90 and code <= 97 then
                                current_fg = code
                            end
                        end
                    end
                end
            end

            i = j + 1
        elseif char == "\n" then
            -- Newline
            table.insert(lines, current_line)
            current_line = ""
            line_num = line_num + 1
            col = 0
            i = i + 1
        else
            -- Regular character - track position for highlighting
            local start_col = col
            current_line = current_line .. char
            col = col + 1

            -- Add highlight for this character if we have an active color
            if current_fg then
                table.insert(highlights, {
                    line = line_num,
                    col_start = start_col,
                    col_end = col,
                    ansi_code = current_fg,
                })
            end

            i = i + 1
        end
    end

    -- Add final line
    table.insert(lines, current_line)

    return lines, highlights
end

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
---@return fun(source: string, target: string, original: string[], callback: fun(err: string|nil, translation: string[], highlights: table[]|nil))
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
        -- FORCE_COLOR=1 forces terminal commands to output ANSI color codes even when piped
        vim.system(
            { "sh", "-c", "FORCE_COLOR=1 " .. final_command },
            { text = true, timeout = timeout },
            vim.schedule_wrap(function(result)
                local stdout = result.stdout or ""
                local stderr = result.stderr or ""

                -- Check for ANSI in output, set metadata flag
                local has_ansi = cmd.has_ansi(stdout)
                local highlights = {}

                -- Check exit code
                if result.code ~= 0 then
                    callback(("Exit code %d: %s"):format(result.code, stderr or "Unknown error"), {}, nil)
                    return
                end

                -- Custom success check if provided
                if command_def.success_check then
                    local success = command_def.success_check(stdout, stderr)
                    if not success then
                        callback("Custom success check failed", {}, nil)
                        return
                    end
                else
                    -- Default: check stdout is not empty/whitespace-only
                    if vim.trim(stdout) == "" then
                        callback("Command returned empty output", {}, nil)
                        return
                    end
                end

                -- Parse ANSI and get clean lines + highlights
                local translation
                if has_ansi then
                    translation, highlights = cmd.parse_ansi(stdout)
                else
                    translation = vim.split(stdout, "\n", { trimempty = false })
                end

                -- Remove trailing empty line if present (common from shell commands)
                if #translation > 0 and translation[#translation] == "" then
                    table.remove(translation)
                end

                callback(nil, translation, has_ansi and highlights or nil)
            end)
        )
    end
end

return cmd
