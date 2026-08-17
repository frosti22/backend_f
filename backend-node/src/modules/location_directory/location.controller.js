const locationService = require(
  './location.service',
);

function getStatus(_req, res) {
  return res.json({
    success: true,
    data: locationService.getStatus(),
  });
}

function getRegions(_req, res) {
  return res.json({
    success: true,
    data: locationService.getRegions(),
  });
}

function getProvinces(req, res) {
  const region = String(
    req.query.region || '',
  ).trim();

  if (!region) {
    return res.status(400).json({
      success: false,
      message:
        'The region query parameter is required.',
    });
  }

  const result =
    locationService.getProvinces(region);

  if (!result) {
    return res.status(404).json({
      success: false,
      message: 'Region was not found.',
    });
  }

  return res.json({
    success: true,
    data: result,
  });
}

function getLocalities(req, res) {
  const region = String(
    req.query.region || '',
  ).trim();

  if (!region) {
    return res.status(400).json({
      success: false,
      message:
        'The region query parameter is required.',
    });
  }

  const result =
    locationService.getLocalities({
      regionName: region,
      provinceName:
        req.query.province
          ? String(req.query.province).trim()
          : null,
      specialAreaName:
        req.query.specialArea
          ? String(
              req.query.specialArea,
            ).trim()
          : null,
    });

  if (!result) {
    return res.status(404).json({
      success: false,
      message: 'Region was not found.',
    });
  }

  return res.json({
    success: true,
    data: result,
  });
}

module.exports = {
  getLocalities,
  getProvinces,
  getRegions,
  getStatus,
};
