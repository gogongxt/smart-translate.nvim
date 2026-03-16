local config = require("smart-translate.config")

local proxy = {}

-- Store original environment variables
local original_env = {}

--- Setup proxy environment variables before HTTP requests
--- @return function restore Function to restore original environment
function proxy.setup()
    local proxy_url = config.proxy

    if not proxy_url then
        return function() end
    end

    -- Support shell variable format like "$HTTP_PROXY"
    if proxy_url:sub(1, 1) == "$" then
        local env_var = proxy_url:sub(2)
        proxy_url = vim.env[env_var] or ""
    end

    if proxy_url == "" then
        return function() end
    end

    -- Save original values
    original_env = {
        http_proxy = vim.env.http_proxy,
        https_proxy = vim.env.https_proxy,
        all_proxy = vim.env.all_proxy,
        HTTP_PROXY = vim.env.HTTP_PROXY,
        HTTPS_PROXY = vim.env.HTTPS_PROXY,
        ALL_PROXY = vim.env.ALL_PROXY,
    }

    -- Set proxy environment variables
    vim.env.http_proxy = proxy_url
    vim.env.https_proxy = proxy_url
    vim.env.all_proxy = proxy_url
    vim.env.HTTP_PROXY = proxy_url
    vim.env.HTTPS_PROXY = proxy_url
    vim.env.ALL_PROXY = proxy_url

    -- Return restore function
    return function()
        vim.env.http_proxy = original_env.http_proxy
        vim.env.https_proxy = original_env.https_proxy
        vim.env.all_proxy = original_env.all_proxy
        vim.env.HTTP_PROXY = original_env.HTTP_PROXY
        vim.env.HTTPS_PROXY = original_env.HTTPS_PROXY
        vim.env.ALL_PROXY = original_env.ALL_PROXY
    end
end

return proxy
