const foodLogService = require(
  './foodLog.service',
);

function getUserId(req) {
  /*
   * Temporary testing user.
   * Later, authentication middleware should provide:
   * req.user.id
   */
  return String(
    req.header('x-user-id') || 'test-user',
  ).trim();
}

function validateFdcId(value) {
  const number = Number(value);

  return (
    Number.isInteger(number) &&
    number > 0
  );
}

function validateConsumedGrams(value) {
  const number = Number(value);

  return (
    Number.isFinite(number) &&
    number > 0 &&
    number <= 10000
  );
}

function validateMealType(value) {
  return foodLogService.VALID_MEAL_TYPES.has(
    String(value || '').toLowerCase(),
  );
}

function validateDate(value) {
  return (
    value === undefined ||
    value === null ||
    !Number.isNaN(Date.parse(value))
  );
}

const MANUAL_NUTRIENT_KEYS = [
  'energyKcal',
  'proteinG',
  'carbohydratesG',
  'fatG',
  'sodiumMg',
  'potassiumMg',
];

function validateManualNutrients(input) {
  if (
    !input ||
    typeof input !== 'object' ||
    Array.isArray(input)
  ) {
    return {
      valid: false,
      message: 'nutrients must be an object.',
    };
  }

  const normalized = {};
  let providedCount = 0;

  for (const key of MANUAL_NUTRIENT_KEYS) {
    const value = input[key];

    if (
      value === undefined ||
      value === null ||
      value === ''
    ) {
      normalized[key] = null;
      continue;
    }

    const numericValue = Number(value);

    if (
      !Number.isFinite(numericValue) ||
      numericValue < 0
    ) {
      return {
        valid: false,
        message: `${key} must be zero or a positive number.`,
      };
    }

    normalized[key] = numericValue;
    providedCount += 1;
  }

  if (providedCount === 0) {
    return {
      valid: false,
      message:
        'Enter at least one nutrient value.',
    };
  }

  return {
    valid: true,
    nutrients: normalized,
  };
}

function createFoodLog(req, res) {
  const {
    fdcId,
    consumedGrams,
    mealType,
    consumedAt,
    notes,
    clientRecordId,
  } = req.body;

  if (!validateFdcId(fdcId)) {
    return res.status(400).json({
      success: false,
      message:
        'fdcId must be a valid USDA food ID.',
    });
  }

  if (!validateConsumedGrams(consumedGrams)) {
    return res.status(400).json({
      success: false,
      message:
        'consumedGrams must be between 0.01 and 10,000 grams.',
    });
  }

  if (!validateMealType(mealType)) {
    return res.status(400).json({
      success: false,
      message:
        'mealType must be breakfast, lunch, dinner, snack, or other.',
    });
  }

  if (!validateDate(consumedAt)) {
    return res.status(400).json({
      success: false,
      message:
        'consumedAt must be a valid date and time.',
    });
  }

  const result = foodLogService.createFoodLog({
    userId: getUserId(req),
    fdcId: Number(fdcId),
    consumedGrams: Number(consumedGrams),
    mealType: mealType.toLowerCase(),
    consumedAt,
    notes,
    clientRecordId,
  });

  if (!result.record) {
    return res.status(404).json({
      success: false,
      message: 'Food record not found.',
    });
  }

  if (result.duplicate) {
    return res.status(200).json({
      success: true,
      duplicate: true,
      message:
        'This food log was already submitted.',
      data: result.record,
    });
  }

  return res.status(201).json({
    success: true,
    duplicate: false,
    message:
      'Food log created successfully.',
    data: result.record,
  });
}

function createManualFoodLog(req, res) {
  const {
    name,
    category,
    consumedGrams,
    mealType,
    consumedAt,
    nutrients,
    notes,
    clientRecordId,
  } = req.body;

  if (
    typeof name !== 'string' ||
    name.trim().length < 2 ||
    name.trim().length > 150
  ) {
    return res.status(400).json({
      success: false,
      message:
        'name must contain between 2 and 150 characters.',
    });
  }

  if (!validateConsumedGrams(consumedGrams)) {
    return res.status(400).json({
      success: false,
      message:
        'consumedGrams must be between 0.01 and 10,000 grams.',
    });
  }

  if (!validateMealType(mealType)) {
    return res.status(400).json({
      success: false,
      message:
        'mealType must be breakfast, lunch, dinner, snack, or other.',
    });
  }

  if (!validateDate(consumedAt)) {
    return res.status(400).json({
      success: false,
      message:
        'consumedAt must be a valid date and time.',
    });
  }

  const nutrientValidation =
    validateManualNutrients(nutrients);

  if (!nutrientValidation.valid) {
    return res.status(400).json({
      success: false,
      message: nutrientValidation.message,
    });
  }

  const result =
    foodLogService.createManualFoodLog({
      userId: getUserId(req),
      name: name.trim(),
      category,
      consumedGrams: Number(consumedGrams),
      mealType: mealType.toLowerCase(),
      consumedAt,
      nutrients:
        nutrientValidation.nutrients,
      notes,
      clientRecordId,
    });

  if (result.duplicate) {
    return res.status(200).json({
      success: true,
      duplicate: true,
      message:
        'This manual food log was already submitted.',
      data: result.record,
    });
  }

  return res.status(201).json({
    success: true,
    duplicate: false,
    message:
      'Manual food log created successfully.',
    data: result.record,
  });
}

function getFoodLogs(req, res) {
  const mealType = req.query.mealType
    ? String(req.query.mealType).toLowerCase()
    : undefined;

  if (
    mealType &&
    !validateMealType(mealType)
  ) {
    return res.status(400).json({
      success: false,
      message: 'Invalid meal type.',
    });
  }

  const records = foodLogService.getFoodLogs({
    userId: getUserId(req),
    date: req.query.date,
    mealType,
  });

  return res.json({
    success: true,
    count: records.length,
    data: records,
  });
}

function getFoodLogById(req, res) {
  const record =
    foodLogService.getFoodLogById({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!record) {
    return res.status(404).json({
      success: false,
      message: 'Food log not found.',
    });
  }

  return res.json({
    success: true,
    data: record,
  });
}

function updateFoodLog(req, res) {
  const {
    fdcId,
    consumedGrams,
    mealType,
    consumedAt,
  } = req.body;

  if (
    fdcId !== undefined &&
    !validateFdcId(fdcId)
  ) {
    return res.status(400).json({
      success: false,
      message: 'Invalid fdcId.',
    });
  }

  if (
    consumedGrams !== undefined &&
    !validateConsumedGrams(consumedGrams)
  ) {
    return res.status(400).json({
      success: false,
      message: 'Invalid consumedGrams.',
    });
  }

  if (
    mealType !== undefined &&
    !validateMealType(mealType)
  ) {
    return res.status(400).json({
      success: false,
      message: 'Invalid mealType.',
    });
  }

  if (!validateDate(consumedAt)) {
    return res.status(400).json({
      success: false,
      message: 'Invalid consumedAt date.',
    });
  }

  const result =
    foodLogService.updateFoodLog({
      userId: getUserId(req),
      id: req.params.id,

      changes: {
        ...req.body,

        fdcId:
          fdcId !== undefined
            ? Number(fdcId)
            : undefined,

        consumedGrams:
          consumedGrams !== undefined
            ? Number(consumedGrams)
            : undefined,

        mealType:
          mealType !== undefined
            ? mealType.toLowerCase()
            : undefined,
      },
    });

  if (result.status === 'not_found') {
    return res.status(404).json({
      success: false,
      message: 'Food log not found.',
    });
  }

  if (result.status === 'food_not_found') {
    return res.status(404).json({
      success: false,
      message:
        'The selected USDA food was not found.',
    });
  }

  return res.json({
    success: true,
    message:
      'Food log updated successfully.',
    data: result.record,
  });
}

function deleteFoodLog(req, res) {
  const record =
    foodLogService.deleteFoodLog({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!record) {
    return res.status(404).json({
      success: false,
      message: 'Food log not found.',
    });
  }

  return res.json({
    success: true,
    message:
      'Food log deleted successfully.',
    data: record,
  });
}

function getFoodLogSummary(req, res) {
  const summary =
    foodLogService.getFoodLogSummary({
      userId: getUserId(req),
      date: req.query.date,
    });

  return res.json({
    success: true,
    data: summary,
  });
}

module.exports = {
  createFoodLog,
  createManualFoodLog,
  getFoodLogs,
  getFoodLogById,
  updateFoodLog,
  deleteFoodLog,
  getFoodLogSummary,
};