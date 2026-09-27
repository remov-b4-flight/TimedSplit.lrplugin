--[[-------------------------------------------------------
@file Info.lua
@brief Information of TimedSplit.lrplugin provided for LrC.
@Author remov_b4_flight
---------------------------------------------------------]]

return {

	LrSdkVersion = 6.0,

	LrToolkitIdentifier = 'cx.ath.remov-b4-flight.timedsplit',
	LrPluginName = 'TimedSplit',
	LrPluginInfoUrl='https://github.com/remov-b4-flight/TimedSplit.lrplugin',
	LrLibraryMenuItems = {
		{title = 'Time-based Split',
		file = 'TimedSplit.lua',},
	},
	LrPluginInfoProvider = 'PluginInfo.lua',
	LrInitPlugin = 'PluginInit.lua',

	VERSION = { major = 0, minor = 0, revision = 1, build = 2, },

}
