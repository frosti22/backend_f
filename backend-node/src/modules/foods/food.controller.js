const foodService = require('./food.service');

function getUserId(req) {
  return String(
    req.header('x-user-id') || 'test-user',
  ).trim();
}

function parseNonNegativeInteger(
  value,
  defaultValue,
  maximum,
) {
  const parsedValue = Number.parseInt(value, 10);

  if (
    !Number.isInteger(parsedValue) ||
    parsedValue < 0
  ) {
    return defaultValue;
  }

  return Math.min(parsedValue, maximum);
}

function searchFoods(req, res) {
  const query = String(
    req.query.q || '',
  ).trim();

  if (!query) {
    return res.status(400).json({
      success: false,
      message:
        'A search query is required. Example: ?q=rice',
    });
  }

  const dataset = req.query.dataset
    ? String(req.query.dataset).toLowerCase()
    : undefined;

  if (
    dataset &&
    ![
      'foundation',
      'fndds',
      'filipino',
    ].includes(dataset)
  ) {
    return res.status(400).json({
      success: false,
      message:
        'dataset must be foundation, fndds, or filipino.',
    });
  }

  const limit = parseNonNegativeInteger(
    req.query.limit,
    20,
    100,
  );

  const offset = parseNonNegativeInteger(
    req.query.offset,
    0,
    100000,
  );

  const result = foodService.searchFoods({
    userId: getUserId(req),
    query,
    dataset,
    limit,
    offset,
  });

  return res.json({
    success: true,
    query,
    dataset: dataset || 'all',
    total: result.total,
    limit,
    offset,
    data: result.results,
  });
}

function getFoodByFdcId(req, res) {
  const food = foodService.getFoodByFdcId(
    req.params.fdcId,
    getUserId(req),
  );

  if (!food) {
    return res.status(404).json({
      success: false,
      message: 'Food record not found.',
    });
  }

  return res.json({
    success: true,
    data: food,
  });
}

function getFoodStatus(_req, res) {
  const counts =
    foodService.getDatasetCounts();

  return res.json({
    success: true,
    datasets: {
      foundationFoods: counts.foundation,
      fnddsSurveyFoods: counts.fndds,
      filipinoFoods: counts.filipino,
      customFoods: counts.custom,
    },
    totalLoadedFoods:
      counts.total + counts.custom,
  });
}

module.exports = {
  searchFoods,
  getFoodByFdcId,
  getFoodStatus,
};