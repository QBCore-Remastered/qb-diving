local isLoggedIn = LocalPlayer.state.isLoggedIn
local zones = {}
local currentArea = 0
local inSellerZone = false
local isWearingSuit = false
local oxygenLevel = 0
local currentDivingLocation = {
    area = 0,
    blip = {
        radius = nil,
        label = nil
    }
}
local currentGear = {
    mask = 0,
    tank = 0,
    oxygen = 0,
    enabled = false
}

-- Functions
local function callCops()
    local call = math.random(1, 3)
    local chance = math.random(1, 3)
    local coords = GetEntityCoords(cache.ped)
    if call ~= chance then return end

    TriggerServerEvent('qb-diving:server:CallCops', coords)
end

local function deleteGear()
	if currentGear.mask ~= 0 then
        DetachEntity(currentGear.mask, false, true)
        DeleteEntity(currentGear.mask)
		currentGear.mask = 0
    end

	if currentGear.tank ~= 0 then
        DetachEntity(currentGear.tank, false, true)
        DeleteEntity(currentGear.tank)
		currentGear.tank = 0
	end
end

local function takeCoral(coral)
    if Config.CoralLocations[currentDivingLocation.area].coords.Coral[coral].PickedUp then return end

    if math.random() > Config.CopsChance then callCops() end

    local times = math.random(2, 5)
    FreezeEntityPosition(cache.ped, true)

    if lib.progressBar({
        duration = times * 1000,
        label = Lang:t("info.collecting_coral"),
        canCancel = true,
        useWhileDead = false,
        disable = {
            move = true,
            car = true,
            mouse = false,
            combat = true
        },
        anim = {
            dict = "weapons@first_person@aim_rng@generic@projectile@thermal_charge@",
            clip = "plant_floor",
            flag = 16
        }
    }) then
        Config.CoralLocations[currentDivingLocation.area].coords.Coral[coral].PickedUp = true
        TriggerServerEvent('qb-diving:server:TakeCoral', currentDivingLocation.area, coral, true)
    end

    ClearPedTasks(cache.ped)
    FreezeEntityPosition(cache.ped, false)
end

local function setDivingLocation(divingLocation)
    if currentDivingLocation.area ~= 0 then
        for k in pairs(Config.CoralLocations[currentDivingLocation.area].coords.Coral) do
            if Config.UseTarget then
                exports['qb-target']:RemoveZone(k)
            else
                if next(zones) then zones[k]:destroy() end
            end
        end
    end

    currentDivingLocation.area = divingLocation

    for _, blip in pairs(currentDivingLocation.blip) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    local coords = Config.CoralLocations[currentDivingLocation.area].coords.Area
    local radiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, 100.0)
    SetBlipRotation(radiusBlip, 0)
    SetBlipColour(radiusBlip, 47)
    currentDivingLocation.blip.radius = radiusBlip

    local labelBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(labelBlip, 597)
    SetBlipDisplay(labelBlip, 4)
    SetBlipScale(labelBlip, 0.7)
    SetBlipColour(labelBlip, 0)
    SetBlipAsShortRange(labelBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Lang:t("info.diving_area"))
    EndTextCommandSetBlipName(labelBlip)
    currentDivingLocation.blip.label = labelBlip
    for k, v in pairs(Config.CoralLocations[currentDivingLocation.area].coords.Coral) do
        if Config.UseTarget then
            exports['qb-target']:AddBoxZone('diving_coral_zone_'..k, v.coords, v.length, v.width, {
                name = 'diving_coral_zone_'..k,
                heading = v.heading,
                debugPoly = false,
                minZ = v.coords.z - 3,
                maxZ = v.coords.z + 2
            }, {
                options = {
                    {
                        label = Lang:t("info.collect_coral"),
                        icon = 'fa-solid fa-water',
                        action = function()
                            takeCoral(k)
                        end
                    }
                },
                distance = 2.0
            })
        else
            zones[k] = BoxZone:Create(v.coords, v.length, v.width, {
                name = 'diving_coral_zone_'..k,
                heading = v.heading,
                debugPoly = false,
                minZ = v.coords.z - 3,
                maxZ = v.coords.z + 2
            })
            zones[k]:onPlayerInOut(function(inside)
                if inside then
                    currentArea = k
                    lib.showTextUI(Lang:t("info.collect_coral_dt"))
                else
                    currentArea = 0
                    lib.hideTextUI()
                end
            end)
        end
    end
end

local function sellCoral()
    LocalPlayer.state:set("invBusy", true, true)
    TaskStartScenarioInPlace(cache.ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)

    if lib.progressBar({
        duration = math.random(2000, 4000),
        label = Lang:t("info.checking_pockets"),
        useWhileDead = false,
        canCancel = true
    }) then
        TriggerServerEvent('qb-diving:server:SellCoral')
    else
        exports.qbx_core:Notify(Lang:t("error.canceled"), "error")
    end

    ClearPedTasks(cache.ped)
    LocalPlayer.state:set("invBusy", false, true)
end

local function createSeller()
    for i, current in pairs(Config.SellLocations) do
        current.model = type(current.model) == 'string' and joaat(current.model) or current.model
        lib.requestModel(current.model)
        local currentCoords = vector4(current.coords.x, current.coords.y, current.coords.z - 1, current.coords.w)
        local ped = CreatePed(0, current.model, currentCoords.x, currentCoords.y, currentCoords.z, currentCoords.w, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        if Config.UseTarget then
            exports['qb-target']:AddTargetEntity(ped, {
                options = {
                    {
                        label = Lang:t("info.sell_coral"),
                        icon = 'fa-solid fa-dollar-sign',
                        action = function()
                            sellCoral()
                        end
                    }
                },
                distance = 2.0
            })
        else
            local zone = BoxZone:Create(current.coords.xyz, current.zoneOptions.length, current.zoneOptions.width, {
                name = 'diving_coral_seller_'..i,
                heading = current.coords.w,
                debugPoly = false,
                minZ = current.coords.z - 1.5,
                maxZ = current.coords.z + 1.5
            })
            zone:onPlayerInOut(function(inside)
                if inside then
                    inSellerZone = true
                    lib.showTextUI(Lang:t("info.sell_coral_dt"))
                else
                    inSellerZone = false
                    lib.hideTextUI()
                end
            end)
        end
    end
end

local function DrawText(text)
	SetTextFont(4)
	SetTextProportional(true)
	SetTextScale(0.0, 0.45)
	SetTextDropshadow(1, 0, 0, 0, 255)
	SetTextEdge(1, 0, 0, 0, 255)
	SetTextDropShadow()
	SetTextOutline()
	BeginTextCommandDisplayText("STRING")
	AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.45, 0.90)
end

-- Events

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local config, area = lib.callback.await('qb-diving:server:GetDivingConfig', false)
    Config.CoralLocations = config
    setDivingLocation(area)
    createSeller()
    isLoggedIn = true
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
end)

RegisterNetEvent('qb-diving:client:NewLocations', function()
    local config, area = lib.callback.await('qb-diving:server:GetDivingConfig', false)
    Config.CoralLocations = config
    setDivingLocation(area)
end)

RegisterNetEvent('qb-diving:client:UpdateCoral', function(area, coral, bool)
    Config.CoralLocations[area].coords.Coral[coral].PickedUp = bool
end)

RegisterNetEvent('qb-diving:client:CallCops', function(coords, msg)
    PlaySound(-1, "Lose_1st", "GTAO_FM_Events_Soundset", false, 0, true)
    TriggerEvent("chatMessage", Lang:t("error.911_chatmessage"), "error", msg)
    local transG = 100
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, 100.0)
    SetBlipSprite(blip, 9)
    SetBlipColour(blip, 1)
    SetBlipAlpha(blip, transG)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Lang:t("info.blip_text"))
    EndTextCommandSetBlipName(blip)

    repeat
        Wait(180 * 4)
        transG -= 1
        SetBlipAlpha(blip, transG)
    until transG == 0

    SetBlipSprite(blip, 2)
    RemoveBlip(blip)
end)

RegisterNetEvent("qb-diving:client:setoxygenlevel", function()
    if oxygenLevel == 0 then
        oxygenLevel = 100 -- oxygenlevel
        exports.qbx_core:Notify(Lang:t("success.tube_filled"), 'success')
        TriggerServerEvent('qb-diving:server:removeItemAfterFill')
        return
    end

    exports.qbx_core:Notify(Lang:t("error.oxygenlevel", {oxygenlevel = oxygenLevel}), 'error')
end)

RegisterNetEvent('qb-diving:client:UseGear', function()
    if isWearingSuit then
        if lib.progressBar({
            duration = 5000,
            label = Lang:t("info.pullout_suit"),
            useWhileDead = false,
            canCancel = true,
            anim = {
                dict = "clothingshirt",
                clip = "try_shirt_positive_d",
                blendIn = 8.0
            }
        }) then
            SetEnableScuba(cache.ped, false)
            SetPedMaxTimeUnderwater(cache.ped, 50.00)
            currentGear.enabled = false
            deleteGear()
            exports.qbx_core:Notify(Lang:t("success.took_out"))
            TriggerServerEvent("InteractSound_SV:PlayOnSource", nil, 0.25)
            isWearingSuit = false
            oxygenLevel = oxygenLevel
        end

        ClearPedTasks(cache.ped)
    else
        if oxygenLevel <= 0 then
            exports.qbx_core:Notify(Lang:t("error.need_otube"), 'error')
            return
        end

        isWearingSuit = true

        if IsPedSwimming(cache.ped) or cache.vehicle then
            exports.qbx_core:Notify(Lang:t("error.not_standing_up"), 'error')
            return
        end

        if lib.progressBar({
            duration = 5000,
            label = Lang:t("info.put_suit"),
            useWhileDead = false,
            canCancel = true,
            anim = {
                dict = "clothingshirt",
                clip = "try_shirt_positive_d",
                blendIn = 8.0
            }
        }) then
            deleteGear()
            local maskModel = `p_d_scuba_mask_s`
            local tankModel = `p_s_scuba_tank_s`
            lib.requestModel(maskModel)
            lib.requestModel(tankModel)
            currentGear.tank = CreateObject(tankModel, 1.0, 1.0, 1.0, true, true, false)
            local bone1 = GetPedBoneIndex(cache.ped, 24818)
            AttachEntityToEntity(currentGear.tank, cache.ped, bone1, -0.25, -0.25, 0.0, 180.0, 90.0, 0.0, true, true, false, false, 2, true)
            currentGear.mask = CreateObject(maskModel, 1.0, 1.0, 1.0, true, true, false)
            local bone2 = GetPedBoneIndex(cache.ped, 12844)
            AttachEntityToEntity(currentGear.mask, cache.ped, bone2, 0.0, 0.0, 0.0, 180.0, 90.0, 0.0, true, true, false, false, 2, true)
            SetEnableScuba(cache.ped, true)
            SetPedMaxTimeUnderwater(cache.ped, 2000.00)
            currentGear.enabled = true
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "breathdivingsuit", 0.25)
            CreateThread(function()
                while currentGear.enabled and IsPedSwimmingUnderWater(cache.ped) do
                    oxygenLevel -= 1
                    if oxygenLevel % 10 == 0 and oxygenLevel ~= 100 then
                        TriggerServerEvent("InteractSound_SV:PlayOnSource", "breathdivingsuit", 0.25)
                    elseif oxygenLevel == 0 then
                        SetEnableScuba(cache.ped, false)
                        SetPedMaxTimeUnderwater(cache.ped, 1.00)
                        currentGear.enabled = false
                        isWearingSuit = false
                        TriggerServerEvent("InteractSound_SV:PlayOnSource", nil, 0.25)
                    end
                    Wait(1000)
                end
            end)
        end

        ClearPedTasks(cache.ped)
    end
end)

-- Threads

CreateThread(function()
    if isLoggedIn then
        local config, area = lib.callback.await('qb-diving:server:GetDivingConfig', false)
        Config.CoralLocations = config
        setDivingLocation(area)
        createSeller()
    end
    if Config.UseTarget then return end
    while isLoggedIn do
        local sleep = 1000
        if currentArea ~= 0 then
            sleep = 0
            if IsControlJustPressed(0, 51) then -- E
                takeCoral(currentArea)
                lib.hideTextUI()
                sleep = 3000
            end
        end

        if inSellerZone then
            sleep = 0
            if IsControlJustPressed(0, 51) then -- E
                sellCoral()
                lib.hideTextUI()
                sleep = 3000
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if currentGear.enabled and isWearingSuit then
            if IsPedSwimmingUnderWater(cache.ped) then
                DrawText(oxygenLevel..'⏱')
            end
        end
        Wait(0)
    end
end)
