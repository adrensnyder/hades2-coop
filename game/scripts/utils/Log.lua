--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopModConfig
local Config = ModRequire "../config.lua"

---@class Log
local Log = {}

---@param text string
function Log.Write(text)
    if not (Config and Config.Debug and Config.Debug.Enabled) then
        return
    end

    text = tostring(text)

    print(text)

    if DebugPrint then
        DebugPrint { Text = text }
    end
end

return Log
