local SENSEME_UDP = {
  localIpAddress = "",
  sendCommand = function(self,command)

    local socket = require "socket"
    if self.localIpAddress == "" then
      local udp = socket.udp()
      udp:settimeout(2)
      udp:setpeername("8.8.8.8", 31415) -- TODO put port, put google dns server in constant to get address
      self.localIpAddress = udp:getsockname()
      debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : local ip address initialized ["..(self.localIpAddress or "NIL").."].",2)
      udp:close()
    end

    local udp = socket.udp()
    udp:setsockname(self.localIpAddress, 31415)
    udp:setoption("broadcast",true)
    udp:sendto("<" .. command .. ">", "255.255.255.255", 31415) -- TODO put as constants
--    udp:sendto("<Living Room Fan;FAN;SPD;GET;ACTUAL>", "255.255.255.255", 31415)
    local response = udp:receive()
    udp:close()
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand): Command: " .. command .. " Response: " .. response)
    return response
  end,

  startPolling = function(self)
    luup.call_delay("poll", 5, PLUGIN.POLL_PERIOD)
  end,
}

poll = function(value)
  debug("("..PLUGIN.NAME.."::SENSEME_UDP::poll): Checking status")

  -- get status for all devices
  -- TODO iterate over all commands
  local response = SENSEME_UDP:sendCommand("Living Room Fan;FAN;SPD;GET;ACTUAL")

  -- schedule next call

      local period = tonumber(value)
      if (period > 0) then
         luup.call_delay("poll", period, value)
      end
      debug("("..PLUGIN.NAME.."::SENSEME_UDP::poll): Status command sent")
end
