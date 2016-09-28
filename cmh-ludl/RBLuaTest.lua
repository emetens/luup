module("RBLuaTest", package.seeall)
local version = "1.6"
local luadir = "/etc/cmh-ludl/"
--[[
	LuaTest is a tool for testing Vera scene Lua code. It runs on Vera as an http handler.

	Upload RBLuaTest.lua to Vera using APPS->Develop Apps->Luup files then restart Vera.

	Enter following three lines into APPS->Develop Apps->Test Luup code (LUA) and click GO:
			
			local rblt = require("RBLuaTest")
			rbLuaTest = rblt.rbLuaTest
			luup.register_handler("rbLuaTest","LuaTest")

	The three lines may also be added to Startup Lua for permanent availability.

	Usage:	<veraip>:3480/data_request?id=lr_LuaTest&file=<filenameorpath>
			<veraip>:3480/data_request?id=lr_LuaTest&run=<filenameorpath>
			
	Written by Rex Beckett - 12 March 2014.
]]
function rbLuaTestRun(luafile)
	local locdmp = ""
	local btdt = {}
	local function pretty(val,name,same)
		if not (same) then btdt = {} end
		local tmp = ""
		if name then tmp = tmp .. name .. "=" end
		if type(val) == "number" then
			tmp = tmp .. tostring(val)
		elseif type(val) == "nil" then
			tmp = tmp .. "nil"
		elseif type(val) == "string" then
			tmp = tmp .. string.format("%q", val)
		elseif type(val) == "boolean" then
			tmp = tmp .. (val and "true" or "false")
		elseif type(val) == "table" then
			if btdt[val] then tmp = tmp .. btdt[val]
			else
				btdt[val] = name
				tmp = tmp .. "{ "
				for k, v in pairs(val) do
					if type(k) == "number" then
						tmp =  tmp .. pretty(v,"["..k.."]",true) .. ", "
					else
						tmp =  tmp .. pretty(v, k, true) .. ", "
					end
				end
				tmp = string.gsub(tmp,", $"," ",1) .. "}"
			end
		else
			tmp = tmp .. type(val)
		end
		return tmp
	end
	function rbLuaErr(errobj)
	for level=2,10 do
			local fname = debug.getinfo(level)
			if fname == nil or ((fname.what ~= "Lua") and (fname.what ~= "main")) then break end
			locdmp = locdmp .. "[" .. (fname.name or "main") .. "]<br>"
			for locn=1, math.huge do
				local lname, lval = debug.getlocal(level,locn)
				if (lname == nil) or (string.sub(lname,1,1) == "(") then break end
				locdmp = locdmp .. pretty(lval,lname) .. "<br>"
			end
		end
		return string.gsub(errobj,"(.+):(%d+):","Line %2:")
	end
	local lualist = ""
	local code, ferr = io.open(luafile)
	if code ~= nil then
		local tab = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
		for l=1,math.huge do
			line = code:read()
			if line == nil then break end
			line = string.gsub(line,"\t",tab)
			lualist = lualist .. string.gsub(string.format("%4d   %s<br>",l,line)," ","&nbsp;")
		end
		code:close()
	end
	local luaerr = ""
	rbLuaCode, luaerr = loadfile(luafile)
	if rbLuaCode ~= nil then 
		_G.pretty = pretty
		local socket = require("socket")
		local tstart = socket.gettime()
		local res, msg = xpcall(rbLuaCode,rbLuaErr)
		local trun = string.format("%6.1f ms",(socket.gettime() - tstart) * 1000)
		_G.pretty = nil
		local retstr
		if res then
			retstr = "No errors<br>Runtime: " .. trun .. "<br>Code returned: "
		else
			retstr = "Runtime error: "
		end
		retstr = retstr .. tostring(msg)	
		luup.log("LuaTest " .. retstr)
		return retstr, lualist, locdmp
	else
		luup.log("LuaTest Code error: " .. luaerr)
		return "Code error: " .. string.gsub(luaerr,"(.+):(%d+):","Line %2:"), lualist, locdmp
	end
end

function rbLuaEditOpen(luafile)
	local strcode = ""
	local file, ferr = io.open(luafile)
	if file ~= nil then
		strcode = file:read("*a")
		file:close()
	end
	return (file ~= nil),strcode
end

function rbLuaEditSave(luafile,savecode)
	local file, ferr = io.open(luafile,"w+")
	if file ~= nil then
		strcode = file:write(savecode)
		file:close()
	end
	return (file ~= nil),ferr
end

function rbLuaTest (lul_request, lul_parameters, lul_outputformat)
	rbPrintOut = ""
	function rbPrint(...)
		local fields = { ... }
		local tab = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
		for i=1, #fields do
			rbPrintOut = rbPrintOut .. tostring(fields[i]) .. tab
		end
		rbPrintOut = rbPrintOut .. "<br>"
	end
	local function filePath(filename)
		if (filename == nil) or (string.sub(filename,1,1) == "/") then return filename
		else return luadir .. filename
		end
	end
	local html = [[
		<head>
		<title>LuaTest</title>
		</head>
		<body>
      <div style="font-family:arial;"> ]] ..
		"<b><u>LuaTest " .. version .. "</u></b><br><br>"
	local content_type = "text/html"
	local function doDevTitle(device)
		local devname = (luup.devices[tonumber(device)] or {description = 'Not found'}).description
		html = html..string.format("<br><b>Device: %d&nbsp;&nbsp;%s</b><br>",device, devname)
	end
	local listopt = lul_parameters["list"]
	local devopt = lul_parameters["device"]
	if (listopt == "variables") or (listopt == "values") then
		local err, resp
		if tonumber(devopt or "0") > 0 then
			devopt = tonumber(devopt)
			html = html ..	"<b><u>Device Status</u></b><br>"
			doDevTitle(devopt)
			err,resp = luup.inet.wget("127.0.0.1:3480/data_request?id=status&output_format=xml&DeviceNum="..devopt)
		else
			html = html ..	"<b><u>Device Variables</u></b><br>"
			err,resp = luup.inet.wget("127.0.0.1:3480/data_request?id=status&output_format=xml")
		end
		if err == 0 then
			local ptrs = string.find(resp,"<",1,true)
			local ptre = 0
			local ptrm = #resp
			while (ptrs ~= nil) do
				ptre = string.find(resp,">",ptrs,true)
				local line = string.sub(resp,ptrs,ptre)
				if string.find(line,"^</devices>",1,true)~=nil then break end
				local devno = string.match(line,"^<device id=\"(%d+)\"")
				if devno ~= nil then doDevTitle(devno)
				else
					local svc,var,val = string.match(line,"^<state id=.-service=(\".-\")%svariable=(\".-\")%svalue=(\".-\")")
					if (svc ~= nil) and (var ~= nil) then
						if val == nil then val = "" end
						local strend
						if (listopt == "values") then 
							strend = "&nbsp;&nbsp;&nbsp;value = "..val.."<br>"
						else strend = "<br>"
						end
						html = html .. svc..","..var..strend
					end
				end
				ptrs = string.find(resp,"<",ptre+1,true)
			end
			html = html .. "<br><b>End</b>"
		else
			html = html .. "<br>Unable to read Vera status!<br>"
		end		
		resp = nil
		return html, content_type
	end
	if (listopt == "actions") then
		html = html ..	"<b><u>Device Actions</u></b><br>"
		for devno=1, table.maxn(luup.devices) do
			if luup.devices[devno] ~= nil then
				local devname = luup.devices[devno].description
				local zwave = ((luup.devices[devno].id or "") ~= "") or (devno == 1)
				html = html..string.format("<br><b>Device: %d&nbsp;&nbsp;%s</b><br>",devno, devname)
				local err,resp = luup.inet.wget("127.0.0.1:3480/data_request?id=lu_invoke&DeviceNum="..devno)
				if err == 0 then
					local ptrs = string.find(resp,"<a href=",1,true)
					local ptre = 0
					while (ptrs ~= nil) do
						ptre = string.find(resp,"</a>",ptrs,true)
						local line = string.sub(resp,ptrs,ptre)
						local svc,act,imp = string.match(line,"serviceId=(.-)&action=(.-)\">(%p?)")
						if (act ~= nil) and (zwave or (imp ~= "")) then
							local action = "\""..(string.match(act,"(.-)&") or act).."\",{"
							local sep = ""
							for k in string.gmatch(act,"&(.-=)") do
								action = action .. sep .. k .. " "
								sep = ","
							end	
							action = action .. "}"
							html = html.."\""..svc.."\","..action.."<br>"
						end
						ptrs = string.find(resp,"<a href=",ptre+4,true)
					end
				end     
			end
		end
		html = html .. "<br><b>End</b>"
		resp = nil
		return html, content_type
	end
	local testfile = filePath(lul_parameters["run"])
	if testfile ~= nil then
		html = html ..	"<b>Lua file: </b>" .. testfile .. "<br><br><b><u>Results</u></b><br>"
		local oldprint = _G.print
		_G.print = rbPrint
		rbLuaRun = coroutine.create(rbLuaTestRun)
		local status, retn, code, locd = coroutine.resume(rbLuaRun,testfile)
		_G.print = oldprint
		html = html .. retn .. "<br>"
		if #(locd or "") > 0 then
			html = html .. "<br><b><u>Locals</u></b><br>" .. locd
		end
		if rbPrintOut == "" then rbPrintOut = "(none)<br>" end
		html = html .. "<br><b><u>Print output</u></b><br>" .. string.gsub(rbPrintOut,"\n","<br>")
		if code == "" then code = "(none)<br>" end
		html = html .. "<br><b><u>Code</u></b><br>" .. code .. "</div>"
		rbPrintOut = nil
		return html, content_type
	else
		local luafile = filePath(lul_parameters["file"] or "luatest.lua")
		local savefile = filePath(lul_parameters["save"])
		if savefile ~= nil then
			local newcode=string.gsub(lul_parameters["code"],"+"," ")
			newcode = string.gsub(newcode,"%%1F","+")
			luafile = savefile
			rbLuaPut = coroutine.create(rbLuaEditSave)
			local status,fileok,serr = coroutine.resume(rbLuaPut,luafile,newcode)
		end
		if string.match(luafile,".lzo$") then
			luafile = string.sub(luafile,1,-5)
			os.execute('pluto-lzo d '..luafile..'.lzo '..luafile) 
		end
		rbLuaGet = coroutine.create(rbLuaEditOpen)
		local status,fileok,code = coroutine.resume(rbLuaGet,luafile)
		local message = ""
		if not fileok then 
			message = "&nbsp;&nbsp;&nbsp;<u>File not found - will be created on <b>Save</b></u>"
		end
		html = html .. "<b>Lua file: </b>" .. luafile .. message .. "<br>" ..
			[[<br><b><u>Code</u></b>
			<form action="/data_request?" method="get" onsubmit="encPlus()">
			<input type="hidden" name="id" value="lr_LuaTest"> ]] ..
			'<input type="hidden" name="save" value="'..luafile..'">' ..
			'<textarea id="code" rows="20" cols="90" name="code" wrap="off" onchange="disTest()"' ..
			' style="font-size:15px;font-weight:bold;">' ..
			code .. '</textarea><br>' ..
			'<input id="bSave" type="submit" value="Save Code" >' ..
			'<input id="bTest" type="button" value="Test Code"' .. 
			' onclick="window.open(\'/data_request?id=lr_LuaTest&run='..luafile ..
			'\',\'_blank\');">' ..
			'<input id="bVars" type="button" value="Device Variable List"' .. 
			' onclick="window.open(\'/data_request?id=lr_LuaTest&list=variables\',\'_blank\');">' ..
			'<input id="bVals" type="button" value="Variable Values List"' .. 
			' onclick="window.open(\'/data_request?id=lr_LuaTest&list=values\',\'_blank\');">' ..
			'<input id="bActs" type="button" value="Device Action List"' .. 
			' onclick="window.open(\'/data_request?id=lr_LuaTest&list=actions\',\'_blank\');">' ..
			'<input id="bStatus" type="button" value="Show Device Status"' .. 
			' onclick="window.open(\'/data_request?id=lr_LuaTest&list=values&device=\'+devno.value,\'_blank\');">' ..
			'&nbsp;<span style="font-size:13px;">Device Number:</span>' ..
			'<input type="text" id="devno" value="" size="2">' ..
			[[</form>
			<script>
			function encPlus()
			{
			var x = document.getElementById("code").value;]] ..
			'var y = x.replace(/\\+/g,"%1F");' ..
			[[document.getElementById("code").value = y;
			}
			function disTest()
			{
				document.getElementById("bTest").disabled = true;
			}
			</script>]]
		return html, content_type
	end
end