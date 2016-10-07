local FILE_MANIFEST = {
  -- TODO compute the md5 of these files
  FILE_LIST = {
    ["D_SenseMe.json"] = "fcc7fd9ff9d52d4c494d91cccf74e905",
    ["D_SenseMe.xml"] = "87a99a8a521f7d685e2630e7537ad54f",
    ["D_SenseMeFan1.json"] = "e22047338d70f58519b601ee6fb90b6b",
    ["D_SenseMeFan1.xml"] = "1829ad3d42bb1178118ad63e7e609b7f",
    ["I_SenseMe.xml"] = "1e80efcd576d0e53ee067040bebea2e9",
    ["J_SenseMe.js"] = "e6c2128899f6d27e485bb3683c35f945",
    ["J_SenseMe.lua"] = "e6c2128899f6d27e485bb3683c35f945",
    ["L_SenseMe_socat.mipsel"] = "8a95f4e83737ccdff5fe3ad168c749a8",
    ["S_SenseMe.xml"] = "24b5881cc107811e6752c12c17ce2cba",
  },
  RemoveFile = function(self, fileName)
    local cmd = "rm -f /etc/cmh-ludl/" .. fileName .. ".lzo"
    local file = assert(io.popen(cmd, 'r'))
    local cOutput = file:read('*all')
    file:close()
    return cOutput:gsub("\r", ""):gsub("\n", "")
  end,
  CalculateMD5 = function(self, fileName)
    local cmd = "md5sum /etc/cmh-ludl/" .. fileName .. ".lzo|cut -d' ' -f 1"
    local file = assert(io.popen(cmd, 'r'))
    local cOutput = file:read('*all')
    file:close()
    return cOutput:gsub("\r", ""):gsub("\n", "")
  end,
  ValidateDevices = function(self)
    -- additional file test when running under openluup - notify user if device files are missing
    if (PLUGIN.OPENLUUP == false) then
      -- no need to test the device files on a real Vera
      return true, "NONE"
    end
    local isValid = true
    local uList = ""
    for idx, fName in pairs(VERA.DEVFILES) do
      if (UTILITIES:file_exists("/etc/cmh-ludl/" .. fName) == false) then
        -- files does not exist in /etc/cmh-ludl - see if it was downloaded by the openluup_getfiles utility
        if (UTILITIES:file_exists("/etc/cmh-ludl/files/" .. fName) == false) then
          isValid = false
          uList = uList .. fName .. ","
        else
          os.execute("cp /etc/cmh-ludl/files/" .. fName .. " /etc/cmh-ludl/.")
        end
      end
    end
    if (isValid == true) then uList = "NONE," end
    local iFiles = (uList:sub(1, #uList - 1) or "")
    PLUGIN.missing_device_files_list = iFiles
    debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::ValidateDevices): Running under OpenLuup - Missing Device Files [" .. (iFiles or "NONE") .. "].", 2)
  end,
  Validate = function(self)
    if (PLUGIN.OPENLUUP == true) then
      PLUGIN.FILES_VALIDATED = false
      PLUGIN.mismatched_files_list = "FILE VALIDATION NOT SUPPORTED"
      debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::Validate): Running under openluup. File Validation not supported.", 1)
      return
    end
    local isValid = true
    local fManifest = ""
    local uList = ""
    for fName, eMD5 in pairs(self.FILE_LIST) do
      if (eMD5 == "OBSOLETE") then
        self:RemoveFile(fName)
      else
        local fMD5 = self:CalculateMD5(fName)
        if (eMD5:sub(1, 1) == "M") then
          -- file is mutable - will be the generic file or the UI5 or UI7 specific version
          eMD5 = eMD5:sub(2, #eMD5)
          local nameUI = fName:gsub(".json", "_" .. PLUGIN.MIOS_VERSION .. ".json")
          local md5UI = self.FILE_LIST[nameUI]
          if ((eMD5 ~= fMD5) and (md5UI ~= fMD5)) then
            isValid = false
            uList = uList .. fName .. ","
            fManifest = fManifest .. "\t[\"" .. fName .. "\"] = \"" .. fMD5 .. "\",\n"
          end
        else
          if (eMD5 ~= fMD5) then
            isValid = false
            uList = uList .. fName .. ","
            fManifest = fManifest .. "\t[\"" .. fName .. "\"] = \"" .. fMD5 .. "\",\n"
          end
        end
      end
    end
    if (((fManifest ~= "") and (#fManifest ~= 1)) or (isValid == false)) then
      debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::Validate) Manifest [\n" .. (fManifest:sub(1, #fManifest - 1) or "NIL") .. "\n].")
    end
    if (isValid == true) then uList = "NONE," end
    local iFiles = (uList:sub(1, #uList - 1) or "")
    luup.variable_set(VERA.SID["SENSEME"], "MISMATCHED_FILES", (iFiles or "NONE"), lug_device)
    PLUGIN.FILES_VALIDATED = isValid
    PLUGIN.mismatched_files_list = iFiles
    debug("(" .. PLUGIN.NAME .. "::FILE_MANIFEST::Validate): Plugin Files Validated [" .. (PLUGIN.FILES_VALIDATED and "TRUE" or "FALSE") .. "] invalid files [" .. (iFiles or "NONE") .. "].", 2)
  end
}
