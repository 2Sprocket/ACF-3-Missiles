local Ammo = ACF.RegisterAmmoType("GLATGM", "HEAT")

function Ammo:OnLoaded()
	Ammo.BaseClass.OnLoaded(self)

	self.Name		 = "Gun-Launched Anti-Tank Missile"
	self.Description = "A missile fired from a gun. While slower than a traditional shell, it makes up for that with guidance."
	self.Blacklist = ACF.GetWeaponBlacklist({
		C = true,
		AL = true,
		HW = true,
		MO = true,
		SC = true,
	})
end

function Ammo:Create(Gun, BulletData)
	if Gun:GetClass() == "acf_ammo" then
		ACF_CreateBullet(BulletData)
	else
		local GLATGM 		  = ents.Create("acf_glatgm")
		GLATGM.Distance		  = BulletData.MuzzleVel * 4 * 39.37 -- optical fuze distance
		GLATGM.BulletData	  = BulletData
		GLATGM.DoNotDuplicate = true
		GLATGM.Owner		  = Gun.Owner
		GLATGM.Guidance		  = Gun

		GLATGM:SetAngles(Gun:GetAngles())
		GLATGM:SetPos(Gun:GetAttachment(1).Pos)
		GLATGM:Spawn()
	end
end

function Ammo:UpdateRoundData(ToolData, Data, GUIData)
	GUIData = GUIData or Data

	ACF.UpdateRoundSpecs(ToolData, Data, GUIData)

	local MaxConeAng = math.deg(math.atan((Data.ProjLength - Data.Caliber * 0.002) / (Data.Caliber * 0.05)))
	local LinerAngle = math.Clamp(ToolData.LinerAngle, GUIData.MinConeAng, MaxConeAng)
	local _, ConeArea, AirVol = self:ConeCalc(LinerAngle, Data.Caliber * 0.05)

	local LinerRad	  = math.rad(LinerAngle * 0.5)
	local SlugCaliber = Data.Caliber * 0.1 - Data.Caliber * (math.sin(LinerRad) * 0.5 + math.cos(LinerRad) * 1.5) * 0.05
	local SlugFrArea  = 3.1416 * (SlugCaliber * 0.5) ^ 2
	local ConeVol	  = ConeArea * Data.Caliber * 0.002
	-- Volume of the projectile as a cylinder - Volume of the filler - Volume of the crush cone * density of steel + Volume of the filler * density of TNT + Area of the cone * thickness * density of steel
	local ProjMass	  = math.max(GUIData.ProjVolume - ToolData.FillerMass, 0) * 0.0079 + math.min(ToolData.FillerMass, GUIData.ProjVolume) * ACF.HEDensity * 0.001 + ConeVol * 0.0079
	local MuzzleVel	  = ACF_MuzzleVelocity(Data.PropMass, ProjMass)
	local Energy	  = ACF_Kinetic(MuzzleVel * 39.37, ProjMass, Data.LimitVel)
	local MaxVol	  = ACF.RoundShellCapacity(Energy.Momentum, Data.FrArea, Data.Caliber, Data.ProjLength)

	GUIData.MaxConeAng	 = MaxConeAng
	GUIData.MaxFillerVol = math.max(MaxVol - AirVol - ConeVol, GUIData.MinFillerVol)
	GUIData.FillerVol	 = math.Clamp(ToolData.FillerMass, GUIData.MinFillerVol, GUIData.MaxFillerVol)

	Data.FillerMass		= GUIData.FillerVol * ACF.HEDensity * 0.0007
	Data.BoomFillerMass	= Data.FillerMass * 0.3333 -- Manually update function "pierceeffect" with the divisor
	Data.ProjMass		= math.max(GUIData.ProjVolume - GUIData.FillerVol - AirVol - ConeVol, 0) * 0.0079 + Data.FillerMass + ConeVol * 0.0079
	Data.MuzzleVel		= ACF_MuzzleVelocity(Data.PropMass, Data.ProjMass)
	Data.ConeAng		= LinerAngle
	Data.SlugMass		= ConeVol * 0.0079
	Data.SlugCaliber	= SlugCaliber
	Data.SlugMV			= (Data.FillerMass * 0.5 * ACF.HEPower * math.sin(math.rad(10 + LinerAngle) * 0.5) / Data.SlugMass) ^ ACF.HEATMVScale --keep fillermass/2 so that penetrator stays the same
	Data.SlugDragCoef	= SlugFrArea * 0.0001 / Data.SlugMass
	Data.SlugPenArea	= SlugFrArea ^ ACF.PenAreaMod
	Data.CasingMass		= Data.ProjMass - Data.FillerMass - ConeVol * 0.0079
	Data.DragCoef		= Data.FrArea * 0.0001 / Data.ProjMass

	for K, V in pairs(self:GetDisplayData(Data)) do
		GUIData[K] = V
	end
end

function Ammo:BaseConvert(Crate, ToolData)
	if not ToolData.Projectile then ToolData.Projectile = 0 end
	if not ToolData.Propellant then ToolData.Propellant = 0 end
	if not ToolData.FillerMass then ToolData.FillerMass = 0 end
	if not ToolData.LinerAngle then ToolData.LinerAngle = 0 end

	local Data, GUIData = ACF.RoundBaseGunpowder(ToolData, {})

	GUIData.MinConeAng	 = 0
	GUIData.MinFillerVol = 0

	Data.SlugRicochet	= 500 -- Base ricochet angle (The HEAT slug shouldn't ricochet at all)
	Data.ShovePower		= 0.1
	Data.PenArea		= Data.FrArea ^ ACF.PenAreaMod
	Data.LimitVel		= 100 -- Most efficient penetration speed in m/s
	Data.KETransfert	= 0.1 -- Kinetic energy transfert to the target for movement purposes
	Data.Ricochet		= 60 -- Base ricochet angle
	Data.DetonatorAngle	= 75
	Data.Crate			= Crate
	Data.Detonated		= false
	Data.NotFirstPen	= false

	self:UpdateRoundData(ToolData, Data, GUIData)

	return Data, GUIData
end

function Ammo:GetDisplayData(Data)
	local Energy	= ACF_Kinetic(Data.MuzzleVel * 39.37 + Data.SlugMV * 39.37 , Data.SlugMass, 999999)
	local Fragments	= math.max(math.floor(Data.BoomFillerMass / Data.CasingMass * ACF.HEFrag), 2)

	return {
		MaxPen		= Energy.Penetration / Data.SlugPenArea * ACF.KEtoRHA,
		BlastRadius	= Data.BoomFillerMass ^ 0.33 * 8,
		Fragments	= Fragments,
		FragMass	= Data.CasingMass / Fragments,
		FragVel		= (Data.BoomFillerMass * ACF.HEPower * 1000 / Data.CasingMass / Fragments) ^ 0.5,
	}
end

function Ammo:GetCrateText(BulletData)
	local Text = "Command Link: %s m\nMax Penetration: %s mm\nBlast Radius: %s m\nBlast Energy: %s KJ"
	local Data = self:GetDisplayData(BulletData)

	return Text:format(math.Round(BulletData.MuzzleVel * 4, 2), math.floor(Data.MaxPen), math.Round(Data.BlastRadius, 2), math.floor(BulletData.BoomFillerMass * ACF.HEPower))
end

function Ammo:Detonate(_, Bullet, HitPos)
	ACF_HE(HitPos - Bullet.Flight:GetNormalized() * 3, Bullet.BoomFillerMass, Bullet.CasingMass, Bullet.Owner, Bullet.Filter, Bullet.Gun)

	local DeltaTime = ACF.CurTime - Bullet.LastThink

	Bullet.Detonated  = true
	Bullet.InitTime	  = ACF.CurTime
	Bullet.FuzeLength = 0.005 + 40 / ((Bullet.Flight + Bullet.Flight:GetNormalized() * Bullet.SlugMV * 39.37):Length() * 0.0254)
	Bullet.Pos		  = HitPos
	Bullet.Flight	  = Bullet.Flight + Bullet.Flight:GetNormalized() * Bullet.SlugMV * 39.37
	Bullet.DragCoef	  = Bullet.SlugDragCoef
	Bullet.ProjMass	  = Bullet.SlugMass
	Bullet.Caliber	  = Bullet.SlugCaliber
	Bullet.PenArea	  = Bullet.SlugPenArea
	Bullet.Ricochet	  = Bullet.SlugRicochet
	Bullet.StartTrace = Bullet.Pos - Bullet.Flight:GetNormalized() * math.min(ACF.PhysMaxVel * DeltaTime, Bullet.FlightTime * Bullet.Flight:Length())
	Bullet.NextPos	  = Bullet.Pos + (Bullet.Flight * ACF.Scale * DeltaTime) -- Calculates the next shell position
end

function Ammo:PropImpact(_, Bullet, Target, HitNormal, HitPos, Bone)
	if ACF_Check(Target) then
		if Bullet.Detonated then
			Bullet.NotFirstPen = true

			local Speed	 = Bullet.Flight:Length() / ACF.Scale
			local Energy = ACF_Kinetic(Speed, Bullet.ProjMass, 999999)
			local HitRes = ACF_RoundImpact(Bullet, Speed, Energy, Target, HitPos, HitNormal, Bone)

			if HitRes.Overkill > 0 then
				table.insert(Bullet.Filter, Target) -- "Penetrate" (Ingoring the prop for the retry trace)

				ACF_Spall(HitPos, Bullet.Flight, Bullet.Filter, Energy.Kinetic * HitRes.Loss, Bullet.Caliber, Target.ACF.Armour, Bullet.Owner) --Do some spalling

				Bullet.Flight = Bullet.Flight:GetNormalized() * (Energy.Kinetic * (1 - HitRes.Loss) * ((Bullet.NotFirstPen and ACF.HEATPenLayerMul) or 1) * 2000 / Bullet.ProjMass) ^ 0.5 * 39.37

				return "Penetrated"
			else
				return false
			end
		else
			local Speed	 = Bullet.Flight:Length() / ACF.Scale
			local Energy = ACF_Kinetic(Speed, Bullet.ProjMass - Bullet.FillerMass, Bullet.LimitVel)
			local HitRes = ACF_RoundImpact(Bullet, Speed, Energy, Target, HitPos, HitNormal, Bone)

			if HitRes.Ricochet then
				return "Ricochet"
			else
				self:Detonate(_, Bullet, HitPos)

				return "Penetrated"
			end
		end
	else
		table.insert(Bullet.Filter, Target)

		return "Penetrated"
	end

	return false
end

function Ammo:WorldImpact(_, Bullet, HitPos, HitNormal)
	if not Bullet.Detonated then
		self:Detonate(_, Bullet, HitPos)

		return "Penetrated"
	end

	local Energy = ACF_Kinetic(Bullet.Flight:Length() / ACF.Scale, Bullet.ProjMass, 999999)
	local HitRes = ACF_PenetrateGround(Bullet, Energy, HitPos, HitNormal)

	if HitRes.Penetrated then
		return "Penetrated"
	else
		return false
	end
end

function Ammo:MenuAction(Menu, ToolData, Data)
	local LinerAngle = Menu:AddSlider("Liner Angle", Data.MinConeAng, Data.MaxConeAng, 2)
	LinerAngle:SetDataVar("LinerAngle", "OnValueChanged")
	LinerAngle:TrackDataVar("Projectile")
	LinerAngle:SetValueFunction(function(Panel)
		ToolData.LinerAngle = math.Round(ACF.ReadNumber("LinerAngle"), 2)

		self:UpdateRoundData(ToolData, Data)

		Panel:SetMax(Data.MaxConeAng)
		Panel:SetValue(Data.ConeAng)

		return Data.ConeAng
	end)

	local FillerMass = Menu:AddSlider("Filler Volume", 0, Data.MaxFillerVol, 2)
	FillerMass:SetDataVar("FillerMass", "OnValueChanged")
	FillerMass:TrackDataVar("Projectile")
	FillerMass:TrackDataVar("LinerAngle")
	FillerMass:SetValueFunction(function(Panel)
		ToolData.FillerMass = math.Round(ACF.ReadNumber("FillerMass"), 2)

		self:UpdateRoundData(ToolData, Data)

		Panel:SetMax(Data.MaxFillerVol)
		Panel:SetValue(Data.FillerVol)

		return Data.FillerVol
	end)

	local Tracer = Menu:AddCheckBox("Tracer")
	Tracer:SetDataVar("Tracer", "OnChange")
	Tracer:SetValueFunction(function(Panel)
		ToolData.Tracer = ACF.ReadBool("Tracer")

		self:UpdateRoundData(ToolData, Data)

		ACF.WriteValue("Projectile", Data.ProjLength)
		ACF.WriteValue("Propellant", Data.PropLength)

		Panel:SetText("Tracer : " .. Data.Tracer .. " cm")
		Panel:SetValue(ToolData.Tracer)

		return ToolData.Tracer
	end)

	local RoundStats = Menu:AddLabel()
	RoundStats:TrackDataVar("Projectile", "SetText")
	RoundStats:TrackDataVar("Propellant")
	RoundStats:TrackDataVar("FillerMass")
	RoundStats:TrackDataVar("LinerAngle")
	RoundStats:SetValueFunction(function()
		self:UpdateRoundData(ToolData, Data)

		local Text		= "Command Distance : %s m\nProjectile Mass : %s\nPropellant Mass : %s\nExplosive Mass : %s"
		local MuzzleVel	= math.Round(Data.MuzzleVel * ACF.Scale * 4, 2)
		local ProjMass	= ACF.GetProperMass(Data.ProjMass)
		local PropMass	= ACF.GetProperMass(Data.PropMass)
		local Filler	= ACF.GetProperMass(Data.FillerMass)

		return Text:format(MuzzleVel, ProjMass, PropMass, Filler)
	end)

	local FillerStats = Menu:AddLabel()
	FillerStats:TrackDataVar("FillerMass", "SetText")
	FillerStats:TrackDataVar("LinerAngle")
	FillerStats:SetValueFunction(function()
		self:UpdateRoundData(ToolData, Data)

		local Text	   = "Blast Radius : %s m\nFragments : %s\nFragment Mass : %s\nFragment Velocity : %s m/s"
		local Blast	   = math.Round(Data.BlastRadius, 2)
		local FragMass = ACF.GetProperMass(Data.FragMass)
		local FragVel  = math.Round(Data.FragVel, 2)

		return Text:format(Blast, Data.Fragments, FragMass, FragVel)
	end)

	local Penetrator = Menu:AddLabel()
	Penetrator:TrackDataVar("Projectile", "SetText")
	Penetrator:TrackDataVar("Propellant")
	Penetrator:TrackDataVar("FillerMass")
	Penetrator:TrackDataVar("LinerAngle")
	Penetrator:SetValueFunction(function()
		self:UpdateRoundData(ToolData, Data)

		local Text	   = "Penetrator Caliber : %s mm\nPenetrator Mass : %s\nPenetrator Velocity : %s m/s"
		local Caliber  = math.Round(Data.SlugCaliber * 10, 2)
		local Mass	   = ACF.GetProperMass(Data.SlugMass)
		local Velocity = math.Round(Data.MuzzleVel + Data.SlugMV, 2)

		return Text:format(Caliber, Mass, Velocity)
	end)

	local PenStats = Menu:AddLabel()
	PenStats:TrackDataVar("Projectile", "SetText")
	PenStats:TrackDataVar("Propellant")
	PenStats:TrackDataVar("FillerMass")
	PenStats:TrackDataVar("LinerAngle")
	PenStats:SetValueFunction(function()
		self:UpdateRoundData(ToolData, Data)

		local Text	   = "Penetration : %s mm RHA\nAt 300m : %s mm RHA @ %s m/s\nAt 800m : %s mm RHA @ %s m/s"
		local MaxPen   = math.Round(Data.MaxPen, 2)
		local R1V, R1P = ACF.PenRanging(Data.MuzzleVel, Data.DragCoef, Data.ProjMass, Data.PenArea, Data.LimitVel, 300)
		local R2V, R2P = ACF.PenRanging(Data.MuzzleVel, Data.DragCoef, Data.ProjMass, Data.PenArea, Data.LimitVel, 800)

		R1P = math.Round((ACF_Kinetic((R1V + Data.SlugMV) * 39.37, Data.SlugMass, 999999).Penetration / Data.SlugPenArea) * ACF.KEtoRHA, 2)
		R2P = math.Round((ACF_Kinetic((R2V + Data.SlugMV) * 39.37, Data.SlugMass, 999999).Penetration / Data.SlugPenArea) * ACF.KEtoRHA, 2)

		return Text:format(MaxPen, R1P, R1V, R2P, R2V)
	end)

	Menu:AddLabel("Note: The penetration range data is an approximation and may not be entirely accurate.")
end

ACF.RegisterAmmoDecal("GLATGM", "damage/heat_pen", "damage/heat_rico", function(Caliber) return Caliber * 0.1667 end)
