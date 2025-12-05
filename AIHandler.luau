local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local detectionRadius = 50
local chasePathUpdateCooldown = 0
local idlePathUpdateCooldown = 2
local stuckDistanceThreshold = 3

local function getNearestPlayer(model, maxDistance)
	local nearestPlayer = nil
	local shortestDistance = maxDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local distance = (model.PrimaryPart.Position - character.HumanoidRootPart.Position).Magnitude
			if distance < shortestDistance then
				nearestPlayer = character
				shortestDistance = distance
			end
		end
	end
	return nearestPlayer
end

local function applyDamage(playerHumanoid, damageAmount)
	if playerHumanoid and playerHumanoid.Health > 0 then
		playerHumanoid:TakeDamage(damageAmount)
	end
end

local charactersFolder = Workspace:WaitForChild("Characters")

for _, folder in ipairs(charactersFolder:GetChildren()) do
	local model = game.ReplicatedStorage.Characters[folder.Name]:Clone()

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("Model", model.Name, "does not have a Humanoid component.")
		continue
	end

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
		if not model.PrimaryPart then
			warn("Model", model.Name, "does not have a suitable PrimaryPart.")
			continue
		end
	end

	local initialPosition = folder:GetAttribute("Position")
	if not initialPosition or typeof(initialPosition) ~= "Vector3" then
		warn("Folder", folder.Name, "does not have a valid 'Position' attribute.")
		continue
	end

	local spawnOffset = Vector3.new(0, 5, 0)
	local spawnPosition = initialPosition + spawnOffset

	model:SetPrimaryPartCFrame(CFrame.new(spawnPosition))
	model.Parent = Workspace

	wait(0.1)

	local function ensureOnGround(model)
		local rayOrigin = model.PrimaryPart.Position
		local rayDirection = Vector3.new(0, -10, 0)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {model}
		raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if raycastResult then
			local groundPosition = raycastResult.Position
			model:SetPrimaryPartCFrame(CFrame.new(groundPosition + Vector3.new(0, 2, 0)))
		else
			warn("NPC", model.Name, "is not properly grounded.")
		end
	end

	ensureOnGround(model)

	local animator = Instance.new("Animator", humanoid)
	local idleAnimation = animator:LoadAnimation(game.ReplicatedStorage.Animations.IdleAnimation)
	local runAnimation = animator:LoadAnimation(game.ReplicatedStorage.Animations.RunAnimation)
	local jumpAnimation = animator:LoadAnimation(game.ReplicatedStorage.Animations.JumpAnimation)
	local climbAnimation = animator:LoadAnimation(game.ReplicatedStorage.Animations.ClimbAnimation)

	idleAnimation.Priority = Enum.AnimationPriority.Idle
	runAnimation.Priority = Enum.AnimationPriority.Movement
	jumpAnimation.Priority = Enum.AnimationPriority.Action
	climbAnimation.Priority = Enum.AnimationPriority.Action
	jumpAnimation.Looped = false
	climbAnimation.Looped = true

	idleAnimation:Play()
	local waypoints = {}
	local waypointIndex = 0
	local isMoving = false
	local isJumping = false
	local isClimbing = false

	local pathId = 0
	local lastPathUpdate = 0

	local function stopAllAnimations()
		idleAnimation:Stop()
		runAnimation:Stop()
		jumpAnimation:Stop()
		climbAnimation:Stop()
	end

	local function playIdleAnimation()
		if not idleAnimation.IsPlaying then
			stopAllAnimations()
			idleAnimation:Play()
		end
	end

	local function playRunAnimation()
		if not runAnimation.IsPlaying then
			stopAllAnimations()
			runAnimation:Play()
		end
	end

	local function playJumpAnimation()
		if not jumpAnimation.IsPlaying then
			stopAllAnimations()
			jumpAnimation:Play()
		end
	end

	local function playClimbAnimation()
		if not climbAnimation.IsPlaying then
			stopAllAnimations()
			climbAnimation:Play()
		end
	end

	local function initiateJump()
		if not isJumping and not isClimbing then
			isJumping = true
			playJumpAnimation()
			humanoid.Jump = true
			delay(0.5, function()
				isJumping = false
				playRunAnimation()
			end)
		end
	end

	local function initiateClimb(waypoint)
		if not isClimbing and not isJumping then
			isClimbing = true
			playClimbAnimation()
			humanoid:MoveTo(waypoint.Position)
		end
	end

	local function isWaypointOnGround(position)
		local rayOrigin = position + Vector3.new(0, 2, 0)
		local rayDirection = Vector3.new(0, -5, 0)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {model}
		raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		return raycastResult ~= nil
	end

	local MoveToFinishedConnection = nil
	local debounceTable = {}

	local function onTouched(hit)
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)
		if player and player.Character and player.Character:FindFirstChild("Humanoid") then
			local playerHumanoid = player.Character.Humanoid
			local playerId = player.UserId

			if not debounceTable[playerId] then
				debounceTable[playerId] = true
				applyDamage(playerHumanoid, 0)
				delay(1, function()
					debounceTable[playerId] = false
				end)
			end
		end
	end

	model.PrimaryPart.Touched:Connect(onTouched)

	local function MoveToNextWaypoint()
		waypointIndex += 1
		local waypoint = waypoints[waypointIndex]
		if not waypoint then
			playIdleAnimation()
			isMoving = false
			return
		end

		if not isWaypointOnGround(waypoint.Position) then
			MoveToNextWaypoint()
			return
		end

		if waypoint.Action == Enum.PathWaypointAction.Jump then
			initiateJump()
			humanoid:MoveTo(waypoint.Position)
		elseif waypoint.Action == Enum.PathWaypointAction.Custom then
			local previousWaypoint = waypoints[waypointIndex - 1]
			if previousWaypoint then
				local elevationChange = waypoint.Position.Y - previousWaypoint.Position.Y
				if elevationChange > 3 then
					initiateClimb(waypoint)
				elseif elevationChange >= 0 then
					playRunAnimation()
					humanoid:MoveTo(waypoint.Position)
				else
					playRunAnimation()
					isMoving = false
				end
			else
				playRunAnimation()
				humanoid:MoveTo(waypoint.Position)
			end
		else
			playRunAnimation()
			humanoid:MoveTo(waypoint.Position)
		end

		if MoveToFinishedConnection then
			MoveToFinishedConnection:Disconnect()
		end

		MoveToFinishedConnection = humanoid.MoveToFinished:Connect(function(reached)
			if isClimbing then
				isClimbing = false
				climbAnimation:Stop()
				playRunAnimation()
				MoveToNextWaypoint()
				return
			end

			if reached then
				MoveToNextWaypoint()
			else
				local waypoint = waypoints[waypointIndex]
				if waypoint then
					local distance = (model.PrimaryPart.Position - waypoint.Position).Magnitude
					if distance < stuckDistanceThreshold then
						local isWaypointAbove = waypoint.Position.Y > model.PrimaryPart.Position.Y
						if isWaypointAbove then
							initiateJump()
						else
							playRunAnimation()
							isMoving = false
						end
					else
						MoveToNextWaypoint()
					end
				end
			end
		end)
	end

	local function updatePath(newTargetPosition, cooldown)
		if isClimbing or isJumping then return end
		if tick() - lastPathUpdate < cooldown then return end
		lastPathUpdate = tick()

		local humanoidState = humanoid:GetState()
		if humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.Jumping then
			return
		end

		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			AgentMaxSlope = 45,
			AgentJumpHeight = 10,
			WaypointSpacing = 4,
			Costs = { ["Water"] = 20, ["Ladder"] = 1 },
			AgentCanClimb = true
		})

		local success, err = pcall(function()
			path:ComputeAsync(model.PrimaryPart.Position, newTargetPosition)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
			waypointIndex = 1
			isMoving = true
			pathId = pathId + 1

			MoveToNextWaypoint()
		else
			playIdleAnimation()
		end
	end

	RunService.Heartbeat:Connect(function()
		local nearestPlayer = getNearestPlayer(model, detectionRadius)
		local newTargetPosition

		if nearestPlayer then
			newTargetPosition = nearestPlayer.HumanoidRootPart.Position
			updatePath(newTargetPosition, chasePathUpdateCooldown)
		else
			newTargetPosition = folder:GetAttribute("Position")
			updatePath(newTargetPosition, idlePathUpdateCooldown)
		end
	end)
end
