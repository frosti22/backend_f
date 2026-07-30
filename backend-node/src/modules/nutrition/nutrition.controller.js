const nutritionService = require(
  './nutrition.service',
);

function calculateNutrition(req, res) {
  const { fdcId, consumedGrams } = req.body;

  const numericFdcId = Number(fdcId);
  const numericConsumedGrams =
    Number(consumedGrams);

  if (
    !Number.isInteger(numericFdcId) ||
    numericFdcId <= 0
  ) {
    return res.status(400).json({
      success: false,
      message:
        'fdcId must be a valid positive USDA food ID.',
    });
  }

  if (
    !Number.isFinite(numericConsumedGrams) ||
    numericConsumedGrams <= 0 ||
    numericConsumedGrams > 10000
  ) {
    return res.status(400).json({
      success: false,
      message:
        'consumedGrams must be between 0.01 and 10,000 grams.',
    });
  }

  const result =
    nutritionService.calculateNutrition({
      fdcId: numericFdcId,
      consumedGrams: numericConsumedGrams,
    });

  if (!result) {
    return res.status(404).json({
      success: false,
      message: 'Food record not found.',
    });
  }

  return res.json({
    success: true,
    data: result,
  });
}

module.exports = {
  calculateNutrition,
};