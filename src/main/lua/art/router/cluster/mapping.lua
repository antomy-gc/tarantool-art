local mapping = {
    init = function()
        if not (box.space._mapping_pending_updates) then
            box.schema.space.create('_mapping_pending_updates', {is_local = true})
            box.space._mapping_pending_updates:format({
                { name = 'id', type = 'unsigned' },
                { name = 'space', type = 'string' },
                { name = 'batch', type = 'any' }
            })
            box.schema.sequence.create('mapping_pending_updates_id', {cycle = true})
            box.space._mapping_pending_updates:create_index('id', {parts = {1}, sequence = box.sequence.mapping_pending_updates_id})
            box.space._mapping_pending_updates:create_index('space', {parts = {2}, unique = false})
        end
        art.cluster.mapping.watcher.start()
    end,

    saveToPending = function(batches)
        for _, v in pairs(batches) do
            box.space._mapping_pending_updates:insert({nil, unpack(v)})
        end
    end,

    space = {
        create = function(space, config)
            box.schema.space.create(space)
            art.cluster.mapping.space.format(space, config['format'])
        end,

        format = function(space, format)
            if not (format) then return end
            if not(box.space[space].index[0] and box.space[space].index.bucket_id) then
                box.space[space]:format(format)
                return
            end

            for _, v in pairs(format) do
                v['is_nullable'] = true
            end

            for _, v in pairs(box.space[space].index[0].parts) do
                format[v.fieldno].is_nullable = false
            end
            box.space[space]:format(format)
        end,

        createIndex = function(space, index_name, index)
            if not (box.space[space].index[0] and box.space[space].index.bucket_id) then
                box.space[space]:create_index(index_name, index)
                art.cluster.mapping.space.format(space, box.space[space]:format())
                return
            end

            local map_index = index
            for k, v in pairs(index.parts) do
                map_index.parts[k] = v
                if not (type(v) == 'table') then
                    map_index.parts[k] = {field = v}
                end
                map_index.parts[k]['is_nullable'] = true
            end
            local result = box.space[space]:create_index(index_name, map_index)
        end,

        dropIndex = function(space, index_name)
            box.space[space].index[index_name]:drop()
        end,

        rename = function(space, new_name)
            box.space[space]:rename(new_name)
            art.cluster.mapping.space.renameSpaceInPending(space, new_name)
        end,

        truncate = function(space)
            box.space[space]:truncate()
            art.cluster.mapping.space.deletePendingSpaceUpdates(space)
        end,

        drop = function(space)
            box.space[space]:drop()
            art.cluster.mapping.space.deletePendingSpaceUpdates(space)
        end,

        deletePendingSpaceUpdates = function(space)
            for _,v in box.space._mapping_pending_updates.index.space:pairs(space) do
                box.space._mapping_pending_updates:delete(v[1])
            end
        end,

        renameSpaceInPending = function(space, new_name)
            for _,v in box.space._mapping_pending_updates.index.space:pairs(space) do
                box.space._mapping_pending_updates:update(v[1], {{'=', 2, new_name}})
            end
        end
    },

    watcher = {
        serviceFiber = nil,
        watchdogFiber = nil,

        start = function()
            art.cluster.mapping.watcher.serviceFiber = art.core.fiber.create(art.cluster.mapping.watcher.service)
            art.cluster.mapping.watcher.watchdogFiber = art.core.fiber.create(art.cluster.mapping.watcher.watchdog)
        end,

        watchdog = function()
            while(true) do
                if (art.core.fiber.status(art.cluster.mapping.watcher.serviceFiber) == 'dead') then
                    art.cluster.mapping.watcher.serviceFiber = art.core.fiber.create(art.cluster.mapping.watcher.service)
                end
                art.core.fiber.sleep(1)

            end
        end,

        service = function()
            local counter = 0

            while true do
                counter = 0
                for _,v in box.space._mapping_pending_updates:pairs(box.sequence.mapping_pending_updates_id:current(), 'GT') do
                    box.atomic(art.cluster.mapping.watcher.updateBatch, v)
                    counter = counter+1
                    if (counter == art.config.mapping.batchesPerTime) then
                        art.core.fiber.sleep(art.config.mapping.timeout)
                        counter = 0
                    end
                end

                counter = 0
                for _,v in box.space._mapping_pending_updates:pairs() do
                    box.atomic(art.cluster.mapping.watcher.updateBatch, v)
                    counter = counter+1
                    if (counter == art.config.mapping.batchesPerTime) then
                        art.core.fiber.sleep(art.config.mapping.timeout)
                        counter = 0
                    end
                end
                art.core.fiber.sleep(art.config.mapping.timeout)
            end
        end,

        updateBatch = function(batch)
            local space = box.space[batch[2]]
            if not(space) then
                box.space._mapping_pending_updates:delete(batch[1])
                return
            end
            for _, v in pairs(batch[3]) do
                if v[2] then
                    table.remove(v, 1)
                    table.remove(v, 1)
                    table.remove(v, 1) --to get primary key from update record
                    space:delete(v)
                else
                    space:put(v[3])
                end
            end
            box.space._mapping_pending_updates:delete(batch[1])
        end

    }
}

return mapping