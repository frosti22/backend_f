const fs = require('fs');
const path = require('path');

const {
  hasVerifiedCoordinates,
  serializeFacility,
} = require('./facility.model');

const FACILITY_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'facilities',
  'processed',
  'philhealth_facilities.json',
);

let facilityData = null;
let facilities = [];
let facilitiesByNumber = new Map();

function normalize(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase()
    .replace(/^city of\s+/, '')
    .replace(/\bcity\b/g, '')
    .replace(/\bmunicipality\b/g, '')
    .replace(/\bprovince\b/g, '')
    .replace(/\bsto\.?\b/g, 'santo')
    .replace(/\bsta\.?\b/g, 'santa')
    .replace(/\bgen\.?\b/g, 'general')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function loadFacilities() {
  if (!fs.existsSync(FACILITY_FILE)) {
    throw new Error(
      `Facility data file was not found: ${FACILITY_FILE}`,
    );
  }

  const parsed = JSON.parse(
    fs.readFileSync(FACILITY_FILE, 'utf8'),
  );

  if (!Array.isArray(parsed.facilities)) {
    throw new Error(
      'Facility JSON must contain a facilities array.',
    );
  }

  facilityData = parsed;
  facilities = parsed.facilities;
  facilitiesByNumber = new Map(
    facilities.map((facility) => [
      Number(facility.facilityNumber),
      facility,
    ]),
  );

  console.log(
    `Loaded ${facilities.length} PhilHealth facilities.`,
  );

  return getStatus();
}

function ensureLoaded() {
  if (!facilityData) {
    loadFacilities();
  }
}

function isAccreditationCurrent(
  facility,
  referenceDate = new Date(),
) {
  if (!facility.accreditationExpiry) {
    return false;
  }

  const expiry = new Date(
    `${facility.accreditationExpiry}T23:59:59Z`,
  );

  return !Number.isNaN(expiry.getTime()) &&
    expiry.getTime() >= referenceDate.getTime();
}

function compareByName(first, second) {
  return String(first.name).localeCompare(
    String(second.name),
  );
}

function getStatus() {
  ensureLoaded();

  const verifiedCoordinateCount =
    facilities.filter(
      hasVerifiedCoordinates,
    ).length;

  return {
    metadata: facilityData.metadata ?? {},
    facilityCount: facilities.length,
    verifiedCoordinateCount,
    unresolvedCoordinateCount:
      facilities.length -
      verifiedCoordinateCount,
    coordinateCoveragePercent:
      facilities.length === 0
        ? 0
        : Number(
            (
              verifiedCoordinateCount /
              facilities.length *
              100
            ).toFixed(2),
          ),
    recommendationMode:
      'selected_location_then_google_maps_address',
    coordinatesRequiredForDirections: false,
  };
}

function getFacilityByNumber(facilityNumber) {
  ensureLoaded();

  const facility = facilitiesByNumber.get(
    Number(facilityNumber),
  );

  return facility
    ? serializeFacility(facility)
    : null;
}

function listFacilities({
  region,
  province,
  cityMunicipality,
  query,
  onlyCurrent = true,
  onlyVerifiedCoordinates = false,
  limit = 20,
  offset = 0,
}) {
  ensureLoaded();

  const normalizedRegion = normalize(region);
  const normalizedProvince = normalize(province);
  const normalizedLocality = normalize(
    cityMunicipality,
  );
  const normalizedQuery = normalize(query);

  const filtered = facilities.filter(
    (facility) => {
      if (
        onlyCurrent &&
        !isAccreditationCurrent(facility)
      ) {
        return false;
      }

      if (
        onlyVerifiedCoordinates &&
        !hasVerifiedCoordinates(facility)
      ) {
        return false;
      }

      if (
        normalizedRegion &&
        normalize(facility.region) !==
          normalizedRegion
      ) {
        return false;
      }

      if (
        normalizedProvince &&
        normalize(facility.province) !==
          normalizedProvince
      ) {
        return false;
      }

      if (
        normalizedLocality &&
        normalize(
          facility.cityMunicipality,
        ) !== normalizedLocality
      ) {
        return false;
      }

      if (normalizedQuery) {
        const searchableText = normalize([
          facility.name,
          facility.streetAddress,
          facility.barangay,
          facility.cityMunicipality,
          facility.province,
          facility.region,
        ].filter(Boolean).join(' '));

        if (!searchableText.includes(normalizedQuery)) {
          return false;
        }
      }

      return true;
    },
  ).sort(compareByName);

  return {
    total: filtered.length,
    results: filtered
      .slice(offset, offset + limit)
      .map((facility) =>
        serializeFacility(facility),
      ),
  };
}

function getMatchLevel(
  facility,
  region,
  province,
  cityMunicipality,
) {
  const sameRegion =
    normalize(facility.region) ===
    normalize(region);

  const sameProvince =
    Boolean(province) &&
    normalize(facility.province) ===
      normalize(province);

  const provinceAllowsLocality =
    !province || sameProvince;

  const sameLocality =
    normalize(facility.cityMunicipality) ===
    normalize(cityMunicipality);

  if (
    sameRegion &&
    provinceAllowsLocality &&
    sameLocality
  ) {
    return 'same_city_municipality';
  }

  if (sameRegion && sameProvince) {
    return 'same_province';
  }

  if (sameRegion) {
    return 'same_region';
  }

  return 'outside_selected_region';
}

function createResult({
  matchLevel,
  message,
  candidateFacilities,
  limit,
}) {
  const results = candidateFacilities
    .slice()
    .sort(compareByName)
    .slice(0, limit)
    .map((facility) =>
      serializeFacility(facility),
    );

  return {
    matchLevel,
    recommendationBasis: 'selected_location',
    isActualNearest: false,
    coordinatesRequired: false,
    directionsProvider: 'google_maps_url',
    directionsUse: 'clinic_name_and_full_address',
    message,
    facilities: results,
  };
}

function recommendFacilities({
  region,
  province,
  cityMunicipality,
  limit = 20,
}) {
  ensureLoaded();

  const currentFacilities = facilities.filter(
    (facility) => isAccreditationCurrent(facility),
  );

  const localMatches = currentFacilities.filter(
    (facility) =>
      getMatchLevel(
        facility,
        region,
        province,
        cityMunicipality,
      ) === 'same_city_municipality',
  );

  if (localMatches.length > 0) {
    return createResult({
      matchLevel: 'same_city_municipality',
      message:
        `Showing PhilHealth-accredited facilities in ` +
        `${cityMunicipality}. Select a facility to display ` +
        'its verified map pin when available.',
      candidateFacilities: localMatches,
      limit,
    });
  }

  const sameProvince = currentFacilities.filter(
    (facility) =>
      getMatchLevel(
        facility,
        region,
        province,
        cityMunicipality,
      ) === 'same_province',
  );

  if (sameProvince.length > 0) {
    return createResult({
      matchLevel: 'same_province',
      message:
        `No accredited facility was found in ` +
        `${cityMunicipality}. Showing facilities elsewhere ` +
        `in ${province}. Verified map pins appear when available.`,
      candidateFacilities: sameProvince,
      limit,
    });
  }

  const sameRegion = currentFacilities.filter(
    (facility) =>
      getMatchLevel(
        facility,
        region,
        province,
        cityMunicipality,
      ) === 'same_region',
  );

  if (sameRegion.length > 0) {
    return createResult({
      matchLevel: 'same_region',
      message:
        `No accredited facility was found in the selected ` +
        `municipality or province. Showing facilities in ` +
        `${region}.`,
      candidateFacilities: sameRegion,
      limit,
    });
  }

  return createResult({
    matchLevel: 'none',
    message:
      'No current PhilHealth-accredited facility was found in the selected location.',
    candidateFacilities: [],
    limit,
  });
}

module.exports = {
  getFacilityByNumber,
  getStatus,
  listFacilities,
  loadFacilities,
  recommendFacilities,
};
