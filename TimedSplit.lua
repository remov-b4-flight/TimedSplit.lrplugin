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
local prefs = import 'LrPrefs'.prefsForPlugin()
local Info = require 'Info'

local LrLogger = import 'LrLogger'
local Logger = LrLogger(Info.LrPluginName)
Logger:enable('logfile')

local CurrentCatalog = LrApplication:activeCatalog()
local CurrentSelectionArray = CurrentCatalog:getActiveSources()
local TIMEOUT = 0.25
local SECPERMIN = 60

-- Define path delimiter
if WIN_ENV then
	PATHDELM = '¥'
else
	PATHDELM = '/'
end

--[[----------------------------------------------------------------------------
public string path, string err
saveMetadata (LrPhoto photo)
Initiates a Metadata > Save Metadata To File for the photo and waits for up
to 10 seconds for it complete.  Ignores videos and virtual copies.
Returns in "path" the file to which the metadata was saved (a .xmp for
raws, nil for videos and virtual copies, the photo file itself otherwise).
If a photo can't be saved, returns an error message in "err".
Starting in LR 15, photo:saveMetadata() can return before saving to disk.
This might have occurred many years previously, not sure, but it didn't
occur in LR 14.
------------------------------------------------------------------------------]]

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
	local ProgressBar = LrProgress({title = LOC '$$$/timedsplit/scanning=Scanning Folder : ' .. FolderName})
	local currPhotos = SourceFolder:getPhotos(false)

	local countPhotos = #currPhotos
	local currentTime = 0
	local TargetArray = {}
	CurrentCatalog:withWriteAccessDo(Info.LrPluginName, function()
		Logger:info('Scan files in folder : ' .. FolderName)
		-- loops photos in collection
		local PartArray = {}
		for i,PhotoIt in ipairs(currPhotos) do
			-- It's omitted 'LrProgress:isCancelled()' check for speedup.
--			Logger:info('Scan photo : ' .. PhotoIt:getFormattedMetadata('fileName'))
			local photoTime = PhotoIt:getRawMetadata('dateTime')
			if (currentTime == 0) then
				currentTime = photoTime
			else
				local diff = math.floor(photoTime - currentTime)
				if (diff >= prefs.interval * SECPERMIN) then
					table.insert(TargetArray, PartArray)
					PartArray = {} -- Reset the part array for the next group
				end
				currentTime = photoTime
			end
			table.insert(PartArray, PhotoIt)
			ProgressBar:setPortionComplete(i,countPhotos)
		end -- end of for photos loop
		table.insert(TargetArray, PartArray) -- Add the last group to TargetArray
		Logger:info('Total groups to split : ' .. #TargetArray)
		if (#TargetArray > 1) then
			ProgressBar:setCaption(LOC '$$$/timedsplit/splitting=Splitting into ' .. #TargetArray .. ' folders.')
			local SourcePath = SourceFolder:getPath()
			local ParentFolder = SourceFolder:getParent()
			Logger:info('Source folder path : ' .. SourcePath)
			for i = 2, #TargetArray do -- Target loops
				local TargetFolderName = FolderName .. '.' .. i
				local TargetFolderPath = ParentFolder:getPath() .. TargetFolderName
				Logger:info('Create destination folder : ' .. TargetFolderPath)
				if (LrFileUtils.exists(TargetFolderPath) == false) then
					LrFileUtils.createDirectory(TargetFolderPath)
				end
				Logger:info('index : '.. i .. ' count : ' .. #TargetArray[i])
				for j,PhotoIt in ipairs(TargetArray[i]) do -- Photo loops
					ProgressBar:setPortionComplete(j, #TargetArray[i])
					local isVirtualCopy = PhotoIt:getRawMetadata ('isVirtualCopy')
			    	local fileFormat = PhotoIt:getRawMetadata ('fileFormat')
					if (isVirtualCopy == false ) then
						local TargetPath = TargetFolderPath .. PATHDELM .. PhotoIt:getFormattedMetadata('fileName')
						CurrentCatalog:setSelectedPhotos(PhotoIt, {})
						--does not save metadata for video files
						if (fileFormat == 'JPG') then
							Logger:info('Metadata saving : ' .. PhotoIt:getFormattedMetadata('fileName') )
							local beforeAttrib = LrFileUtils.fileAttributes(PhotoIt:getRawMetadata('path'))
							PhotoIt:saveMetadata()
							for k = 1, 10 do
								local afterAttrib = LrFileUtils.fileAttributes(PhotoIt:getRawMetadata('path'))
								if (beforeAttrib.fileModificationDate < afterAttrib.fileModificationDate) then
									break
								end
								LrTasks.sleep(0.5)
							end
						end
						LrSelection.removeFromCatalog(PhotoIt)
						Logger:info('Photo to move : ' .. PhotoIt:getRawMetadata('path') .. ' -> ' .. TargetPath)
						LrFileUtils.move(PhotoIt:getRawMetadata('path'), TargetPath)
						Logger:info('Add to catalog : ' .. TargetPath)
						CurrentCatalog:addPhoto(TargetPath)
					end
				end
			end -- end of for Target loop
		else
			Logger:info('No need to split.')
		end
 	end ,
		-- a block called by write access can't get
		{ timeout = TIMEOUT, asynchronous = true }
	) -- end of withWriteAccessDo function()
	ProgressBar:done()

end ) -- end of startAsyncTask function()
return
