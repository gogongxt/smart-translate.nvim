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
    default_config = vim.tbl_deep_extend("force", default_config, opts or {})
end

return config
