-- Rayflare by Vhyse | v1

local Aimbot = {
    Settings = {
        Enabled = false,
        AimPart = "Head", -- E.g., "Head", "HumanoidRootPart"
        AimType = "Camera", -- Options: "Camera", "Cursor"
        Smoothness = 5, -- 0 = Instant Snap (Camera only). Higher = Slower
        
        FOV = {
            Visible = true,
            Radius = 150,
            Color = Color3.fromRGB(255, 255, 255),
            Chroma = false
        },
        
        TeamCheck = {
            Enabled = true,
            IgnoredTeams = {} -- Put team names here as strings (e.g., {"Red", "Blue"})
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

-- Check if Executor supports Drawing API (for FOV Circle)
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

-- Checks if a player's team is in the IgnoredTeams list
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

-- Finds the closest player to the center of the FOV circle
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

-- Calculates the predicted 3D position of the target
local function GetPredictedPosition(targetPart)
    local pos = targetPart.Position
    
    if Aimbot.Settings.Prediction.Enabled then
        local velocity = targetPart.AssemblyLinearVelocity
        local predX, predY = Aimbot.Settings.Prediction.X, Aimbot.Settings.Prediction.Y
        
        -- Dynamic Prediction: Scales the prediction based on how fast they are moving
        if Aimbot.Settings.Prediction.Dynamic then
            local speed = velocity.Magnitude
            -- The faster they move, the further ahead we aim. Divided by a baseline constant to normalize it.
            local dynamicFactor = speed / 150 
            predX = math.clamp(dynamicFactor, 0.05, 0.5)
            predY = math.clamp(dynamicFactor, 0.05, 0.5)
        end
        
        -- Apply prediction strictly to X and Y axes of the velocity
        pos = pos + Vector3.new(velocity.X * predX, velocity.Y * predY, velocity.Z * predX)
    end
    
    return pos
end

-- ========================================== --
--                MAIN LOOP                   --
-- ========================================== --

function Aimbot:Load()
    if self.Connections.RenderLoop then return end -- Prevent double execution
    
    self.Connections.RenderLoop = RunService.RenderStepped:Connect(function(deltaTime)
        local mousePos = UserInputService:GetMouseLocation()

        -- 1. Update FOV Circle
        if self.FOVCircle then
            self.FOVCircle.Visible = self.Settings.FOV.Visible
            self.FOVCircle.Radius = self.Settings.FOV.Radius
            self.FOVCircle.Position = mousePos
            
            if self.Settings.FOV.Chroma then
                self.FOVCircle.Color = Color3.fromHSV(tick() % 5 / 5, 1, 1)
            else
                self.FOVCircle.Color = self.Settings.FOV.Color
            end
        end

        -- 2. Master Toggle Check
        if not self.Settings.Enabled then 
            self.CurrentTarget = nil
            return 
        end

        -- 3. Acquire Target
        self.CurrentTarget = GetClosestTarget()
        
        -- 4. Aim Logic
        if self.CurrentTarget and self.CurrentTarget.Character then
            local targetPart = self.CurrentTarget.Character:FindFirstChild(self.Settings.AimPart)
            if not targetPart then return end
            
            local predictedPos = GetPredictedPosition(targetPart)
            
            if self.Settings.AimType == "Camera" then
                -- [ CAMERA AIM ]
                local currentCFrame = Camera.CFrame
                local targetCFrame = CFrame.new(currentCFrame.Position, predictedPos)
                
                if self.Settings.Smoothness <= 0 then
                    -- Instant Snap
                    Camera.CFrame = targetCFrame
                else
                    -- Smooth lerping (Higher smoothness = smaller alpha = slower aim)
                    local alpha = math.clamp(1 / (self.Settings.Smoothness + 1), 0.01, 1)
                    Camera.CFrame = currentCFrame:Lerp(targetCFrame, alpha)
                end
                
            elseif self.Settings.AimType == "Cursor" then
                -- [ CURSOR AIM ]
                -- mousemoverel is an executor function to simulate physical mouse movement
                if mousemoverel then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
                    if onScreen then
                        local deltaX = screenPos.X - mousePos.X
                        local deltaY = screenPos.Y - mousePos.Y
                        
                        -- Avoid instant snapping for cursor to prevent anti-cheat mouse-teleport flags
                        local smoothFactor = math.max(self.Settings.Smoothness, 1) 
                        
                        mousemoverel(deltaX / smoothFactor, deltaY / smoothFactor)
                    end
                else
                    warn("[ Rayflare ] 'mousemoverel' is not supported by your executor. Cursor aim will not work.")
                    self.Settings.AimType = "Camera" -- Fallback to Camera
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
    -- Disconnect loops
    if self.Connections.RenderLoop then
        self.Connections.RenderLoop:Disconnect()
        self.Connections.RenderLoop = nil
    end
    
    -- Destroy drawings
    if self.FOVCircle then
        self.FOVCircle:Remove()
        self.FOVCircle = nil
    end
    
    self.CurrentTarget = nil
    print("[ Rayflare ] Engine unloaded and memory cleared.")
end

return Aimbot
