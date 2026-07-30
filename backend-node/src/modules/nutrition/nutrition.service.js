const foodService = require(
  '../foods/food.service',
);

const NUTRIENT_KEYS = [
  'energyKcal',
  'proteinG',
  'carbohydratesG',
  'fatG',
  'sodiumMg',
  'potassiumMg',
];

function roundNumber(
  value,
  decimalPlaces = 2,
) {
  const multiplier = 10 ** decimalPlaces;

  return (
    Math.round(
      (value + Number.EPSILON) * multiplier,
    ) / multiplier
  );
}

function calculateNutrientAmount(
  nutrientPer100g,
  consumedGrams,
) {
  /*
   * Keep missing nutrients as null.
   * This allows carbohydrates and potassium
   * to remain hidden when the food has no value.
   */
  if (
    nutrientPer100g === null ||
    nutrientPer100g === undefined ||
    nutrientPer100g === ''
  ) {
    return null;
  }

  const numericNutrient = Number(
    nutrientPer100g,
  );

  if (!Number.isFinite(numericNutrient)) {
    return null;
  }

  return roundNumber(
    (numericNutrient * consumedGrams) / 100,
  );
}

function calculateNutrition({
  userId = 'test-user',
  fdcId,
  consumedGrams,
}) {
  /*
   * Pass the user ID so manually created foods
   * can also be found and calculated.
   */
  const food = foodService.getFoodByFdcId(
    fdcId,
    userId,
  );

  if (!food) {
    return null;
  }

  const nutrientsPer100g =
    food.nutrientsPer100g || {};

  const calculatedNutrients = {};

  for (const nutrientKey of NUTRIENT_KEYS) {
    calculatedNutrients[nutrientKey] =
      calculateNutrientAmount(
        nutrientsPer100g[nutrientKey],
        consumedGrams,
      );
  }

  return {
    food: {
      fdcId: food.source?.fdcId ?? null,
      name: food.name,
      category: food.category ?? null,
      source: food.source,
      isCustom:
        food.source?.isCustom === true,
    },

    quantity: {
      consumedGrams,
      unit: 'g',
      nutrientBasis: 'per 100 g',
    },

    nutrientsPer100g,

    calculatedNutrients,

    calculatedAt: new Date().toISOString(),

    disclaimer:
      'Nutrition values are estimates based on the selected food record and quantity.',
  };
}

module.exports = {
  calculateNutrition,
};