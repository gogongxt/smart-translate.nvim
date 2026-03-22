local float = {}

local api = vim.api
local cache_scrolloff = vim.opt.scrolloff:get()

--- Check if a preview window with the given id is open
---@param id string
---@return integer? winid
local function is_open(id)
    for _, winid in ipairs(api.nvim_list_wins()) do
        if vim.w[winid].smart_translate_preview == id then
            return winid
        end
    end
end

--- Focus the open preview window if it exists
---@param id string
---@return integer? winid
local function focus_open(id)
    local winid = is_open(id)
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
    if focus_open(id) then
        return
    end

    local title = "SmartTranslate(cache)"

    if not translator.use_cache_translation then
        title = ("SmartTranslate(%s)"):format(translator.engine)
    end

    local width = title:len()
    for _, l in ipairs(translator.translation) do
        width = math.max(width, #l)
    end

    local height = math.min(#translator.translation, math.floor(vim.o.lines * 3 / 4))

    -- When the display length is not long enough to display the title, we will hide the title
    if #translator.translation == 1 and #translator.translation[1] < width then
        title = ""
        width = #translator.translation[1]
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
