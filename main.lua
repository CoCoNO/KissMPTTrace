KSA = {}

KSA.ban_list = {}
KSA.player_roles = {}

KSA.race = {
    start_transform = nil,
    finish = nil,
    start_time = nil,
    player = nil,
    vehicleid = nil,
    distance_to_finish = 10,
    penalty_time = 0,
    penalty_for_reset = 10,
    leaderboard = {},
    countdown_time = 5, -- Time in seconds for countdown before race
    countdown_timer = nil,
    state = 0 -- 0 = Nothing, 1 = Counting Down, 2 = In Progress
}

KSA.commands = {
    kick = {
        roles = {
            admin = true,
            superadmin = true
        },
        exec = function(executor, args)
            if not args[1] then
                executor:sendChatMessage("No arguments provided")
            end
            for id, client in pairs(connections) do
                if client:getName() == args[1] then
                    client:kick("You have been kicked. Reason: " .. (args[2] or "No reason provided"))
                    return
                end
            end
        end
    },
    ban = {
        roles = {
            admin = true,
            superadmin = true
        },
        exec = function(executor, args)
            if not args[1] then
                executor:sendChatMessage("No arguments provided")
            end
            for id, client in pairs(connections) do
                if client:getName() == args[1] then
                    KSA.ban(client:getSecret(), client:getName(), client:getID(), tonumber(args[2]) or math.huge)
                    return
                end
            end
        end
    },
    promote = {
        roles = {
            superadmin = true
        },
        exec = function(executor, args)
            if not args[1] then
                executor:sendChatMessage("No arguments provided")
            end
            for id, client in pairs(connections) do
                if client:getName() == args[1] then
                    KSA.promote(client:getSecret(), args[2] or "user")
                    return
                end
            end
        end
    },
    set_start = {
        roles = {
            admin = true,
            superadmin = true
        },
        exec = function(executor, args)
            print("Setting up race start position" .. tostring(executor:getCurrentVehicle()))

            local vehicle = executor:getCurrentVehicle()
            if not vehicle then
                executor:sendChatMessage("You must be in a vehicle to set the race start")
                return
            end

            local transform = vehicles[vehicle]:getTransform()

            KSA.race.start_transform = {transform:getPosition()[1], transform:getPosition()[2],
                                        transform:getPosition()[3], transform:getRotation()[1],
                                        transform:getRotation()[2], transform:getRotation()[3],
                                        transform:getRotation()[4]}

            executor:sendChatMessage("Race start set to " .. KSA.race.start_transform[1] .. ", " ..
                                         KSA.race.start_transform[2] .. ", " .. KSA.race.start_transform[3])
        end
    },
    set_end = {
        roles = {
            admin = true,
            superadmin = true
        },
        exec = function(executor, args)
            local vehicle = executor:getCurrentVehicle()
            if not vehicle then
                executor:sendChatMessage("You must be in a vehicle to set the race end")
                return
            end
            KSA.race.finish = vehicles[vehicle]:getTransform():getPosition()
            executor:sendChatMessage("Race end set to " .. KSA.race.finish[1] .. ", " .. KSA.race.finish[2] .. ", " ..
                                         KSA.race.finish[3])
        end
    },
    save_race = {
        roles = {
            admin = true,
            superadmin = true
        },
        exec = function(executor, args)
            if not KSA.race.start_transform or not KSA.race.finish then
                executor:sendChatMessage("Race start and end positions not set")
                return
            end
            local data = {}
            data[SERVER_MAP] = {
                start_transform = KSA.race.start_transform,
                end_position = KSA.race.finish
            }
            local file = io.open("./ksa_race.json", "w")
            file:write(encode_json_pretty(data))
            file:close()
        end
    },
    race = {
        roles = {
            user = true,
            admin = true,
            superadmin = true
        },
        exec = function(executor, args)
            if not KSA.race.finish or not KSA.race.start_transform then
                executor:sendChatMessage("Race start and end positions not set")
                return
            end
            if KSA.race.player then
                executor:sendChatMessage("A race is already in progress")
                return
            end
            local vehicle = executor:getCurrentVehicle()
            if not vehicle then
                executor:sendChatMessage("You must be in a vehicle to set the race start")
                return
            end
            KSA.race.vehicleid = vehicle
            KSA.race.penalty_time = 0
            KSA.race.player = executor
            KSA.race.start_time = os.clock() + KSA.race.countdown_time
            KSA.race.countdown_timer = KSA.race.countdown_time -1
            send_message_broadcast("Race started by " .. executor:getName())
            -- Teleport the player to the start position
            vehicles[KSA.race.vehicleid]:setPositionRotation(KSA.race.start_transform[1], KSA.race.start_transform[2],
                KSA.race.start_transform[3], KSA.race.start_transform[4], KSA.race.start_transform[5],
                KSA.race.start_transform[6], KSA.race.start_transform[7])
            -- Disable brake override to prevent players from jumping the start
            -- core_vehicleBridge.executeAction(getPlayerVehicle(0),'setFreeze', true)
            KSA.race.player:sendLua("core_vehicleBridge.executeAction(getPlayerVehicle(0),'setFreeze', true)")
            KSA.race.player:sendLua("guihooks.message(\"Get Ready!\")")
            KSA.race.state = 1
        end
    },
    blackflag = {
        roles = {
            user = true,
            admin = true,
            superadmin = true
        },
        exec = function(executor, args)
            if KSA.race.state == 2 then
                send_message_broadcast("Race Cancelled!")
                KSA.race.player = nil
                KSA.race.start_time = nil
                KSA.race.state = 0
                KSA.race.penalty_time = 0
            end
        end
    }
}

local function load_raceposition()
    local file = io.open("./ksa_race.json", "r")
    if not file then
        return
    end
    local content = file:read("*a")
    if not content then
        return
    end
    local data = decode_json(content)
    if not data then
        return
    end
    local map_data = data[SERVER_MAP]
    if not map_data then
        return
    end
    KSA.race.start_transform = map_data.start_transform
    KSA.race.finish = map_data.end_position
    print("Loaded race position for map " .. SERVER_MAP)
end

local calculate_distance = function(vec1, vec2)
    local diff = {0, 0, 0}
    diff[1] = vec1[1] - vec2[1]
    diff[2] = vec1[2] - vec2[2]
    diff[3] = vec1[3] - vec2[3]
    return math.sqrt(diff[1] * diff[1] + diff[2] * diff[2] + diff[3] * diff[3])
end

local function load_leaderboard()
    print("Loading leaderboard for map " .. SERVER_MAP)
    --KSA.race.leaderboard = {}
    
    local file = io.open("./ksa_leaderboard.json", "r")
    if file then
        local content = file:read("*a")
        if content then
            KSA.race.leaderboard = decode_json(content)
        end
        file:close()
        if not KSA.race.leaderboard then
            KSA.race.leaderboard = {}
            print("Leaderboard: " .. tostring(KSA.race.leaderboard) )
            --KSA.race.leaderboard[SERVER_MAP] = {}
        end
    end
    
end

local function save_leaderboard()
    local file = io.open("./ksa_leaderboard.json", "w")
    local content = encode_json_pretty(KSA.race.leaderboard)
    if not content then
        return
    end
    file:write(content)
end

local function add_leaderboard(time, player_name)
    print("Adding leaderboard entry for map " .. SERVER_MAP .. " Time: " .. tostring(time) .. " Player: " ..
              tostring(player_name).. tostring(KSA.race.leaderboard))
    local entry = {
        time = time,
        player_name = player_name
    }
    if not KSA.race.leaderboard[SERVER_MAP] then
        KSA.race.leaderboard[SERVER_MAP] = {}
    end
    table.insert(KSA.race.leaderboard[SERVER_MAP], entry)
    table.sort(KSA.race.leaderboard[SERVER_MAP], function(a, b)
        return a.time < b.time
    end)

    local rank = 1
    for index, value in ipairs(KSA.race.leaderboard[SERVER_MAP]) do
        if value.player_name == player_name and value.time == time then
            break
        end
        rank = rank + 1
    end
    save_leaderboard()
    return rank
end

-- Created by Dummiesman
local function cmd_parse(cmd)
    local parts = {}
    local len = cmd:len()
    local escape_sequence_stack = 0
    local in_quotes = false

    local cur_part = ""
    for i = 1, len, 1 do
        local char = cmd:sub(i, i)
        if escape_sequence_stack > 0 then
            escape_sequence_stack = escape_sequence_stack + 1
        end
        local in_escape_sequence = escape_sequence_stack > 0
        if char == "\\" then
            escape_sequence_stack = 1
        elseif char == " " and not in_quotes then
            table.insert(parts, cur_part)
            cur_part = ""
        elseif char == '"' and not in_escape_sequence then
            in_quotes = not in_quotes
        else
            cur_part = cur_part .. char
        end
        if escape_sequence_stack > 1 then
            escape_sequence_stack = 0
        end
    end
    if cur_part:len() > 0 then
        table.insert(parts, cur_part)
    end
    return parts
end

local function load_roles()
    local file = io.open("./ksa_roles.json", "r")
    if not file then
        return
    end
    KSA.player_roles = decode_json(file:read("*a"))
    -- print("Loaded roles: " .. tostring(KSA.player_roles))
end

local function save_roles()
    local file = io.open("./ksa_roles.json", "w")
    local content = encode_json_pretty(KSA.player_roles)
    if not content then
        return
    end
    file:write(content)
end

local function load_banlist()
    local file = io.open("./ksa_banlist.json", "r")
    if not file then
        return
    end
    KSA.ban_list = decode_json(file:read("*a"))
end

local function save_banlist()
    local file = io.open("./ksa_banlist.json", "w")
    local content = encode_json_pretty(KSA.ban_list)
    if not content then
        return
    end
    file:write(content)
end

function KSA.ban(secret, name, client_id, time)
    local time = time or math.huge()
    KSA.ban_list[secret] = {
        name = name,
        unban_time = os.time() + (time * 60)
    }
    connections[client_id]:kick("You've been banned on this server.")
    save_banlist()
end

function KSA.unban(secret)
    KSA.ban_list[secret] = nil
    save_banlist()
end

function KSA.promote(secret, new_role)
    KSA.player_roles[secret] = new_role
    save_roles()
end

hooks.register("OnPlayerConnected", "CheckBanList", function(client_id)
    local secret = connections[client_id]:getSecret()
    local ban = KSA.ban_list[secret]
    if not ban then
        return
    end
    local remaining = ban.unban_time - os.time()
    if remaining < 0 then
        KSA.unban(secret)
        return
    end
    connections[client_id]:kick("You've been banned on this server. Time remaining: " .. tostring(remaining / 60) ..
                                    " min")
end)

hooks.register("OnStdIn", "KSA_Run_Lua", function(str)
    if string.sub(str, 1, 7) == "run_lua" then
        load(string.sub(str, 9, #str))()
    end
end)

hooks.register("OnStdIn", "KSA_Test", function(str)
    if not str == "test" then
        return
    end
    print("Hello world!")

end)

hooks.register("OnStdIn", "KSA_Promote", function(str)
    if not string.sub(str, 1, 9) == "set_super" then
        return
    end
    local target = string.sub(str, 11, #str)
    print(target)
    for id, client in pairs(connections) do
        if client:getName() == target then
            KSA.promote(client:getSecret(), "superadmin")
        end
    end
end)

hooks.register("OnChat", "KSA_Process_Commands", function(client_id, str)
    if not string.sub(str, 1, 4) == "/ksa" then
        return
    end
    local args = cmd_parse(str, " ")
    table.remove(args, 1)
    local base = table.remove(args, 1)
    local executor = connections[client_id]
    local command = KSA.commands[base]

    if not command then
        executor:sendChatMessage("KSA: Command not found")
        return
    end

    if not command.roles[KSA.player_roles[executor:getSecret()] or "user"] then
        executor:sendChatMessage("KSA: You're not allowed to use this command")
        return
    end

    command.exec(executor, args)
    return ""
end)


hooks.register("Tick", "KSA_race_tick", function()
    if KSA.race.state == 0 then
        return
    end
    if KSA.race.state == 1 then
        if os.clock() >= KSA.race.start_time then
            print("Race Started")
            KSA.race.state = 2
            KSA.race.countdown_timer = nil
            KSA.race.player:sendLua("core_vehicleBridge.executeAction(getPlayerVehicle(0),'setFreeze', false)")
            KSA.race.player:sendLua("guihooks.message(\"GO!\")")
        else
            local remaining_time = math.floor(KSA.race.start_time - os.clock())
            --print("Race Starts in " .. (remaining_time) .. " seconds :".. (KSA.race.countdown_timer))
            if remaining_time == math.floor(KSA.race.countdown_timer) and KSA.race.countdown_timer > 0 then
                print("Countdown: " .. tostring(KSA.race.countdown_timer))  
                KSA.race.player:sendLua("guihooks.message(\"".. KSA.race.countdown_timer .."!\")")
                KSA.race.countdown_timer = KSA.race.countdown_timer - 1
            end
        end
    
        return
    end
    if KSA.race.state == 2 then
        local distanceToFinish = calculate_distance(vehicles[KSA.race.vehicleid]:getTransform():getPosition(),
            KSA.race.finish)
        -- print("Distance to finish: " .. tostring(distanceToFinish))
        if distanceToFinish < KSA.race.distance_to_finish then

            KSA.race.player:sendLua("guihooks.message(\"Race Finished!\")")
            local base_time = (os.clock()) - KSA.race.start_time
            local total_time = base_time + KSA.race.penalty_time
            local b_minutes = math.floor(base_time / 60)
            local b_seconds = base_time - b_minutes * 60
            local base_str = string.format("%d:%05.2f", b_minutes, b_seconds)
            local t_minutes = math.floor(total_time / 60)
            local t_seconds = total_time - t_minutes * 60
            local total_str = string.format("%d:%05.2f", t_minutes, t_seconds)
            send_message_broadcast("Race Finished!")
            send_message_broadcast("Player: " .. KSA.race.player:getName() .. " Time = " .. base_str .. " (+" ..
                                       tostring(KSA.race.penalty_time) .. "s penalty) Total = " .. total_str)
            local index = add_leaderboard(total_time, KSA.race.player:getName())
            send_message_broadcast("Your position on the leaderboard is: " .. tostring(index))
            KSA.race.player = nil
            KSA.race.start_time = nil
            KSA.race.state = 0
            KSA.race.penalty_time = 0
        end
        return
    end
end)

hooks.register("OnVehicleRemoved", "RacerRemoved", function(vehicle_id, client_id)
    if KSA.race.state == 2 then
        if KSA.race.vehicleid == vehicle_id then
            send_message_broadcast("Race Cancelled!")
            send_message_broadcast("Player: " .. KSA.race.player:getName() .. " Removed Vehicle")
            KSA.race.player = nil
            KSA.race.start_time = nil
            KSA.race.state = 0
            KSA.race.penalty_time = 0
        end
    end
    return value
end)

hooks.register("OnVehicleResetted", "RacerResetted", function(vehicle_id, client_id)
    print("Vehicle reset: " .. tostring(KSA.race.vehicleid) .. " Client ID: " .. tostring(vehicle_id))
    if KSA.race.state == 2 then
        print("in a race")
        if KSA.race.vehicleid == vehicle_id then
            send_message_broadcast("Player: " .. KSA.race.player:getName() .. " Reset Vehicle: + " ..
                                       KSA.race.penalty_for_reset .. "s")
            KSA.race.penalty_time = KSA.race.penalty_for_reset + KSA.race.penalty_time
        end
    end
    return value
end)

load_roles()
load_banlist()
load_leaderboard()
load_raceposition()

print("KISS Multiplayer Race Addon Loaded - Created by CoCoNO" .. " - Map " .. tostring(SERVER_MAP))
