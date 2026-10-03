--[[-------------------------------------------------------
@file	TimedSplit.lua
@brief	this is main part of TimedSplit.lrplugin
@author	remov-b4-flight
---------------------------------------------------------]]

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrProgress= import 'LrProgressScope'
local LrFileUtils = import 'LrFileUtils'
local LrSelection = import 'LrSelection'
local LrDate = import 'LrDate'
local prefs = import 'LrPrefs'.prefsForPlugin()
local Info = require 'Info'

local LrLogger = import 'LrLogger'
local Logger = LrLogger(Info.LrPluginName)
Logger:enable('logfile')

local CurrentCatalog = LrApplication:activeCatalog()
local CurrentSelectionArray = CurrentCatalog:getActiveSources()
local TIMEOUT = 0.25
local SECPERMIN = 60
local UI_WAIT = 0.33 -- Reducing will cause issue with saveMetadata() and removeFromCatalog()
local FILE_WAIT = 0.5
local RETRYLIMIT = 10
-- Define path delimiter
if WIN_ENV then
	PATHDELM = '¥'
else
	PATHDELM = '/'
end

if (#CurrentSelectionArray > 1) then
	return
end
-- get 1st value of array
local currSelection = CurrentSelectionArray[1]

if (currSelection == nil) then 
	return
-- Check selected collection is not kAllPhotos,k** .. etc.
elseif (type(currSelection) == "string") then
	return
elseif (currSelection.type() ~= 'LrFolder') then
	return
end
local SourceFolder = currSelection
-- Main part of this plugin.
LrTasks.startAsyncTask( function ()
	local FolderName = SourceFolder:getName()
	local ProgressBar = LrProgress({title = LOC '$$$/timedsplit/splitting=Splitting Folder: ' .. FolderName})
	local currPhotos = SourceFolder:getPhotos(false)

	local countPhotos = #currPhotos
	Logger:info('*** Plugin started scanning: "' .. FolderName .. '" # of Photos: ' .. countPhotos .. ' ***')
	local currentTime = 0
	local TargetArray = {}
	CurrentCatalog:withWriteAccessDo(Info.LrPluginName, function()
		-- loop photos and determine gaps in collection
		local PartArray = {}
		for i,PhotoIt in ipairs(currPhotos) do
			local photoTime = PhotoIt:getRawMetadata('dateTime')
			if (currentTime == 0) then
				currentTime = photoTime
			else
				local diff = math.abs(math.floor(photoTime - currentTime))
				if (diff >= prefs.interval * SECPERMIN) then
					table.insert(TargetArray, PartArray)
					Logger:info('Gap: ' .. #TargetArray .. ' diff: ' .. diff .. '(s)'  .. ' size: ' .. #PartArray)
					PartArray = {} -- Reset the part array for the next gaps
				end
				currentTime = photoTime
			end
			table.insert(PartArray, PhotoIt)
		end -- end of for photo scan loop
		table.insert(TargetArray, PartArray) -- Add the last gap to TargetArray
		Logger:info('Gap: ' .. #TargetArray .. ' "LAST" size: ' .. #PartArray)
		-- If there are more than one gap, proceed to split into folders
		if (#TargetArray > 1) then
			ProgressBar:setCaption(LOC '$$$/timedsplit/splitting=Splitting into ' .. #TargetArray .. 'folders.')
			local ParentFolder = SourceFolder:getParent()
			local cnt = #TargetArray[1] -- 1st gap does not need to be moved, so start from the 2nd gap
			for i = 2, #TargetArray do -- Target loops start from 2nd gap
				local TargetFolderName = FolderName .. '.' .. i
				local TargetFolderPath = ParentFolder:getPath() .. TargetFolderName
				Logger:info('Gap: '.. i .. ' Create dest. folder: ' .. TargetFolderPath .. ' count:' .. #TargetArray[i])
				if (LrFileUtils.exists(TargetFolderPath) == false) then
					LrFileUtils.createDirectory(TargetFolderPath)
				end
				for j, PhotoIt in ipairs(TargetArray[i]) do -- Photo loops
					ProgressBar:setPortionComplete(cnt, countPhotos)
					local isVirtualCopy = PhotoIt:getRawMetadata ('isVirtualCopy')
			    	local fileFormat = PhotoIt:getRawMetadata ('fileFormat')
					if (isVirtualCopy == false ) then
						local SourceFileName = PhotoIt:getFormattedMetadata('fileName')
						local TargetPath = TargetFolderPath .. PATHDELM .. SourceFileName
						local SourcePath = PhotoIt:getRawMetadata('path')
						CurrentCatalog:setSelectedPhotos(PhotoIt, {})
						LrTasks.sleep(UI_WAIT) -- just workaround
						-- save Metadata for JPEG, not for RAW,VIDEO files
						if (fileFormat == 'JPG') then
							local beforeAttrib = LrFileUtils.fileAttributes(SourcePath) or {fileModificationDate = LrDate.currentTime()}
							for l = 1, RETRYLIMIT do
								local status, err = LrTasks.pcall(PhotoIt.saveMetadata, PhotoIt)
								if status then
									break
								else
									Logger:error('saveMetadata() error: ' .. err)
									LrTasks.sleep(FILE_WAIT)
								end
							end
							for k = 1, RETRYLIMIT do
								LrTasks.sleep(FILE_WAIT)
								local afterAttrib = LrFileUtils.fileAttributes(SourcePath) or beforeAttrib
								if (beforeAttrib.fileModificationDate < afterAttrib.fileModificationDate) then
									Logger:info('saveMetadata() confirmed: ' .. k)
									break
								end
							end
						end
						Logger:info(j .. ' Remove from cat.: ' .. SourceFileName)
						LrSelection.removeFromCatalog(PhotoIt)
						LrTasks.sleep(UI_WAIT) -- just workaround
						Logger:info('Move to: ' .. TargetPath)
						LrFileUtils.move(SourcePath, TargetPath)
						Logger:info('Add to cat.: ' .. SourceFileName)
						CurrentCatalog:addPhoto(TargetPath)
						Logger:info('Done')
						cnt = cnt + 1
					end -- vitual copy
				end -- photos in gap loop
			end -- end of for Target loop
		else
			Logger:info('Not needed.')
		end
 	end ,
		-- a block called by write access can't get
		{ timeout = TIMEOUT, asynchronous = true }
	) -- end of withWriteAccessDo function()
	ProgressBar:done()
	Logger:info('*** Plugin finished ***')

end ) -- end of startAsyncTask function()
return
