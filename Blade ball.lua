local f = Instance.new("Folder")
f.Name = "BB_Suite_Trajectory"
f.Parent = workspace
for i = 1, 8 do
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(0.3, 0.3, 0.3)
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Material = Enum.Material.Neon
    p.Transparency = 1
    p.Parent = f
end
print("TESTE D: parts no workspace")
