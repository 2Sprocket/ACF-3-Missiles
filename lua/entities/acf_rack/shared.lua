-- shared.lua

DEFINE_BASECLASS("base_wire_entity")

ENT.Type        	= "anim"
ENT.Base        	= "base_wire_entity"
ENT.PrintName 		= "XCF Rack"
ENT.Author 			= "Bubbus"
ENT.Contact 		= "splambob@googlemail.com"
ENT.Purpose		 	= "Because launch tubes aren't cool enough."
ENT.Instructions 	= "Point towards face for removal of face.  Point away from face for instant fake tan (then removal of face)."

ENT.Spawnable 		= false
ENT.AdminOnly		= false
ENT.AdminSpawnable = false

function ENT:GetOverlayText()
	local name          = self:GetNWString("WireName")
	local GunType       = self:GetNWString("GunType")
	local Ammo          = self:GetNWInt("Ammo")
	local FireRate      = self:GetNWFloat("Interval")
	local Reload        = self:GetNWFloat("Reload")
	local ReloadBonus   = self:GetNWFloat("ReloadBonus")
	local Status        = self:GetNWString("Status")

	local txt = GunType .. " (" .. Ammo .. " left) \n" ..
				"Fire interval: " .. (math.Round(FireRate, 2)) .. " sec\n" ..
				"Reload interval: " .. (math.Round(Reload, 2)) .. " sec" .. (ReloadBonus > 0 and (" (-" .. math.floor(ReloadBonus * 100) .. "%)") or "") ..
				((Status and Status ~= "") and ("\n - " .. Status .. " - ") or "")

	if CPPI and not game.SinglePlayer() then
		local Owner = self:CPPIGetOwner():GetName()

		txt = txt .. "\n(" .. Owner .. ")"
	end

	if name and name ~= "" then
		if (txt == "") then
			return "- " .. name .. " -"
		end

		return "- " .. name .. " -\n" .. txt
	end

	return txt
end

function ENT:GetMuzzle(shot, missile)
	shot = (shot or 0) + 1

	local trymissile = "missile" .. shot
	local attach = self:LookupAttachment(trymissile)

	if attach ~= 0 then return attach, self:GetMunitionAngPos(missile, attach, trymissile) end

	trymissile = "missile1"
	attach = self:LookupAttachment(trymissile)

	if attach ~= 0 then return attach, self:GetMunitionAngPos(missile, attach, trymissile) end

	trymissile = "muzzle"
	attach = self:LookupAttachment(trymissile)

	if attach ~= 0 then return attach, self:GetMunitionAngPos(missile, attach, trymissile) end

	return 0, {Pos = self:GetPos(), Ang = self:GetAngles()}
end

function ENT:GetMunitionAngPos(missile, attach, attachname)
	local angpos

	if attach ~= 0 then
		angpos = self:GetAttachment(attach)
	else
		angpos = {Pos = self:GetPos(), Ang = self:GetAngles()}
	end

	local guns = list.Get("ACFEnts").Guns
	local gun = guns[missile.BulletData.Id]

	if not gun then return angpos end

	local offset = (gun.modeldiameter or gun.caliber) / (2.54 * 2)
	local rack = ACF.Weapons.Rack[self.Id]

	if not rack then return angpos end

	local mountpoint = rack.mountpoints[attachname] or {["offset"] = Vector(), ["scaledir"] = Vector(0, 0, -1)}

	if not IsValid(self:GetParent()) then
		angpos.Pos = angpos.Pos + (self:LocalToWorld(mountpoint.offset) - self:GetPos()) + (self:LocalToWorld(mountpoint.scaledir) - self:GetPos()) * offset
	else
		if table.Count(self:GetAttachments()) ~= 1 then
			offset = gun.modeldiameter or gun.caliber * 2
		end

		angpos.Pos =  Vector() + (mountpoint.offset - Vector()) + (mountpoint.scaledir - Vector()) * offset
	end

	return angpos
end
