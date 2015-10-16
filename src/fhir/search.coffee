parser = require('./params')
expand = require('./expand_params')
norm = require('./normalize_params')
cond = require('./conditions')
namings = require('../core/namings')
meta_db = require('./meta_pg')
index = require('./meta_index')
utils = require('../core/utils')
sql = require('../honey')
# cases

# Patient.active
# 1 to 1; primitive
# (resource->>'active')::boolean [= <> is null]
# not selective; we do not need index for such type

# address-city

# 1 to *; complex
# a)
#   (resource#>>'{address,0,city}') ilike ~ =
#   (resource#>>'{address,1,city}') ilike ~ =
#   (resource#>>'{address,2,city}') ilike ~ =
#   (resource#>>'{address,3,city}') ilike ~ =
# we need trigram and/or fulltext index
# separate index for each index - starting from 0 and accumulating statistic
#
#  pro: more accurate result
#  contra: quite complex solution
#
# b)
#   use GIN (expr::text[]) gin_trgm_ops) or GIST
#   GIN (extract(resource, paths,opts)::text[] gin_trgm_ops)
#   one index for parameter
#
# NOTES: we need umlauts normalization for strings

_search_sql = (plv8, idx, query)->
  params = parser.parse(query.queryString)
  params.resourceType = query.resourceType
  eparams = expand._expand(idx, params)
  eparams = norm.normalize(eparams)
  select: [':*']
  from: [namings.table_name(plv8, eparams.resourceType)]
  where: cond.walk(eparams.params)

exports._search_sql = _search_sql

search_sql = (plv8, query)->
  idx_db = index.new(plv8, meta_db.getter)
  sql(_search_sql(plv8, idx_db, query))

exports.search_sql = search_sql

countize_query = (q)->
  delete q.limit
  delete q.offset
  delete q.order
  q.select = [':count(*) as count']
  q

to_entry = (row)->
  resource: JSON.parse(row.resource)

exports.search = (plv8, query)->
  idx_db = index.new(plv8, meta_db.getter)
  honey = _search_sql(plv8, idx_db, query)
  resources = utils.exec(plv8, honey)

  count = utils.exec(plv8, countize_query(honey))[0].count

  type: 'searchset'
  total: count
  entry: resources.map(to_entry)