const facilityService = require(
  './facility.service',
);
const {
  parseNonNegativeInteger,
  parsePositiveInteger,
  validateRecommendationBody,
} = require('./facility.validator');

function getStatus(_req, res) {
  return res.json({
    success: true,
    data: facilityService.getStatus(),
  });
}

function listFacilities(req, res) {
  const limit = parsePositiveInteger(
    req.query.limit,
    20,
    100,
  );

  const offset = parseNonNegativeInteger(
    req.query.offset,
    0,
    100000,
  );

  const onlyCurrent =
    String(
      req.query.onlyCurrent ?? 'true',
    ).toLowerCase() !== 'false';

  const onlyVerifiedCoordinates =
    String(
      req.query.onlyVerifiedCoordinates ??
        'false',
    ).toLowerCase() === 'true';

  const result =
    facilityService.listFacilities({
      region: req.query.region,
      province: req.query.province,
      cityMunicipality:
        req.query.cityMunicipality,
      query: req.query.q,
      onlyCurrent,
      onlyVerifiedCoordinates,
      limit,
      offset,
    });

  return res.json({
    success: true,
    total: result.total,
    limit,
    offset,
    data: result.results,
  });
}

function getFacility(req, res) {
  const facility =
    facilityService.getFacilityByNumber(
      req.params.facilityNumber,
    );

  if (!facility) {
    return res.status(404).json({
      success: false,
      message: 'Facility was not found.',
    });
  }

  return res.json({
    success: true,
    data: facility,
  });
}

function recommendFacilities(req, res) {
  try {
    const input = validateRecommendationBody(
      req.body || {},
    );

    const result =
      facilityService.recommendFacilities(input);

    return res.json({
      success: true,
      selectedLocation: {
        region: input.region,
        province: input.province,
        cityMunicipality:
          input.cityMunicipality,
        latitude: input.latitude,
        longitude: input.longitude,
      },
      data: result,
    });
  } catch (error) {
    return res.status(400).json({
      success: false,
      message: error.message,
    });
  }
}

module.exports = {
  getFacility,
  getStatus,
  listFacilities,
  recommendFacilities,
};
