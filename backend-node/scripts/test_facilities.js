const assert = require('assert');

const facilityService = require(
  '../src/modules/facility_directory/facility.service',
);
const locationService = require(
  '../src/modules/location_directory/location.service',
);

facilityService.loadFacilities();
locationService.loadLocations();

const status = facilityService.getStatus();

assert.strictEqual(
  status.facilityCount,
  904,
  'Expected 904 facilities.',
);

assert.strictEqual(
  status.coordinatesRequiredForDirections,
  false,
);

assert.strictEqual(
  status.verifiedCoordinateCount,
  33,
  'Expected 33 Pampanga facilities with coordinates.',
);

assert.strictEqual(
  status.unresolvedCoordinateCount,
  871,
  'Expected 871 facilities without verified coordinates.',
);

const accuRenal =
  facilityService.getFacilityByNumber(216);

assert.ok(
  accuRenal,
  'ACCU-RENAL facility 216 was not found.',
);

assert.ok(
  accuRenal.googleMapsSearchUrl.includes(
    'google.com/maps/search',
  ),
);

assert.ok(
  accuRenal.googleMapsDirectionsUrl.includes(
    'google.com/maps/dir',
  ),
);

assert.ok(
  decodeURIComponent(
    accuRenal.googleMapsDirectionsUrl,
  ).includes('15.209423717638353,120.57915625233133'),
  'Verified facilities must use their exact coordinates for directions.',
);

const lubaoDialysis =
  facilityService.getFacilityByNumber(225);

assert.ok(lubaoDialysis);
assert.strictEqual(
  lubaoDialysis.exactClinicLocationVerified,
  false,
);
assert.strictEqual(lubaoDialysis.latitude, null);
assert.strictEqual(lubaoDialysis.longitude, null);

const pampangaMapped =
  facilityService.listFacilities({
    region: 'Region III (Central Luzon)',
    province: 'Pampanga',
    onlyVerifiedCoordinates: true,
    limit: 100,
    offset: 0,
  });

assert.strictEqual(
  pampangaMapped.total,
  33,
  'Expected 33 mapped Pampanga facilities.',
);

const mabalacat =
  facilityService.listFacilities({
    region: 'Region III (Central Luzon)',
    province: 'Pampanga',
    cityMunicipality: 'Mabalacat City',
    limit: 20,
    offset: 0,
  });

assert.strictEqual(
  mabalacat.total,
  4,
  'Expected four Mabalacat facilities.',
);

const recommendation =
  facilityService.recommendFacilities({
    region: 'Region III (Central Luzon)',
    province: 'Pampanga',
    cityMunicipality: 'Mabalacat City',
    limit: 20,
  });

assert.strictEqual(
  recommendation.matchLevel,
  'same_city_municipality',
);

assert.strictEqual(
  recommendation.isActualNearest,
  false,
);

assert.strictEqual(
  recommendation.coordinatesRequired,
  false,
);

assert.strictEqual(
  recommendation.facilities.length,
  4,
);

for (const facility of recommendation.facilities) {
  assert.ok(facility.googleMapsDirectionsUrl);

  assert.strictEqual(
    facility.googleMapsDestinationType,
    facility.exactClinicLocationVerified
      ? 'verified_coordinates'
      : 'clinic_name_and_address',
  );
}

const anaoFallback =
  facilityService.recommendFacilities({
    region: 'Region III (Central Luzon)',
    province: 'Tarlac',
    cityMunicipality: 'Anao',
    limit: 20,
  });

assert.strictEqual(
  anaoFallback.matchLevel,
  'same_province',
);

assert.ok(
  anaoFallback.facilities.length > 0,
  'Expected Tarlac province fallback clinics.',
);

const pampanga =
  locationService.getLocalities({
    regionName:
      'Region III (Central Luzon)',
    provinceName: 'Pampanga',
  });

assert.strictEqual(
  pampanga.localities.length,
  21,
);

assert.ok(
  pampanga.localities.some(
    (locality) =>
      locality.name === 'Mabalacat City',
  ),
);


const regionThreeAreas =
  locationService.getProvinces(
    'Region III (Central Luzon)',
  );

const regionThreeAreaNames = [
  ...regionThreeAreas.provinces,
  ...regionThreeAreas.regionLevelLocalities,
  ...regionThreeAreas.specialAreas,
]
  .map((area) => area.name)
  .sort((first, second) =>
    first.localeCompare(second),
  );

assert.deepStrictEqual(
  regionThreeAreaNames,
  [
    'Aurora',
    'Bataan',
    'Bulacan',
    'City of Angeles',
    'City of Olongapo',
    'Nueva Ecija',
    'Pampanga',
    'Tarlac',
    'Zambales',
  ],
  'Region III must place independent cities directly in the Province dropdown.',
);

for (const region of locationService.getRegions()) {
  const areas = locationService.getProvinces(
    region.name,
  );

  assert.ok(
    areas,
    `Missing area data for ${region.name}.`,
  );

  const combinedAreas = [
    ...areas.provinces,
    ...areas.regionLevelLocalities,
    ...areas.specialAreas,
  ];

  assert.ok(
    combinedAreas.length > 0,
    `No selectable Province entry was created for ${region.name}.`,
  );
}


const ncrAreas = locationService.getProvinces(
  'National Capital Region (NCR)',
);

assert.strictEqual(
  ncrAreas.provinces.length,
  0,
  'NCR must not contain regular provinces.',
);

assert.ok(
  ncrAreas.combinedAreas.some(
    (area) => area.name === 'City of Manila',
  ),
  'NCR cities must appear directly in the Province dropdown.',
);

assert.ok(
  ncrAreas.combinedAreas.some(
    (area) => area.name === 'Quezon City',
  ),
  'Quezon City must appear directly in the NCR Province dropdown.',
);

assert.ok(
  ncrAreas.combinedAreas.some(
    (area) => area.name === 'Pateros',
  ),
  'Pateros must appear directly in the NCR Province dropdown.',
);

const angelesRecommendation =
  facilityService.recommendFacilities({
    region: 'Region III (Central Luzon)',
    province: null,
    cityMunicipality: 'City of Angeles',
    limit: 20,
  });

assert.strictEqual(
  angelesRecommendation.matchLevel,
  'same_city_municipality',
  'An independent city must work as a direct clinic locality.',
);

console.log(
  'Address-based facility directory tests passed.',
);
