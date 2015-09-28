namings = require('./namings')
pg_meta = require('./pg_meta')
utils = require('./utils')
bundle = require('./bundle')

exports.plv8_schema = 'fhir'

validate_create_resource = (resource)->
  unless resource.resourceType
    {status: "Error", message: "resource should have type element"}

assert = (pred, msg)->
  unless pred
    throw new Error("Asserted: #{msg}")

ensure_meta = (resource, props)->
  resource.meta ||= {}
  for k,v of props
    resource.meta[k] = v
  resource

exports.create = (plv8, resource)->
  errors = validate_create_resource(resource)
  if errors then return errors
  table_name = namings.table_name(plv8, resource.resourceType)
  unless pg_meta.table_exists(plv8, table_name)
    return {status: "Error", message: "Table for #{resource.resourceType} not exists"}

  id = resource.id || utils.uuid(plv8)
  resource.id = id
  version_id = (resource.meta && resource.meta.versionId) ||  utils.uuid(plv8)

  ensure_meta(resource,
    versionId: version_id
    lastUpdated: new Date()
    request:
      method: 'POST'
      url: resource.resourceType
  )

  utils.exec plv8,
    insert: table_name
    values:
      id: id
      version_id: version_id
      resource: JSON.stringify(resourece)
      created_at: '^CURRENT_TIMESTAMP'
      updated_at: '^CURRENT_TIMESTAMP'

  utils.exec plv8,
    insert: "history.#{table_name}"
    values:
      id: id
      version_id: version_id
      resource: JSON.stringify(resourece)
      valid_from: '^CURRENT_TIMESTAMP'
      valid_to: '^CURRENT_TIMESTAMP'

  resource

exports.create.plv8_signature = ['jsonb', 'jsonb']

exports.read = (plv8, query)->
  assert(query.id, 'query.id')
  assert(query.resourceType, 'query.resourceType')

  table_name = namings.table_name(plv8, query.resourceType)
  unless pg_meta.table_exists(plv8, table_name)
    return {status: "Error", message: "Table for #{query.resourceType} not exists"}

  res = utils.exec(plv8, select: [':*'], from: [table_name], where: [':=', ':id',query.id])
  row = res[0]
  unless row
    return {status: "Error", message: "Not found"}

  JSON.parse(row.resource)

exports.read.plv8_signature = ['jsonb', 'jsonb']

exports.vread = (plv8, query)->
  assert(query.id, 'query.id')
  version_id = query.versionId || query.meta.versionId
  assert(version_id, 'query.versionId or query.meta.versionId')
  assert(query.resourceType, 'query.resourceType')

  table_name = namings.table_name(plv8, query.resourceType)
  unless pg_meta.table_exists(plv8, table_name)
    return {status: "Error", message: "Table for #{query.resourceType} not exists"}

  q =
    select: [':*']
    from: ["history.#{table_name}"]
    where: [':and', [':=', ':id',query.id],
                    [':=', ':version_id', version_id]]

  res = utils.exec(plv8,q)
  row = res[0]
  unless row
    return {status: "Error", message: "Not found"}

  JSON.parse(row.resource)

exports.vread.plv8_signature = ['jsonb', 'jsonb']

exports.update = (plv8, resource)->
  id = resource.id
  assert(id, 'resource.id')
  assert(resource.resourceType, 'resource.resourceType')

  table_name = namings.table_name(plv8, resource.resourceType)
  unless pg_meta.table_exists(plv8, table_name)
    return {status: "Error", message: "Table for #{resource.resourceType} not exists"}

  old_version = exports.read(plv8, resource)

  unless old_version
    return {status: "Error", message: "Resource #{resource.resourceType}/#{id} not exists"}

  version_id = utils.uuid(plv8)
  #TODO: should it merge meta of prev version
  resource.meta ||= {}
  resource.meta.versionId = version_id
  resource.meta.lastUpdated = new Date()
  resource.meta.request = {
    method: 'PUT'
    url: resource.resourceType
  }

  plv8.execute """
    UPDATE #{table_name}
    SET version_id = $2
        ,resource = $3
        ,updated_at = CURRENT_TIMESTAMP
    WHERE id = $1
    """, [id, version_id, JSON.stringify(resource)]

  plv8.execute """
    UPDATE history.#{table_name}
    SET valid_to = CURRENT_TIMESTAMP
    WHERE id = $1 and version_id = $2
    """, [id, old_version.meta.versionId]

  utils.exec plv8,
    insert: "history.#{table_name}"
    values:
      id: id
      version_id: version_id
      resource: JSON.stringify(resourece)
      valid_from: '^CURRENT_TIMESTAMP'
      valid_to: '^infinity'

  resource


exports.update.plv8_signature = ['jsonb', 'jsonb']

exports.delete = (plv8, resource)->
  id = resource.id
  assert(id, 'resource.id')
  assert(resource.resourceType, 'resource.resourceType')

  table_name = namings.table_name(plv8, resource.resourceType)
  unless pg_meta.table_exists(plv8, table_name)
    return {status: "Error", message: "Table for #{resource.resourceType} not exists"}

  old_version = exports.read(plv8, resource)

  unless old_version
    return {status: "Error", message: "Resource #{resource.resourceType}/#{id} not exists"}

  resource = utils.copy(old_version)

  version_id = utils.uuid(plv8)
  resource.meta ||= {}
  resource.meta.versionId = version_id
  resource.meta.lastUpdated = new Date()
  resource.meta.request = {
    method: 'DELETE'
    url: resource.resourceType
  }

  plv8.execute "DELETE FROM #{table_name} WHERE id = $1", [id]

  plv8.execute """
    UPDATE history.#{table_name}
    SET valid_to = CURRENT_TIMESTAMP
    WHERE id = $1 and version_id = $2
    """, [id, old_version.meta.versionId]

  utils.exec plv8,
    insert: "history.#{table_name}"
    values:
      id: id
      version_id: version_id
      resource: JSON.stringify(resourece)
      valid_from: '^CURRENT_TIMESTAMP'
      valid_to: '^CURRENT_TIMESTAMP'

  resource


exports.delete.plv8_signature = ['jsonb', 'jsonb']

exports.history = (plv8, query)->
  id = query.id
  assert(id, 'query.id')
  assert(query.resourceType, 'query.resourceType')

  table_name = namings.table_name(plv8, query.resourceType)
  unless pg_meta.table_exists(plv8, table_name)
    return {status: "Error", message: "Table for #{query.resourceType} not exists"}

  q =
    select: [':*']
    from: ["history.#{table_name}"]
    where: [':=', ':id',query.id]

  resources = utils.exec(plv8,q).map((x)-> JSON.parse(x.resource))
  bundle.history_bundle(resources)