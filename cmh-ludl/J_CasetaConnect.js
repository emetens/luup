//***********************************************************************************//
// J_CasetaConnect.js : Caseta Connect Plugin Device selection and Summary functions //
//***********************************************************************************//

var CASETA_SID = "urn:micasaverde-com:serviceId:CasetaConnect1";

function showBridgeSummary(device) {

	// unique identifier for this plugin...
	var uuid = 'EE429894-EBD7-4712-97EF-D4D21E311C25';

	var device_summary_html = get_device_state(device, CASETA_SID, "DEVICE_SUMMARY", 0);

	var deviceObject = get_device_obj(device);
	var RemoteName = deviceObject.name;
	var html = '<H1>DEVICE SUMMARY not yet available</H1>';
	if ((typeof(device_summary_html) !== 'undefined') && (device_summary_html !== "") && (device_summary_html !== "<br>")) {
		html = device_summary_html;
	}

	set_panel_html(html);
}

function setVar(device,SID, varName,varValue) {
	try {
		// UI7
		api.setDeviceStateVariable(device, SID, varName, varValue, {'dynamic': true}); 
		api.setDeviceStateVariable(device, SID, varName, varValue, {'dynamic': false}); 
		alert("Changes saved.");
	}
	catch(err) {
		// UI5
		set_device_state(device, SID, varName, varValue, 1);
		set_device_state(device, SID, varName, varValue, 0);
	}
	return;
}

function selectBridge(device,mac,ip) {
//alert("dev: "+device+"    ip: "+ip+"    mac:"+mac);
//	setVar(device, CASETA_SID, "BRIDGE_IP", ip); 
//	setVar(device, CASETA_SID, "BRIDGE_MAC", mac); 
//	setVar(device, CASETA_SID, "MDNS_DEVICES", ""); 
//	setVar(device, CASETA_SID, "ARP_DEVICES", ""); 
	var setUrl1 = '/port_3480/data_request?id=variableset&DeviceNum='+device+'&serviceId='+CASETA_SID+'&Variable=BRIDGE_IP&Value='+ip;
	var setUrl2 = '/port_3480/data_request?id=variableset&DeviceNum='+device+'&serviceId='+CASETA_SID+'&Variable=BRIDGE_MAC&Value='+mac;
	var setUrl3 = '/port_3480/data_request?id=variableset&DeviceNum='+device+'&serviceId='+CASETA_SID+'&Variable=MDNS_DEVICES&Value=';
	var setUrl4 = '/port_3480/data_request?id=variableset&DeviceNum='+device+'&serviceId='+CASETA_SID+'&Variable=ARP_DEVICES&Value=';
//	var	addUrl = '/port_3480/data_request?id=action&DeviceNum='+device+'&serviceId='+CASETA_SID+'&action=selectBridge&selectedIP='+ip+'&selectedMAC='+mac;
	var	addUrl = '/port_3480/data_request?id=reload';
	jQuery.get( setUrl1);
	jQuery.get( setUrl2);
	jQuery.get( setUrl3);
	jQuery.get( setUrl4);
	jQuery.get( addUrl, function( data ) {
		var sData = (new XMLSerializer()).serializeToString(data);
		if (sData == "OK") {
			jQuery('#CasetaConnect_Status').show();
		}
		var $status = jQuery('#CasetaConnect_status');
		$status.html('');
		$status.html('Status: Device selected. Caseta plugin reinitializing...').css({
			color: '#FF0000',
			'font-weight': 'bold'
			}).show();
		setTimeout(function() {
			selectBridgeDevice(device);
		}, 5000);
	});
}

function selectBridgeDevice(device) {

	// unique identifier for this plugin...
	var uuid = 'EE429894-EBD7-4712-97EF-D4D21E311C25';

	var found_devices = false;
	var found_device_list = [];
	
	var selected_bridge = get_device_state(device, CASETA_SID, "BRIDGE_IP", 0);
	var selected_bridge_mac = get_device_state(device, CASETA_SID, "BRIDGE_MAC", 0);

	var mdns_devices = get_device_state(device, CASETA_SID, "MDNS_DEVICES", 0);
	var arp_devices = get_device_state(device, CASETA_SID, "ARP_DEVICES", 0);
	if ((typeof(mdns_devices) !== 'undefined') && (mdns_devices !== "")) {
		found_device_list = mdns_devices.split(";");
		found_devices = true
	}
	else if ((typeof(arp_devices) !== 'undefined') && (arp_devices !== "")) {
		found_device_list = arp_devices.split(";");
		found_devices = true;
	} else {
		found_devices = false;
	}
	
	var deviceObject = get_device_obj(device);
	var RemoteName = deviceObject.name;

	var html = '';
	if ((typeof(selected_bridge) !== 'undefined') && (selected_bridge !== "") && (selected_bridge !== "<br>")) {
		html = '<H1>SELECTED BRIDGE: '+selected_bridge_mac+' ['+selected_bridge+']</H1>';
	} else {
		if (found_devices === true) {
			if (found_device_list[0] == "0.0.0.0,00:00:00:00:00:00,FINDALL") {
				html += '<H2>Available Devices on network:</H2>';
			} else {
				html += '<H2>Available Smart Bridge Devices:</H2>';
			}
			for (var i = 0; i < found_device_list.length; i++)
			{
				if (found_device_list[i] != "0.0.0.0,00:00:00:00:00:00,FINDALL") {
					var params = found_device_list[i].split(",");
					html += '<p><b>'+params[2]+'</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'+params[1]+'&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'+params[0]+'&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;';
					html += '<input type="button" value="Select" onclick="selectBridge('+device+',\''+params[1]+'\',\''+params[0]+'\');return false;"></input"></p>';
				}
			}
		} else {
			html = '<H1>NO BRIDGE DEVICES FOUND</H1>';
		}
	}

	html += '<span id="CasetaConnect_status" style="display: none; padding-left: 15px;"></span></p>';

	set_panel_html(html);
}
