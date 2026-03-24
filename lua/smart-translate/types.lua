---@class SmartTranslate.Config.DefaultOpts.Cmds
---@field public source string
---@field public target string
---@field public handle string
---@field public engine string Primary engine name
---@field public fallback_engines string[]|nil Fallback engine names tried in order

---@class SmartTranslate.Config.DefaultOpts
---@field public cmds SmartTranslate.Config.DefaultOpts.Cmds
---@field public cache string

---@class SmartTranslate.Config
---@field public timeout number Timeout in seconds for HTTP requests
---@field public float SmartTranslate.Config.Float Float window configuration

---@class SmartTranslate.Config.EngineOpts.Openai
---@field public model string
---@field public api_key string
---@field public base_url string

---@class SmartTranslate.Config.EngineOpts.Baidu
---@field public app_id string
---@field public api_key string
---@field public base_url string

---@class SmartTranslate.Config.EngineOpts.DeepL
---@field public api_key string
---@field public base_url string

---@class SmartTranslate.Config.EngineOpts
---@field public deepl SmartTranslate.Config.EngineOpts.DeepL
---@field public baidu SmartTranslate.Config.EngineOpts.Baidu

---@class SmartTranslate.Config.Hooks.BeforeCallOpts
---@field public mode string
---@field public engine string
---@field public source string
---@field public target string
---@field public original string[]

---@class SmartTranslate.Config.Hooks.AfterCallOpts
---@field public mode string
---@field public engine string
---@field public source string
---@field public target string
---@field public translation string[]

---@class SmartTranslate.Config.HooksOpts
---@field public before_translate fun(otps: SmartTranslate.Config.Hooks.BeforeCallOpts): string[]
---@field public after_translate fun(otps: SmartTranslate.Config.Hooks.AfterCallOpts): string[]

--- Callback signature for translation engines
---@alias TranslateEngineCallback fun(err: string|nil, translation: string[])

--- Callback signature for EngineProxy.translate
---@alias TranslateProxyCallback fun(use_cache: boolean, translation: string[], actual_engine: string)

---@class SmartTranslate.Config.Translator.Engine
---@field public name string
---@field public translate fun(source: string, target:string, original: string[], callback: TranslateEngineCallback)

---@class SmartTranslate.Config.Translator.Engine.TerminalCommand
---@field public name string
---@field public command string Command with {text} placeholder
---@field public timeout number|nil Optional timeout in seconds (default: config.timeout)
---@field public success_check fun(stdout: string, stderr: string): boolean Optional function to check if translation succeeded

---@class SmartTranslate.Config.Translator.Handle
---@field public name string
---@field public render fun(translator: SmartTranslate.Translator)

---@class SmartTranslate.Config.Translator
---@field public engine SmartTranslate.Config.Translator.Engine[]
---@field public handle SmartTranslate.Config.Translator.Engine[]
---@field public terminal_commands SmartTranslate.Config.Translator.Engine.TerminalCommand[]|nil Terminal command definitions

---@class SmartTranslate.Config.Float
---@field public max_width integer Maximum width of the float window (0 means no limit)
---@field public wrap boolean Enable text wrapping in the float window
