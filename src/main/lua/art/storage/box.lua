local box = {
    findFirst = function(request)
        local space = request[1]
        local key = request[2]
        local index = request[3]

        if not (index) then
            return box.space[space]:get(key)
        end
        return box.space[space].index[index]:get(key)
    end,

    findAll = function(request)
        local space = request[1]
        local keys = request[2]
        local result = {}
        for _, key in pairs(keys) do
            table.insert(result, art.box.findFirst(space, key))
        end
        return result
    end,

    find = function(request)
        local space = request[1]
        local index = request[2]
        local key = request[3]
        local iterator = request[4]
        local operations = request[5]

        local generator, param, state = box.space[space].index[index]:pairs(key, { iterator = iterator })

        for _, operation in pairs(operations) do
            local operationName = operation[1]
            local operationParameters = operation[2]
            generator, param, state = art.storage.stream.select(operationName)(generator, param, state, operationParameters)
        end

        local response = art.core.stream.collect(generator, param, state)
    end,

    delete = function(space, key)
        local data = box.space[space]:get(key)
        if data == nil then
            return { {} }
        end
        return box.space[space]:delete(key)
    end,

    insert = function(space, data)
        return box.space[space]:insert(data)
    end,

    put = function(space, data)
        return box.space[space]:put(data)
    end,

    replace = art.box.put,

    update = function(space, key, commands)
        return box.space[space].update(space, key, commands)
    end,

    upsert = function(space, data, commands)
        return box.space[space].upsert(data, commands)
    end,

    count = function(space)
        return box.space[space]:count()
    end,

    truncate = function(space)
        box.space[space]:truncate()
        return {}
    end,


    createIndex = function(space, name, index)
        return box.space[space]:create_index(name, index)
    end,

    dropIndex = function(space, name)
        box.space[space].index[name]:drop()
        return {}
    end,

    rename = function(space, name)
        return box.space[space]:rename(name)
    end,

    format = function(space, format)
        return box.space[space]:format(format)
    end,

    drop = function(space)
        box.space[space]:drop()
    end,

    create = function(name, configuration)
        if not (configuration) then
            configuration = {}
        end
        box.schema.space.create(name, configuration)
    end,


    spaces = function()
        local result = {}
        for _, value in pairs(box.space._space:select()) do
            if not (string.startswith(value[3], '_')) then
                table.insert(result, value[3])
            end
        end
        return result
    end,

    indicies = function(space)
        local result = {}
        for _, value in pairs(box.space[space].index) do
            table.insert(result, value.name)
        end
        return result
    end,
}

return box
