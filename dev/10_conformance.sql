--db:fhirb
--{{{

-- most of params should go from _cfg
-- TODO: check all fields
CREATE OR REPLACE
FUNCTION fhir_conformance(_cfg jsonb) RETURNS jsonb
LANGUAGE sql AS $$
SELECT json_build_object(
  'resourceType', 'Conformance',
  'identifier', _cfg->'identifier',
  'version', _cfg->'version',
  'name', _cfg->'name',
  'publisher', _cfg->'publisher',
  'telecom', _cfg->'telecom',
  'description', _cfg->'description',
  'status', 'active',
  'date', _cfg->'date',
  'software', _cfg->'software',
  'fhirVersion', _cfg->'fhirVersion',
  'acceptUnknown', _cfg->'acceptUnknown',
  'format', _cfg->'format',
  'rest', ARRAY[json_build_object(
    'mode', 'server',
    'operation', '[ { "code": "transaction" }, { "code": "history-system" } ]',
    'cors', _cfg->'cors',
    'resource',
      (SELECT json_agg(
          json_build_object(
            'type', e.path[1],
            'profile', json_build_object(
              'reference', _cfg->>'base' || '/Profile/' || e.path[1]
            ),
            'readHistory', true,
            'updateCreate', true,
            'operation', '[{ "code": "read" }, { "code": "vread" }, { "code": "update" }, { "code": "history-instance" }, { "code": "create" }, { "code": "history-type" } ]'::json,
            'searchParam',  (
              SELECT  json_agg(t.*)  FROM (
                SELECT sp.name, sp.type, sp.documentation
                FROM fhir.resource_search_params sp
                  WHERE sp.path[1] = e.path[1]
              ) t
            )

          )
        )
        FROM fhir.resource_elements e
        WHERE array_length(path,1) = 1
      )
  )]
)::jsonb;
$$;


CREATE OR REPLACE
FUNCTION fhir_profile(_cfg jsonb, _resource_name_ text) RETURNS jsonb
LANGUAGE sql AS $$
SELECT null::jsonb
$$;
--}}}