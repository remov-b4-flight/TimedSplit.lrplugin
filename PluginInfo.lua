--[[-------------------------------------------------------
@file	PluginInfo.lua
@brief	Define plugin manager dialogs at TimedSplit.lrplugin
@author	remov-b4-flight
---------------------------------------------------------]]
local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'
local bind = LrView.bind -- a local shortcut for the binding function
local prefs = import 'LrPrefs'.prefsForPlugin()
local Info = require 'Info'

local PluginInfo = {}
local CurrentCatalog = LrApplication.activeCatalog()
local INTVALMIN = 20
local INTVALMAX = 120

function PluginInfo.startDialog( propertyTable )
	propertyTable.interval = prefs.interval
	propertyTable.savemetadata = prefs.savemetadata
end

function PluginInfo.endDialog( propertyTable )
	LrTasks.startAsyncTask( function ()
		prefs.interval = propertyTable.interval
		prefs.savemetadata = propertyTable.savemetadata
	end)
end

function PluginInfo.sectionsForTopOfDialog( viewFactory, propertyTable )
	return {
		{
			title = Info.LrPluginName,
			synopsis = LOC '$$$/timedsplit/description=If thare is gap between shoot, split into folders.',
			bind_to_object = propertyTable,
			viewFactory:row {
				viewFactory:static_text {title = LOC '$$$/timedsplit/interval=Interval (minutes)'},
				viewFactory:slider {value = bind 'interval', min = INTVALMIN, max = INTVALMAX, integral = true},
				viewFactory:edit_field {value = bind 'interval', width_in_digits = 3, min = INTVALMIN, max = INTVALMAX, integral = true},
				viewFactory:checkbox {value = bind 'savemetadata', title = LOC '$$$/timedsplit/savemetadata=Save metadata' },
			},
		},
	}
end

return PluginInfo
