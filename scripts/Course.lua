--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS22)
Copyright (C) 2018-2022 Peter Va9ko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

---@class Course
Course = CpObject()

--- Course constructor
---@param waypoints Waypoint[] table of waypoints of the course
---@param temporary boolean optional, default false is this a temporary course?
---@param first number optional, index of first waypoint to use
---@param last number optional, index of last waypoint to use to construct of the course
function Course:init(vehicle, waypoints, temporary, first, last)
	-- add waypoints from current vehicle course
	---@type Waypoint[]
	self.waypoints = self:initWaypoints()
	local n = 0
	for i = first or 1, last or #waypoints do
		-- make sure we pass in the original vehicle.Waypoints index with n+first
		table.insert(self.waypoints, Waypoint(waypoints[i], n + (first or 1)))
		n = n + 1
	end
	-- offset to apply to every position
	self.offsetX, self.offsetZ = 0, 0
	self.temporaryOffsetX, self.temporaryOffsetZ = CpSlowChangingObject(0, 0), CpSlowChangingObject(0, 0)
	self.numberOfHeadlands = 0
	self.workWidth = 0
	self.name = ''
	self.editedByCourseEditor = false
	-- only for logging purposes
	self.vehicle = vehicle
	self.temporary = temporary or false
	self.currentWaypoint = 1
	self.length = 0
	self.workingLength = 0
	self.headlandLength = 0
	self.totalTurns = 0
	self:enrichWaypointData()
end

function Course:getDebugTable()
	return {
		{name = "numWp",value=self:getNumberOfWaypoints()},
		{name = "workWidth",value=self.workWidth},
		{name = "curWpIx",value=self:getCurrentWaypointIx()},
		{name = "length",value=self.length},
		{name = "numTurns",value=self.totalTurns},
		{name = "offsetX",value=self.offsetX},
		{name = "offsetZ",value=self.offsetZ},
		{name = "multiTools",value=self.multiTools},
		{name = "numHeadlands",value=self.numberOfHeadlands},
		{name = "totalTurns",value=self.totalTurns},
	}

end

function Course:isFieldworkCourse()
	return (self.workWidth and self.workWidth > 0) or (self.numberOfHeadlands and self.numberOfHeadlands > 0)
end

function Course:setName(name)
	self.name = name
end

function Course:setVehicle(vehicle)
	self.vehicle = vehicle
end

function Course:setFieldPolygon(polygon)
	self.fieldPolygon = polygon
end

-- The field polygon used to generate the course
function Course:getFieldPolygon()
	return self.fieldPolygon
end

function Course:getName()
	return self.name
end

function Course:setEditedByCourseEditor()
	self.editedByCourseEditor = true
end

function Course:wasEditedByCourseEditor()
	return self.editedByCourseEditor
end


function Course:getAllWaypoints()
	return self.waypoints
end

function Course:initWaypoints()
	return setmetatable({}, {
		-- add a function to clamp the index between 1 and #self.waypoints
		__index = function(tbl, key)
			local result = rawget(tbl, key)
			if not result and type(key) == "number" then
				result = rawget(tbl, math.min(math.max(1, key), #tbl))
			end
			return result
		end
	})
end

--- Current offset to apply. getWaypointPosition() will always return the position adjusted by the
-- offset. The x and z offset are in the waypoint's coordinate system, waypoints are directed towards
-- the next waypoint, so a z = 1 offset will move the waypoint 1m forward, x = 1 1 m to the right (when
-- looking in the drive direction)
--- IMPORTANT: the offset for multitool (laneOffset) must not be part of this as it is already part of the
--- course,
--- @see Course#calculateOffsetCourse
function Course:setOffset(x, z)
	self.offsetX, self.offsetZ = x, z
end

function Course:getOffset()
	return self.offsetX, self.offsetZ
end

--- Temporary offset to apply. This is to use an offset temporarily without overwriting the normal offset of the course
function Course:setTemporaryOffset(x, z, t)
	self.temporaryOffsetX:set(x, t)
	self.temporaryOffsetZ:set(z, t)
end

function Course:changeTemporaryOffsetX(dx, t)
	self.temporaryOffsetX:set(self.temporaryOffsetX:get() + dx, t)
end

function Course:setWorkWidth(w)
	self.workWidth = w
end

function Course:getWorkWidth()
	return self.workWidth
end

function Course:getNumberOfHeadlands()
	return self.numberOfHeadlands
end

--- get number of waypoints in course
function Course:getNumberOfWaypoints()
	return #self.waypoints
end

function Course:getWaypoint(ix)
	return self.waypoints[ix]
end

function Course:getMultiTools()
	return self.multiTools
end

--- Is this a temporary course? Can be used to differentiate between recorded and dynamically generated courses
-- The Course() object does not use this attribute for anything
function Course:isTemporary()
	return self.temporary
end

-- add missing angles and world directions from one waypoint to the other
-- PPC relies on waypoint angles, the world direction is needed to calculate offsets
function Course:enrichWaypointData(startIx)
	if #self.waypoints < 2 then return end
	if not startIx then
		-- initialize only if recalculating the whole course, otherwise keep (and update) the old values)
		self.length = 0
		self.workingLength = 0
		self.headlandLength = 0
		self.firstHeadlandWpIx = nil
		self.firstCenterWpIx = nil
	end
	for i = startIx or 1, #self.waypoints - 1 do
		self.waypoints[i].dToHere = self.length
		self.waypoints[i].dToHereOnHeadland = self.headlandLength
		local cx, _, cz = self:getWaypointPosition(i)
		local nx, _, nz = self:getWaypointPosition(i + 1)
		local dToNext = MathUtil.getPointPointDistance(cx, cz, nx, nz)
		self.waypoints[i].dToNext = dToNext
		self.length = self.length + dToNext
		if not self:isOnConnectingTrack(i) then
			-- working length is where we do actual fieldwork
			self.workingLength = self.workingLength + dToNext
		end
		if self:isOnHeadland(i) then
			self.headlandLength = self.headlandLength + dToNext
			self.firstHeadlandWpIx = self.firstHeadlandWpIx or i
		else
			-- TODO: this and firstHeadlandWpIx works only if there is one block on the field and
			-- no islands, as then we have more than one group of headlands. But these are only
			-- for the convoy mode anyway so it is ok if it does not work in all possible situations
			self.firstCenterWpIx = self.firstCenterWpIx or i
		end
		if self:isTurnStartAtIx(i) then self.totalTurns = self.totalTurns + 1 end
		if self:isTurnEndAtIx(i) then
			self.dFromLastTurn = 0
		elseif self.dFromLastTurn then
			self.dFromLastTurn = self.dFromLastTurn + dToNext
		end
		self.waypoints[i].turnsToHere = self.totalTurns
		-- TODO: looks like we may end up with the first two waypoint of a course being the same. This takes care
		-- of setting dx/dz to 0 (instead of NaN) but should investigate as it does not make sense
		local dx, dz = MathUtil.vector2Normalize(nx - cx, nz - cz)
		-- check for NaN
		if dx == dx and dz == dz then
			self.waypoints[i].dx, self.waypoints[i].dz = dx, dz
			self.waypoints[i].yRot = MathUtil.getYRotationFromDirection(dx, dz)
		else
			self.waypoints[i].dx, self.waypoints[i].dz = 0, 0
			self.waypoints[i].yRot = 0
		end
		self.waypoints[i].angle = math.deg(self.waypoints[i].yRot)
		self.waypoints[i].calculatedRadius = i == 1 and math.huge or self:calculateRadius(i)
		self.waypoints[i].curvature = i == 1 and 0 or 1 / self:calculateSignedRadius(i)
		if (self:isReverseAt(i) and not self:switchingToForwardAt(i)) or self:switchingToReverseAt(i) then
			-- X offset must be reversed at waypoints where we are driving in reverse
			self.waypoints[i].reverseOffset = true
		end
		if self.waypoints[i].lane and self.waypoints[i].lane < 0 then
			self.numberOfHeadlands = math.max(self.numberOfHeadlands, -self.waypoints[i].lane)
		end
	end
	-- make the last waypoint point to the same direction as the previous so we don't
	-- turn towards the first when ending the course. (the course generator points the last
	-- one to the first, should probably be changed there)
	self.waypoints[#self.waypoints].angle = self.waypoints[#self.waypoints - 1].angle
	self.waypoints[#self.waypoints].yRot = self.waypoints[#self.waypoints - 1].yRot
	self.waypoints[#self.waypoints].dx = self.waypoints[#self.waypoints - 1].dx
	self.waypoints[#self.waypoints].dz = self.waypoints[#self.waypoints - 1].dz
	self.waypoints[#self.waypoints].dToNext = 0
	self.waypoints[#self.waypoints].dToHere = self.length
	self.waypoints[#self.waypoints].dToHereOnHeadland = self:isOnHeadland(#self.waypoints - 1) and
		self.waypoints[#self.waypoints - 1].dToHereOnHeadland + self.waypoints[#self.waypoints - 1].dToNext or
		self.waypoints[#self.waypoints - 1].dToHereOnHeadland
	self.waypoints[#self.waypoints].turnsToHere = self.totalTurns
	self.waypoints[#self.waypoints].calculatedRadius = math.huge
	self.waypoints[#self.waypoints].curvature = 0
	self.waypoints[#self.waypoints].reverseOffset = self:isReverseAt(#self.waypoints)
	-- now add some metadata for the combines
	local dToNextTurn, lNextRow, nextRowStartIx = 0, 0, 0
	local dToNextDirectionChange, nextDirectionChangeIx = 0, 0
	local turnFound = false
	local directionChangeFound = false
	for i = #self.waypoints - 1, 1, -1 do
		if turnFound then
			dToNextTurn = dToNextTurn + self.waypoints[i].dToNext
			self.waypoints[i].dToNextTurn = dToNextTurn
			self.waypoints[i].lNextRow = lNextRow
			self.waypoints[i].nextRowStartIx = nextRowStartIx
		end
		if self:isTurnStartAtIx(i) then
			lNextRow = dToNextTurn
			nextRowStartIx = i + 1
			dToNextTurn = 0
			turnFound = true
		end
		if directionChangeFound then
			dToNextDirectionChange = dToNextDirectionChange + self.waypoints[i].dToNext
			self.waypoints[i].dToNextDirectionChange = dToNextDirectionChange
			self.waypoints[i].nextDirectionChangeIx = nextDirectionChangeIx
		end
		if self:switchingDirectionAt(i) then
			dToNextDirectionChange = 0
			nextDirectionChangeIx = i
			directionChangeFound = true
		end
	end
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle or g_currentMission.controlledVehicle,
			'Course with %d waypoints created/updated, %.1f meters, %d turns', #self.waypoints, self.length, self.totalTurns)
end

function Course:calculateSignedRadius(ix)
	local deltaAngle = getDeltaAngle(self.waypoints[ix].yRot, self.waypoints[ix - 1].yRot)
	return self:getDistanceToNextWaypoint(ix) / ( 2 * math.sin(deltaAngle / 2 ))
end

function Course:calculateRadius(ix)
	return math.abs(self:calculateSignedRadius(ix))
end

--- Is this the same course as otherCourse?
-- TODO: is there a hash we could use instead?
function Course:equals(other)
	if #self.waypoints ~= #other.waypoints then return false end
	-- for now just check the coordinates of the first waypoint
	if self.waypoints[1].x - other.waypoints[1].x > 0.01 then return false end
	if self.waypoints[1].z - other.waypoints[1].z > 0.01 then return false end
	-- same number of waypoints, first waypoint same coordinates, equals!
	return true
end

--- A super simple hash to identify and compare courses (see convoy)
function Course:getHash()
	local hash = ''
	for i = 1, math.min(20, #self.waypoints) do
		hash = hash .. string.format('%d%d', self.waypoints[i].x, self.waypoints[i].z)
	end
	return hash
end

function Course:setCurrentWaypointIx(ix)
	self.currentWaypoint = ix
end

function Course:getCurrentWaypointIx()
	return self.currentWaypoint
end

function Course:setLastPassedWaypointIx(ix)
	self.lastPassedWaypoint = ix
end

function Course:getLastPassedWaypointIx()
	return self.lastPassedWaypoint
end

function Course:isReverseAt(ix)
	return self.waypoints[math.min(math.max(1, ix), #self.waypoints)].rev
end

function Course:getLastReverseAt(ix)
	for i=ix,#self.waypoints do
		if not self.waypoints[i].rev then
			return i-1
		end
	end
end

function Course:isForwardOnly()
	for _, wp in ipairs(self.waypoints) do
		if wp.rev then
			return false
		end
	end
	return true
end

function Course:isTurnStartAtIx(ix)
	return self.waypoints[ix].turnStart
end

function Course:isTurnEndAtIx(ix)
	return self.waypoints[ix].turnEnd
end

function Course:skipOverTurnStart(ix)
	if self:isTurnStartAtIx(ix) then
		return ix + 1
	else
		return ix
	end
end

--- Is this waypoint on a connecting track, that is, a transfer path between
-- a headland and the up/down rows where there's no fieldwork to do.
function Course:isOnConnectingTrack(ix)
	return self.waypoints[ix].isConnectingTrack
end

function Course:switchingDirectionAt(ix)
	return self:switchingToForwardAt(ix) or self:switchingToReverseAt(ix)
end

function Course:getNextDirectionChangeFromIx(ix)
	for i = ix, #self.waypoints do
		if self:switchingDirectionAt(i) then
			return i
		end
	end
end

function Course:getNextWaitPointFromIx(ix)
	for i = ix, #self.waypoints do
		if self:isWaitAt(i) then
			return i
		end
	end
end

function Course:switchingToReverseAt(ix)
	return not self:isReverseAt(ix) and self:isReverseAt(ix + 1)
end

function Course:switchingToForwardAt(ix)
	return self:isReverseAt(ix) and not self:isReverseAt(ix + 1)
end

function Course:isUnloadAt(ix)
	return self.waypoints[ix].unload
end

function Course:isWaitAt(ix)
	return self.waypoints[ix].interact
end

function Course:getHeadlandNumber(ix)
	return self.waypoints[ix].lane
end

function Course:isOnHeadland(ix, n)
	ix = ix or self.currentWaypoint
	if n then
		return self.waypoints[ix].lane and self.waypoints[ix].lane == -n
	else
		return self.waypoints[ix].lane and self.waypoints[ix].lane < 0
	end
end

function Course:isOnOutermostHeadland(ix)
	return self.waypoints[ix].lane and self.waypoints[ix].lane == -1
end

function Course:getTurnControls(ix)
	return self.waypoints[ix].turnControls
end

function Course:useTightTurnOffset(ix)
	return self.waypoints[ix].useTightTurnOffset
end

--- Returns the position of the waypoint at ix with the current offset applied.
---@param ix number waypoint index
---@return number, number, number x, y, z
function Course:getWaypointPosition(ix)
	if self:isTurnStartAtIx(ix) then
		-- turn start waypoints point to the turn end wp, for example at the row end they point 90 degrees to the side
		-- from the row direction. This is a problem when there's an offset so use the direction of the previous wp
		-- when calculating the offset for a turn start wp.
		return self:getOffsetPositionWithOtherWaypointDirection(ix, ix - 1)
	else
		return self.waypoints[ix]:getOffsetPosition(self.offsetX + self.temporaryOffsetX:get(), self.offsetZ + self.temporaryOffsetZ:get())
	end
end

---Return the offset coordinates of waypoint ix as if it was pointing to the same direction as waypoint ixDir
function Course:getOffsetPositionWithOtherWaypointDirection(ix, ixDir)
	return self.waypoints[ix]:getOffsetPosition(self.offsetX + self.temporaryOffsetX:get(), self.offsetZ + self.temporaryOffsetZ:get(),
		self.waypoints[ixDir].dx, self.waypoints[ixDir].dz)
end

-- distance between (px,pz) and the ix waypoint
function Course:getDistanceBetweenPointAndWaypoint(px, pz, ix)
	return self.waypoints[ix]:getDistanceFromPoint(px, pz)
end

function Course:getDistanceBetweenVehicleAndWaypoint(vehicle, ix)
	return self.waypoints[ix]:getDistanceFromVehicle(vehicle)
end

--- get waypoint position in the node's local coordinates
function Course:getWaypointLocalPosition(node, ix)
	local x, y, z = self:getWaypointPosition(ix)
	local dx, dy, dz = worldToLocal(node, x, y, z)
	return dx, dy, dz
end

function Course:havePhysicallyPassedWaypoint(node, ix)
	local _, _, dz = self:getWaypointLocalPosition(node, ix)
	return dz < 0;
end

function Course:getWaypointAngleDeg(ix)
	return self.waypoints[math.min(#self.waypoints, ix)].angle
end

--- Gets the world directions of the waypoint.
---@param ix number
---@return number x world direction
---@return number z world direction
function Course:getWaypointWorldDirections(ix)
	local wp = self.waypoints[math.min(#self.waypoints, ix)]
	return wp.dx, wp.dz
end

--- Get the driving direction at the waypoint. y rotation points in the direction
--- of the next waypoint, but at the last wp before a direction change this is the opposite of the driving
--- direction, since we want to reach that last waypoint
function Course:getYRotationCorrectedForDirectionChanges(ix)
	if ix == #self.waypoints or self:switchingDirectionAt(ix) and ix > 1 then
		-- last waypoint before changing direction, use the yRot from the previous waypoint
		return self.waypoints[ix - 1].yRot
	else
		return self.waypoints[ix].yRot
	end
end

-- This is the radius from the course generator. For now ony island bypass waypoints nodes have a
-- radius.
function Course:getRadiusAtIx(ix)
	local r = self.waypoints[ix].radius
	if r ~= r then
		-- radius can be nan
		return nil
	else
		return r
	end
end

-- This is the radius calculated when the course is created.
function Course:getCalculatedRadiusAtIx(ix)
	local r = self.waypoints[ix].calculatedRadius
	if r ~= r then
		-- radius can be nan
		return nil
	else
		return r
	end
end


--- Get the minimum radius within d distance from waypoint ix
---@param ix number waypoint index to start
---@param d number distance in meters to look forward
---@return number the  minimum radius within d distance from waypoint ix
function Course:getMinRadiusWithinDistance(ix, d)
	local ixAtD = self:getNextWaypointIxWithinDistance(ix, d) or ix
	local minR, count = math.huge, 0
	for i = ix, ixAtD do
		if self:isTurnStartAtIx(i) or self:isTurnEndAtIx(i) then
			-- the turn maneuver code will take care of speed
			return nil
		end
		local r = self:getCalculatedRadiusAtIx(i)
		if r and r < minR then
			count = count + 1
			minR = r
		end
	end
	return count > 0 and minR or nil
end

--- Get the Y rotation of a waypoint (pointing into the direction of the next)
function Course:getWaypointYRotation(ix)
	local i = ix
	-- at the last waypoint use the incoming direction
	if ix >= #self.waypoints then
		i = #self.waypoints - 1
	elseif ix < 1 then
		i = 1
	end
	local cx, _, cz = self:getWaypointPosition(i)
	local nx, _, nz = self:getWaypointPosition(i + 1)
	local dx, dz = MathUtil.vector2Normalize(nx - cx, nz - cz)
	-- check for NaN
	if dx ~= dx or dz ~= dz then return 0 end
	return MathUtil.getYRotationFromDirection(dx, dz)
end

function Course:getRidgeMarkerState(ix)
	return self.waypoints[ix].ridgeMarker or 0
end

--- Get the average speed setting across n waypoints starting at ix
function Course:getAverageSpeed(ix, n)
	local total, count = 0, 0
	for i = ix, ix + n - 1 do
		local index = self:getIxRollover(i)
		if self.waypoints[index].speed ~= nil and self.waypoints[index].speed ~= 0 then
			total = total + self.waypoints[index].speed
			count = count + 1
		end
	end
	return (total > 0 and count > 0) and (total / count) or nil
end

function Course:getIxRollover(ix)
	if ix > #self.waypoints then
		return ix - #self.waypoints
	elseif ix < 1 then
		return #self.waypoints - ix
	end
	return ix
end

function Course:isLastWaypointIx(ix)
	return #self.waypoints == ix
end

function Course:print()
	for i = 1, #self.waypoints do
		local p = self.waypoints[i]
		print(string.format('%d: x=%.1f z=%.1f a=%.1f yRot=%.1f ts=%s te=%s r=%s i=%s d=%.1f t=%d l=%s p=%s tt=%s',
			i, p.x, p.z, p.angle or -1, math.deg(p.yRot or 0),
			tostring(p.turnStart), tostring(p.turnEnd), tostring(p.rev), tostring(p.interact),
			p.dToHere or -1, p.turnsToHere or -1, tostring(p.lane), tostring(p.pipeInFruit), tostring(p.useTightTurnOffset)))
	end
end

function Course:getDistanceToNextWaypoint(ix)
	return self.waypoints[math.min(#self.waypoints, ix)].dToNext
end

function Course:getDistanceBetweenWaypoints(a, b)
	return math.abs(self.waypoints[a].dToHere - self.waypoints[b].dToHere)
end

function Course:getDistanceFromFirstWaypoint(ix)
	return self.waypoints[ix].dToHere
end

function Course:getDistanceToLastWaypoint(ix)
	return self.length - self.waypoints[ix].dToHere
end

function Course:getWaypointsWithinDrivingTime(startIx, fwd, seconds, speed)
	local waypoints = {}
	local travelTimeSeconds = 0
	local first, last, step = startIx, #self.waypoints - 1, 1
	if not fwd then
		first, last, step = startIx - 1, 1, -1
	end
	for i = startIx, #self.waypoints - 1 do
		table.insert(waypoints, self.waypoints[i])
		local v = speed or self.waypoints[i].speed or 10
		local s = self:getDistanceToNextWaypoint(i)
		travelTimeSeconds = travelTimeSeconds + s / (v / 3.6)
		if travelTimeSeconds > seconds then
			break
		end
	end
	return waypoints
end

--- How far are we from the waypoint marked as the beginning of the up/down rows?
---@param ix number start searching from this index. Will stop searching after 100 m
---@return number, number of meters or math.huge if no start up/down row waypoint found within 100 meters and the
--- index of the first up/down waypoint
function Course:getDistanceToFirstUpDownRowWaypoint(ix)
	local d = 0
	local isConnectingTrack = false
	for i = ix, #self.waypoints - 1 do
		isConnectingTrack = isConnectingTrack or self.waypoints[i].isConnectingTrack
		d = d + self.waypoints[i].dToNext
		if self.waypoints[i].lane and not self.waypoints[i + 1].lane and isConnectingTrack then
			return d, i + 1
		end
		if d > 1000 then
			return math.huge, nil
		end
	end
	return math.huge, nil
end

--- Find the waypoint with the original index cpIx in vehicle.Waypoints
-- This is needed when legacy code like turn or reverse finishes and continues the
-- course at at given waypoint. The index of that waypoint may be different when
-- we have combined courses, so here find the correct one.
function Course:findOriginalIx(cpIx)
	for i = 1, #self.waypoints do
		if self.waypoints[i].cpIndex == cpIx then
			return i
		end
	end
	return 1
end

--- Is any of the waypoints around ix an unload point?
---@param ix number waypoint index to look around
---@param forward number look forward this number of waypoints when searching
---@param backward number look back this number of waypoints when searching
---@return boolean true if any of the waypoints are unload points and the index of the next unload point
function Course:hasUnloadPointAround(ix, forward, backward)
	return self:hasWaypointWithPropertyAround(ix, forward, backward, function(p) return p.unload end)
end

--- Is any of the waypoints around ix a wait point?
---@param ix number waypoint index to look around
---@param forward number look forward this number of waypoints when searching
---@param backward number look back this number of waypoints when searching
---@return boolean true if any of the waypoints are wait points and the index of the next wait point
function Course:hasWaitPointAround(ix, forward, backward)
	-- TODO: clarify if we use interact or wait or both?
	return self:hasWaypointWithPropertyAround(ix, forward, backward, function(p) return p.wait or p.interact end)
end

function Course:hasWaypointWithPropertyAround(ix, forward, backward, hasProperty)
	for i = math.max(ix - backward + 1, 1), math.min(ix + forward - 1, #self.waypoints) do
		if hasProperty(self.waypoints[i]) then
			-- one of the waypoints around ix has this property
			return true, i
		end
	end
	return false
end

--- Is there an unload waypoint within distance around ix?
---@param ix number waypoint index to look around
---@param distance number distance in meters to look around the waypoint
---@return boolean true if any of the waypoints are unload points and the index of the next unload point
function Course:hasUnloadPointWithinDistance(ix, distance)
	return self:hasWaypointWithPropertyWithinDistance(ix, distance, function(p) return p.unload end)
end

--- Is there a wait waypoint within distance around ix?
---@param ix number waypoint index to look around
---@param distance number distance in meters to look around the waypoint
---@return boolean true if any of the waypoints are wait points and the index of that wait point
function Course:hasWaitPointWithinDistance(ix, distance)
	return self:hasWaypointWithPropertyWithinDistance(ix, distance, function(p) return p.wait or p.interact end)
end

--- Is there an turn (start or end) around ix?
---@param ix number waypoint index to look around
---@param distance number distance in meters to look around the waypoint
---@return boolean true if any of the waypoints are turn start/end point
function Course:hasTurnWithinDistance(ix, distance)
	return self:hasWaypointWithPropertyWithinDistance(ix, distance, function(p) return p.turnStart or p.turnEnd end)
end

function Course:hasWaypointWithPropertyWithinDistance(ix, distance, hasProperty)
	-- search backwards first
	local d = 0
	for i = math.max(1, ix - 1), 1, -1 do
		if hasProperty(self.waypoints[i]) then
			return true, i
		end
		d = d + self.waypoints[i].dToNext
		if d > distance then break end
	end
	-- search forward
	d = 0
	for i = ix, #self.waypoints - 1 do
		if hasProperty(self.waypoints[i]) then
			return true, i
		end
		d = d + self.waypoints[i].dToNext
		if d > distance then break end
	end
	return false
end


--- Get the index of the first waypoint from ix which is at least distance meters away
---@param backward boolean search backward if true
---@return number, number index and exact distance
function Course:getNextWaypointIxWithinDistance(ix, distance, backward)
	local d = 0
	local from, to, step = ix, #self.waypoints - 1, 1
	if backward then
		from, to, step = ix - 1, 1, -1
	end
	for i = from, to, step do
		d = d + self.waypoints[i].dToNext
		if d > distance then return i + 1, d end
	end
	-- at the end/start of course return last/first wp
	return to + 1, d
end

--- Get the index of the first waypoint from ix which is at least distance meters away (search backwards)
function Course:getPreviousWaypointIxWithinDistance(ix, distance)
	local d = 0
	for i = math.max(1, ix - 1), 1, -1 do
		d = d + self.waypoints[i].dToNext
		if d > distance then return i end
	end
	return nil
end

--- Collect a nSteps number of positions on the course, starting at startIx, one position for every second,
--- or every dStep meters, whichever is less
---@param startIx number start at this waypoint
---@param dStep number step in meters
---@param nSteps number number of positions to collect
function Course:getPositionsOnCourse(nominalSpeed, startIx, dStep, nSteps)

	local function addPosition(positions, ix, x, y, z, dFromLastWp, speed)
		table.insert(positions, {x = x + dFromLastWp * self.waypoints[ix].dx,
								 y = y,
								 z = z + dFromLastWp * self.waypoints[ix].dz,
								 yRot = self.waypoints[ix].yRot,
								 speed = speed,
			-- for debugging only
								 dToNext = self.waypoints[ix].dToNext,
								 dFromLastWp = dFromLastWp,
								 ix = ix})
	end

	local positions = {}
	local d = 0 -- distance from the last step
	local dFromLastWp = 0
	local ix = startIx
	while #positions < nSteps and ix < #self.waypoints do
		local speed = nominalSpeed
		if self.waypoints[ix].speed then
			speed = (self.waypoints[ix].speed > 0) and self.waypoints[ix].speed or nominalSpeed
		end
		-- speed / 3.6 is the speed in meter/sec, that's how many meters we travel in one sec
		-- don't step more than 4 m as that would move the boxes too far away from each other creating a gap between them
		-- so if we drive fast, our event horizon shrinks, which is probably not a good thing
		local currentStep = math.min(speed / 3.6, dStep)
		local x, y, z = self:getWaypointPosition(ix)
		if dFromLastWp + currentStep < self.waypoints[ix].dToNext then
			while dFromLastWp + currentStep < self.waypoints[ix].dToNext and #positions < nSteps and ix < #self.waypoints do
				d = d + currentStep
				dFromLastWp = dFromLastWp + currentStep
				addPosition(positions, ix, x, y, z, dFromLastWp, speed)
			end
			-- this is before wp ix, so negative
			dFromLastWp = - (self.waypoints[ix].dToNext - dFromLastWp)
			d = 0
			ix = ix + 1
		else
			d = - dFromLastWp
			-- would step over the waypoint
			while d < currentStep and ix < #self.waypoints do
				d = d + self.waypoints[ix].dToNext
				ix = ix + 1
			end
			-- this is before wp ix, so negative
			dFromLastWp = - (d - currentStep)
			d = 0
			x, y, z = self:getWaypointPosition(ix)
			addPosition(positions, ix, x, y, z, dFromLastWp, speed)
		end
	end
	return positions
end

function Course:getLength()
	return self.length
end

--- Is there a turn between the two waypoints?
function Course:isTurnBetween(ix1, ix2)
	return self.waypoints[ix1].turnsToHere ~= self.waypoints[ix2].turnsToHere
end

function Course:getRemainingDistanceAndTurnsFrom(ix)
	local distance = self.length - self.waypoints[ix].dToHere
	local numTurns = self.totalTurns - self.waypoints[ix].turnsToHere
	return distance, numTurns
end

function Course:getNextFwdWaypointIx(ix)
	for i = ix, #self.waypoints do
		if not self:isReverseAt(i) then
			return i
		end
	end
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: could not find next forward waypoint after %d', ix)
	return ix
end

function Course:getNextFwdWaypointIxFromVehiclePosition(ix, vehicleNode, maxDx)
	-- only look at the next few waypoints, we don't want to find anything far away, really, it should be in front of us
	for i = ix, math.min(ix + 10, #self.waypoints) do
		if not self:isReverseAt(i) then
			local uX, uY, uZ = self:getWaypointPosition(i)
			local dx, _, dz = worldToLocal(vehicleNode, uX, uY, uZ);
			if dz > 0 and math.abs(dx) < maxDx then
				return i
			end
		end
	end
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: could not find next forward waypoint after %d', ix)
	return ix
end

function Course:getNextRevWaypointIxFromVehiclePosition(ix, vehicleNode, lookAheadDistance)
	for i = ix, #self.waypoints do
		if self:isReverseAt(i) then
			local uX, uY, uZ = self:getWaypointPosition(i)
			local _, _, z = worldToLocal(vehicleNode, uX, uY, uZ);
			if z < -lookAheadDistance then
				return i
			end
		end
	end
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: could not find next forward waypoint after %d', ix)
	return ix
end

--- Cut waypoints from the end of the course until we shortened it by at least d
-- @param d length in meters to shorten course
-- @return true if shortened
-- TODO: this must be protected from courses with a few waypoints only
function Course:shorten(d)
	local dCut = 0
	local from = #self.waypoints - 1
	for i = from, 1, -1 do
		dCut = dCut + self.waypoints[i].dToNext
		if dCut > d then
			self:enrichWaypointData()
			return true
		end
		table.remove(self.waypoints)
	end
	self:enrichWaypointData()
	return false
end

--- Append waypoints to the course
---@param waypoints Waypoint[]
function Course:appendWaypoints(waypoints)
	for i = 1, #waypoints do
		table.insert(self.waypoints, Waypoint(waypoints[i], #self.waypoints + 1))
	end
	self:enrichWaypointData()
end

--- Append another course to the course
function Course:append(other)
	self:appendWaypoints(other.waypoints)
end

--- Return a copy of the course
function Course:copy(vehicle, first, last)
	local newCourse = Course(vehicle or self.vehicle, self.waypoints, self:isTemporary(), first, last)
	newCourse:setName(self:getName())
	newCourse.multiTools = self.multiTools
	newCourse.workWidth = self.workWidth
	newCourse.numHeadlands = self.numHeadlands
	return newCourse
end

--- Append a single waypoint to the course
---@param waypoint Waypoint
function Course:appendWaypoint(waypoint)
	table.insert(self.waypoints, Waypoint(waypoint, #self.waypoints + 1))
end

--- Extend a course with a straight segment (same direction as last WP)
---@param length number the length to extend the course with
---@param dx number	direction to extend
---@param dz number direction to extend
function Course:extend(length, dx, dz)
	-- remember the number of waypoints when we started
	local nWaypoints = #self.waypoints
	local lastWp = self.waypoints[#self.waypoints]
	dx, dz = dx or lastWp.dx, dz or lastWp.dz
	local step = 5
	local first = math.min(length, step)
	local last = length
	for i = first, last, step do
		local x = lastWp.x + dx * i
		local z = lastWp.z + dz * i
		self:appendWaypoint({x = x, z = z})
	end
	-- enrich the waypoints we added
	self:enrichWaypointData(nWaypoints)
end

--- Create a new (straight) temporary course based on a node
---@param vehicle table
---@param referenceNode number
---@param xOffset number side offset of the new course (relative to node), left positive
---@param from number start at this many meters z offset from node
---@param to number end at this many meters z offset from node
---@param step number step (waypoint distance), must be negative if to < from
---@param reverse boolean is this a reverse course?
function Course.createFromNode(vehicle, referenceNode, xOffset, from, to, step, reverse)
	local waypoints = {}
	local nPoints = math.floor(math.abs((from - to) / step)) + 1
	local dBetweenPoints = (to - from) / nPoints
	local dz = from
	for i = 1, nPoints do
		local x, _, z = localToWorld(referenceNode, xOffset, 0, dz + i * dBetweenPoints)
		table.insert(waypoints, {x = x, z = z, rev = reverse})
	end
	local course = Course(vehicle, waypoints, true)
	course:enrichWaypointData()
	return course
end

--- Move a course by dx/dz world coordinates
function Course:translate(dx, dz)
	for _, wp in ipairs(self.waypoints) do
		wp.x = wp.x + dx
		wp.z = wp.z + dz
		wp.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, wp.x, 0, wp.z)
	end
end


--- The Reeds-Shepp algorithm we have does not take into account any towed implement or trailer, it calculates
--- the path for a single vehicle. Therefore, we need to extend the path at the cusps (direction changes) to
--- allow the towed implement to also reach the cusp, or, when reversing, reverse enough that the tractor reaches
--- the cusp.
function Course:adjustForTowedImplements(extensionLength)
	local waypoints = {self.waypoints[1]}
	for i = 2, #self.waypoints do
		if self:switchingDirectionAt(i) then
			local wp = self.waypoints[i - 1]
			local wpDistance = 1
			for j = wpDistance, math.max(extensionLength, wpDistance), wpDistance do
				local newWp = Waypoint(wp)
				newWp.x = wp.x + wp.dx * j
				newWp.z = wp.z + wp.dz * j
				table.insert(waypoints, newWp)
			end
		else
			table.insert(waypoints, self.waypoints[i])
		end
	end
	self.waypoints = waypoints
	self:enrichWaypointData()
end


--- Create a new temporary course between two nodes.
---@param vehicle table
---@param startNode number
---@param endNode number
---@param xOffset number side offset of the new course (relative to node), left positive
---@param zStartOffset number start at this many meters z offset from node
---@param zEndOffset number end at this many meters z offset from node
---@param step number step (waypoint distance), must be positive
---@param reverse boolean is this a reverse course?
function Course.createFromNodeToNode(vehicle, startNode, endNode, xOffset, zStartOffset, zEndOffset, step, reverse)
	local waypoints = {}

	local dist = calcDistanceFrom(startNode,endNode)

	local node = createTransformGroup("temp")

	local x,y,z = getWorldTranslation(startNode)
	local dx,_,dz = getWorldTranslation(endNode)
	local nx,nz =  MathUtil.vector2Normalize(dx-x,dz-z)

	local yRot = 0
	if nx == nx or nz == nz then
		yRot = MathUtil.getYRotationFromDirection(nx,nz)
	end

	setTranslation(node,x,0,z)
	setRotation(node,0,yRot,0)

	for d = zStartOffset, dist + zEndOffset, step do
		local ax, _, az = localToWorld(node, xOffset, 0, d)
		table.insert(waypoints, {x = ax, z = az, rev = reverse})
	end
	---Make sure that at the end is a waypoint.
	local ax, _, az = localToWorld(node, xOffset, 0, dist+zEndOffset)
	table.insert(waypoints, {x = ax, z = az, rev = reverse})

	CpUtil.destroyNode(node)
	local course = Course(vehicle, waypoints, true)
	course:enrichWaypointData()
	return course
end

--- Create a new (straight) temporary course based on a world coordinates
---@param vehicle table
---@param sx number x at start position
---@param sz number z at start position
---@param ex number x at end position
---@param ez number z at end position
---@param referenceNode number
---@param xOffset number side offset of the new course (relative to node), left positive
---@param zStartOffset number start at this many meters z offset from node
---@param zEndOffset number end at this many meters z offset from node
---@param step number step (waypoint distance), must be positive
---@param reverse boolean is this a reverse course?
function Course.createFromTwoWorldPositions(vehicle, sx, sz, ex, ez, xOffset, zStartOffset, zEndOffset, step, reverse)
	local waypoints = {}

	local yRot
	local nx,nz = MathUtil.vector2Normalize(ex - sx, ez - sz)
	if nx ~= nx or nz ~= nz then
		yRot=0
	else
		yRot = MathUtil.getYRotationFromDirection(nx,nz)
	end

	local node = createTransformGroup("temp")

	setTranslation(node, sx,0, sz)
	setRotation(node,0,yRot,0)

	local dist = MathUtil.getPointPointDistance(sx, sz, ex, ez)

	for d = zStartOffset, dist + zEndOffset, step do
		local ax, _, az = localToWorld(node, xOffset, 0, d)
		if MathUtil.getPointPointDistance(ex, ez, ax, az) > 0.1 * step then
			-- only add this point if not too close to the end point (as the end point will always be added)
			table.insert(waypoints, {x = ax, z = az, rev = reverse})
		end
	end
	---Make sure that at the end is a waypoint.
	local ax, _, az = localToWorld(node, xOffset, 0, dist + zEndOffset)
	table.insert(waypoints, {x = ax, z = az, rev = reverse})

	CpUtil.destroyNode(node)
	local course = Course(vehicle, waypoints, true)
	course:enrichWaypointData()
	return course
end

function Course:getDirectionToWPInDistance(ix, vehicle, distance)
	local lx, lz = 0, 1
	for i = ix, #self.waypoints do
		if self:getDistanceBetweenVehicleAndWaypoint(vehicle, i) > distance then
			local x,y,z = self:getWaypointPosition(i)
			lx,lz = AIVehicleUtil.getDriveDirection(vehicle.cp.directionNode, x, y, z)
			break
		end
	end
	return lx, lz
end

function Course:getDistanceToNextTurn(ix)
	return self.waypoints[ix].dToNextTurn
end

function Course:getDistanceFromLastTurn(ix)
	return self.waypoints[ix].dFromLastTurn
end

function Course:getDistanceToNextDirectionChange(ix)
	return self.waypoints[ix].dToNextDirectionChange
end

--- Are we closer than distance to the next turn?
---@param distance number
---@return boolean true when we are closer than distance to the next turn, false otherwise, even
--- if we can't determine the distance to the next turn.
function Course:isCloseToNextTurn(distance)
	local ix = self.currentWaypoint
	if ix then
		local dToNextTurn = self:getDistanceToNextTurn(ix)
		if dToNextTurn and dToNextTurn < distance then
			return true
		elseif self:isTurnEndAtIx(ix) or self:isTurnStartAtIx(ix) then
			return true
		else
			return false
		end
	end
	return false
end

--- Is the current waypoint within distance of a property, where getDistanceFunc() is a function which
--- determines this distance
---@param distance number
---@param getDistanceFunc function(ix)
function Course:isCloseToProperty(distance, getDistanceFunc)
	local ix = self.currentWaypoint
	if ix then
		local d = getDistanceFunc(self, ix)
		if d and d < distance then
			return true
		else
			return false
		end
	end
	return false
end

--- Are we closer than distance from the last turn?
---@param distance number
---@return boolean true when we are closer than distance to the last turn, false otherwise, even
--- if we can't determine the distance to the last turn.
function Course:isCloseToLastTurn(distance)
	return self:isCloseToProperty(distance, Course.getDistanceFromLastTurn)
end

--- Are we closer than distance to the next direction change?
---@param distance number
---@return boolean true when we are closer than distance to the next direction change, false otherwise, or when
--- the distance is not known
function Course:isCloseToNextDirectionChange(distance)
	return self:isCloseToProperty(distance, Course.getDistanceToNextDirectionChange)
end

function Course:isCloseToLastWaypoint(distance)
	return self:isCloseToProperty(distance, Course.getDistanceToLastWaypoint)
end

--- Get the length of the up/down row where waypoint ix is located
--- @param ix number waypoint index in the row
--- @return number, number length of the current row and the index of the first waypoint of the row
function Course:getRowLength(ix)
	for i = ix, 1, -1 do
		if self:isTurnEndAtIx(i) then
			return self:getDistanceToNextTurn(i), i
		end
	end
	return 0, nil
end

function Course:getNextRowLength(ix)
	return self.waypoints[ix].lNextRow
end

function Course:getNextRowStartIx(ix)
	return self.waypoints[ix].nextRowStartIx
end

function Course:draw()
	for i = 1, self:getNumberOfWaypoints() do
		local x, y, z = self:getWaypointPosition(i)
		-- TODO_22
		--cpDebug:drawPoint(x, y + 3, z, 10, 0, 0)
		Utils.renderTextAtWorldPosition(x, y + 3.2, z, tostring(i), getCorrectTextSize(0.012), 0)
		if i < self:getNumberOfWaypoints() then
			local nx, ny, nz = self:getWaypointPosition(i + 1)
			DebugUtil.drawDebugLine(x, y + 3, z, nx, ny + 3, nz, 0, 0, 100)
		end
	end
end

--- Waypoints generated by AD have no explicit reverse attribute, they infer it from elsewhere, see
--- https://github.com/Courseplay/courseplay/issues/7026#issuecomment-808715976
--- We assume all AD courses start forward and assume there's a direction change whenever there's an angle
--- over 100 degrees between two subsequent waypoints
function Course:addReverseForAutoDriveCourse()
	local reverse = false
	for i = 2, #self.waypoints do
		local deltaAngleDeg = math.abs(math.deg(getDeltaAngle(self.waypoints[i].yRot, self.waypoints[i - 1].yRot)))
		if deltaAngleDeg >= 100 then
			reverse = not reverse
			CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle,
				'Adding reverse for AutoDrive: direction change at %d (delta angle %.1f, reverse is now %s',
				i, deltaAngleDeg, tostring(reverse))
		end
		self.waypoints[i].rev = reverse or nil
	end
end

-- Create a legacy course. This is used for compatibility when loading a virtual AutoDrive course
function Course:createLegacyCourse()
	local legacyCourse = {}
	for i = 1, #self.waypoints do
		local x, _, z = self:getWaypointPosition(i)
		legacyCourse[i] = {
			x = x,
			cx = x, -- darn legacy cx/cz, why? why? why cx? why not just x? please someone explain...
			z = z,
			cz = z,
			rev = self:isReverseAt(i),
			angle = self:getWaypointAngleDeg(i),
			unload = self:isUnloadAt(i),
			wait = self:isWaitAt(i)
		}
	end
	legacyCourse[1].crossing = true
	legacyCourse[#legacyCourse].crossing = true
	return legacyCourse
end

function Course:worldToWaypointLocal(ix, x, y, z)
	local tempNode = WaypointNode('worldToWaypointLocal')
	tempNode:setToWaypoint(self,ix)
	setRotation(tempNode.node, 0, self:getWaypointYRotation(ix), 0);
	local dx,dy,dz = worldToLocal(tempNode.node,x, y, z)
	tempNode:destroy()
	return dx,dy,dz
end

function Course:waypointLocalToWorld(ix, x, y, z)
	local tempNode = WaypointNode('waypointLocalToWorld')
	tempNode:setToWaypoint(self,ix)
	setRotation(tempNode.node, 0, self:getWaypointYRotation(ix), 0);
	local dx,dy,dz = localToWorld(tempNode.node,x, y, z)
	tempNode:destroy()
	return dx,dy,dz
end

function Course:setNodeToWaypoint(node, ix)
	local x, y, z = self:getWaypointPosition(ix)
	setTranslation(node, x, y, z)
	setRotation(node, 0, self:getWaypointYRotation(ix), 0)
end

--- Run a function for all waypoints of the course within the last d meters
---@param d number
---@param lambda function (waypoint)
---@param stopAtDirectionChange boolean if we reach a direction change, stop there, the last waypoint the function
--- is called for is the one before the direction change
function Course:executeFunctionForLastWaypoints(d, lambda, stopAtDirectionChange)
	local i = self:getNumberOfWaypoints()
	while i > 1 and self:getDistanceToLastWaypoint(i) < d and
			((stopAtDirectionChange and not self:switchingDirectionAt(i)) or not stopAtDirectionChange) do
		lambda(self.waypoints[i])
		i = i - 1
	end
end

function Course:setUseTightTurnOffsetForLastWaypoints(d)
	self:executeFunctionForLastWaypoints(d, function(wp) wp.useTightTurnOffset = true end)
end

--- Get the next contiguous headland section of a course, starting at startIx
---@param lane number of lane (headland), starting at -1 on the outermost headland, any headland if nil
---@param startIx number start at this waypoint index
---@return Course, number headland section as a Course object, next wp index after the section
function Course:getNextHeadlandSection(lane, startIx)
	return self:getNextSectionWithProperty(startIx, function(wp)
		if lane then
			return wp.lane and wp.lane == lane
		else
			return wp.lane ~= nil
		end
	end)
end

--- Get the next contigous non-headland section of a course, starting at startIx
---@param startIx number start at this waypoint index
---@return Course, number headland section as a Course object, next wp index after the section
function Course:getNextNonHeadlandSection(startIx)
	return self:getNextSectionWithProperty(startIx, function(wp)
		return not wp.lane
	end)
end

--- Get a list contiguous of waypoints with a property, starting at startIx
--- @param startIx number start at this waypoint index
--- @param hasProperty function(wp) returns true if waypoint ix has the property
--- @return Course, number section as a Course object, next wp index after the section
function Course:getNextSectionWithProperty(startIx, hasProperty)
	local section = Course(self.vehicle, {})
	for i = startIx, self:getNumberOfWaypoints() do
		if hasProperty(self.waypoints[i]) then
			section:appendWaypoint(self.waypoints[i])
		else
			-- wp hasn't this property, stop here
			section:enrichWaypointData()
			return section, i
		end
	end
	section:enrichWaypointData()
	return section, self:getNumberOfWaypoints()
end

--- Move every non-headland waypoint of the course (up/down rows only) to their offset position
function Course:offsetUpDownRows(offsetX, offsetZ, useSameTurnWidth)
	local currentOffsetX = offsetX
	for i, _ in ipairs(self.waypoints) do
		if self:isTurnStartAtIx(i) then
			-- turn start waypoints point to the turn end wp, for example at the row end they point 90 degrees to the side
			-- from the row direction. This is a problem when there's an offset so use the direction of the previous wp
			-- when calculating the offset for a turn start wp.
			self.waypoints[i]:setOffsetPosition(currentOffsetX, offsetZ, self.waypoints[i - 1].dx, self.waypoints[i - 1].dz)
			if useSameTurnWidth then
				-- flip the offset for the next row (symmetric lane change) so every turn for every vehicle is of the same width
				currentOffsetX = - currentOffsetX
			end
		else
			self.waypoints[i]:setOffsetPosition(currentOffsetX, offsetZ)
		end
	end
	self:enrichWaypointData()
end

---@param waypoints Polyline
function Course:markAsHeadland(waypoints, passNumber)
	-- TODO: this should be in Polyline

	for _, p in ipairs(waypoints) do
		-- don't care which headland, just make sure it is a headland
		p.lane = passNumber
	end
end

--- @param nVehicles number of vehicles working together
--- @param position number an integer defining the position of this vehicle within the group, negative numbers are to
--- the left, positives to the right. For example, a -2 means that this is the second vehicle to the left (and thus,
--- there are at least 4 vehicles in the group), a 0 means the vehicle in the middle, for which obviously no offset
--- headland is required as it it driving on the original headland.
--- @param width number working width of one vehicle
function Course.calculateOffsetForMultitools(nVehicles, position, width)
	local offset
	if nVehicles % 2 == 0 then
		-- even number of vehicles
		offset = math.abs(position) * width - width / 2
	else
		offset = math.abs(position) * width
	end
	-- correct for side
	return position >= 0 and offset or -offset
end

--- Calculate an offset course from an existing course. This is used when multiple vehicles working on
--- the same field. In this case we only generate one course with the total implement width of all vehicles and use
--- the same course for all vehicles, only with different offsets (multitool).
--- Naively offsetting all waypoints may result in undrivable courses at corners, especially with offsets towards the
--- inside of the field. Therefore, we use the grassfire algorithm from the course generator to generate a drivable
--- offset headland.
---
--- In short, if multitool is used every vehicle of the pack gets a new course generated when it is started (and its
--- position in the pack is known).
---
--- The up/down row offset (laneOffset) is therefore not applied to the course being driven anymore, only the tool
--- and other offsets.
---
--- @param nVehicles number of vehicles working together
--- @param position number an integer defining the position of this vehicle within the group, negative numbers are to
--- the left, positives to the right. For example, a -2 means that this is the second vehicle to the left (and thus,
--- there are at least 4 vehicles in the group), a 0 means the vehicle in the middle, for which obviously no offset
--- headland is required as it it driving on the original headland.
--- @param width number working width of one vehicle
--- @param useSameTurnWidth boolean row end turns are always the same width: 'symmetric lane change' enabled, meaning
--- after each turn we reverse the offset
--- @return Course the course with the appropriate offset applied.
function Course:calculateOffsetCourse(nVehicles, position, width, useSameTurnWidth)
	-- find out the absolute offset in meters first
	local offset = Course.calculateOffsetForMultitools(nVehicles, position, width)
	local offsetCourse = Course(self.vehicle, {})
	offsetCourse.multiTools = nVehicles
	offsetCourse.name = self.name
	local ix = 1
	while ix and (ix < #self.waypoints) do
		local origHeadlandsCourse
		-- time to get rid of this negative lane number marking the headland, why on Earth must it be negative?
		local currentLaneNumber = self.waypoints[ix].lane
		-- work on the headland passes one by one to keep have the correct lane number in the offset course
		origHeadlandsCourse, ix = self:getNextHeadlandSection(currentLaneNumber, ix)
		if origHeadlandsCourse:getNumberOfWaypoints() > 0 then
			if origHeadlandsCourse:getNumberOfWaypoints() > 2 then
				CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Headland section to %d', ix)
				CourseGenerator.pointsToXyInPlace(origHeadlandsCourse.waypoints)
				local origHeadlands = Polyline:new(origHeadlandsCourse.waypoints)
				origHeadlands:calculateData()
				-- generating inward when on the right side and clockwise or when on the left side ccw
				local inward = (position > 0 and origHeadlands.isClockwise) or (position < 0 and not origHeadlands.isClockwise)
				local offsetHeadlands = calculateHeadlandTrack( origHeadlands, CourseGenerator.HEADLAND_MODE_NORMAL	, origHeadlands.isClockwise,
					math.abs(offset), 0.5, math.rad( 25 ), math.rad( 60 ), 0, inward,
					{}, 1 )

				if not offsetHeadlands or #offsetHeadlands == 0 then
					CpUtil.info('Could not generate offset headland')
				else
					offsetHeadlands:calculateData()
					self:markAsHeadland(offsetHeadlands, currentLaneNumber)
					if origHeadlandsCourse:isTurnStartAtIx(origHeadlandsCourse:getNumberOfWaypoints()) then
						CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Original headland transitioned to the center with a turn, adding a turn start to the offset one')
						offsetHeadlands[#offsetHeadlands].turnStart = true
					end
					addTurnsToCorners(offsetHeadlands, math.rad(60), true)
					CourseGenerator.pointsToXzInPlace(offsetHeadlands)
					offsetCourse:appendWaypoints(offsetHeadlands)
					CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Headland done %d', ix)
				end
			else
				CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Short headland section to %d', ix)
				origHeadlandsCourse:offsetUpDownRows(offset, 0)
				offsetCourse:append(origHeadlandsCourse)
			end
		else
			local upDownCourse
			CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Get next non-headland %d', ix)
			upDownCourse, ix = self:getNextNonHeadlandSection(ix)
			if upDownCourse:getNumberOfWaypoints() > 0 then
				CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Up/down section to %d', ix)
				upDownCourse:offsetUpDownRows(offset, 0, useSameTurnWidth)
				offsetCourse:append(upDownCourse)
			end
		end
	end
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Original headland length %.0f m, new headland length %.0f m (%.1f %%, %.1f m)',
		self.headlandLength, offsetCourse.headlandLength, 100 * offsetCourse.headlandLength / self.headlandLength,
		offsetCourse.headlandLength - self.headlandLength)
	local originalNonHeadlandLength = self.length - self.headlandLength
	local offsetNonHeadlandLength = offsetCourse.length - offsetCourse.headlandLength
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Original non-headland length %.0f m, new non-headland length %.0f m (%.1f %%, %.1f m)',
		originalNonHeadlandLength, offsetNonHeadlandLength,
		100 * offsetNonHeadlandLength / originalNonHeadlandLength,
		offsetNonHeadlandLength - originalNonHeadlandLength)
	-- apply tool offset to new course
	offsetCourse:setOffset(self.offsetX, self.offsetZ)
	return offsetCourse
end

--- @param node number the node around we are looking for waypoints
--- @return number, number, number, number the waypoint closest to node, its distance, the waypoint closest to the node
--- pointing approximately (+-45) in the same direction as the node and its distance
function Course:getNearestWaypoints(node)
	local nx, _, nz = getWorldTranslation(node)
	local lx, _, lz = localDirectionToWorld(node, 0, 0, 1)
	local nodeAngle = math.atan2(lx, lz)
	local maxDeltaAngle = math.pi / 2
	local dClosest, dClosestRightDirection = math.huge, math.huge
	local ixClosest, ixClosestRightDirection = 1, 1

	for i, p in ipairs(self.waypoints) do
		local x, _, z = self:getWaypointPosition(i)
		local d = MathUtil.getPointPointDistance(x, z, nx, nz)
		if d < dClosest then
			dClosest = d
			ixClosest = i
		end
		local deltaAngle = math.abs(getDeltaAngle(math.rad(p.angle), nodeAngle))
		if d < dClosestRightDirection and deltaAngle < maxDeltaAngle then
			dClosestRightDirection = d
			ixClosestRightDirection = i
		end
	end

	return ixClosest, dClosest, ixClosestRightDirection, dClosestRightDirection
end

--- Based on what option the user selected, find the waypoint index to start this course
--- @param node table the node around we are looking for waypoints
--- @param startingPoint StartingPointSetting at which waypoint to start the course
function Course:getStartingWaypointIx(node, startingPoint)
	if startingPoint:is(StartingPointSetting.START_AT_FIRST_POINT) then
		return 1
	end
	if startingPoint:is(StartingPointSetting.START_AT_LAST_POINT) then
		return self:getNumberOfWaypoints()
	end

	local ixClosest, _, ixClosestRightDirection, _ = self:getNearestWaypoints(node)
	if startingPoint:is(StartingPointSetting.START_AT_NEAREST_POINT) then
		return ixClosest
	end
	if startingPoint:is(StartingPointSetting.START_AT_NEXT_POINT) then
		return ixClosestRightDirection
	end
	return self:getCurrentWaypointIx()
end

function Course:isPipeInFruitAt(ix)
	return self.waypoints[ix].pipeInFruit
end

--- For each non-headland waypoint of the course determine if the pipe will be
--- in the fruit at that waypoint, assuming that the course is driven continuously from the
--- start to the end waypoint
---@return number, number the total number of non-headland waypoints, the total number waypoint where
--- the pipe will be in the fruit
function Course:setPipeInFruitMap(pipeOffsetX, workWidth)
	local pipeInFruitMapHelperWpNode = WaypointNode('pipeInFruitMapHelperWpNode')
	---@param rowStartIx number index of the first waypoint of the row
	local function createRowRectangle(rowStartIx)
		-- find the end of the row
		local rowEndIx = #self.waypoints
		for i = rowStartIx, #self.waypoints do
			if self:isTurnStartAtIx(i) then
				rowEndIx = i
				break
			end
		end
		pipeInFruitMapHelperWpNode:setToWaypoint(self, rowStartIx, true)
		local x, y, z = self:getWaypointPosition(rowEndIx)
		local _, _, rowLength = worldToLocal(pipeInFruitMapHelperWpNode.node, x, y, z)
		local row = {
			startIx = rowStartIx,
			length = rowLength
		}
		return row
	end

	local function setPipeInFruit(ix, pipeOffsetX, rows)
		local halfWorkWidth = workWidth / 2
		pipeInFruitMapHelperWpNode:setToWaypoint(self, ix, true)
		local x, y, z = localToWorld(pipeInFruitMapHelperWpNode.node, pipeOffsetX, 0, 0)
		for _, row in ipairs(rows) do
			pipeInFruitMapHelperWpNode:setToWaypoint(self, row.startIx)
			-- pipe's local position in the row start wp's system
			local lx, _, lz = worldToLocal(pipeInFruitMapHelperWpNode.node, x, y, z)
			-- add 20 m buffer to account for non-perpendicular headlands where technically the pipe
			-- would not be in the fruit around the end of the row
			if math.abs(lx) <= halfWorkWidth and lz >= -20 and lz <= row.length + 20 then
				-- pipe is in the fruit at ix
				return true
			end
		end
		return false
	end

	-- The idea here is that we walk backwards on the course, remembering each row and adding them
	-- to the list of unworked rows. This way, at any waypoint we have a list of rows the vehicle
	-- wouldn't have finished if it was driving the course the right way (start to end).
	-- Now check if the pipe would be in any of these unworked rows
	local rowsNotDone = {}
	local totalNonHeadlandWps = 0
	local pipeInFruitWps = 0
	-- start at the end of the course
	local i = #self.waypoints
	while i > 1 do
		-- skip over the headland, we assume the headland is worked first and will always be harvested before
		-- we get to the middle of the field. If not, your problem...
		if not self:isOnHeadland(i) then
			totalNonHeadlandWps = totalNonHeadlandWps + 1
			-- check if the pipe is in an unworked row
			self.waypoints[i].pipeInFruit = setPipeInFruit(i, pipeOffsetX, rowsNotDone)
			pipeInFruitWps = pipeInFruitWps + (self.waypoints[i].pipeInFruit and 1 or 0)
			if self:isTurnEndAtIx(i) then
				-- we are at the start of a row (where the turn ends)
				table.insert(rowsNotDone, createRowRectangle(i))
			end
		end
		i = i - 1
	end
	pipeInFruitMapHelperWpNode:destroy()
	return totalNonHeadlandWps, pipeInFruitWps
end

---@param ix number waypoint where we want to get the progress, when nil, uses the current waypoint
---@return number, number, boolean 0-1 progress, waypoint where the progress is calculated, true if last waypoint
function Course:getProgress(ix)
	ix = ix or self:getCurrentWaypointIx()
	return self.waypoints[ix].dToHere / self.length, ix, ix == #self.waypoints
end

-- This may be useful in the future, the idea is not to store the waypoints of a fieldwork row (as it is just a straight
-- line), only the start and the end of the row (turn end and turn start waypoints). We still need those intermediate
-- waypoints though when working so the PPC does not put the targets kilometers away, so after loading a course, these
-- points can be generated by this function
-- TODO: fix headland -> up/down transition where there is no turn start/end
function Course:addWaypointsForRows()
	local waypoints = self:initWaypoints()

	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: adding waypoints for rows')

	for i = 1, #self.waypoints - 1 do
		table.insert(waypoints, Waypoint(self.waypoints[i]))
		local p = self.waypoints[i]
		if self:isTurnEndAtIx(i) and self:isTurnStartAtIx(i + 1) and
			p.dToNext > CourseGenerator.waypointDistance + 0.1 then
			CpUtil.debugVehiccle(CpDebug.DBG_COURSES, self.vehicle, 'Course: adding waypoints for row, length %.1f', p.dToNext)
			for n = 1, (p.dToNext / CourseGenerator.waypointDistance) - 1 do
				local newWp = Waypoint(p)
				newWp.turnEnd = nil
				newWp.x = p.x + n * CourseGenerator.waypointDistance * p.dx
				newWp.z = p.z + n * CourseGenerator.waypointDistance * p.dz
				table.insert(waypoints, newWp)
			end
		end
	end
	table.insert(waypoints, Waypoint(self.waypoints[#self.waypoints]))
	self.waypoints = waypoints
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: has now %d waypoints', #self.waypoints)
	self:enrichWaypointData()
end

--- Use a single XML node to store all waypoints. Waypoints are separated by a '|' and a newline, latter for better
--- readability only.
--- The attributes of individual waypoints are separated by a ';', the order of the attributes can be read from the
--- code below.
---@param compress boolean if true, will skip waypoints of rows between turn end and turn start
function Course:serializeWaypoints(compress)
	local function serializeBool(bool)
		return bool and 'Y' or 'N'
	end

	local function serializeInt(number)
		return number and string.format('%d', number) or ''
	end

	local serializedWaypoints = '\n' -- (pure cosmetic)
	for i, p in ipairs(self.waypoints) do
		-- do not save waypoints of a row between the turn start and end as it is just a long straight
		-- line between the two and can be re-generated on load
		-- always include first and last waypoint
		local mustInclude = i == 1 or i == #self.waypoints
		-- always include turn starts and turn ends and everything which does not have a row number
		mustInclude = mustInclude or p.turnStart or p.turnEnd or not p.rowNumber
		-- always include the first waypoint of the first row (after transitioning from the headland, in case it is not a turn)
		mustInclude = mustInclude or (i > 1 and not self.waypoints[i - 1].rowNumber and p.rowNumber)
		-- always include the last waypoint of the last row (before transitioning to the headland in case it is not a turn)
		mustInclude = mustInclude or (i < #self.waypoints and not self.waypoints[i + 1].rowNumber and p.rowNumber)
		if not compress or mustInclude then
			local x, y, z = p.x, p.y, p.z
			local turn = p.turnStart and 'S' or (p.turnEnd and 'E' or '')
			local serializedWaypoint = string.format('%.2f %.2f %.2f;%.2f;%s;%s;',
				x, y, z, p.angle, serializeInt(p.speed), turn)
			serializedWaypoint = serializedWaypoint .. string.format('%s;%s;%s;%s;',
				serializeBool(p.rev), serializeBool(p.unload), serializeBool(p.wait), serializeBool(p.crossing))
			serializedWaypoint = serializedWaypoint .. string.format('%s;%s;%s;%s|\n',
				serializeInt(p.lane), serializeInt(p.ridgeMarker),
				serializeInt(p.headlandHeightForTurn), serializeBool(p.isConnectingTrack))
			serializedWaypoints = serializedWaypoints .. serializedWaypoint
		end
	end
	return serializedWaypoints
end

function Course.deserializeWaypoints(serializedWaypoints)
	local function deserializeBool(str)
		if str == 'Y' then
			return true
		elseif str == 'N' then
			return false
		else
			return nil
		end
	end

	local waypoints = {}

	local lines = string.split(serializedWaypoints, '|')
	for _, line in ipairs(lines) do
		local p = {}
		local fields = string.split(line,';')
		p.x, p.y, p.z = string.getVector(fields[1])
		-- just skip empty lines
		if p.x then
			p.angle = tonumber(fields[2])
			p.speed = tonumber(fields[3])
			local turn = fields[4]
			p.turnStart = turn == 'S'
			p.turnEnd = turn == 'E'
			p.rev = deserializeBool(fields[5])
			p.unload = deserializeBool(fields[6])
			p.wait = deserializeBool(fields[7])
			p.crossing = deserializeBool(fields[8])
			p.lane = tonumber(fields[9])
			p.ridgeMarker = tonumber(fields[10])
			p.headlandHeightForTurn = tonumber(fields[11])
			p.isConnectingTrack = deserializeBool(fields[12])
			table.insert(waypoints, p)
		end
	end
	return waypoints
end

function Course:saveToXml(courseXml, courseKey)
	courseXml:setValue(courseKey .. '#name',self.name)
	courseXml:setValue(courseKey  .. '#workWidth',self.workWidth or 0)
	courseXml:setValue(courseKey  .. '#numHeadlands',self.numHeadlands or 0)
	courseXml:setValue(courseKey  .. '#multiTools',self.multiTools or 0)
	courseXml:setValue(courseKey  .. '#wasEdited', self.editedByCourseEditor)
	--- For backward compatibility a flag is set to indicate, that the waypoints between rows are not saved.
	--courseXml:setValue(courseKey  .. '#isCompressed',true)
	for i,p in ipairs(self.waypoints) do 
		local key = string.format("%s%s(%d)",courseKey,Waypoint.xmlKey,i-1)
		courseXml:setString(key,p:getXmlString())
	end
end

function Course:writeStream(vehicle,streamId, connection)
	streamWriteString(streamId, self.name or "")
	streamWriteFloat32(streamId, self.workWidth or 0)
	streamWriteInt32(streamId, self.numHeadlands or 0 )
	streamWriteInt32(streamId, self.multiTools or 1)
	streamWriteInt32(streamId, #self.waypoints or 0)
	streamWriteBool(streamId, self.editedByCourseEditor)
	for i,p in ipairs(self.waypoints) do 
		streamWriteString(streamId,p:getXmlString())
	end
end

---@param vehicle  table
---@param courseXml XmlFile
---@param courseKey string key to the course in the XML
function Course.createFromXml(vehicle, courseXml, courseKey)
	local name = courseXml:getValue( courseKey .. '#name')
	local workWidth = courseXml:getValue( courseKey .. '#workWidth')
	local numHeadlands = courseXml:getValue( courseKey .. '#numHeadlands')
	local multiTools = courseXml:getValue( courseKey .. '#multiTools')
	local isCompressed = courseXml:getValue(courseKey  .. '#isCompressed')
	local wasEdited = courseXml:getValue(courseKey  .. '#wasEdited', false)
	local waypoints = {}
	if courseXml:hasProperty(courseKey  .. Waypoint.xmlKey) then 
		local d
		courseXml:iterate(courseKey..Waypoint.xmlKey,function (ix,key)
			d = CpUtil.getXmlVectorValues(courseXml:getString(key))
			table.insert(waypoints,Waypoint.initFromXmlFile(d,ix))
		end)
	else
		--- old course save format for backwards compatibility
		local serializedWaypoints = courseXml:getValue(courseKey  .. '.waypoints')
		waypoints = Course.deserializeWaypoints(serializedWaypoints)
	end

	local course = Course(vehicle,waypoints)
	course.name = name
	course.workWidth = workWidth
	course.numHeadlands = numHeadlands
	course.multiTools = multiTools
	course.editedByCourseEditor = wasEdited
	if isCompressed then
		course:addWaypointsForRows()
	end
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, vehicle, 'Course with %d waypoints loaded.', #course.waypoints)
	return course
end

function Course.createFromStream(vehicle,streamId, connection)
	local name = streamReadString(streamId)
	local workWidth = streamReadFloat32(streamId)
	local numHeadlands = streamReadInt32(streamId)
	local multiTools = streamReadInt32(streamId)
	local numWaypoints = streamReadInt32(streamId)
	local wasEdited = streamReadBool(streamId)
	local waypoints = {}
	for ix=1,numWaypoints do 
		local d = CpUtil.getXmlVectorValues(streamReadString(streamId))
		table.insert(waypoints,Waypoint.initFromXmlFile(d,ix))
	end
	local course = Course(vehicle, waypoints)
	course.name = name
	course.workWidth = workWidth
	course.numHeadlands = numHeadlands
	course.multiTools = multiTools
	course.editedByCourseEditor = wasEdited
	CpUtil.debugVehicle(CpDebug.DBG_MULTIPLAYER, vehicle, 'Course with %d waypoints loaded.', #course.waypoints)
	return course
end

function Course.createFromGeneratedCourse(vehicle, generatedCourse, workWidth, numHeadlands, multiTools)
	local waypoints = {}
	for i, wp in ipairs(generatedCourse) do
		table.insert(waypoints, Waypoint.initFromGeneratedWp(wp, i))
	end
	local course = Course(vehicle or g_currentMission.controlledVehicle, waypoints)
	course.workWidth = workWidth
	course.numHeadlands = numHeadlands
	course.multiTools = multiTools
	return course
end

--- When creating a course from an analytic path, we want to have the direction of the last waypoint correct
function Course.createFromAnalyticPath(vehicle, path, isTemporary)
	local course = Course(vehicle, CourseGenerator.pointsToXzInPlace(path), isTemporary)
	-- enrichWaypointData rotated the last waypoint in the direction of the second to last,
	-- correct that according to the analytic path's last waypoint
	local yRot = CourseGenerator.toCpAngle(path[#path].t)
	course.waypoints[#course.waypoints].yRot = yRot
	course.waypoints[#course.waypoints].angle = math.deg(yRot)
	course.waypoints[#course.waypoints].dx, course.waypoints[#course.waypoints].dz =
	MathUtil.getDirectionFromYRotation(yRot)
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, vehicle,
		'Last waypoint of the course created from analytical path: angle set to %.1f°', math.deg(yRot))
	return course
end