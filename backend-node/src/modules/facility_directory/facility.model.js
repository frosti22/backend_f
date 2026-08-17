const VERIFIED_COORDINATE_STATUSES = new Set([
  'exact_clinic_pin',
  'exact_building',
  'manually_verified',
  'verified',
]);

function isFiniteCoordinate(value) {
  return value !== null &&
    value !== undefined &&
    value !== '' &&
    Number.isFinite(Number(value));
}

function hasVerifiedCoordinates(facility) {
  return isFiniteCoordinate(facility.latitude) &&
    isFiniteCoordinate(facility.longitude) &&
    facility.exactClinicLocationVerified === true &&
    VERIFIED_COORDINATE_STATUSES.has(
      facility.coordinateStatus,
    );
}

function cleanAddressPart(value) {
  return String(value ?? '')
    .trim()
    .replace(/^[,;\s]+|[,;\s]+$/g, '')
    .replace(/\s+/g, ' ');
}

function buildGoogleMapsAddress(facility) {
  return [
    facility.name,
    facility.streetAddress,
    facility.barangay,
    facility.cityMunicipality,
    facility.province,
    'Philippines',
  ]
    .map(cleanAddressPart)
    .filter(Boolean)
    .join(', ');
}

function buildGoogleMapsSearchUrl(facility) {
  const query = buildGoogleMapsAddress(facility);

  return (
    'https://www.google.com/maps/search/?api=1' +
    `&query=${encodeURIComponent(query)}`
  );
}

function buildGoogleMapsDirectionsUrl(facility) {
  const destination = hasVerifiedCoordinates(facility)
    ? `${Number(facility.latitude)},${Number(facility.longitude)}`
    : buildGoogleMapsAddress(facility);

  return (
    'https://www.google.com/maps/dir/?api=1' +
    `&destination=${encodeURIComponent(destination)}` +
    '&travelmode=driving' +
    '&dir_action=navigate'
  );
}

function serializeFacility(facility, distanceKm = null) {
  return {
    facilityNumber: facility.facilityNumber,
    name: facility.name,
    facilityType: facility.facilityType,
    region: facility.region,
    province: facility.province ?? null,
    specialArea: facility.specialArea ?? null,
    cityMunicipality: facility.cityMunicipality,
    cityMunicipalityType:
      facility.cityMunicipalityType ?? null,
    subLocality: facility.subLocality ?? null,
    barangay: facility.barangay ?? null,
    streetAddress: facility.streetAddress ?? null,
    telephone: Array.isArray(facility.telephone)
      ? facility.telephone
      : facility.telephone
        ? [String(facility.telephone)]
        : [],
    email: Array.isArray(facility.email)
      ? facility.email
      : facility.email
        ? [String(facility.email)]
        : [],
    latitude: isFiniteCoordinate(facility.latitude)
      ? Number(facility.latitude)
      : null,
    longitude: isFiniteCoordinate(facility.longitude)
      ? Number(facility.longitude)
      : null,
    distanceKm,
    coordinateStatus:
      facility.coordinateStatus ?? 'unresolved',
    coordinateSource:
      facility.coordinateSource ?? null,
    coordinateConfidence:
      facility.coordinateConfidence ?? null,
    coordinateCheckedAt:
      facility.coordinateCheckedAt ?? null,
    exactClinicLocationVerified:
      facility.exactClinicLocationVerified === true,
    accreditationExpiry:
      facility.accreditationExpiry ?? null,
    sector: facility.sector ?? null,
    source: facility.source ?? null,
    sourcePage: facility.sourcePage ?? null,

    // These links work without a Google Maps API key. They use the
    // clinic name and full address, so latitude/longitude are optional.
    googleMapsQuery: buildGoogleMapsAddress(facility),
    googleMapsSearchUrl:
      buildGoogleMapsSearchUrl(facility),
    googleMapsDirectionsUrl:
      buildGoogleMapsDirectionsUrl(facility),
    googleMapsDestinationType: hasVerifiedCoordinates(facility)
      ? 'verified_coordinates'
      : 'clinic_name_and_address',
  };
}

module.exports = {
  VERIFIED_COORDINATE_STATUSES,
  buildGoogleMapsAddress,
  buildGoogleMapsDirectionsUrl,
  buildGoogleMapsSearchUrl,
  hasVerifiedCoordinates,
  isFiniteCoordinate,
  serializeFacility,
};
