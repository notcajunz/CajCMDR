--[[
	Thin DataStore wrapper. Every call is wrapped in pcall with retries, and everything falls back to an
	in-memory table when DataStores are unavailable (for example Studio without API access), so a missing
	DataStore never breaks a command.
]]

const DataStoreService = game:GetService("DataStoreService")

const RETRIES = 3

const Store = {}

const stores: { [string]: DataStore } = {}
const memory: { [string]: { [string]: any } } = {}
local available: boolean? = nil

const function memoryFor(name: string): { [string]: any }
	if not memory[name] then
		memory[name] = {}
	end

	return memory[name]
end

const function checkAvailable(): boolean
	if available ~= nil then
		return available
	end

	const ok = pcall(function()
		DataStoreService:GetDataStore("CajAdmin_Probe"):GetAsync("probe")
	end)

	available = ok
	if not ok then
		warn("[CajAdmin] DataStores are unavailable (enable API access in Studio). Persistent data will only last until the server closes.")
	end

	return ok
end

const function getStore(name: string): DataStore
	if not stores[name] then
		stores[name] = DataStoreService:GetDataStore(`CajAdmin_{name}`)
	end

	return stores[name]
end

--[[ Returns true when real DataStores are being used. ]]
function Store.IsPersistent(): boolean
	return checkAvailable()
end

function Store.Get(name: string, key: string, default: any?): any
	if not checkAvailable() then
		const value = memoryFor(name)[key]
		if value == nil then
			return default
		end

		return value
	end

	const dataStore = getStore(name)
	for attempt = 1, RETRIES do
		const ok, value = pcall(dataStore.GetAsync, dataStore, key)
		if ok then
			if value == nil then
				return default
			end

			return value
		end

		if attempt < RETRIES then
			task.wait(attempt)
		end
	end

	warn(`[CajAdmin] Could not read {name}/{key} from the DataStore.`)
	return default
end

function Store.Set(name: string, key: string, value: any): boolean
	if not checkAvailable() then
		memoryFor(name)[key] = value
		return true
	end

	const dataStore = getStore(name)
	for attempt = 1, RETRIES do
		const ok = pcall(dataStore.SetAsync, dataStore, key, value)
		if ok then
			return true
		end

		if attempt < RETRIES then
			task.wait(attempt)
		end
	end

	warn(`[CajAdmin] Could not write {name}/{key} to the DataStore.`)
	return false
end

--[[ `transform` receives the old value (or nil) and returns the new value. Returning nil cancels the write. ]]
function Store.Update(name: string, key: string, transform: (any) -> any): boolean
	if not checkAvailable() then
		const memoryStore = memoryFor(name)
		const newValue = transform(memoryStore[key])
		if newValue ~= nil then
			memoryStore[key] = newValue
		end

		return true
	end

	const dataStore = getStore(name)
	for attempt = 1, RETRIES do
		const ok = pcall(dataStore.UpdateAsync, dataStore, key, transform)
		if ok then
			return true
		end

		if attempt < RETRIES then
			task.wait(attempt)
		end
	end

	warn(`[CajAdmin] Could not update {name}/{key} in the DataStore.`)
	return false
end

function Store.Remove(name: string, key: string): boolean
	if not checkAvailable() then
		memoryFor(name)[key] = nil
		return true
	end

	const dataStore = getStore(name)
	for attempt = 1, RETRIES do
		const ok = pcall(dataStore.RemoveAsync, dataStore, key)
		if ok then
			return true
		end

		if attempt < RETRIES then
			task.wait(attempt)
		end
	end

	return false
end

return Store
