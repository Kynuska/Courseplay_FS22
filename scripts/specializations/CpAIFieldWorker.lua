--- Cp field worker that drives along a course.
local modName = CpAIFieldWorker and CpAIFieldWorker.MOD_NAME -- for reload

---@class CpAIFieldWorker
CpAIFieldWorker = {}

CpAIFieldWorker.MOD_NAME = g_currentModName or modName
CpAIFieldWorker.NAME = ".cpAIFieldWorker"
CpAIFieldWorker.SPEC_NAME = CpAIFieldWorker.MOD_NAME .. CpAIFieldWorker.NAME
CpAIFieldWorker.KEY = "."..CpAIFieldWorker.MOD_NAME..CpAIFieldWorker.NAME

function CpAIFieldWorker.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAIFieldWorker.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")
    CpJobParameters.registerXmlSchema(schema, key..".cpJobStartAtLastWp")
end

function CpAIFieldWorker.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAIFieldWorker.register(typeManager,typeName,specializations)
	if CpAIFieldWorker.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAIFieldWorker.SPEC_NAME)
	end
end

function CpAIFieldWorker.registerEvents(vehicleType)
  --  SpecializationUtil.registerEvent(vehicleType, "onCpFinished")
	
end

function CpAIFieldWorker.registerEventListeners(vehicleType)
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", CpAIFieldWorker)

    SpecializationUtil.registerEventListener(vehicleType, "onCpEmpty", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onCpFull", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onCpFinished", CpAIFieldWorker)

    SpecializationUtil.registerEventListener(vehicleType, "onPostDetachImplement", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttachImplement", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onCpCourseChange', CpAIFieldWorker)
end

function CpAIFieldWorker.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpFieldWorkActive", CpAIFieldWorker.getIsCpFieldWorkActive)
    SpecializationUtil.registerFunction(vehicleType, "getCpFieldWorkProgress", CpAIFieldWorker.getCpFieldWorkProgress)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterWaitingForUnload",
            CpAIFieldWorker.getIsCpHarvesterWaitingForUnload)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterWaitingForUnloadInPocket",
            CpAIFieldWorker.getIsCpHarvesterWaitingForUnloadInPocket)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterWaitingForUnloadAfterPulledBack",
            CpAIFieldWorker.getIsCpHarvesterWaitingForUnloadAfterPulledBack)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterManeuvering", CpAIFieldWorker.getIsCpHarvesterManeuvering)
    SpecializationUtil.registerFunction(vehicleType, "holdCpHarvesterTemporarily", CpAIFieldWorker.holdCpHarvesterTemporarily)
    SpecializationUtil.registerFunction(vehicleType, "startCpFieldWorker", CpAIFieldWorker.startCpFieldWorker)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpFieldWork", CpAIFieldWorker.getCanStartCpFieldWork)

    SpecializationUtil.registerFunction(vehicleType, "startCpAtFirstWp", CpAIFieldWorker.startCpAtFirstWp)
    SpecializationUtil.registerFunction(vehicleType, "startCpAtLastWp", CpAIFieldWorker.startCpAtLastWp)
    SpecializationUtil.registerFunction(vehicleType, "getCpDriveStrategy", CpAIFieldWorker.getCpDriveStrategy)
    SpecializationUtil.registerFunction(vehicleType, "getCpStartingPointSetting", CpAIFieldWorker.getCpStartingPointSetting)
    SpecializationUtil.registerFunction(vehicleType, "getCpLaneOffsetSetting", CpAIFieldWorker.getCpLaneOffsetSetting)
end

function CpAIFieldWorker.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAIFieldWorker.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAIFieldWorker.getCpStartableJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartText', CpAIFieldWorker.getCpStartText)
end

------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAIFieldWorker:onLoad(savegame)
	--- Register the spec: spec_CpAIFieldWorker
    self.spec_cpAIFieldWorker = self["spec_" .. CpAIFieldWorker.SPEC_NAME]
    local spec = self.spec_cpAIFieldWorker
    --- This job is for starting the driving with a key bind or the hud.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK_CP)
    spec.cpJob:getCpJobParameters().startAt:setValue(CpJobParameters.START_AT_NEAREST_POINT)
    spec.cpJob:setVehicle(self)
    --- Theses jobs are used for external mod, for example AutoDrive.
    spec.cpJobStartAtFirstWp = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK_CP)
    spec.cpJobStartAtFirstWp:getCpJobParameters().startAt:setValue(CpJobParameters.START_AT_FIRST_POINT)
    spec.cpJobStartAtLastWp = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK_CP)
    spec.cpJobStartAtLastWp:getCpJobParameters().startAt:setValue(CpJobParameters.START_AT_LAST_POINT)
    
end

function CpAIFieldWorker:onLoadFinished(savegame)
    local spec = self.spec_cpAIFieldWorker
    if savegame ~= nil then 
        spec.cpJob:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIFieldWorker.KEY..".cpJob")
        spec.cpJobStartAtLastWp:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIFieldWorker.KEY..".cpJobStartAtLastWp")
    end
end

function CpAIFieldWorker:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAIFieldWorker
    spec.cpJob:getCpJobParameters():saveToXMLFile(xmlFile, baseKey.. ".cpJob")
    spec.cpJobStartAtLastWp:getCpJobParameters():saveToXMLFile(xmlFile, baseKey.. ".cpJobStartAtLastWp")
end

function CpAIFieldWorker:onCpCourseChange()
    local spec = self.spec_cpAIFieldWorker
    spec.cpJob:getCpJobParameters():validateSettings()
end

function CpAIFieldWorker:onPostDetachImplement()
    local spec = self.spec_cpAIFieldWorker
    spec.cpJob:getCpJobParameters():validateSettings()
end

function CpAIFieldWorker:onPostAttachImplement()
    local spec = self.spec_cpAIFieldWorker
    spec.cpJob:getCpJobParameters():validateSettings()
end


function CpAIFieldWorker:getCpStartingPointSetting()
    local spec = self.spec_cpAIFieldWorker
    return spec.cpJob:getCpJobParameters().startAt
end

function CpAIFieldWorker:getCpLaneOffsetSetting()
    local spec = self.spec_cpAIFieldWorker
    return spec.cpJob:getCpJobParameters().laneOffset
end

------------------------------------------------------------------------------------------------------------------------
--- Interface for other mods, like AutoDrive
------------------------------------------------------------------------------------------------------------------------

--- Is a cp fieldwork job active ?
function CpAIFieldWorker:getIsCpFieldWorkActive()
    return self:getIsAIActive() and self:getJob() and self:getJob():isa(CpAIJobFieldWork)
end

function CpAIFieldWorker:getCpFieldWorkProgress()
    local strategy = self:getCpDriveStrategy()
    if strategy then
        return strategy:getProgress()
    end
end

--- Gets the current field work drive strategy.
function CpAIFieldWorker:getCpDriveStrategy()
    return self.spec_cpAIFieldWorker.driveStrategy
end

--- To find out if a harvester is waiting to be unloaded, either because it is full or ended the fieldwork course
--- with some grain in the tank.
---@return boolean true when the harvester is waiting to be unloaded
function CpAIFieldWorker:getIsCpHarvesterWaitingForUnload()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isWaitingForUnload()
end

--- To find out if a harvester is waiting to be unloaded in a pocket. Harvesters may cut a pocket on the opposite
--- side of the pipe to make room for an unloader if:
--- * working on the first headland (so the unloader can get under the pipe while staying on the headland)
--- * cutting the first row in the middle of the field
---@return boolean true when the harvester is waiting to be unloaded in a pocket
function CpAIFieldWorker:getIsCpHarvesterWaitingForUnloadInPocket()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isWaitingInPocket()
end

--- To find out if a harvester is waiting to be unloaded after it pulled back to the side. This
--- is similar to a pocket but in this case there is no fruit on the opposite side of the pipe,
--- so the harvester just moves to the side and backwards without cutting a pocket.
---@return boolean
function CpAIFieldWorker:getIsCpHarvesterWaitingForUnloadAfterPulledBack()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isWaitingForUnloadAfterPulledBack()
end

--- Maneuvering means turning or working on a pocket or pulling back due to the pipe in fruit
---@return boolean true when the harvester is maneuvering so that an unloader should stay away.
function CpAIFieldWorker:getIsCpHarvesterManeuvering()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isManeuvering()
end

--- Hold the harvester (set its speed to 0) for a period of periodMs milliseconds.
--- Calling this again will restart the timer with the new value. Calling with 0 will end the temporary hold
--- immediately.
---@param periodMs number
function CpAIFieldWorker:holdCpHarvesterTemporarily(periodMs)
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:hold(periodMs)
end

--- Starts the cp driver at the first waypoint.
function CpAIFieldWorker:startCpAtFirstWp()
    local spec = self.spec_cpAIFieldWorker
    self:updateAIFieldWorkerImplementData()
    if self:hasCpCourse() and self:getCanStartCpFieldWork() then
        spec.cpJobStartAtFirstWp:applyCurrentState(self, g_currentMission, g_currentMission.player.farmId, true)
        --- Applies the lane offset set in the hud, so ad can start with the correct lane offset.
        spec.cpJobStartAtFirstWp:getCpJobParameters().laneOffset:setValue(self:getCpLaneOffsetSetting():getValue())
        spec.cpJobStartAtFirstWp:setValues()
        local success = spec.cpJobStartAtFirstWp:validate(false)
        if success then
            g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJobStartAtFirstWp, self:getOwnerFarmId()))
            return true
        end
    end
end

--- Starts the cp driver at the last driven waypoint.
function CpAIFieldWorker:startCpAtLastWp()
    local spec = self.spec_cpAIFieldWorker
    self:updateAIFieldWorkerImplementData()
    if self:hasCpCourse() and self:getCanStartCpFieldWork() then
        spec.cpJobStartAtLastWp:applyCurrentState(self, g_currentMission, g_currentMission.player.farmId, true)
        --- Applies the lane offset set in the hud, so ad can start with the correct lane offset.
        --- TODO: This should only be applied, if the driver was started for the first time by ad and not every time.
        spec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:setValue(self:getCpLaneOffsetSetting():getValue())
        spec.cpJobStartAtLastWp:setValues()
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "lane offset: %s", spec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:getString())
        local success = spec.cpJobStartAtLastWp:validate(false)
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "lane offset: %s", spec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:getString())
        if success then
            g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJobStartAtLastWp, self:getOwnerFarmId()))
            return true
        end
    end
end

--- Event listener called, when an implement is full.
function CpAIFieldWorker:onCpFull()
  
end

--- Event listener called, when an implement is empty.
function CpAIFieldWorker:onCpEmpty()
  
end

--- Event listener called, when the cp job is finished.
function CpAIFieldWorker:onCpFinished()
 
end

function CpAIFieldWorker:getCanStartCpFieldWork()
    -- built in helper can't handle it, but we may be able to ...
    if AIUtil.hasChildVehicleWithSpecialization(self, Baler) or
            AIUtil.hasImplementWithSpecialization(self, BaleWrapper) or
            AIUtil.hasImplementWithSpecialization(self, BaleLoader) or
            AIUtil.hasChildVehicleWithSpecialization(self, ForageWagon) or
            -- built in helper can't handle forage harvesters.
            AIUtil.hasImplementWithSpecialization(self, Cutter) or 
            AIUtil.hasChildVehicleWithSpecialization(self, VineCutter) or 
            AIUtil.hasChildVehicleWithSpecialization(self, VinePrepruner) or
            --- precision farming
            AIUtil.hasChildVehicleWithSpecialization(self, nil, "spec_soilSampler") or 
            --- FS22_aPalletAutoLoader from Achimobil: https://bitbucket.org/Achimobil79/ls22_palletautoloader/src/master/
            AIUtil.hasChildVehicleWithSpecialization(self, nil, "spec_aPalletAutoLoader") then
        return true
    end
    return self:getCanStartFieldWork()
end

--- Only allow the basic field work job to start, if a course is assigned.
function CpAIFieldWorker:getCanStartCp(superFunc)
    return self:hasCpCourse() and self:getCanStartCpFieldWork() or superFunc(self)
end

--- Gets the field work job for the hud or start action event.
function CpAIFieldWorker:getCpStartableJob(superFunc)
    local spec = self.spec_cpAIFieldWorker
	return self:getCanStartCpFieldWork() and self:hasCpCourse() and spec.cpJob or superFunc(self)
end

function CpAIFieldWorker:getCpStartText(superFunc)
    local spec = self.spec_cpAIFieldWorker
	return self:hasCpCourse() and spec.cpJob:getCpJobParameters().startAt:getString() or superFunc(self)
end


--- Custom version of AIFieldWorker:startFieldWorker()
function CpAIFieldWorker:startCpFieldWorker(jobParameters, startPosition)
    --- Calls the giants startFieldWorker function.
    self:startFieldWorker()
    if self.isServer then 
        --- Replaces drive strategies.
        CpAIFieldWorker.replaceAIFieldWorkerDriveStrategies(self, jobParameters, startPosition)

        --- Remembers the last lane offset setting value that was used.
        local spec = self.spec_cpAIFieldWorker
        spec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:setValue(jobParameters.laneOffset:getValue())
    end
end

-- We replace the Giants AIDriveStrategyStraight with our AIDriveStrategyFieldWorkCourse  to take care of
-- field work.
function CpAIFieldWorker:replaceAIFieldWorkerDriveStrategies(jobParameters, startPosition)
    CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'This is a CP field work job, start the CP AI driver, setting up drive strategies...')
    local spec = self.spec_aiFieldWorker
    if spec.driveStrategies ~= nil then
        for i = #spec.driveStrategies, 1, -1 do
            spec.driveStrategies[i]:delete()
            table.remove(spec.driveStrategies, i)
        end

        spec.driveStrategies = {}
    end
    local cpDriveStrategy
    --- Checks if there are any vine nodes close to the starting point.
    if startPosition and g_vineScanner:hasVineNodesCloseBy(startPosition.x, startPosition.z) then 
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Found a vine course, install CP vine fieldwork drive strategy for it')
        cpDriveStrategy = AIDriveStrategyVineFieldWorkCourse.new()
    elseif AIUtil.hasImplementWithSpecialization(self, Plow) then 
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Found a plow, install CP plow drive strategy for it')
        cpDriveStrategy = AIDriveStrategyPlowCourse.new()
    else
        local combine = AIUtil.getImplementOrVehicleWithSpecialization(self, Combine) 
        local pipe = combine and SpecializationUtil.hasSpecialization(Pipe, combine.specializations)
        if combine and pipe or -- Default harvesters with a pipe.
            SpecializationUtil.hasSpecialization(Combine, self.specializations) then -- Cotton harvester
            --- TODO: Make sure the combine strategy is only used for combines with a pipe and not the cotton harvesters!
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Found a combine with pipe, install CP combine drive strategy for it')
            cpDriveStrategy = AIDriveStrategyCombineCourse.new()
            self.spec_cpAIFieldWorker.combineDriveStrategy = cpDriveStrategy
        end
        if not cpDriveStrategy then 
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Installing default CP fieldwork drive strategy')
            cpDriveStrategy = AIDriveStrategyFieldWorkCourse.new()
        end
    end
    cpDriveStrategy:setAIVehicle(self, jobParameters)
    self.spec_cpAIFieldWorker.driveStrategy = cpDriveStrategy
    --- TODO: Correctly implement this strategy.
	local driveStrategyCollision = AIDriveStrategyCollision.new(cpDriveStrategy)
    driveStrategyCollision:setAIVehicle(self)
    table.insert(spec.driveStrategies, driveStrategyCollision)
    --- Only the last driving strategy can stop the helper, while it is running.
    table.insert(spec.driveStrategies, cpDriveStrategy)
end

--- Makes sure a callstack is printed, when an error appeared.
--- TODO: Might be a good idea to stop the cp helper.
local function onUpdate(vehicle, superFunc, ...)
    CpUtil.try(superFunc, vehicle, ...)
end

AIFieldWorker.onUpdate = Utils.overwrittenFunction(AIFieldWorker.onUpdate, onUpdate)