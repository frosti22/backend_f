const fs = require('fs');
const path = require('path');

const LOCATION_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'locations',
  'processed',
  'complete_philippine_lgu_hierarchy.json',
);

let locationData = null;

function normalize(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function loadLocations() {
  if (!fs.existsSync(LOCATION_FILE)) {
    throw new Error(
      `Location data file was not found: ${LOCATION_FILE}`,
    );
  }

  const parsed = JSON.parse(
    fs.readFileSync(LOCATION_FILE, 'utf8'),
  );

  if (!Array.isArray(parsed.regions)) {
    throw new Error(
      'Location JSON must contain a regions array.',
    );
  }

  locationData = parsed;

  console.log(
    `Loaded ${parsed.regions.length} Philippine regions.`,
  );

  return getStatus();
}

function ensureLoaded() {
  if (!locationData) {
    loadLocations();
  }
}

function getStatus() {
  ensureLoaded();

  return {
    metadata: locationData.metadata ?? {},
    regionCount: locationData.regions.length,
  };
}

function getRegions() {
  ensureLoaded();

  return locationData.regions.map(
    (region) => ({
      name: region.name,
      hasProvinces:
        Array.isArray(region.provinces) &&
        region.provinces.length > 0,
      hasRegionLevelLocalities:
        Array.isArray(
          region.regionLevelLocalities,
        ) &&
        region.regionLevelLocalities.length > 0,
      hasSpecialAreas:
        Array.isArray(region.specialAreas) &&
        region.specialAreas.length > 0,
      cityCount: region.cityCount ?? 0,
      municipalityCount:
        region.municipalityCount ?? 0,
    }),
  );
}

function findRegion(regionName) {
  ensureLoaded();

  const target = normalize(regionName);

  return locationData.regions.find(
    (region) =>
      normalize(region.name) === target,
  ) || null;
}

function getProvinces(regionName) {
  const region = findRegion(regionName);

  if (!region) {
    return null;
  }

  const provinces = (
    Array.isArray(region.provinces)
      ? region.provinces
      : []
  ).map((province) => ({
    name: province.name,
    type: province.type ?? 'province',
    cityCount: province.cityCount ?? 0,
    municipalityCount:
      province.municipalityCount ?? 0,
  }));

  const regionLevelLocalities = (
    Array.isArray(region.regionLevelLocalities)
      ? region.regionLevelLocalities
      : []
  ).map((locality) => ({
    name: locality.name,
    type: 'region_level_locality',
    localityType: locality.type ?? 'locality',
  }));

  const specialAreas = (
    Array.isArray(region.specialAreas)
      ? region.specialAreas
      : []
  ).map((specialArea) => ({
    name: specialArea.name,
    type: specialArea.type ??
      'special_area',
    cityCount:
      specialArea.cityCount ?? 0,
    municipalityCount:
      specialArea.municipalityCount ??
      0,
  }));

  const combinedAreas = [
    ...provinces,
    ...regionLevelLocalities,
    ...specialAreas,
  ].sort((first, second) =>
    first.name.localeCompare(second.name),
  );

  return {
    region: region.name,
    provinces,
    regionLevelLocalities,
    specialAreas,
    combinedAreas,
    hasRegionLevelLocalities:
      regionLevelLocalities.length > 0,
  };
}

function getLocalities({
  regionName,
  provinceName,
  specialAreaName,
}) {
  const region = findRegion(regionName);

  if (!region) {
    return null;
  }

  if (provinceName) {
    const target = normalize(provinceName);

    const province = (
      region.provinces || []
    ).find(
      (item) =>
        normalize(item.name) === target,
    );

    if (!province) {
      return {
        region: region.name,
        area: null,
        localities: [],
      };
    }

    return {
      region: region.name,
      area: {
        name: province.name,
        type: 'province',
      },
      localities:
        province.localities || [],
    };
  }

  if (specialAreaName) {
    const target = normalize(
      specialAreaName,
    );

    const specialArea = (
      region.specialAreas || []
    ).find(
      (item) =>
        normalize(item.name) === target,
    );

    if (!specialArea) {
      return {
        region: region.name,
        area: null,
        localities: [],
      };
    }

    return {
      region: region.name,
      area: {
        name: specialArea.name,
        type: specialArea.type ??
          'special_area',
      },
      localities:
        specialArea.localities || [],
    };
  }

  return {
    region: region.name,
    area: null,
    localities:
      region.regionLevelLocalities || [],
  };
}

module.exports = {
  getLocalities,
  getProvinces,
  getRegions,
  getStatus,
  loadLocations,
};
