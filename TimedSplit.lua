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
local UI_WAIT = 0.25
local FILE_WAIT = 0.5
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
	Logger:info('# of photos: ' .. countPhotos)
	local currentTime = 0
	local TargetArray = {}
	CurrentCatalog:withWriteAccessDo(Info.LrPluginName, function()
		Logger:info('Scanning: ' .. FolderName)
		-- loop photos and determine gaps in collection
		local PartArray = {}
		for i,PhotoIt in ipairs(currPhotos) do
			local photoTime = PhotoIt:getRawMetadata('dateTime')
--			Logger:info(i ..':' .. PhotoIt:getFormattedMetadata('fileName'))
			if (currentTime == 0) then
				currentTime = photoTime
			else
				local diff = math.abs(math.floor(photoTime - currentTime))
				if (diff >= prefs.interval * SECPERMIN) then
					table.insert(TargetArray, PartArray)
					Logger:info('Diff: ' .. diff .. '(s) Gap: ' .. #TargetArray .. ' curr. size: ' .. #PartArray)
					PartArray = {} -- Reset the part array for the next group
				end
				currentTime = photoTime
			end
			table.insert(PartArray, PhotoIt)
			ProgressBar:setPortionComplete(i,countPhotos)
		end -- end of for photo scan loop
		table.insert(TargetArray, PartArray) -- Add the last group to TargetArray
		Logger:info('Gap: ' .. #TargetArray .. ' curr. size: ' .. #PartArray)
		-- If there are more than one group, proceed to split into folders
		if (#TargetArray > 1) then
			ProgressBar:setCaption(LOC '$$$/timedsplit/splitting=Splitting into ' .. #TargetArray .. 'folders.')
			local SourcePath = SourceFolder:getPath()
			local ParentFolder = SourceFolder:getParent()
			Logger:info('Source folder: ' .. SourcePath)
			for i = 2, #TargetArray do -- Target loops
				local TargetFolderName = FolderName .. '.' .. i
				local TargetFolderPath = ParentFolder:getPath() .. TargetFolderName
				Logger:info(i .. ' Create dest. folder: ' .. TargetFolderPath .. ' count:' .. #TargetArray[i])
				if (LrFileUtils.exists(TargetFolderPath) == false) then
					LrFileUtils.createDirectory(TargetFolderPath)
				end
				for j,PhotoIt in ipairs(TargetArray[i]) do -- Photo loops
					ProgressBar:setPortionComplete(j, #TargetArray[i])
					local isVirtualCopy = PhotoIt:getRawMetadata ('isVirtualCopy')
			    	local fileFormat = PhotoIt:getRawMetadata ('fileFormat')
					if (isVirtualCopy == false ) then
						local TargetPath = TargetFolderPath .. PATHDELM .. PhotoIt:getFormattedMetadata('fileName')
						local SourcePath = PhotoIt:getRawMetadata('path')
						local SourceFileName = PhotoIt:getFormattedMetadata('fileName')
						CurrentCatalog:setSelectedPhotos(PhotoIt, {})
						LrTasks.sleep(UI_WAIT) -- just workaround
						-- does not save metadata for RAW,VIDEO files
						if (fileFormat == 'JPG') then
							Logger:info('saveMetadata(): ' .. SourceFileName)
							local beforeAttrib = LrFileUtils.fileAttributes(SourcePath)
							if (beforeAttrib == nil) then
								beforeAttrib = {fileModificationDate = LrDate.currentTime()}
								Logger:error('fileAttributes() error: ' .. SourcePath)
							end
							for l = 0, 10 do
								local status, err = LrTasks.pcall(PhotoIt.saveMetadata, PhotoIt)
								if status then
									break
								else
									Logger:error('saveMetadata() error: ' .. err)
									LrTasks.sleep(FILE_WAIT)
								end
							end
							for k = 1, 10 do
								LrTasks.sleep(FILE_WAIT)
								local afterAttrib = LrFileUtils.fileAttributes(SourcePath)
								if (afterAttrib == nil) then
									afterAttrib = beforeAttrib;
								end
								if (beforeAttrib.fileModificationDate < afterAttrib.fileModificationDate) then
									break
								end
							end
						end
						Logger:info(j .. ' Remove from catalog: ' .. SourceFileName)
						LrSelection.removeFromCatalog(PhotoIt)
						LrTasks.sleep(UI_WAIT) -- just workaround
						Logger:info('Move: ' .. SourceFileName .. ' => ' .. TargetPath)
						LrFileUtils.move(SourcePath, TargetPath)
						Logger:info('Add to catalog: ' .. SourceFileName)
						CurrentCatalog:addPhoto(TargetPath)
						Logger:info('Done')
					end
				end
			end -- end of for Target loop
		else
			Logger:info('Not needed.')
		end
 	end ,
		-- a block called by write access can't get
		{ timeout = TIMEOUT, asynchronous = true }
	) -- end of withWriteAccessDo function()
	ProgressBar:done()

end ) -- end of startAsyncTask function()
return
