--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@class Log
local Log = {}

---@param text string
function Log.Write(text)
    print(text)

    if DebugPrint then
        DebugPrint { Text = text }
    end
end

return Log
