--[=[
	Bridges attributes and serializable data table. It's typical to need to define data in 3 ways.

	1. Attributes on an instance for replication
	2. Tables for Lua configuration
	3. Within AttributeValues for writing regular code

	Providing all 3

	@class AdorneeData
]=]

local require = require(script.Parent.loader).load(script)

local AdorneeDataEntry = require("AdorneeDataEntry")
local AdorneeDataValue = require("AdorneeDataValue")
local AttributeUtils = require("AttributeUtils")
local t = require("t")

local AdorneeData = {}
AdorneeData.ClassName = "AdorneeData"
AdorneeData.__index = AdorneeData

--[=[
	Attribute data specification

	@param prototype any
	@return AdorneeData<T>
]=]
function AdorneeData.new(prototype)
	local self = setmetatable({}, AdorneeData)

	self._fullPrototype = assert(prototype, "Bad prototype")
	self._attributePrototype = {}
	self._defaultValuesPrototype = {}
	self._valueObjectPrototype = {}

	for key, item in pairs(self._fullPrototype) do
		if AdorneeDataEntry.isAdorneeDataEntry(item) then
			local default = item:GetDefaultValue()
			self._defaultValuesPrototype[key] = default
			self._valueObjectPrototype[key] = item
		else
			self._defaultValuesPrototype[key] = item
			self._attributePrototype[key] = item
		end
	end

	return self
end

--[=[
	Returns true if the data is valid data, otherwise returns false and an error.

	@param data any
	@return boolean
	@return string -- Error message
]=]
function AdorneeData:IsStrictData(data)
	return self:GetStrictTInterface()(data)
end

--[=[
	Validates and creates a new data table for the data that is readonly and frozen

	@param data TStrict
	@return TStrict
]=]
function AdorneeData:CreateStrictData(data)
	assert(self:IsStrictData(data))

	return table.freeze(table.clone(data))
end

--[=[
	Validates and creates a new data table that is readonly. This table will have all values or
	the defaults

	@param data T
	@return T
]=]
function AdorneeData:CreateFullData(data)
	assert(self:IsData(data))

	local result = table.clone(self._defaultValuesPrototype)

	for key, value in pairs(data) do
		result[key] = value
	end

	return table.freeze(table.clone(result))
end

--[=[
	Validates and creates a new data table that is readonly and frozen, but for partial
	data.

	The  data can just be part of the attributes.

	@param data TPartial
	@return TPartial
]=]
function AdorneeData:CreateData(data)
	assert(self:IsData(data))

	return table.freeze(table.clone(data))
end

--[=[
	Observes the attribute table for adornee

	@param adornee Instance
	@return Observable<TStrict>
]=]
function AdorneeData:Observe(adornee)
	assert(typeof(adornee) == "Instance", "Bad adornee")

	return self:CreateAdorneeDataValue(adornee):Observe(adornee)
end

--[=[
	Gets attribute table for the data

	@param adornee Instance
	@return AdorneeDataValue
]=]
function AdorneeData:CreateAdorneeDataValue(adornee)
	assert(typeof(adornee) == "Instance", "Bad adornee")

	local attributeTableValue = AdorneeDataValue.new(adornee, self._fullPrototype)

	return attributeTableValue
end

--[=[
	Gets the attributes for the adornee

	@param adornee Instance
	@return TStrict
]=]
function AdorneeData:GetAttributes(adornee)
	assert(typeof(adornee) == "Instance", "Bad adornee")

	local data = {}
	for key, defaultValue in pairs(self._attributePrototype) do
		local result = adornee:GetAttribute(key)
		if result == nil then
			result = defaultValue
		end
		data[key] = result
	end

	-- TODO: Avoid additional allocation
	for key, value in pairs(self._valueObjectPrototype) do
		data[key] = value:CreateValueObject(adornee).Value
	end

	return self:CreateStrictData(data)
end

--[=[
	Sets the attributes for the adornee

	@param adornee Instance
	@param data T
]=]
function AdorneeData:SetAttributes(adornee, data)
	assert(typeof(adornee) == "Instance", "Bad adornee")
	assert(self:IsData(data))

	local attributeTable = self:CreateAdorneeDataValue(adornee)
	for key, value in pairs(data) do
		attributeTable[key].Value = value
	end
end

--[=[
	Sets the attributes for the adornee

	@param adornee Instance
	@param data TStrict
]=]
function AdorneeData:SetStrictAttributes(adornee, data)
	assert(typeof(adornee) == "Instance", "Bad adornee")
	assert(self:IsStrictData(data))

	for key, _ in pairs(self._attributePrototype) do
		adornee:SetAttribute(key, data[key])
	end

	-- TODO: Avoid additional allocation
	for key, value in pairs(self._valueObjectPrototype) do
		value:CreateValueObject(adornee).Value = data[key]
	end
end

--[=[
	Initializes the attributes for the adornee

	@param adornee Instance
	@param data T
]=]
function AdorneeData:InitAttributes(adornee, data)
	assert(typeof(adornee) == "Instance", "Bad adornee")
	assert(self:IsData(data))

	for key, defaultValue in pairs(self._attributePrototype) do
		if adornee:GetAttribute(key) == nil then
			if data[key] ~= nil then
				adornee:SetAttribute(key, data[key])
			else
				adornee:SetAttribute(key, defaultValue)
			end
		end
	end

	-- TODO: Avoid additional allocation
	for key, value in pairs(self._valueObjectPrototype) do
		local valueObject = value:CreateValueObject(adornee)
		if valueObject == nil then
			if data[key] ~= nil then
				valueObject.Value = data[key]
			end
		end
	end
end

--[=[
	Gets a strict interface which will return true if the value is a partial interface and
	false otherwise.

	@return function
]=]
function AdorneeData:GetStrictTInterface()
	if self._fullInterface then
		return self._fullInterface
	end

	self._fullInterface = t.strictInterface(self:_getOrCreateTypeInterfaceList())
	return self._fullInterface
end

--[=[
	Gets a [t] interface which will return true if the value is a partial interface, and
	false otherwise.

	@return function
]=]
function AdorneeData:GetTInterface()
	if self._interface then
		return self._interface
	end

	local interfaceList = {}
	for key, value in pairs(self:_getOrCreateTypeInterfaceList()) do
		interfaceList[key] = t.optional(value)
	end

	self._interface = t.strictInterface(interfaceList)
	return self._interface
end

--[=[
	Returns true if the data is valid partial data, otherwise returns false and an error.

	@param data any
	@return boolean
	@return string -- Error message
]=]
function AdorneeData:IsData(data)
	return self:GetTInterface()(data)
end

function AdorneeData:_getOrCreateTypeInterfaceList()
	if self._typeInterfaceList then
		return self._typeInterfaceList
	end

	local interfaceList = {}

	for key, value in pairs(self._fullPrototype) do
		if AdorneeDataEntry.isAdorneeDataEntry(value) then
			interfaceList[key] = value:GetStrictInterface()
		else
			local valueType = typeof(value)
			assert(AttributeUtils.isValidAttributeType(valueType), "Not a valid value type")

			interfaceList[key] = t.typeof(valueType)
		end
	end

	self._typeInterfaceList = interfaceList
	return interfaceList
end

return AdorneeData