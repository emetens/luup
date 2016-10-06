SENSEME_UDP = {
  sendCommand = function(self,command)
    debug("("..PLUGIN.NAME.."::SENSEME_UDP::sendCommand) : sending command [\n"..(command or "NIL").."].",2)
-- return UTILITIES:shellExecute("(sleep 2;echo '"..command.."')|/etc/cmh-ludl/socat - EXEC:\"ssh "..PLUGIN.SSH_OPTIONS.." -i "..PLUGIN.SSH_KEYFILE.." leap@"..PLUGIN.BRIDGE_IP.."\",pty,setsid,ctty|grep -e 'Response'")
  end,
}
