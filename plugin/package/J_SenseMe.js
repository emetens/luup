
var SENSEME_SID = "urn:micasaverde-com:serviceId:SenseMe1";

function showSummary(device) {

	// unique identifier for this plugin...
	var uuid = '1B66F5B0-F673-45D9-8F5D-46B30CFF73ED';

	var device_summary_html = get_device_state(device, SENSEME_SID, "DEVICE_SUMMARY", 0);

	var deviceObject = get_device_obj(device);
	var RemoteName = deviceObject.name;
	var html = '<H1>DEVICE SUMMARY not yet available</H1>';
	if ((typeof(device_summary_html) !== 'undefined') && (device_summary_html !== "") && (device_summary_html !== "<br>")) {
		html = device_summary_html;
	}

	set_panel_html(html);
}
