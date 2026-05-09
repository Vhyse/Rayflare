-- Rayflare by Vhyse | v1.1

local Aimbot = {
    Settings = {
        Enabled = false,
        AimPart = "Head", -- E.g., "Head", "HumanoidRootPart"
        AimType = "Camera", -- Options: "Camera", "Cursor"
        Smoothness = 5, -- 0 = Instant Snap (Camera only). Higher = Slower
        
        Trigger = {
            TriggerKey = Enum.UserInputType.MouseButton2, -- Default to Right Click
            TriggerMode = "Hold", -- Options: "Always", "Hold", "Toggle"
            IsAiming = false -- Internal state
        },

        FOV = {
            Visible = true,
            Radius = 150,
            Color = Color3.fromRGB(255, 255, 255),
            Chroma = false
        },
        
        TeamCheck = {
            Enabled = true,
            IgnoredTeams = {} 
        },
        
        Prediction = {
            Enabled = false,
            X = 0.1,
            Y = 0.1,
            Dynamic = false
        }
    },
    
    Connections = {},
    CurrentTarget = nil,
    FOVCircle = nil
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ========================================== --
--              INITIALIZATION                --
-- ========================================== --

if Drawing then
    Aimbot.FOVCircle = Drawing.new("Circle")
    Aimbot.FOVCircle.Thickness = 1.5
    Aimbot.FOVCircle.Filled = false
    Aimbot.FOVCircle.Transparency = 1
else
    warn("[ Rayflare ] Executor does not support Drawing API. FOV Circle will not render.")
end

-- ========================================== --
--              UTILITY FUNCTIONS             --
-- ========================================== --

local function IsTeamIgnored(player)
    if not Aimbot.Settings.TeamCheck.Enabled then return false end
    if not player.Team then return false end
    
    for _, teamName in ipairs(Aimbot.Settings.TeamCheck.IgnoredTeams) do
        if player.Team.Name == teamName then
            return true
        end
    end
    return false
end

local function GetClosestTarget()
    local closestPlayer = nil
    local shortestDistance = Aimbot.Settings.FOV.Radius
    local mousePos = UserInputService:GetMouseLocation()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(Aimbot.Settings.AimPart) then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 and not IsTeamIgnored(player) then
                local targetPart = player.Character[Aimbot.Settings.AimPart]
                local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < shortestDistance then
                        shortestDistance = dist
                        closestPlayer = player
                    end
                end
            end
        end
    end
    
    return closestPlayer
end

local function GetPredictedPosition(targetPart)
    local pos = targetPart.Position
    
    if Aimbot.Settings.Prediction.Enabled then
        local velocity = targetPart.AssemblyLinearVelocity
        local predX, predY = Aimbot.Settings.Prediction.X, Aimbot.Settings.Prediction.Y
        
        if Aimbot.Settings.Prediction.Dynamic then
            local speed = velocity.Magnitude
            local dynamicFactor = speed / 150 
            predX = math.clamp(dynamicFactor, 0.05, 0.5)
            predY = math.clamp(dynamicFactor, 0.05, 0.5)
        end
        
        pos = pos + Vector3.new(velocity.X * predX, velocity.Y * predY, velocity.Z * predX)
    end
    
    return pos
end

-- ========================================== --
--                MAIN ENGINE                 --
-- ========================================== --

function Aimbot:Load()
    if self.Connections.RenderLoop then return end 
    
    -- [ INPUT HANDLING FOR TRIGGER ]
    self.Connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if not self.Settings.Enabled then return end

        local isTriggerKey = (input.UserInputType == self.Settings.Trigger.TriggerKey) or (input.KeyCode == self.Settings.Trigger.TriggerKey)
        
        if isTriggerKey then
            if self.Settings.Trigger.TriggerMode == "Toggle" then
                self.Settings.Trigger.IsAiming = not self.Settings.Trigger.IsAiming
            elseif self.Settings.Trigger.TriggerMode == "Hold" then
                self.Settings.Trigger.IsAiming = true
            end
        end
    end)

    self.Connections.InputEnded = UserInputService.InputEnded:Connect(function(input)
        -- Note: We intentionally skip gameProcessed here so the aimbot doesn't get stuck if you release the key over a UI
        local isTriggerKey = (input.UserInputType == self.Settings.Trigger.TriggerKey) or (input.KeyCode == self.Settings.Trigger.TriggerKey)
        
        if isTriggerKey then
            if self.Settings.Trigger.TriggerMode == "Hold" then
                self.Settings.Trigger.IsAiming = false
            end
        end
    end)

    -- [ RENDERING & AIM LOGIC ]
    self.Connections.RenderLoop = RunService.RenderStepped:Connect(function(deltaTime)
        local mousePos = UserInputService:GetMouseLocation()

        -- 1. Update FOV Circle (Always updates if Enabled, even if not actively holding the trigger)
        if self.FOVCircle then
            if self.Settings.Enabled and self.Settings.FOV.Visible then
                self.FOVCircle.Visible = true
                self.FOVCircle.Radius = self.Settings.FOV.Radius
                self.FOVCircle.Position = mousePos
                
                if self.Settings.FOV.Chroma then
                    self.FOVCircle.Color = Color3.fromHSV(tick() % 5 / 5, 1, 1)
                else
                    self.FOVCircle.Color = self.Settings.FOV.Color
                end
            else
                self.FOVCircle.Visible = false
            end
        end

        -- 2. Master Toggle & Trigger Check
        if not self.Settings.Enabled then 
            self.CurrentTarget = nil
            self.Settings.Trigger.IsAiming = false
            return 
        end

        -- If mode is "Always", bypass the trigger system. Otherwise, check if we are aiming.
        local shouldAim = (self.Settings.Trigger.TriggerMode == "Always") or self.Settings.Trigger.IsAiming
        
        if not shouldAim then
            self.CurrentTarget = nil
            return
        end

        -- 3. Acquire Target
        self.CurrentTarget = GetClosestTarget()
        
        -- 4. Aim Manipulation
        if self.CurrentTarget and self.CurrentTarget.Character then
            local targetPart = self.CurrentTarget.Character:FindFirstChild(self.Settings.AimPart)
            if not targetPart then return end
            
            local predictedPos = GetPredictedPosition(targetPart)
            
            if self.Settings.AimType == "Camera" then
                local currentCFrame = Camera.CFrame
                local targetCFrame = CFrame.new(currentCFrame.Position, predictedPos)
                
                if self.Settings.Smoothness <= 0 then
                    Camera.CFrame = targetCFrame
                else
                    local alpha = math.clamp(1 / (self.Settings.Smoothness + 1), 0.01, 1)
                    Camera.CFrame = currentCFrame:Lerp(targetCFrame, alpha)
                end
                
            elseif self.Settings.AimType == "Cursor" then
                if mousemoverel then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
                    if onScreen then
                        local deltaX = screenPos.X - mousePos.X
                        local deltaY = screenPos.Y - mousePos.Y
                        
                        local smoothFactor = math.max(self.Settings.Smoothness, 1) 
                        mousemoverel(deltaX / smoothFactor, deltaY / smoothFactor)
                    end
                else
                    warn("[ Rayflare ] 'mousemoverel' is not supported by your executor. Cursor aim will not work.")
                    self.Settings.AimType = "Camera" 
                end
            end
        end
    end)
    
    print("[ Rayflare ] Engine loaded successfully.")
end

-- ========================================== --
--              DESTRUCTION API               --
-- ========================================== --

function Aimbot:Unload()
    for name, connection in pairs(self.Connections) do
        if connection then
            connection:Disconnect()
        end
    end
    self.Connections = {}
    
    if self.FOVCircle then
        self.FOVCircle:Remove()
        self.FOVCircle = nil
    end
    
    self.CurrentTarget = nil
    self.Settings.Trigger.IsAiming = false
    print("[ Rayflare ] Engine unloaded and memory cleared.")
end

return Aimbot
