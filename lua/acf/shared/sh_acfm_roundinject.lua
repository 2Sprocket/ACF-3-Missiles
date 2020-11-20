local ACF       = ACF
local Guidances = ACF.Classes.Guidances
local Fuzes     = ACF.Classes.Fuzes

hook.Add("ACF_UpdateRoundData", "ACF Missile Ammo", function(_, ToolData, Data)
	if ToolData.Destiny ~= "Missiles" then return end
	if Data.RealMuzzleVel then return end

	Data.RealMuzzleVel = Data.MuzzleVel
	Data.MuzzleVel     = 0
	Data.SlugPenMul    = ACF_GetGunValue(ToolData.Weapon, "PenMul")
end)

hook.Add("ACF_GetDisplayData", "ACF Missile Ammo", function(_, Data)
	if not Data.RealMuzzleVel then return end

	Data.MuzzleVel     = Data.RealMuzzleVel
	Data.RealMuzzleVel = nil
end)

if CLIENT then
	local function GetGuidanceList(Data)
		local Result = {}

		if Data then
			for Guidance in pairs(Data.Guidance) do
				local Info = Guidances[Guidance]

				if Info then
					Result[Guidance] = Info
				end
			end
		end

		return Result
	end

	local function GetFuzeList(Data)
		local Result = {}

		if Data then
			for Fuze in pairs(Data.Fuzes) do
				local Info = Fuzes[Fuze]

				if Info then
					Result[Fuze] = Info
				end
			end
		end

		return Result
	end

	hook.Add("ACF_AddAmmoControls", "ACF Add Missiles Menu", function(Base, ToolData, Ammo, BulletData)
		if ToolData.Destiny ~= "Missiles" then return end

		local Missile      = Base.MissileData
		local GuidanceList = Base:AddComboBox()
		local GuidanceBase = Base:AddPanel("ACF_Panel")
		local FuzeList     = Base:AddComboBox()
		local FuzeBase     = Base:AddPanel("ACF_Panel")

		function GuidanceList:OnSelect(Index, Name, Data)
			if self.Selected == Data then return end

			self:SetText("Guidance: " .. Name)

			self.ListData.Index = Index
			self.Selected = Data

			ACF.WriteValue("Guidance", Data.ID)

			local Guidance = Data()

			if Guidance.OnFirst then
				Guidance:OnFirst("Menu", ToolData)
			end

			GuidanceBase:ClearTemporal(GuidanceList)
			GuidanceBase:StartTemporal(GuidanceList)

			if Guidance.AddMenuControls then
				Guidance:AddMenuControls(GuidanceBase, ToolData, Ammo, BulletData)
			end

			GuidanceBase:AddHelp(Guidance.Description)

			GuidanceBase:EndTemporal(GuidanceList)

			BulletData.Guidance = Guidance
		end

		function FuzeList:OnSelect(Index, Name, Data)
			if self.Selected == Data then return end

			self:SetText("Fuze: " .. Name)

			self.ListData.Index = Index
			self.Selected = Data

			ACF.WriteValue("Fuze", Data.ID)

			local Fuze = Data()

			if Fuze.OnFirst then
				Fuze:OnFirst("Menu", ToolData)
			end

			FuzeBase:ClearTemporal(FuzeList)
			FuzeBase:StartTemporal(FuzeList)

			if Fuze.AddMenuControls then
				Fuze:AddMenuControls(FuzeBase, ToolData, Ammo, BulletData)
			end

			FuzeBase:AddHelp(Fuze.Description)

			FuzeBase:EndTemporal(FuzeList)

			BulletData.Fuze = Fuze
		end

		ACF.LoadSortedList(GuidanceList, GetGuidanceList(Missile), "Name")
		ACF.LoadSortedList(FuzeList, GetFuzeList(Missile), "Name")
	end)

	--[[
	-- Unused, uncomment if needed
	hook.Add("ACF_AddAmmoInformation", "ACF Add Missiles Menu", function(Base, ToolData, Ammo, BulletData)
		if ToolData.Destiny ~= "Missiles" then return end

		local Guidance     = BulletData.Guidance
		local Fuze         = BulletData.Fuze
		local GuidanceBase = Base:AddPanel("ACF_Panel")
		local FuzeBase     = Base:AddPanel("ACF_Panel")
	end)
	]]
else
	local Display      = "%s: %s%s\n\n%s: %s%s"
	local AllowedClass = {
		acf_missile = true,
		acf_ammo = true,
	}

	local function DecodeData(String, Classes)
		if not isstring(String) then return end

		local Arguments = {}
		local Name

		-- Parsing the old string
		for Part in string.gmatch(String, "[^:]+") do
			if not Name and Classes[Part] then
				Name = Part
			else
				local Key = string.match(Part, "^[^=]+")
				local Value = string.match(Part, "[^=]+$")

				if Key and Value then
					Arguments[string.upper(Key)] = tonumber(Value) or 0
				end
			end
		end

		return Name, next(Arguments) and Arguments
	end

	local function ConcatConfig(tbl)
		local Result = ""

		for K, V in pairs(tbl) do
			Result = Result .. "\n" .. tostring(K) .. ": " .. tostring(V)
		end

		return Result
	end

	hook.Add("ACF_VerifyData", "ACF Missile Ammo", function(EntClass, Data, ...)
		if not AllowedClass[EntClass] then return end
		if Data.Destiny ~= "Missiles" then return end

		do -- Verifying guidance
			if not Data.Guidance then -- Porting old guidance data
				Data.Guidance = DecodeData(Data.RoundData7, Guidances) or "Dumb"
			end

			local Allowed  = ACF_GetGunValue(Data.Weapon, "Guidance")
			local Guidance = Guidances[Data.Guidance]

			if not (Guidance and Allowed[Data.Guidance]) then
				Data.Guidance = "Dumb"

				Guidance = Guidances.Dumb
			end

			if Guidance.VerifyData then
				Guidance:VerifyData(EntClass, Data, ...)
			end
		end

		do -- Fuze verification
			if not Data.Fuze then -- Porting old fuze data
				local Name, Arguments = DecodeData(Data.RoundData8, Fuzes)

				Data.Fuze = Name or "Contact"
				Data.FuzeArgs = Arguments
			end

			local Allowed = ACF_GetGunValue(Data.Weapon, "Fuzes")
			local Fuze    = Fuzes[Data.Fuze]

			if not (Fuze and Allowed[Data.Fuze]) then
				Data.Fuze = "Contact"

				Fuze = Fuzes.Contact
			end

			if Fuze.VerifyData then
				Fuze:VerifyData(EntClass, Data, ...)
			end
		end
	end)

	hook.Add("ACF_OnAmmoFirst", "ACF Missile Ammo", function(_, Entity, Data, ...)
		if Data.Destiny ~= "Missiles" then return end
		if Entity.IsRefill then return end

		local Guidance = Guidances[Data.Guidance]()
		local Fuze     = Fuzes[Data.Fuze]()

		if Guidance.OnFirst then
			Guidance:OnFirst(Entity, Data, ...)
		end

		if Fuze.OnFirst then
			Fuze:OnFirst(Entity, Data, ...)
		end

		Guidance:Configure(Entity)
		Fuze:Configure(Entity)

		Entity.IsMissileAmmo = true
		Entity.GuidanceData  = Guidance
		Entity.FuzeData      = Fuze
	end)

	hook.Add("ACF_OnAmmoLast", "ACF Missile Ammo", function(_, Entity)
		if not Entity.IsMissileAmmo then return end

		local Guidance = Entity.GuidanceData
		local Fuze     = Entity.FuzeData

		if Guidance.OnLast then
			Guidance:OnLast(Entity)
		end

		if Fuze.OnLast then
			Fuze:OnLast(Entity)
		end

		Entity.IsMissileAmmo = nil
		Entity.GuidanceData  = nil
		Entity.FuzeData      = nil
		Entity.Guidance      = nil
		Entity.Fuze          = nil
	end)

	ACF.AddEntityArguments("acf_ammo", "Guidance", "Fuze") -- Adding extra info to ammo crates

	ACF.RegisterOverlayText("acf_ammo", "ACF Missile Overlay", function(Crate)
		if not Crate.IsMissileAmmo then return end

		local Guidance     = Crate.GuidanceData
		local Fuze         = Crate.FuzeData
		local GuidanceText = ConcatConfig(Guidance:GetDisplayConfig())
		local FuzeText     = ConcatConfig(Fuze:GetDisplayConfig())

		return Display:format("Guidance", Guidance.Name, GuidanceText, "Fuze", Fuze.Name, FuzeText)
	end)
end
