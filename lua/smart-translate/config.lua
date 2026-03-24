---@class SmartTranslate.Config
---@field public default SmartTranslate.Config.DefaultOpts
---@field public engine SmartTranslate.Config.EngineOpts
---@field public hooks SmartTranslate.Config.HooksOpts
---@field public translator SmartTranslate.Config.Translator
local config = {}

local default_config = {
    default = {
        cmds = {
            source = "auto",
            target = "zh-CN",
            handle = "float",
            engine = "google",
            fallback_engines = nil, -- e.g., {"bing", "deepl"}
        },
        cache = true,
    },
    -- Proxy configuration: "http://127.0.0.1:7890" or "$HTTP_PROXY"
    proxy = nil,
    -- Timeout in seconds for HTTP requests (default: 10 seconds)
    timeout = 10,
    -- Float window configuration
    float = {
        max_width = 80,  -- Maximum width of the float window (0 means no limit)
        wrap = true,     -- Enable text wrapping in the float window
    },
    engine = {
        deepl = {
            --Support SHELL variables, or fill in directly
            api_key = "$DEEPL_API_KEY",
            base_url = "https://api-free.deepl.com/v2/translate",
        },
        baidu = {
            --Support SHELL variables, or fill in directly
            app_id = "$BAIDU_APP_ID",
            api_key = "$BAIDU_API_KEY",
            base_url = "https://fanyi-api.baidu.com/ait/api/aiTextTranslate",
        },
    },
    hooks = {
        ---@param opts SmartTranslate.Config.Hooks.BeforeCallOpts
        ---@return string[]
        before_translate = function(opts)
            return opts.original
        end,
        ---@param opts SmartTranslate.Config.Hooks.AfterCallOpts
        ---@return string[]
        after_translate = function(opts)
            return opts.translation
        end,
    },
    translator = {
        engine = {},
        handle = {},
        terminal_commands = nil, -- Terminal command definitions
    },
}

setmetatable(config, {
    -- getter
    __index = function(_, key)
        return default_config[key]
    end,

    -- setter
    __newindex = function(_, key, value)
        default_config[key] = value
    end,
})

---@param opts? table<string, any>
function config.update(opts)
    -- Store old terminal_commands to check if cache needs clearing
    local old_terminal_commands = default_config.translator.terminal_commands
    local old_custom_engines = default_config.translator.engine

    default_config = vim.tbl_deep_extend("force", default_config, opts or {})

    -- Only clear engine cache if terminal_commands or custom engines changed
    local new_terminal_commands = default_config.translator.terminal_commands
    local new_custom_engines = default_config.translator.engine

    if old_terminal_commands ~= new_terminal_commands or old_custom_engines ~= new_custom_engines then
        local util = require("smart-translate.util")
        util._engins = nil
    end
end

return config
