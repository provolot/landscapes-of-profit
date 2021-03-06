SELECT l.*,
  m.crfn, m.recorded_borough, m.doc_type, m.document_date, m.document_amt, m.recorded_datetime, m.modified_date, m.percent_trans, p.party_type, p.name, p.addr1, p.addr2, p.country, p.city, p.state, p.zip
INTO deriv
FROM acris_real_property_legals l, acris_real_property_master m, acris_real_property_parties p
WHERE l.document_id = m.document_id
  AND m.document_id = p.document_id
  AND m.recorded_datetime >= '2003-01-01'
  AND doc_type in ('DEED', 'DEEDO')
;

CREATE INDEX document_id on deriv (document_id);
CREATE INDEX bbl ON deriv (borough, block, lot);

SELECT document_id, count(distinct borough || '|' || block || '|' || lot) INTO acris_real_property_dupes FROM deriv GROUP BY document_id;
CREATE INDEX document_id_key on acris_real_property_dupes (document_id);

DELETE FROM deriv
WHERE document_id IN
  (SELECT document_id FROM acris_real_property_dupes WHERE "count" > 1);
DELETE FROM deriv WHERE document_amt < 100000;

SELECT
  before.document_id before_document_id,
  before.borough borough,
  before.block block,
  before.lot lot,
  before.document_date before_document_date,
  before.document_amt before_document_amt,
  before.recorded_datetime before_recorded_datetime,
  before.party_type before_party_type,
  before.name before_name,
  before.addr1 before_addr1,
  before.addr2 before_addr2,
  before.country before_country,
  before.city before_city,
  before.state before_state,
  before.zip before_zip,
  after.document_id after_document_id,
  after.document_date after_document_date,
  after.document_amt after_document_amt,
  after.recorded_datetime after_recorded_datetime,
  after.party_type after_party_type,
  after.name after_name,
  after.addr1 after_addr1,
  after.addr2 after_addr2,
  after.country after_country,
  after.city after_city,
  after.state after_state,
  after.zip after_zip
INTO flips_raw
FROM deriv before, deriv after
WHERE after.document_date::date - before.document_date::date BETWEEN 1 and 730
  AND before.document_amt * 1.5 < after.document_amt
  AND before.borough = after.borough
  AND before.block = after.block
  AND before.lot = after.lot;

SELECT borough,
  block,
  lot,
  MAX(before_document_date) before_document_date,
  MAX(after_document_date) after_document_date,
  MAX(before_document_amt) before_document_amt,
  MAX(after_document_amt) after_document_amt,
  MAX(after_document_amt::float) / MAX(before_document_amt) ratiopricediff,
  MAX(after_document_date) - MAX(before_document_date) dayspast,
  SUBSTR(STRING_AGG(CASE WHEN before_party_type::int = 1 THEN before_name ELSE NULL END, '|'), 0, 255) AS sellers_before,
  SUBSTR(STRING_AGG(CASE WHEN before_party_type::int = 2 THEN before_name ELSE NULL END, '|'), 0, 255) AS buyers_before,
  SUBSTR(STRING_AGG(CASE WHEN after_party_type::int = 1 THEN after_name ELSE NULL END, '|'), 0, 255) AS sellers_after,
  SUBSTR(STRING_AGG(CASE WHEN after_party_type::int = 2 THEN after_name ELSE NULL END, '|'), 0, 255) AS buyers_after
INTO flips_output
FROM flips_raw
GROUP BY borough, block, lot;

-- to join the queried acris_real_property data to pluto:
CREATE TABLE pluto_flips AS
SELECT a.*, 
  b.before_document_date,
  b.after_document_date,
  b.before_document_amt,
  b.after_document_amt,
  b.sellers_before,
  b.sellers_after,
  b.ratiopricediff,
  b.dayspast
  FROM pluto a, flips b
  WHERE a.borocode = b.borough 
    AND a.block = b.block 
    AND a.lot = b.lot;

-- to query in cartodb:
SELECT address, the_geom, cartodb_id, the_geom_webmercator, yearbuilt,
      ratiopricediff, before_document_amt, after_document_amt, 
      sellers_after, sellers_before
FROM table_150712_flips_output_withnames_joined
WHERE ratiopricediff < 10
ORDER BY ratiopricediff
