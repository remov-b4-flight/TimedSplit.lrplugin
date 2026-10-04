--[[-------------------------------------------------------
@file	PluginInit.lua
@brief	Initialize routines when TimedSplit.lrplugin Plugin is loaded. 
@author	remove-b4-flight
---------------------------------------------------------]]
local prefs = import 'LrPrefs'.prefsForPlugin()

if prefs.interval == nil then
	prefs.interval = 60
end

if prefs.savemetadata == nil then
	prefs.savemetadata = false
end
