local characters = {}

local GetPosition = function(folder)
	local data = characters[folder]
	data = data [math.random(#data)]
	local offset = Vector3.new(math.random(-data.size.X/2, data.size.X/2), 0, math.random(-data.size.Z/2, data.size.Z/2))
	return data.cFrame:PointToWorldSpace(offset)
end

for i, folder in ipairs(workspace.Characters:GetChildren()) do
	local data = {}
	for i, part in ipairs(folder:GetChildren()) do
		table.insert(data, {["cFrame"] = part.CFrame, ["size"] = part.Size})
		part:Destroy()
	end
	characters[folder] = data
	folder:SetAttribute("Position", GetPosition(folder))
end

while true do
	for folder, data in pairs(characters) do
		folder:SetAttribute("Position", GetPosition(folder))
		wait(5)
	end
end
