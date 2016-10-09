local function debug(text, level, forced)
  if (forced == nil) then forced = false end
  if true then -- TODO remove this and use condition on line 2
--  if (PLUGIN.DEBUG_MODE or (forced == true)) then
    if (#text < 7000) then
      if (level == nil) then
        luup.log((text or "NIL"))
      else
        luup.log((text or "NIL"), level)
      end
    else
      -- split the output into multiple debug lines
      local prefix_string = ""
      local _, debug_prefix, _ = text:find("): ")
      if (debug_prefix) then
        prefix_string = text:sub(1, debug_prefix)
        text = text:sub(debug_prefix + 1)
      end
      while (#text > 0) do
        local debug_text = text:sub(1, 7000)
        text = text:sub(7001)
        if (level == nil) then
          luup.log((prefix_string .. (debug_text or "NIL")))
        else
          luup.log((prefix_string .. (debug_text or "NIL")), level)
        end
      end
    end
  end
end
