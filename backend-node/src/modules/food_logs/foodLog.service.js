const { randomUUID } = require('crypto');

const nutritionService = require(
  '../nutrition/nutrition.service',
);

const foodLogs = [];

const VALID_MEAL_TYPES = new Set([
  'breakfast',
  'lunch',
  'dinner',
  'snack',
  'other',
]);

function roundNumber(value, decimalPlaces = 2) {
  const multiplier = 10 ** decimalPlaces;

  return (
    Math.round(
      (value + Number.EPSILON) * multiplier,
    ) / multiplier
  );
}

function createFoodLog({
  userId,
  fdcId,
  consumedGrams,
  mealType,
  consumedAt,
  notes,
  clientRecordId,
}) {
  if (clientRecordId) {
    const existingRecord = foodLogs.find(
      (record) =>
        record.userId === userId &&
        record.clientRecordId === clientRecordId,
    );

    if (existingRecord) {
      return {
        created: false,
        duplicate: true,
        record: existingRecord,
      };
    }
  }

  const nutritionResult =
    nutritionService.calculateNutrition({
      fdcId,
      consumedGrams,
    });

  if (!nutritionResult) {
    return {
      created: false,
      duplicate: false,
      record: null,
    };
  }

  const now = new Date().toISOString();

  const record = {
    id: randomUUID(),

    // Temporary until JWT authentication is connected.
    userId,

    clientRecordId: clientRecordId || null,

    food: {
      fdcId: nutritionResult.food.fdcId,
      name: nutritionResult.food.name,
      category: nutritionResult.food.category,
      source: nutritionResult.food.source,
    },

    mealType,

    quantity: {
      consumedGrams,
      unit: 'g',
    },

    nutrients: nutritionResult.calculatedNutrients,

    consumedAt: consumedAt || now,
    notes: notes || null,

    createdAt: now,
    updatedAt: now,
  };

  foodLogs.push(record);

  return {
    created: true,
    duplicate: false,
    record,
  };
}

function normalizeManualNutrient(value) {
  if (
    value === undefined ||
    value === null ||
    value === ''
  ) {
    return null;
  }

  const numericValue = Number(value);

  if (
    !Number.isFinite(numericValue) ||
    numericValue < 0
  ) {
    return null;
  }

  return roundNumber(numericValue);
}

function createManualFoodLog({
  userId,
  name,
  category,
  consumedGrams,
  mealType,
  consumedAt,
  nutrients,
  notes,
  clientRecordId,
}) {
  if (clientRecordId) {
    const existingRecord = foodLogs.find(
      (record) =>
        record.userId === userId &&
        record.clientRecordId === clientRecordId,
    );

    if (existingRecord) {
      return {
        created: false,
        duplicate: true,
        record: existingRecord,
      };
    }
  }

  const now = new Date().toISOString();

  const record = {
    id: randomUUID(),
    userId,

    clientRecordId: clientRecordId || null,

    food: {
      fdcId: null,
      name: name.trim(),
      category: category?.trim() || null,

      source: {
        provider: 'User',
        dataset: 'Manual nutrient entry',
      },
    },

    mealType,

    quantity: {
      consumedGrams,
      unit: 'g',
    },

    nutrients: {
      energyKcal: normalizeManualNutrient(
        nutrients.energyKcal,
      ),

      proteinG: normalizeManualNutrient(
        nutrients.proteinG,
      ),

      carbohydratesG: normalizeManualNutrient(
        nutrients.carbohydratesG,
      ),

      fatG: normalizeManualNutrient(
        nutrients.fatG,
      ),

      sodiumMg: normalizeManualNutrient(
        nutrients.sodiumMg,
      ),

      potassiumMg: normalizeManualNutrient(
        nutrients.potassiumMg,
      ),
    },

    consumedAt: consumedAt || now,
    notes: notes?.trim() || null,

    createdAt: now,
    updatedAt: now,
  };

  foodLogs.push(record);

  return {
    created: true,
    duplicate: false,
    record,
  };
}

function getFoodLogs({
  userId,
  date,
  mealType,
}) {
  let results = foodLogs.filter(
    (record) => record.userId === userId,
  );

  if (mealType) {
    results = results.filter(
      (record) => record.mealType === mealType,
    );
  }

  if (date) {
    const startDate = new Date(
      `${date}T00:00:00.000Z`,
    );

    const endDate = new Date(
      `${date}T23:59:59.999Z`,
    );

    results = results.filter((record) => {
      const consumedAt = new Date(record.consumedAt);

      return (
        consumedAt >= startDate &&
        consumedAt <= endDate
      );
    });
  }

  return [...results].sort(
    (a, b) =>
      new Date(b.consumedAt) -
      new Date(a.consumedAt),
  );
}

function getFoodLogById({
  userId,
  id,
}) {
  return (
    foodLogs.find(
      (record) =>
        record.id === id &&
        record.userId === userId,
    ) || null
  );
}

function updateFoodLog({
  userId,
  id,
  changes,
}) {
  const index = foodLogs.findIndex(
    (record) =>
      record.id === id &&
      record.userId === userId,
  );

  if (index === -1) {
    return {
      status: 'not_found',
      record: null,
    };
  }

  const existingRecord = foodLogs[index];

  const nextFdcId =
    changes.fdcId !== undefined
      ? changes.fdcId
      : existingRecord.food.fdcId;

  const nextConsumedGrams =
    changes.consumedGrams !== undefined
      ? changes.consumedGrams
      : existingRecord.quantity.consumedGrams;

  const nutritionResult =
    nutritionService.calculateNutrition({
      fdcId: nextFdcId,
      consumedGrams: nextConsumedGrams,
    });

  if (!nutritionResult) {
    return {
      status: 'food_not_found',
      record: null,
    };
  }

  const updatedRecord = {
    ...existingRecord,

    food: {
      fdcId: nutritionResult.food.fdcId,
      name: nutritionResult.food.name,
      category: nutritionResult.food.category,
      source: nutritionResult.food.source,
    },

    mealType:
      changes.mealType ??
      existingRecord.mealType,

    quantity: {
      consumedGrams: nextConsumedGrams,
      unit: 'g',
    },

    nutrients:
      nutritionResult.calculatedNutrients,

    consumedAt:
      changes.consumedAt ??
      existingRecord.consumedAt,

    notes:
      changes.notes !== undefined
        ? changes.notes
        : existingRecord.notes,

    updatedAt: new Date().toISOString(),
  };

  foodLogs[index] = updatedRecord;

  return {
    status: 'updated',
    record: updatedRecord,
  };
}

function deleteFoodLog({
  userId,
  id,
}) {
  const index = foodLogs.findIndex(
    (record) =>
      record.id === id &&
      record.userId === userId,
  );

  if (index === -1) {
    return null;
  }

  const [deletedRecord] = foodLogs.splice(
    index,
    1,
  );

  return deletedRecord;
}

function sumNutrient(records, nutrientKey) {
  let total = 0;
  let hasAvailableValue = false;

  for (const record of records) {
    const value = record.nutrients?.[nutrientKey];

    if (
      typeof value === 'number' &&
      Number.isFinite(value)
    ) {
      total += value;
      hasAvailableValue = true;
    }
  }

  return hasAvailableValue
    ? roundNumber(total)
    : null;
}

function getFoodLogSummary({
  userId,
  date,
}) {
  const records = getFoodLogs({
    userId,
    date,
  });

  return {
    date: date || null,
    recordCount: records.length,

    totals: {
      energyKcal: sumNutrient(
        records,
        'energyKcal',
      ),

      proteinG: sumNutrient(
        records,
        'proteinG',
      ),

      carbohydratesG: sumNutrient(
        records,
        'carbohydratesG',
      ),

      fatG: sumNutrient(
        records,
        'fatG',
      ),

      sodiumMg: sumNutrient(
        records,
        'sodiumMg',
      ),

      potassiumMg: sumNutrient(
        records,
        'potassiumMg',
      ),
    },
  };
}

module.exports = {
  VALID_MEAL_TYPES,
  createFoodLog,
  createManualFoodLog,
  getFoodLogs,
  getFoodLogById,
  updateFoodLog,
  deleteFoodLog,
  getFoodLogSummary,
};