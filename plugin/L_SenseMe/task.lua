local TASK = {
  ERROR = 2,
  ERROR_PERM = -2,
  SUCCESS = 4,
  BUSY = 1
}

local function task(text, mode)
  if (text == nil) then text = "" end
  if (mode == nil) then mode = TASK.BUSY end
  debug("(" .. PLUGIN.NAME .. "::task) " .. (text or ""))
  if (mode == TASK.ERROR_PERM) then
    g_taskHandle = luup.task(text, TASK.ERROR, PLUGIN.NAME, g_taskHandle)
  else
    g_taskHandle = luup.task(text, mode, PLUGIN.NAME, g_taskHandle)

    -- Clear the previous error, since they're all transient.
    if (mode ~= TASK.SUCCESS) then
      luup.call_delay("clearTask", 30, "", false)
    end
  end
end

function clearTask()
  task("Clearing...", TASK.SUCCESS)
  return true
end
