
--about ids and lookups
---------------------------------------------------------------------

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

--just to test
print(x:to_stateful():id():to_s())

--casting a route to something more specific
local y=x:to_track():to_audio_track()
if y:isnil() then print ('is nil') end

--showing id again
print(y:to_stateful():id():to_s())

