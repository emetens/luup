SENSEME_UDP = {
  localIpAddress = "",
  sendCommand = function(self,command)
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : sending command [\n"..(command or "NIL").."].",2)

    local socket = require "socket"
    if self.localIpAddress == "" then
      local udp = socket.udp()
      udp:settimeout(2)
      udp:setpeername("8.8.8.8", 31415) -- TODO put port, put google dns server in constant to get address
      self.localIpAddress = udp:getsockname()
      debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : local ip address initialized [\n"..(self.localIpAddress or "NIL").."].",2)
      udp:close()
    end

    local udp = socket.udp()
    udp:setsockname(self.localIpAddress, 31415)
    udp:setoption("broadcast",true))
    udp:sendto("<" .. command .. ">", "255.255.255.255", 31415)) -- TODO put as constants
--    udp:sendto("<Living Room Fan;FAN;SPD;GET;ACTUAL>", "255.255.255.255", 31415))
    local response = udp:receive()
    udp:close()

    -- TO poll on a regular basis:
    luup.call_delay("getStatusLIP", 5, PLUGIN.pollPeriod)

    then in the function

    function getStatusLIP(value)
      debug("("..PLUGIN.NAME.."::getStatusLIP): Checking Status")
      local period = tonumber(value)
      if (period > 0) then
        luup.call_delay("getStatusLIP", period, value)
      end
      debug("("..PLUGIN.NAME.."::getStatusLIP): Status command sent")
    end


    return response
  end,
 }
