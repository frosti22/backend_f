function parsePositiveInteger(
  value,
  defaultValue,
  maximum,
) {
  const parsed = Number.parseInt(value, 10);

  if (!Number.isInteger(parsed) || parsed <= 0) {
    return defaultValue;
  }

  return Math.min(parsed, maximum);
}

function parseNonNegativeInteger(
  value,
  defaultValue,
  maximum,
) {
  const parsed = Number.parseInt(value, 10);

  if (!Number.isInteger(parsed) || parsed < 0) {
    return defaultValue;
  }

  return Math.min(parsed, maximum);
}

function parseOptionalCoordinate(value, fieldName) {
  if (
    value === undefined ||
    value === null ||
    value === ''
  ) {
    return null;
  }

  const parsed = Number(value);

  if (!Number.isFinite(parsed)) {
    throw new Error(
      `${fieldName} must be a valid number.`,
    );
  }

  if (
    fieldName === 'latitude' &&
    (parsed < -90 || parsed > 90)
  ) {
    throw new Error(
      'latitude must be between -90 and 90.',
    );
  }

  if (
    fieldName === 'longitude' &&
    (parsed < -180 || parsed > 180)
  ) {
    throw new Error(
      'longitude must be between -180 and 180.',
    );
  }

  return parsed;
}

function validateRecommendationBody(body) {
  const region = String(body.region || '').trim();
  const cityMunicipality = String(
    body.cityMunicipality || '',
  ).trim();

  if (!region) {
    throw new Error('region is required.');
  }

  if (!cityMunicipality) {
    throw new Error(
      'cityMunicipality is required.',
    );
  }

  const latitude = parseOptionalCoordinate(
    body.latitude,
    'latitude',
  );

  const longitude = parseOptionalCoordinate(
    body.longitude,
    'longitude',
  );

  if (
    (latitude === null) !==
    (longitude === null)
  ) {
    throw new Error(
      'latitude and longitude must be provided together.',
    );
  }

  return {
    region,
    province: body.province
      ? String(body.province).trim()
      : null,
    cityMunicipality,
    latitude,
    longitude,
    limit: parsePositiveInteger(
      body.limit,
      20,
      100,
    ),
  };
}

module.exports = {
  parsePositiveInteger,
  parseNonNegativeInteger,
  validateRecommendationBody,
};
