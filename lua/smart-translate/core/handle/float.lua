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

    -- If preview is already open, focus it
    if float.focus_open(id) then
        return
    end

    local title = "SmartTranslate(cache)"

    if not translator.use_cache_translation then
        title = ("SmartTranslate(%s)"):format(translator.engine)
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

        -- If single line selection, align with selection start
        -- If multi-line selection, align with line start
        if #translator.range == 1 then
            display_col = first_range.scol
        else
            display_col = 1
        end
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
        zindex = 200,
    })

    -- Mark the window with an identifier
    vim.w[winner].smart_translate_preview = id

    -- Enable wrap if configured
    if enable_wrap then
        vim.wo[winner].wrap = true
    end

    footer_handle(winner, bufnr)

    -- Set up keymaps in the float window buffer
    api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>quit!<cr>", { silent = true })
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

    -- Close the popup when navigating to any window which is not the preview itself
    local group = "smart-translate-popup"
    local group_id = api.nvim_create_augroup(group, { clear = false })
    api.nvim_create_augroup(group, { clear = true }) -- Clear the group first

    local old_cursor = api.nvim_win_get_cursor(0)

    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group_id,
        callback = function()
            local cursor = api.nvim_win_get_cursor(0)
            -- Did the cursor REALLY change (neovim/neovim#12923)
            if (old_cursor[1] ~= cursor[1] or old_cursor[2] ~= cursor[2]) and api.nvim_get_current_win() ~= winner then
                -- Clear the augroup
                api.nvim_create_augroup(group, { clear = true })
                pcall(api.nvim_win_close, winner, true)
                return
            end
            old_cursor = cursor
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
