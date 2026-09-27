--[[-------------------------------------------------------
@file	TimedSplit.lua
@brief	this is main part of TimedSplit.lrplugin
@author	remov-b4-flight
---------------------------------------------------------]]

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrProgress= import 'LrProgressScope'
local LrFileUtils = import 'LrFileUtils'
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
local function saveMetadata (photo)
    local fileFormat = photo:getRawMetadata ("fileFormat")
    local isVirtualCopy = photo:getRawMetadata ("isVirtualCopy")
    if fileFormat == "VIDEO" or isVirtualCopy then return nil, nil end
    local function returnErr (err)
        local msg = Util.logError ("Couldn't save metadata to file: %s\n%s",photo.path, err)
        return photo.path, msg
        end
        --[[ Sometimes photo:saveMetadata() fails with an obscure
        error, perhaps because of a race inside LR. Retrying 
        for up to 10 seconds seems to reduce the occurrences. ]]
    local startTime = currentTime()
    for i = 1, math.huge do
        local success, err = LrTasks.pcall (photo.saveMetadata, photo)
        if success then
            if i > 1 then
                Debug.logn ("Util.saveMetadata:", i,
                    "tries needed for successful save", photo.path)
                end
            break
            end
        if i >= 10 and not success then return returnErr (err) end
        LrTasks.sleep (1)
        end
        --[[ Starting in LR 15, photo:saveMetadata () is asynchronous.
        Wait until we observe the file's modification time changes. ]]
    local paths = fileFormat ~= "RAW" and {photo.path} or 
        {removeExtension (photo.path) .. ".xmp", 
         photo.path .. "_xmp"}
    local delay, waitTime, maxWaitTime = 0.01, 0, 5
    while true do
        if currentTime () > startTime + maxWaitTime then 
            return returnErr ("Timed out")
            end
        for _, path in ipairs (paths) do 
            local modTime = fileAttributes (path).fileModificationDate or 0
            if modTime >= startTime then 
                if waitTime > 0 then
                    Util.logError ("Util.saveMetadata wait: %g secs %s", 
                        waitTime, path)
                    end
                return path, nil 
                end
            end
        LrTasks.sleep (delay)
        waitTime = waitTime + delay
        delay = math.min (delay * 1.5, 0.2)
        end
    return path, nil
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
			Logger:info('Scan photo : ' .. PhotoIt:getFormattedMetadata('fileName'))
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
		if (#TargetArray > 1) then
			ProgressBar:setCaption(LOC '$$$/timedsplit/splitting=Splitting into ' .. #TargetArray .. ' folders.')
			ProgressBar:setPortionComplete(1, #TargetArray)
			local SourcePath = SourceFolder:getPath()
			local ParentFolder = SourceFolder:getParent()
			Logger:info('Source folder path : ' .. SourcePath)
			-- Todo : check folder name is already exist. and seek next folder name.
			for i = 2, #TargetArray do -- Target loops
				local TargetFolderName = FolderName .. '.' .. i
				local TargetFolderPath = ParentFolder:getPath() .. PATHDELM .. TargetFolderName
				Logger:info('Create new folder : ' .. TargetFolderPath)
				LrFileUtils.createDirectory(TargetFolderPath)
				for j,PhotoIt in ipairs(TargetArray[i]) do -- Photo loops
					local TargetPath = TargetFolderPath .. PATHDELM .. PhotoIt:getFormattedMetadata('fileName')
					Logger:info('Photo to move : ' .. PhotoIt:getRawMetadata('path') .. ' -> ' .. TargetPath)
					CurrentCatalog:setSelectedPhotos(PhotoIt)
	--				LrSelection.removeFromCatalog(PhotoIt)
	--				LrFileUtils.move(PhotoIt:getRawMetadata('path'), TargetPath)
	--				CurrentCatalog:addPhoto(TargetFolderPath)
				end
				ProgressBar:setPortionComplete(i, #TargetArray)
			end -- end of for Target loop
		else
			ProgressBar:done()
			Logger:info('No need to split.')
		end
 	end ,
		-- a block called by write access can't get
		{ timeout = TIMEOUT, asynchronous = true }
	) -- end of withWriteAccessDo function()

end ) -- end of startAsyncTask function()
return
