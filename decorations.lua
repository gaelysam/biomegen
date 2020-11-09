-- decorations.lua

local emptynodes = {
	air = true,
	ignore = true,
}

local function generateDecoSimple(deco, vm, pr, p, ceiling)
	print(deco.name, minetest.pos_to_string(p))
	local emin, emax = vm:get_emerged_area()

	local place_offset_y = deco.place_offset_y
	if ceiling then
		if p.y - place_offset_y - deco.height_max < emin.y then
			return 0
		elseif p.y - 1 - place_offset_y > emax.y then
			return 0
		end
	else
		if p.y + place_offset_y + deco.height_max > emax.y then
			return 0
		elseif p.y + 1 + place_offset_y < emin.y then
			return 0
		end
	end

	local decos = deco.decoration
	local nodename = decos[pr:next(1,#decos)]
	local height = deco.vary_height and pr:next(deco.height, deco.height_max) or deco.height
	local param2 = deco.vary_param2 and pr:next(deco.param2, deco.param2_max) or deco.param2
	local force_placement = deco.flags.force_placement == true

	local direction = ceiling and -1 or 1
	p.y = p.y + place_offset_y * direction
	for i=1, height do
		p.y = p.y + direction
		local node = vm:get_node_at(p)
		if not force_placement and not emptynodes[node.name] then
			break
		end
		node.name = nodename
		node.param2 = param2
		vm:set_node_at(p, node)
	end

	return 1
end

local function get_schematic_size(schem)
	if type(schem) == "table" then
		return schem.size
	elseif type(schem) == "string" then
		local mts = io.open(schem)
		if not mts then
			return {x=0, y=0, z=0}
		end
		mts:seek('set', 6)
		local sx1, sx2, sy1, sy2, sz1, sz2 = mts:read(6):byte()
		mts:close()
		return {x=sx1*256+sx2, y=sy1*256+sy2, z=sz1*256+sz2}
	end

	return {x=0, y=0, z=0}
end

local function generateDecoSchematic(deco, vm, pr, p, ceiling)
	print(deco.name, minetest.pos_to_string(p))
	local force_placement = deco.flags.force_placement == true
	local direction = ceiling and -1 or 1
	if not deco.flags.place_center_y then
		if ceiling then
			local size = get_schematic_size(schem)
			p.y = p.y - deco.place_offset_y - size.y + 1
		else
			p.y = p.y + deco.place_offset_y
		end
	end

	minetest.place_schematic_on_vmanip(vm, p, deco.schematic, deco.rotation, deco.replacements, force_placement, deco.schem_flags)

	return 1
end

local function parse_node_list(raw_list)
	if not raw_list then
		return {}
	end
	local ilist = {}
	if type(raw_list) == "string" then
		raw_list = {raw_list}
	end

	local cid = minetest.get_content_id
	for i, node in ipairs(raw_list) do
		if node:sub(1, 6) == "group:" then
			local groupname = node:sub(7, -1)
			for name, ndef in pairs(minetest.registered_nodes) do
				if ndef.groups and ndef.groups[groupname] and ndef.groups[groupname] > 0 then
					ilist[cid(name)] = true
				end
			end
		else
			ilist[cid(node)] = true
		end
	end

	return ilist
end

local function make_decolist()
	local decos = {}
	
	local cid = minetest.get_content_id

	for i, a in pairs(minetest.registered_decorations) do
		local b = {}
		decos[i] = b

		b.name = a.name or "unnamed " .. i

		b.deco_type = a.deco_type or "simple"

		b.place_on = parse_node_list(a.place_on)

		b.sidelen = a.sidelen or 8
		b.fill_ratio = a.fill_ratio or 0.02
		local np = a.noise_params
		b.use_noise = false
		if np then
			b.use_noise = true
			b.noise = minetest.get_perlin(np)
		end

		b.use_biomes = false
		if a.biomes then
			local biomes_raw = a.biomes
			b.use_biomes = true
			if type(biomes_raw) == "table" then
				local biomes = {}
				b.biomes = biomes
				for i, biome in pairs(biomes_raw) do
					if type(biome) == "number" then
						biome = minetest.get_biome_name(biome)
					end
					biomes[biome] = true
				end
			else
				if type(biomes_raw) == "number" then
					biomes_raw = minetest.get_biome_name(biomes_raw)
				end
				b.biomes = {[biomes_raw] = true}
			end
		end

		b.y_min = a.y_min or -31000
		b.y_max = a.y_max or 31000

		b.spawn_by = parse_node_list(a.spawn_by)
		b.num_spawn_by = a.num_spawn_by or 0

		local flags_raw = a.flags or ""
		local flags = {}
		b.flags = flags
		for i, flag in ipairs(flags_raw:split()) do
			flag = flag:trim()
			local status = true
			if flag:sub(1,2) == "no" then
				flag = flag:sub(3,-1)
				status = false
			end
			flags[flag] = status
		end

		if b.deco_type == "simple" then
			local deco = a.decoration
			if type(deco) == "string" then
				deco = {deco}
			end
			b.decoration = deco
			b.height = a.height or 1
			b.height_max = math.max(a.height_max or b.height, b.height)
			b.vary_height = b.height < b.height_max
			b.param2 = a.param2 or 0
			b.param2_max = math.max(a.params2_max or b.param2, b.height)
			b.vary_param2 = b.param2 < b.param2_max
			b.place_offset_y = a.place_offset_y or 0
			b.generate = generateDecoSimple
		elseif b.deco_type == "schematic" then
			b.schematic = a.schematic
			b.replacements = a.replacements or {}
			b.rotation = a.rotation or 0
			b.place_offset_y = a.place_offset_y or 0

			local schem_flags = {}
			for _, flag in ipairs({'place_center_x', 'place_center_y', 'place_center_z'}) do
				if flags[flag] then
					table.insert(schem_flags, flag)
				end
			end
			b.schem_flags = table.concat(schem_flags, ',')

			b.generate = generateDecoSchematic
		end
	end

	return decos
end

return make_decolist
