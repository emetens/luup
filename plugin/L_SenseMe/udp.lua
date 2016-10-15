local SENSEME_UDP = {

  FAN_SPEED_INDEX = 5,

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
    else
      debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : using ip address ["..(self.localIpAddress or "NIL").."].",2)
    end

    local udp = socket.udp()
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : getting socket",2)
    udp:settimeout(2)
    udp:setsockname(self.localIpAddress, 31415)
    udp:setoption("broadcast",true)
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : setting options",2)
    udp:sendto("<" .. command .. ">", "255.255.255.255", 31415) -- TODO put as constants
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : sending",2)
--    udp:sendto("<Living Room Fan;FAN;SPD;GET;ACTUAL>", "255.255.255.255", 31415)
    local response, msg = udp:receive()
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : received",2)
    udp:close()
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand): Command: " .. command .. " Response: " .. (response or "NIL"))
    return response
  end,
}