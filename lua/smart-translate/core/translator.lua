local util = require("smart-translate.util")
local config = require("smart-translate.config")
local EngineProxies = require("smart-translate.core.engine")
local HandleProxy = require("smart-translate.core.handle")

local special_cmds = {
    "--stream",
    "--comment",
    "--cleanup",
    "--variable",
}

---@class SmartTranslate.Translator
---@field public namespace integer                          -- Namespace
---@field public special string[]                           -- Special operations, e.g., --comment/--cleanup
---@field public buffer buffer                              -- The buffer the original text came from
---@field public window window                              -- The window the original text came from
---@field public mode string                                -- Mode when translation was invoked
---@field public source string                              -- Source language
---@field public target string                              -- Target language
---@field public handle string                              -- Handler
---@field public engine string                              -- Translation engine
---@field public fallback_engines string[]|nil              -- Fallback engines
---@field public original string[]                          -- Original text
---@field public public translation string[]                -- Translated text
---@field public highlights table[]|nil                     -- ANSI color highlights
---@field public use_cache_translation boolean              -- Whether cache was hit
---@field public range table<string, integer>[]             -- Original text range
---@field public engine_proxy SmartTranslate.EngineProxy|SmartTranslate.FallbackEngineProxy
---@field public handle_proxy SmartTranslate.HandleProxy
local Translator = {}
Translator.__index = Translator

---@param env vim.api.keyset.create_user_command.command_args
function Translator.new(env)
    local self = setmetatable({}, Translator)

    util.with_defaults(self, config.default.cmds)

    self.range = {}
    self.special = {}
    self.original = {}
    self.translation = {}
    self.mode = env.range == 0 and vim.fn.mode() or vim.fn.visualmode()

    self.buffer = vim.api.nvim_get_current_buf()
    self.window = vim.api.nvim_get_current_win()
    self.cursor = vim.api.nvim_win_get_cursor(self.window)
    self.namespace = vim.api.nvim_create_namespace(("Transtor-ns-%s"):format(self.buffer))

    self:parser_env(env)

    self.use_cache_translation = false

    -- Create appropriate proxy based on whether fallback is configured
    if self.fallback_engines and #self.fallback_engines > 0 then
        -- Combine primary engine with fallbacks
        local all_engines = { self.engine }
        for _, fallback in ipairs(self.fallback_engines) do
            table.insert(all_engines, fallback)
        end
        self.engine_proxy = EngineProxies.FallbackEngineProxy.new(all_engines)
    else
        self.engine_proxy = EngineProxies.EngineProxy.new(self.engine)
    end

    self.handle_proxy = HandleProxy.new(self.handle)

    return self
end

---@param env vim.api.keyset.create_user_command.command_args
function Translator:parser_env(env)
    for _, v in ipairs(env.fargs) do
        if v:sub(1, 2) == "--" then
            if vim.tbl_contains(special_cmds, v) then
                table.insert(self.special, v)
            else
                local parts = vim.split(v:sub(3), "=", { trimempty = true })
                self[parts[1]] = parts[2]
            end
        else
            table.insert(self.original, v)
        end
    end
end

function Translator:translate()
    self.original = config.hooks.before_translate({
        mode = self.mode,
        engine = self.engine,
        source = self.source,
        target = self.target,
        original = self.original,
    })

    self.engine_proxy:translate(
        self.source,
        self.target,
        self.original,
        ---@param use_cache boolean
        ---@param translation string[]
        ---@param actual_engine string The engine that actually performed the translation
        ---@param highlights table[]|nil ANSI color highlights
        function(use_cache, translation, actual_engine, highlights)
            self.use_cache_translation = use_cache
            -- Update engine to show which engine actually translated
            self.engine = actual_engine
            self.highlights = highlights
            self.translation = config.hooks.after_translate({
                mode = self.mode,
                engine = self.engine,
                source = self.source,
                target = self.target,
                translation = translation,
            })

            self.handle_proxy:render(self)
        end
    )
end

return Translator
