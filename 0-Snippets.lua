---- this header is (only) required to save the script
--ardour { ["type"] = "Snippet", name = "0-Snippets" }
--function factory () return function () end end

--about ids and lookups
---------------------------------------------------------------------

function test1()
--get ARDOUR:Route with remote id 0 (route is at index 0)
local t=Session:get_remote_nth_route(0)
if t:isnil() then print ('is nil') end

--casting route to PBD:Stateful
local sf=t:to_stateful()
if sf:isnil() then print ('is nil') end

--getting PBD:ID, getting id as string (it's a number indeed)
local id=sf:id():to_s()
print(id) --this id should be unique in a session-wide scope

--lookup up a route by knowing the PBD:ID
local x=Session:route_by_id(PBD.ID(id))
if x:isnil() then print ('is nil') end

--other _by_id methods:
--[[
	Region		ARDOUR:Playlist		region_by_id
	Region		ARDOUR:RegionFactory	region_by_id
	Controllable	ARDOUR:Session		controllable_by_id
	Processor	ARDOUR:Session		processor_by_id
	Route		ARDOUR:Session		route_by_id
	Source		ARDOUR:Session		source_by_id
--]]

--just to test
print(x:to_stateful():id():to_s())

--casting a route to something more specific
local y=x:to_track():to_audio_track()
if y:isnil() then print ('is nil') end

--showing id again
print(y:to_stateful():id():to_s())
end -- test1()

--finding a route by name to store its PBD:ID
---------------------------------------------------------------------
function get_route_id_by_name(name)
	return Session:route_by_name(name):to_stateful():id():to_s()
end

--finding a route by index to store its PBD:ID
---------------------------------------------------------------------
function get_route_id_by_index(index)
	return Session:get_remote_nth_route(index):to_stateful():id():to_s()
end

--other _by_name methods:
--[[
	Port		ARDOUR:AudioEngine	get_port_by_name
	std::string	ARDOUR:AudioEngine	get_pretty_name_by_name
	Port		ARDOUR:IO		port_by_name
	int		ARDOUR:Port		connect_by_name
	int		ARDOUR:Port		disconnect_by_name
	int		 ARDOUR:AudioPort	connect_by_name
	int		 ARDOUR:AudioPort	disconnect_by_name
	int		 ARDOUR:MidiPort	connect_by_name
	int		 ARDOUR:MidiPort	disconnect_by_name
	Port		ARDOUR:PortManager	get_port_by_name
	Port		ARDOUR:PortManager	get_pretty_name_by_name
	Route		ARDOUR:Session		route_by_name
--]]

--finding a route by other filters to store its PBD:ID
---------------------------------------------------------------------
--[[
function get_route_id_by_name_something(name, something)
	for r in Session:get_routes():iter() do --there is also Session:get_tracks()
		if (string.match (r:name(), name) and something==1) then --dummy filter
			return r:to_stateful():id():to_s()
		end
	end
end
--]]

--finding the nth instance of a plugin matching a given name on a route to store its PBD:ID
--a plugin with the same name can easily appear twice or more on a track
---------------------------------------------------------------------
function get_nth_plugin_id_by_name(route_id, name, nth_match) --nth_match 0: first match
	local r=Session:route_by_id(PBD.ID(route_id))
	if r:isnil() then return nil end

	--getting plugin count (?)
	local proc
	local matches=0
	local i=0
	--try and error
	repeat
		-- get Nth Ardour::Processor
		proc = r:nth_plugin (i)
		if (not proc:isnil() and proc:display_name () == name) then
			if matches == nth_match then
				return proc:to_stateful():id():to_s()
			else
				matches=matches+1
			end
		end
		i = i + 1
	until proc:isnil()
	return nil
end

--finding a plugin at the given index on a route to store its PBD:ID
---------------------------------------------------------------------
function get_plugin_id_by_index(route_id, index)
	local r=Session:route_by_id(PBD.ID(route_id))
	if r:isnil() then return nil end

	local proc = r:nth_plugin (index)
	if proc:isnil() then return nil end

	return proc:to_stateful():id():to_s()
end

--finding the nth instance of a plugin parameter name matching a given name on a route to store its index
--a plugin with two or more equal parameter names can not be ruled out
---------------------------------------------------------------------
function get_nth_plugin_parameter_index_by_name(plugin_id, name, nth_match) --nth_match 0: first match
	local proc=Session:processor_by_id(PBD.ID(plugin_id))
	if proc:isnil() then return nil end

	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end

	local plugin=pinsert:plugin(0)
	--this includes both input AND output ports
	local param_count=plugin:parameter_count()
	--print(param_count)

	local matches=0

	for param_index=0,param_count-1 do
		local _,pd = plugin:get_parameter_descriptor(param_index,ARDOUR.ParameterDescriptor())
		-- t[2].label --.. " " .. t[2].lower .. " " .. t[2].upper
		if pd[2].label == name then
			if matches == nth_match then
				--local ctrl = Evoral.Parameter(ARDOUR.AutomationType.PluginAutomation,0,param_index)
				return param_index
			else
				matches=matches+1
			end
		end
	end
	return nil
end -- get_nth_plugin_parameter_index_by_name()

--
---------------------------------------------------------------------
function set_plugin_control_value(plugin_id, param_index, value)
	local proc=Session:processor_by_id(PBD.ID(plugin_id))
	if proc:isnil() then return nil end

	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end

--not a good idea to try to set an output control value
	return ARDOUR.LuaAPI.set_plugin_insert_param(pinsert,param_index,value)
end

--
---------------------------------------------------------------------
function get_plugin_control_value(plugin_id, param_index)
	local proc=Session:processor_by_id(PBD.ID(plugin_id))
	if proc:isnil() then return nil end

	local pinsert=proc:to_insert()
	if pinsert:isnil() then return nil end

	local val,ok=ARDOUR.LuaAPI.get_plugin_insert_param(pinsert,param_index,ok)
	if ok==false then return nil end
	return val
end

--test1()
local rid=get_route_id_by_index(0)
--local rid=get_route_id_by_name('Audio')

local pid=get_nth_plugin_id_by_name(rid, '0-SD', 0)
--local pid=get_plugin_id_by_index(rid, 0)

local ppi=get_nth_plugin_parameter_index_by_name(pid,'Threshold',0)

print(set_plugin_control_value(pid,ppi,1))
print(get_plugin_control_value(pid,ppi))
