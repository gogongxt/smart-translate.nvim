local config = require("smart-translate.config")
local http = require("http")

local baidu = {}

-- https://fanyi-api.baidu.com/doc/21
local source_mappings = {
    ["auto"] = "auto",
}

local target_mappings = {
    ["zh-CN"] = "zh",
    ["zh-TW"] = "cht",
    ["en"] = "en",
    ["ja"] = "jp",
    ["ko"] = "kor",
    ["fr"] = "fra",
    ["de"] = "de",
    ["ru"] = "ru",
}

---@param lang string
---@return string
function baidu.source_lang(lang)
    if source_mappings[lang] then
        return source_mappings[lang]
    end

    -- Check for special mappings
    if target_mappings[lang] then
        return target_mappings[lang]
    end

    return lang
end

---@param lang string
---@return string
function baidu.target_lang(lang)
    if target_mappings[lang] then
        return target_mappings[lang]
    end

    return lang
end

---@param source string
---@param target string
---@param original string[]
---@param callback fun(err: string|nil, translation: string[])
function baidu.translate(source, target, original, callback)
    local text = table.concat(original, "\n")

    local api_key = config.engine.baidu.api_key
    if api_key:sub(1, 1) == "$" then
        local env = os.getenv(api_key:sub(2))
        assert(env, "Baidu api_key: %s get failed")
        api_key = env
    end

    local app_id = config.engine.baidu.app_id
    if app_id:sub(1, 1) == "$" then
        local env = os.getenv(app_id:sub(2))
        assert(env, "Baidu app_id: %s get failed")
        app_id = env
    end

    local json_body = {
        appid = app_id,
        from = baidu.source_lang(source),
        to = baidu.target_lang(target),
        q = text,
    }

    local base_url = config.engine.baidu.base_url or "https://fanyi-api.baidu.com/ait/api/aiTextTranslate"

    http.post(base_url, {
        headers = {
            Authorization = "Bearer " .. api_key,
            ["Content-Type"] = "application/json",
        },
        json = json_body,
        allow_redirects = true,
        timeout = config.timeout,
    }):add_done_callback(function(future)
        local err = future:exception()
        if err then
            callback(tostring(err), {})
            return
        end

        local response = future:result()
        if response:ok() then
            local result = response:json()
            -- Baidu LLM API response structure
            -- trans_result is an array where each element has 'src' and 'dst'
            -- Each element corresponds to one line from the input
            if result and result.trans_result and #result.trans_result > 0 then
                local translations = {}
                for _, item in ipairs(result.trans_result) do
                    table.insert(translations, item.dst)
                end
                callback(nil, translations)
            else
                callback("Baidu translation failed: " .. vim.inspect(result), {})
            end
        else
            callback(("HTTP %d: %s"):format(response:status_code(), response:status_text()), {})
        end
    end)
end

return baidu
