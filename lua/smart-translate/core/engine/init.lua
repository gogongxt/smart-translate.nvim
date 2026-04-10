local md5 = require("smart-translate.libs.md5")
local util = require("smart-translate.util")
local config = require("smart-translate.config")
local cacher = require("smart-translate.core.cacher")
local content = require("smart-translate.util.content")
local proxy = require("smart-translate.util.proxy")

---@param engine string
---@return boolean
local function has_engine(engine)
    return vim.tbl_contains(util.engines(), engine)
end

---@param engine string
---@return table
local function get_engine(engine)
    -- Try built-in engine
    local ok, pkg = pcall(
        require,
        ("smart-translate.core.engine.%s"):format(engine:lower())
    )

    if ok then
        return pkg
    end

    -- Try custom engine from config
    ---@param item SmartTranslate.Config.Translator.Engine
    local filters = vim.tbl_filter(function(item)
        return item.name == engine
    end, config.translator.engine)

    if not vim.tbl_isempty(filters) then
        return filters[1]
    end

    -- Try terminal command engine
    local cmd = require("smart-translate.core.engine.cmd")
    local commands = cmd.get_commands()

    if commands[engine] then
        return {
            name = engine,
            translate = cmd.create_translate_fn(commands[engine])
        }
    end

    return {}
end

--[[
    A sophisticated caching mechanism is integral to our translator's design. The system generates cache keys using MD5 hashing, combining four essential components:
    - Source language
    - Target language
    - Original text content
    - Translation engine identifier

    The translation process optimizes performance by:
    1. Checking the cache before translation
    2. Only processing uncached lines
    3. Maintaining line-level granularity

    The cache validation enforces a line count match between source and translation. When line counts differ, the system continues to function but excludes those results from the cache, ensuring cache integrity without compromising translation functionality.
]]

---@class SmartTranslate.Engine
---@field public translate fun(source: string, target: string, original: string[], callback: fun(err: string|nil, translation: string[], highlights: table[]|nil))

---@class SmartTranslate.EngineProxy
---@field private placeholder string
---@field private proxy string
---@field private engine SmartTranslate.Engine
local EngineProxy = {}
EngineProxy.__index = EngineProxy

---@param proxy string
function EngineProxy.new(proxy)
    local self = setmetatable({}, EngineProxy)
    assert(has_engine(proxy), ("Invalid engine: %s"):format(proxy))

    self.proxy = proxy
    self.engine = get_engine(proxy)

    self.placeholder = "{{NO_CACHE}}"

    assert(
        type(self.engine) == "table"
            and type(self.engine.translate) == "function",
        ("Not implemented `translate`, form: %s"):format(proxy)
    )
    return self
end

---@param source string
---@param target string
---@param original string[]
---@param callback function(use_cache: boolean, translation: string[], actual_engine: string, highlights: table[]|nil)
function EngineProxy:translate(source, target, original, callback)
    -- Setup proxy and get restore function
    local restore = proxy.setup()

    if not config.default.cache then
        self.engine.translate(source, target, original, function(err, translation, highlights)
            restore()
            if err then
                vim.notify(
                    ("Translation failed: %s"):format(err),
                    "ERROR",
                    { annote = "[smart-translate]" }
                )
                callback(false, {}, self.proxy, nil)
            else
                callback(false, translation, self.proxy, highlights)
            end
        end)
        return
    end

    local cached, no_cache = self:query_cache(source, target, original)

    if vim.tbl_isempty(no_cache) then
        restore()
        callback(true, cached, self.proxy, nil)
    else
        self.engine.translate(source, target, original, function(err, translation, highlights)
            restore()

            if err then
                vim.notify(
                    ("Translation failed: %s"):format(err),
                    "ERROR",
                    { annote = "[smart-translate]" }
                )
                callback(false, {}, self.proxy, nil)
                return
            end

            local cached_copy = vim.deepcopy(cached)

            -- When we cannot ensure that the number of lines of the translation and the original text are always consistent, caching should not be performed
            -- The engines currently experiencing this situation are:
            -- - bing
            if #translation ~= #cached_copy then
                callback(false, translation, self.proxy, highlights)
            else
                local no_cache_index = 1
                for index, line in ipairs(cached) do
                    if line == self.placeholder then
                        cached_copy[index] = translation[index]

                        local key = self:cache_key(
                            source,
                            target,
                            vim.trim(no_cache[no_cache_index])
                        )

                        cacher.set(key, vim.trim(translation[index]))

                        no_cache_index = no_cache_index + 1
                    end
                end
                callback(false, cached_copy, self.proxy, nil)
            end
        end)
    end
end

---@param source string
---@param target string
---@param original_text string
---@return string
function EngineProxy:cache_key(source, target, original_text)
    return md5.sumhexa(
        self.proxy:lower() .. source:lower() .. target:lower() .. original_text
    )
end

---@param source string
---@param target string
---@param original string[]
---@return string[], string[]
function EngineProxy:query_cache(source, target, original)
    local cached = {}
    local no_cache = {}

    for index, line in ipairs(original) do
        local trim_line = vim.trim(line)

        if trim_line:len() > 0 then
            local key = self:cache_key(source, target, trim_line)
            local cache = cacher.get(key)

            if cache then
                --Get the indent of the current line and add the cached content
                cached[index] = content.get_indentation(line) .. cache
            else
                -- placeholder
                cached[index] = self.placeholder
                table.insert(no_cache, line)
            end
        else
            cached[index] = line
        end
    end

    return cached, no_cache
end

---@class SmartTranslate.FallbackEngineProxy
---@field private engines string[] List of engine names to try in order
---@field private current_index integer Current engine being tried
---@field private source string
---@field private target string
---@field private original string[]
---@field private final_callback function
---@field private cache_hits string[] Lines from cache
---@field private cache_misses string[] Lines needing translation
---@field private placeholder string
---@field private successful_engine string|nil The engine that successfully translated
local FallbackEngineProxy = {}
FallbackEngineProxy.__index = FallbackEngineProxy

---@param engines string[] Engine names in priority order
function FallbackEngineProxy.new(engines)
    local self = setmetatable({}, FallbackEngineProxy)

    assert(#engines > 0, "At least one engine must be specified")

    -- Validate all engines exist
    for _, engine in ipairs(engines) do
        assert(has_engine(engine), ("Invalid engine: %s"):format(engine))
    end

    self.engines = engines
    self.current_index = 1
    self.placeholder = "{{NO_CACHE}}"

    return self
end

---@param source string
---@param target string
---@param original string[]
---@param callback function(use_cache: boolean, translation: string[], actual_engine: string, highlights: table[]|nil)
function FallbackEngineProxy:translate(source, target, original, callback)
    local restore = proxy.setup()

    self.source = source
    self.target = target
    self.original = original
    self.final_callback = callback

    if not config.default.cache then
        self:try_next_engine(restore, original)
        return
    end

    -- Check cache using first engine (cache key includes engine name)
    local first_engine_proxy = EngineProxy.new(self.engines[1])
    local cached, no_cache = first_engine_proxy:query_cache(source, target, original)

    self.cache_hits = cached
    self.cache_misses = no_cache

    if vim.tbl_isempty(no_cache) then
        restore()
        callback(true, cached, self.engines[1], nil)
    else
        self:try_next_engine(restore, no_cache)
    end
end

---@param restore function Function to restore proxy settings
---@param to_translate string[] Text to translate
function FallbackEngineProxy:try_next_engine(restore, to_translate)
    if self.current_index > #self.engines then
        -- All engines failed
        restore()
        vim.notify(
            ("All %d translation engines failed"):format(#self.engines),
            "ERROR",
            { annote = "[smart-translate]" }
        )
        self.final_callback(false, {}, nil, nil)
        return
    end

    local engine_name = self.engines[self.current_index]
    local engine = get_engine(engine_name)

    engine.translate(self.source, self.target, to_translate, function(err, translation, highlights)
        -- Check for explicit error
        if err then
            vim.notify(
                ("Engine '%s' failed: %s"):format(engine_name, err),
                "WARN",
                { annote = "[smart-translate]" }
            )
            self.current_index = self.current_index + 1
            self:try_next_engine(restore, to_translate)
            return
        end

        -- Check for empty translation (could be valid but unusual)
        if #translation == 0 then
            vim.notify(
                ("Engine '%s' returned empty translation"):format(engine_name),
                "WARN",
                { annote = "[smart-translate]" }
            )
            self.current_index = self.current_index + 1
            self:try_next_engine(restore, to_translate)
            return
        end

        -- Success! Handle caching and merge results
        restore()
        self.successful_engine = engine_name
        self:handle_success(engine_name, translation, highlights)
    end)
end

---@param engine_name string The engine that succeeded
---@param translation string[] Translation result
---@param highlights table[]|nil ANSI highlights
function FallbackEngineProxy:handle_success(engine_name, translation, highlights)
    -- If no caching or all from cache
    if not config.default.cache or not self.cache_hits then
        self.final_callback(false, translation, engine_name, highlights)
        return
    end

    -- Check line count matches for caching
    if #translation ~= #self.cache_misses then
        -- Line count mismatch - return translation directly but don't cache
        -- For terminal commands like 'wd' that return multiple lines for single input
        self.final_callback(false, translation, engine_name, highlights)
        return
    end

    -- Cache the successful translation with the FIRST engine's cache key
    -- This ensures consistency - cache is always associated with primary engine
    local first_engine_proxy = EngineProxy.new(self.engines[1])

    for i, line in ipairs(translation) do
        local cache_key = first_engine_proxy:cache_key(
            self.source,
            self.target,
            vim.trim(self.cache_misses[i])
        )
        cacher.set(cache_key, vim.trim(line))
    end

    -- Merge cached lines with new translation
    local merged_result = self:merge_with_cache(translation)
    self.final_callback(false, merged_result, engine_name, nil)
end

---@param translation string[] Translation for cache-miss lines
---@return string[]
function FallbackEngineProxy:merge_with_cache(translation)
    if not self.cache_hits then
        return translation
    end

    local result = vim.deepcopy(self.cache_hits)
    local trans_idx = 1

    for i, line in ipairs(result) do
        if line == self.placeholder then
            result[i] = translation[trans_idx]
            trans_idx = trans_idx + 1
        end
    end

    return result
end

return {
    EngineProxy = EngineProxy,
    FallbackEngineProxy = FallbackEngineProxy,
}
