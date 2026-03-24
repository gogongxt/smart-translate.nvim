<h3 align="center">
smart-translate.nvim
</h3>

<h6 align="center">
<img src="https://github.com/user-attachments/assets/837721df-350b-456c-9af7-e3c21c1d9e72" alt="" width="100%">
</h6>

<h6 align="center">
Powerful Caching System Builds Intelligent Translators
</h6>

<h6 align="center" style="font-size:.8rem; font-weight:lighter;color:#E95793">
<p>`smart-translate.nvim` is a very fast and elegantly designed plugin that provides you with an experience like no other translation plugin</p>.
</h6>

## Features

> The following features build the powerful `smart-translate.nvim`.

- Intelligent caching system, no need for repeated API calls, fast and accurate we have it all!
- Multiple engine support (`google`, `bing`, `deepl`, `baidu`) or build your own translator, more will be added in the future.
- Rich export capabilities (floating window, split window, replace, clipboard)

## Install and Use

> [!IMPORTANT]
>
> - `curl`
> - [tree-sitter-http](https://github.com/rest-nvim/tree-sitter-http) is not mandatory, you will be missing some of the functionality, such as `--comment`.

To install using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "askfiy/smart-translate.nvim",
    cmd = { "Translate" },
    dependencies = {
        "askfiy/http.nvim" -- a wrapper implementation of the Python aiohttp library that uses CURL to send requests.
    },
    opts = {},
}
```

## Default Configuration

`smart-translate.nvim` uses `Google` translation by default. But you can change the default translation engine:

```lua
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
            -- Support SHELL variables, or fill in directly
            api_key = "$DEEPL_API_KEY",
            base_url = "https://api-free.deepl.com/v2/translate",
        },
        baidu = {
            -- Support SHELL variables, or fill in directly
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
    -- Custom translator
    translator = {
        engine = {},
        handle = {},
        terminal_commands = nil, -- Terminal command definitions
    }
}
```

## Plugin Commands

The default command for the plugin is `Translate`, which provides the following multi-seed options.

- `--source`: the source language of the translation, supports `auto`.
- `--target`: target language of translation
- `--engine`: engine of translation
- `--handle`: Translation handler

Some special sub-options.

- `--comment`: translates the content of the comment block
- `--cleanup`: Clears all caches.

Here are some examples.

```vim
-- Manual translation, using the default configuration for scheduling translators
:Translate hello world

-- Automatically selects the original based on the current Mode
:Translate

--Select the Comment Block under the current cursor for translation.
:Translate --comment

-- with option parameters
:Translate --source=auto --target=zh-CN --engine=google --handle=float --comment

-- Translation of words
:normal! m'viw<cr>:Translate --target=zh-CN --source=en --handle=float<cr>`'
```

## language supports

The language is unified using Google Translate style:

- [languages](https://cloud.google.com/translate/docs/languages)

## Hook functions

`smart-translate.nvim` provides 2 `hooks` functions.

- `before_translate`
- `after_translate`

They take one argument, `Opts` as follows.

```lua
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
```

The `after_translate` always happens after the cache has been built. So you don't have to worry about your changes affecting the cache, it actually only affects the handling of the `handle`.

## Custom translator(Advanced)

`smart-translate.nvim` Support custom translator.

> [!TIP]
>
> - If the lines length of the original text and translation are consistent, the result will be stored in the cache
> - This will greatly improve the speed of subsequent repeated translations

Examples are as follows:

```lua
require("smart-translate").setup({
    translator = {
        engine = {
            {
                name = "translate-shell",
                ---@param source string
                ---@param target string
                ---@param original string[]
                ---@param callback fun(err: string|nil, translation: string[])
                translate = function(source, target, original, callback)
                    -- 1. Optional: Do you need to convert the command line input language to the language supported by the translator?
                    source = "en"
                    target = "zh"
                    -- 2. Add your custom processing logic
                    vim.system(
                        {
                            "trans",
                            "-b",
                            ("%s:%s"):format(source, target),
                            table.concat(original, "\n"),
                        },
                        { text = true },
                        ---@param completed vim.SystemCompleted
                        vim.schedule_wrap(function(completed)
                            -- 3. Check for errors
                            if completed.code ~= 0 then
                                callback(("Exit code %d: %s"):format(completed.code, completed.stderr or "Unknown error"), {})
                                return
                            end
                            -- 4. Call callback for rendering processing, the translation needs to return string[]
                            callback(
                                nil,
                                vim.split(
                                    completed.stdout,
                                    "\n",
                                    { trimempty = false }
                                )
                            )
                        end)
                    )
                end,
            },
        },
        handle = {
            {
                name = "echo",
                ---@param translator SmartTranslate.Translator
                render = function(translator)
                    vim.print(translator.translation)

                    --[[
                        SmartTranslate.Translator is an object that contains a lot of useful information:

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
                        ---@field public original string[]                          -- Original text
                        ---@field public public translation string[]                -- Translated text
                        ---@field public use_cache_translation boolean              -- Whether cache was hit
                        ---@field public range table<string, integer>[]             -- Original text range
                    ]]
                end,
            },
        },
    },
})
```

If you need to send an `http` request, you can use the [askfiy/http.nvim](https://github.com/askfiy/http.nvim) plug-in or `vim.system`, refer to [Google](./lua/smart-translate/core/engine/google.lua) translation implementation.

## Multi-Source Fallback (Advanced)

`smart-translate.nvim` supports configuring multiple translation engines with automatic fallback. If the primary engine fails, the next engine in the list is automatically tried.

### Basic Fallback Configuration

```lua
require("smart-translate").setup({
    default = {
        cmds = {
            engine = "google",
            fallback_engines = { "bing", "deepl" }, -- Try bing if google fails, then deepl
        },
    },
})
```

### Terminal Command Engines

You can define custom translation engines that execute shell commands. This is useful for CLI tools like `wd` (WordReference), `trans` (Translate Shell), or any custom script.

```lua
require("smart-translate").setup({
    default = {
        cmds = {
            engine = "wd", -- Use terminal command as primary
            handle = "terminal", -- Use terminal handler to preserve ANSI colors
            fallback_engines = { "google" }, -- Fallback to google if wd fails
        },
    },
    translator = {
        terminal_commands = {
            {
                name = "wd",
                command = "wd {text}", -- {text} will be replaced with translation text
                timeout = 10, -- Optional: defaults to config.timeout
                -- Optional: custom function to check if translation succeeded
                success_check = function(stdout, stderr)
                    -- wd returns "无法查询到相关释义" when not found
                    if stdout:find("无法查询到相关释义") then
                        return false
                    end
                    return vim.trim(stdout) ~= ""
                end,
            },
            {
                name = "my-custom-translator",
                command = "/path/to/script.sh --translate {text}",
                timeout = 30,
                success_check = function(stdout, stderr)
                    -- Custom logic to determine success
                    return stdout:find("SUCCESS") ~= nil
                end,
            },
        },
    },
})
```

> [!WARNING]
>
> **Security Consideration**: Terminal commands are executed through `sh -c`, which means you should only use trusted commands from your configuration. Avoid using commands from untrusted sources, as they could potentially execute arbitrary shell commands. The `{text}` placeholder is properly escaped using `shellescape()`, but the command template itself should be trusted.

**Terminal Command Requirements:**

- Use `{text}` placeholder where translation text should be inserted (required)
- Exit code must be 0 on success
- stdout must contain non-empty, non-whitespace output
- Output is split by newlines (one translation per line)
- **Optional**: Provide `success_check` function for custom success detection

**Preserving ANSI Colors:**
When using terminal command engines, you can preserve ANSI color codes by setting `handle = "terminal"`. This displays the command output in a terminal buffer with full color support:

```lua
default = {
    cmds = {
        engine = "wd",
        handle = "terminal", -- Preserves colors from terminal commands
    },
},
```

The `terminal` handler will:

- Execute the command in a Neovim terminal buffer
- Preserve all ANSI colors and formatting
- Automatically fall back to `float` handler for non-terminal engines

**Custom Success Check:**
The `success_check` function receives:

- `stdout` (string): The standard output from the command
- `stderr` (string): The standard error from the command

It should return `true` if the translation succeeded, `false` otherwise. This is useful when:

- The command returns exit code 0 even on failure
- The command outputs error messages to stdout instead of stderr
- You need to check for specific strings in the output

### Failure Detection

An engine is considered failed when:

- Exit code != 0 (for terminal commands)
- stdout is empty or contains only whitespace
- HTTP request times out
- HTTP response status is not OK (4xx, 5xx)
- Callback receives an error parameter
- Custom `success_check` function returns `false`

### Cache Behavior with Fallback

When using fallback engines:

- Cache keys are always associated with the **primary engine** (first in list)
- If a fallback engine succeeds, the translation is cached under the primary engine's key
- This ensures consistent cache behavior regardless of which engine actually performed the translation
- Line count matching rules still apply (translations with different line counts won't be cached)

### Example: Robust Production Setup

```lua
require("smart-translate").setup({
    default = {
        cmds = {
            source = "auto",
            target = "zh-CN",
            engine = "wd", -- Fast local dictionary
            fallback_engines = { "google", "bing" }, -- Fallback to online services
        },
    },
    translator = {
        terminal_commands = {
            {
                name = "wd",
                command = "wd {text}",
                timeout = 5, -- Fast timeout for local tool
            },
        },
    },
})
```

## Similar

The design and style of `smart-translate.nvim` is very much inspired by `translate.nvim`. We would like to thank you.

- [uga-rosa/translate.nvim](https://github.com/uga-rosa/translate.nvim)

## License

This plugin is licensed under the MIT License. See the [LICENSE](https://github.com/askfiy/smart-translate.nvim/blob/master/LICENSE) file for details.

## Contributing

Contributions are welcome! If you encounter a bug or want to enhance this plugin, feel free to open an issue or create a pull request.
