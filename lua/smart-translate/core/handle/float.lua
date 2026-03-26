local float = {}

local api = vim.api
local cache_scrolloff = vim.opt.scrolloff:get()
local config = require("smart-translate.config")

--- Calculate the number of screen lines needed for a line with wrap enabled
---@param line string
---@param width integer
---@return integer
local function calculate_wrapped_lines(line, width)
    if width <= 0 then
        return 1
    end
    local line_len = vim.fn.strdisplaywidth(line)
    if line_len == 0 then
        return 1
    end
    return math.ceil(line_len / width)
end

--- Calculate total height needed for all lines with wrap enabled
---@param lines string[]
---@param width integer
---@return integer
local function calculate_total_height(lines, width)
    local total = 0
    for _, line in ipairs(lines) do
        total = total + calculate_wrapped_lines(line, width)
    end
    return total
end

--- Check if a preview window with the given id is open
---@param id string
---@return integer? winid
function float.is_open(id)
    for _, winid in ipairs(api.nvim_list_wins()) do
        if vim.w[winid].smart_translate_preview == id then
            return winid
        end
    end
end

--- Find the topmost (highest nesting level) translate window
---@return integer? winid
function float.get_topmost_window()
    local topmost_winid = nil
    local topmost_level = 0

    for _, winid in ipairs(api.nvim_list_wins()) do
        local id = vim.w[winid].smart_translate_preview
        if id then
            -- Extract nesting level from ID
            local level = 0
            if id == "translate" then
                level = 1
            elseif id:match("^translate_n(%d+)$") then
                level = tonumber(id:match("^translate_n(%d+)$"))
            end

            if level > topmost_level then
                topmost_level = level
                topmost_winid = winid
            end
        end
    end

    return topmost_winid
end

--- Get the parent window of a nested translate window
---@param winid integer
---@return integer? parent_winid
function float.get_parent_window(winid)
    local id = vim.w[winid].smart_translate_preview
    if not id then
        return nil
    end

    local current_level = 0
    if id == "translate" then
        current_level = 1
    elseif id:match("^translate_n(%d+)$") then
        current_level = tonumber(id:match("^translate_n(%d+)$"))
    else
        return nil
    end

    -- Find the parent window (level - 1)
    if current_level <= 1 then
        return nil
    end

    local parent_level = current_level - 1
    local parent_id = parent_level == 1 and "translate" or ("translate_n" .. parent_level)

    return float.is_open(parent_id)
end

--- Focus the open preview window if it exists
---@param id string
---@return integer? winid
function float.focus_open(id)
    local winid = float.is_open(id)
    if winid then
        api.nvim_set_current_win(winid)
    end
    return winid
end

local function footer_handle(winner, bufnr)
    local cursor_line = vim.fn.line(".", winner)
    local buffer_total_line = api.nvim_buf_line_count(bufnr)
    local window_height = api.nvim_win_get_height(winner)
    local window_last_line = vim.fn.line("w$", winner)

    local progress = math.floor(window_last_line / buffer_total_line * 100)

    if buffer_total_line <= window_height + 1 then
        return
    end

    if cursor_line == 1 then
        progress = 0
    end

    local footer = ("%s%%"):format(progress)

    api.nvim_win_set_config(winner, {
        footer = footer,
        footer_pos = "right",
    })
end

local function scroll_hover(count, winner, bufnr)
    local cursor_line = vim.fn.line(".", winner)
    local buffer_line_count = api.nvim_buf_line_count(bufnr)
    local window_head_line = vim.fn.line("w0", winner)
    local window_last_line = vim.fn.line("w$", winner)

    vim.opt.scrolloff = 0

    if count > 0 then
        if cursor_line < window_last_line then
            local target = math.min(window_last_line + count, buffer_line_count)
            api.nvim_win_set_cursor(winner, { target, 0 })
        else
            local target = math.min(cursor_line + count, buffer_line_count)
            api.nvim_win_set_cursor(winner, { target, 0 })
        end
        footer_handle(winner, bufnr)
    else
        if cursor_line > window_head_line then
            local target = math.max(window_head_line + count, 1)
            api.nvim_win_set_cursor(winner, { target, 0 })
        else
            local target = math.max(cursor_line + count, 1)
            api.nvim_win_set_cursor(winner, { target, 0 })
        end

        footer_handle(winner, bufnr)
    end

    vim.opt.scrolloff = cache_scrolloff
end

---@param translator SmartTranslate.Translator
function float.render(translator)
    local id = "translate"
    local source_bufnr = translator.buffer

    -- Determine nesting level based on current window
    local current_win = api.nvim_get_current_win()
    local current_id = vim.w[current_win].smart_translate_preview
    local nesting_level = 0

    if current_id then
        -- We're in a translate window, extract its level
        if current_id:match("^translate_n(%d+)$") then
            nesting_level = tonumber(current_id:match("^translate_n(%d+)$"))
        elseif current_id == "translate" then
            nesting_level = 1
        end

        -- The next level window should have level + 1
        local next_level = nesting_level + 1
        id = "translate_n" .. next_level

        -- Check if this nested window already exists and focus it
        if float.focus_open(id) then
            return
        end
    else
        -- We're not in a translate window, this is the first level
        -- Check if first-level window already exists and focus it
        if float.focus_open(id) then
            return
        end
    end

    local title = "SmartTranslate(cache)"
    if not translator.use_cache_translation then
        title = ("SmartTranslate(%s)"):format(translator.engine)
    end

    -- Add nesting level indicator for nested translations
    -- The new window's level is current_level + 1 (or 1 if this is the first window)
    local display_level = nesting_level + 1
    if display_level > 1 then
        title = title .. (" [L%d]"):format(display_level)
    end

    -- Get float configuration
    local float_config = config.float or {}
    local max_width = float_config.max_width or 0
    local enable_wrap = float_config.wrap ~= false -- default to true

    -- Calculate base width from content
    local base_width = title:len()
    for _, l in ipairs(translator.translation) do
        base_width = math.max(base_width, vim.fn.strdisplaywidth(l))
    end

    -- Apply max_width limit if configured
    local width
    if max_width > 0 and base_width > max_width then
        width = max_width
    else
        width = base_width
    end

    -- Calculate height considering wrap
    local height
    if enable_wrap and max_width > 0 and base_width > max_width then
        -- Calculate actual height needed when wrap is enabled
        height = calculate_total_height(translator.translation, width)
    else
        -- No wrap or no width limit, use number of lines
        height = #translator.translation
    end

    -- Limit height to 3/4 of screen
    height = math.min(height, math.floor(vim.o.lines * 3 / 4))

    -- When the display length is not long enough to display the title, we will hide the title
    if #translator.translation == 1 and #translator.translation[1] < width then
        title = ""
        width = vim.fn.strdisplaywidth(translator.translation[1])
    end

    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, translator.translation)
    vim.bo[bufnr].filetype = "translate-float"
    vim.bo[bufnr].bufhidden = "wipe"

    -- Calculate display position: show below the selected text
    local display_row, display_col

    if not vim.tbl_isempty(translator.range) then
        local last_range = translator.range[#translator.range]
        local first_range = translator.range[1]

        -- Use the last line of the range
        display_row = last_range.lnum

        -- Always align with selection start column for consistency
        display_col = first_range.scol
    else
        -- Fallback to saved cursor position
        display_row = translator.cursor[1]
        display_col = translator.cursor[2] + 1
    end

    -- Get screen position for the calculated position
    local screen_pos = vim.fn.screenpos(translator.window, display_row, display_col)

    -- When wrap is enabled, a single logical line can span multiple screen rows.
    -- We need to find the bottom-most screen row of the current line to avoid overlap.
    -- Use screenpos with a very large column to find where the line ends on screen.
    local source_wrap = api.nvim_win_get_option(translator.window, "wrap")
    if source_wrap then
        local wrap_screen_pos = vim.fn.screenpos(translator.window, display_row, 999999)
        -- The bottom of the current line is the screen row where the line wraps
        screen_pos.row = wrap_screen_pos.row
    end

    local winner = api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = screen_pos.row,
        col = screen_pos.col - 1,
        width = width,
        height = height,
        title = title,
        title_pos = "center",
        style = "minimal",
        border = "rounded",
        focusable = true,
        zindex = 200 + display_level * 10, -- Increase zindex for nested windows
    })

    -- Mark the window with an identifier
    vim.w[winner].smart_translate_preview = id

    -- Enable wrap if configured
    if enable_wrap then
        vim.wo[winner].wrap = true
    end

    footer_handle(winner, bufnr)

    -- Set up keymaps in the float window buffer
    api.nvim_buf_set_keymap(bufnr, "n", "q", "", {
        callback = function()
            -- Get parent window before closing
            local parent_winid = float.get_parent_window(winner)

            -- If parent exists, navigate to it first (this will update its autocmd state)
            -- Then close current window
            if parent_winid and api.nvim_win_is_valid(parent_winid) then
                api.nvim_set_current_win(parent_winid)
                -- Now safe to close the child window
                api.nvim_win_close(winner, true)
            else
                -- No parent, close and return to source window
                api.nvim_win_close(winner, true)
                if api.nvim_win_is_valid(translator.window) then
                    api.nvim_set_current_win(translator.window)
                end
            end
        end,
        silent = true,
    })
    api.nvim_buf_set_keymap(bufnr, "n", "<c-f>", "", {
        callback = function()
            scroll_hover(5, winner, bufnr)
        end,
        silent = true,
    })
    api.nvim_buf_set_keymap(bufnr, "n", "<c-b>", "", {
        callback = function()
            scroll_hover(-5, winner, bufnr)
        end,
        silent = true,
    })

    -- Add visual mode keymaps for nested translation
    api.nvim_buf_set_keymap(bufnr, "v", "q", "<esc>", { silent = true })
    api.nvim_buf_set_keymap(bufnr, "v", "<c-f>", "", {
        callback = function()
            scroll_hover(5, winner, bufnr)
        end,
        silent = true,
    })
    api.nvim_buf_set_keymap(bufnr, "v", "<c-b>", "", {
        callback = function()
            scroll_hover(-5, winner, bufnr)
        end,
        silent = true,
    })

    -- Close the popup when navigating to any window which is not the preview itself
    -- Use unique augroup per window to avoid conflicts with nested windows
    local group = "smart-translate-popup-" .. id
    local group_id = api.nvim_create_augroup(group, { clear = true })

    -- Track the last window where cursor was moved
    -- This helps detect when user has entered this window vs. stayed in parent window
    local last_win = api.nvim_get_current_win()
    local last_cursor = api.nvim_win_get_cursor(0)

    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group_id,
        callback = function()
            local cursor = api.nvim_win_get_cursor(0)
            local current_win = api.nvim_get_current_win()

            -- Check if we're leaving this window
            if current_win ~= winner then
                local target_id = vim.w[current_win].smart_translate_preview

                -- Close if:
                -- 1. Moving to a non-translate window, OR
                -- 2. User never entered this window (last_win was not this window)
                --    AND moving to any other window
                if not target_id then
                    -- Moving to a non-translate window, close this window
                    api.nvim_create_augroup(group, { clear = true })
                    pcall(api.nvim_win_close, winner, true)
                    return
                elseif last_win ~= winner then
                    -- User never entered this window, close it
                    api.nvim_create_augroup(group, { clear = true })
                    pcall(api.nvim_win_close, winner, true)
                    return
                end
                -- Moving to another translate window and user had entered this window, keep it open
                return
            end

            -- Cursor moved within this window, update tracking
            last_win = current_win
            last_cursor = cursor
        end,
    })

    api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(winner),
        group = group_id,
        callback = function()
            -- Clear the augroup
            api.nvim_create_augroup(group, { clear = true })
        end,
    })
end

return float
