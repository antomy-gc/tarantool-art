local api = {
    space = {
        create = function(name, config)
            if not config then config = {} end
            local result = art.cluster.space.execute('createVsharded', {name, config})
            if (result[1]) then
                art.cluster.mapping.space.create(name, config)
            end
            return result
        end,

        format = function(space, format)
            local result = art.cluster.space.execute('format', {space, format})
            if (result[1]) then
                art.cluster.mapping.space.format(space, format)
            end
            return result
        end,

        createIndex = function(space, index_name, index)
            local result = art.cluster.space.execute('createIndex', {space, index_name, index})
            if (result[1]) then
                art.cluster.mapping.space.createIndex(space, index_name, index)
            end
            return result
        end,

        dropIndex = function(space, index_name)
            local result = art.cluster.space.execute('dropIndex', {space, index_name})
            if result[1] then
                art.cluster.mapping.space.dropIndex(space, index_name)
            end
            return result
        end,

        rename = function(space, new_name)
            local result = art.cluster.space.execute('rename', {space, new_name})
            if (result[1]) then
                box.atomic(art.cluster.mapping.space.rename, space, new_name)
            end
            return result
        end,

        truncate = function(space)
            local result = art.cluster.space.execute('truncate', {space})
            if (result[1]) then
                art.cluster.mapping.space.truncate(space)
            end
            return result
        end,

        drop = function(space)
            local result = art.cluster.space.execute('drop', {space})
            if (result[1]) then
                art.cluster.mapping.space.drop(space)
            end
            return result
        end,

        count = function(space)
            local counts = art.cluster.space.execute('count', {space})
            local result = 0
            if (not counts[1]) then return counts end
            for _,v in pairs(counts[2]) do
                result = result + v[2]
            end
            return result
        end,

        len = function(space)
            local counts = art.cluster.space.execute('len', {space})
            local result = 0
            if (not counts[1]) then return counts end
            for _,v in pairs(counts[2]) do
                result = result + v[2]
            end
            return result
        end,

        list = function()
            local result = {}
            for _,v in pairs(box.space._space:select()) do
                if not (string.startswith(v[3], '_')) then table.insert(result, v[3]) end
            end
            return result
        end,

        listIndices = function(space)
            local temp = {}
            local result = {}
            for _, v in pairs(box.space[space].index) do
                temp[v.name] = true
            end
            for k in pairs(temp) do
                table.insert(result, k)
            end
            return result
        end
    },

    transaction = function(requests, bucket_id)
        return unpack(art.transaction.execute(requests, bucket_id))
    end,

    get = function(space, key, index)
        local bucket_id = art.core.mapBucket(space, key)
        if not(bucket_id) then return {{}} end
        return vshard.router.callro(bucket_id, 'art.api.get', {space, key, index})
    end,

    delete = function(space, key)
        local bucket_id = art.core.mapBucket(space, key)
        if not(bucket_id) then return {{}} end
        return vshard.router.callrw(bucket_id, 'art.api.delete', {space, key})
    end,

    insert = function(space, data, bucket_id)
        local response = vshard.router.callrw(bucket_id, 'art.api.insert', {space, art.core.insertBucket(space, data, bucket_id)})
        return art.core.removeBucket(space, response)
    end,

    autoIncrement = function(space, data, bucket_id)
        local response = vshard.router.callrw(bucket_id, 'art.api.autoIncrement', {space, art.core.insertBucket(space, data, bucket_id)})
        return art.core.removeBucket(space, response)
    end,

    put = function(space, data, bucket_id)
        local response = vshard.router.callrw(bucket_id, 'art.api.put', {space, art.core.insertBucket(space, data, bucket_id)})
        return art.core.removeBucket(space, response)
    end,

    update = function(space, key, commands)
        local bucket_id = art.core.mapBucket(space, key)
        if not(bucket_id) then return {{}} end
        return vshard.router.callrw(bucket_id, 'art.api.update', {space, key, commands})
    end,

    replace = function(space, data, bucket_id)
        local response = vshard.router.callrw(bucket_id, 'art.api.replace', {space, art.core.insertBucket(space, data, bucket_id)})
        return art.core.removeBucket(space, response)
    end,

    upsert = function(space, data, bucket_id, commands)
        local response = vshard.router.callrw(bucket_id, 'art.api.upsert', {space, art.core.insertBucket(space, data, bucket_id), commands})
        return art.core.removeBucket(space, response)
    end,

    select = function(space, request, index, ...)
        if not (index) then index = 0 end
        local get_requests = {}
        local key_fields_mapping = {}
        local request_entry
        local result = {}

        for _,part in pairs(box.space[space].index[0].parts) do
            key_fields_mapping[part.fieldno] = true
        end

        for _,mapping_entry in pairs(box.space[space].index[index]:select(request, ...)) do
            if not (get_requests[mapping_entry.bucket_id]) then get_requests[mapping_entry.bucket_id] = {} end
            request_entry = {}
            for k in pairs(key_fields_mapping) do
                request_entry[k] = mapping_entry[k]
            end
            table.insert(get_requests[mapping_entry.bucket_id], request_entry)
        end

        for bucket_id, batch_req in pairs(get_requests) do
            local response = vshard.router.callro(bucket_id, 'art.api.getBatch', {space, batch_req})
            if (response) then for _,v in pairs(response) do table.insert(result, v) end end
        end
        if not (result[1]) then return {} end
        return result
    end
}

return api