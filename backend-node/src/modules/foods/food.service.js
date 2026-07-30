const fs = require('fs');
const path = require('path');
const { randomUUID } = require('crypto');

const localStorage = require(
  '../../common/storage/localJsonStorage',
);

const FOUNDATION_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'usda',
  'processed',
  'foundation_foods.json',
);

const FNDDS_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'usda',
  'processed',
  'fndds_foods.json',
);

const FILIPINO_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'filipino_foods',
  'processed',
  'Filipino_Food_Nutrients.json',
);

const customFoods = localStorage.getCollection(
  'customFoods',
);

let foods = [];
let foodsByFdcId = new Map();

let datasetCounts = {
  filipino: 0,
  foundation: 0,
  fndds: 0,
  total: 0,
};

function readJsonArray(filePath, datasetName) {
  if (!fs.existsSync(filePath)) {
    throw new Error(
      `${datasetName} JSON file was not found: ${filePath}`,
    );
  }

  const parsedData = JSON.parse(
    fs.readFileSync(filePath, 'utf8'),
  );

  if (!Array.isArray(parsedData)) {
    throw new Error(
      `${datasetName} JSON must contain an array.`,
    );
  }

  return parsedData;
}

function loadFoods() {
  console.log('Loading food datasets...');

  const foundationFoods = readJsonArray(
    FOUNDATION_FILE,
    'Foundation Foods',
  );

  const fnddsFoods = readJsonArray(
    FNDDS_FILE,
    'FNDDS Survey Foods',
  );

  const filipinoFoods = readJsonArray(
    FILIPINO_FILE,
    'Filipino Foods',
  );

  const combinedFoods = [
    ...filipinoFoods,
    ...foundationFoods,
    ...fnddsFoods,
  ];

  foodsByFdcId = new Map();

  for (const food of combinedFoods) {
    const fdcId = Number(food.source?.fdcId);

    if (!Number.isInteger(fdcId)) {
      continue;
    }

    if (!foodsByFdcId.has(fdcId)) {
      foodsByFdcId.set(fdcId, food);
    }
  }

  foods = Array.from(foodsByFdcId.values());

  datasetCounts = {
    filipino: filipinoFoods.length,
    foundation: foundationFoods.length,
    fndds: fnddsFoods.length,
    total: foods.length,
  };

  console.log(
    `Loaded ${datasetCounts.filipino} Filipino Foods.`,
  );

  console.log(
    `Loaded ${datasetCounts.foundation} Foundation Foods.`,
  );

  console.log(
    `Loaded ${datasetCounts.fndds} FNDDS Survey Foods.`,
  );

  console.log(
    `Total searchable dataset foods: ${datasetCounts.total}`,
  );
}

function normalizeText(value) {
  return String(value || '')
    .trim()
    .toLowerCase();
}

function getSearchScore(food, query) {
  const name = normalizeText(food.name);
  const category = normalizeText(food.category);

  if (name === query) {
    return 100;
  }

  if (name.startsWith(query)) {
    return 80;
  }

  if (name.includes(query)) {
    return 60;
  }

  if (category.startsWith(query)) {
    return 30;
  }

  if (category.includes(query)) {
    return 20;
  }

  return 0;
}

function isDatasetMatch(food, normalizedDataset) {
  if (!normalizedDataset) {
    return true;
  }

  const sourceDataset = normalizeText(
    food.source?.dataset,
  );

  if (normalizedDataset === 'filipino') {
    return sourceDataset.includes('filipino');
  }

  if (normalizedDataset === 'foundation') {
    return sourceDataset.includes('foundation');
  }

  if (normalizedDataset === 'fndds') {
    return sourceDataset.includes('survey');
  }

  return false;
}

function searchFoods({
  userId,
  query,
  limit = 20,
  offset = 0,
  dataset,
}) {
  const normalizedQuery = normalizeText(query);
  const normalizedDataset = normalizeText(dataset);

  if (!normalizedQuery) {
    return {
      total: 0,
      results: [],
    };
  }

  /*
   * When no dataset filter is selected, include foods
   * manually created by the current user.
   */
  const searchableFoods = normalizedDataset
    ? foods
    : [
        ...customFoods.filter(
          (food) => food.userId === userId,
        ),
        ...foods,
      ];

  const matches = [];

  for (const food of searchableFoods) {
    if (!isDatasetMatch(food, normalizedDataset)) {
      continue;
    }

    const score = getSearchScore(
      food,
      normalizedQuery,
    );

    if (score === 0) {
      continue;
    }

    matches.push({
      food,
      score,
    });
  }

  matches.sort((a, b) => {
    if (b.score !== a.score) {
      return b.score - a.score;
    }

    const aIsCustom =
      a.food.source?.isCustom === true;

    const bIsCustom =
      b.food.source?.isCustom === true;

    /*
     * Put the user's manually added foods first.
     */
    if (aIsCustom !== bIsCustom) {
      return aIsCustom ? -1 : 1;
    }

    const aIsFilipino = normalizeText(
      a.food.source?.dataset,
    ).includes('filipino');

    const bIsFilipino = normalizeText(
      b.food.source?.dataset,
    ).includes('filipino');

    if (aIsFilipino !== bIsFilipino) {
      return aIsFilipino ? -1 : 1;
    }

    const aIsFoundation = normalizeText(
      a.food.source?.dataset,
    ).includes('foundation');

    const bIsFoundation = normalizeText(
      b.food.source?.dataset,
    ).includes('foundation');

    if (aIsFoundation !== bIsFoundation) {
      return aIsFoundation ? -1 : 1;
    }

    return String(a.food.name).localeCompare(
      String(b.food.name),
    );
  });

  const results = matches
    .slice(offset, offset + limit)
    .map(({ food }) => ({
      fdcId: food.source?.fdcId ?? null,
      name: food.name,
      category: food.category ?? null,
      nutrientBasis:
        food.nutrientBasis ?? 'per 100 g',
      nutrientsPer100g:
        food.nutrientsPer100g ?? {},
      portions: food.portions ?? [],
      isCustom:
        food.source?.isCustom === true,
    }));

  return {
    total: matches.length,
    results,
  };
}

function getFoodByFdcId(fdcId, userId) {
  const numericFdcId = Number(fdcId);

  if (!Number.isInteger(numericFdcId)) {
    return null;
  }

  const datasetFood =
    foodsByFdcId.get(numericFdcId);

  if (datasetFood) {
    return datasetFood;
  }

  return (
    customFoods.find(
      (food) =>
        food.userId === userId &&
        Number(food.source?.fdcId) ===
          numericFdcId,
    ) || null
  );
}

function nextCustomFdcId() {
  /*
   * Custom foods use a high number range so that their
   * IDs do not conflict with USDA or Filipino food IDs.
   */
  let highest = 1500000000;

  for (const fdcId of foodsByFdcId.keys()) {
    if (
      Number.isInteger(fdcId) &&
      fdcId > highest
    ) {
      highest = fdcId;
    }
  }

  for (const food of customFoods) {
    const fdcId = Number(food.source?.fdcId);

    if (
      Number.isInteger(fdcId) &&
      fdcId > highest
    ) {
      highest = fdcId;
    }
  }

  return highest + 1;
}

function normalizeNutrientPer100g(
  value,
  consumedGrams,
) {
  if (
    value === undefined ||
    value === null ||
    value === ''
  ) {
    return null;
  }

  const numericValue = Number(value);

  if (!Number.isFinite(numericValue)) {
    return null;
  }

  return (
    Math.round(
      (
        (numericValue * 100) /
          consumedGrams +
        Number.EPSILON
      ) * 100,
    ) / 100
  );
}

function saveCustomFood({
  userId,
  name,
  category,
  consumedGrams,
  nutrients,
}) {
  const normalizedName = normalizeText(name);
  const now = new Date().toISOString();

  /*
   * The user enters nutrients for the consumed amount.
   * Convert those values into per-100-gram values so
   * other serving amounts can be calculated later.
   */
  const nutrientsPer100g = {
    energyKcal: normalizeNutrientPer100g(
      nutrients.energyKcal,
      consumedGrams,
    ),

    proteinG: normalizeNutrientPer100g(
      nutrients.proteinG,
      consumedGrams,
    ),

    carbohydratesG:
      normalizeNutrientPer100g(
        nutrients.carbohydratesG,
        consumedGrams,
      ),

    fatG: normalizeNutrientPer100g(
      nutrients.fatG,
      consumedGrams,
    ),

    sodiumMg: normalizeNutrientPer100g(
      nutrients.sodiumMg,
      consumedGrams,
    ),

    potassiumMg:
      normalizeNutrientPer100g(
        nutrients.potassiumMg,
        consumedGrams,
      ),
  };

  /*
   * When a food with the same name already exists for
   * this user, update it instead of making a duplicate.
   */
  const existingIndex = customFoods.findIndex(
    (food) =>
      food.userId === userId &&
      normalizeText(food.name) ===
        normalizedName,
  );

  if (existingIndex !== -1) {
    const existing = customFoods[existingIndex];

    const updated = {
      ...existing,
      name: name.trim(),
      category:
        category?.trim() || null,
      nutrientBasis: 'per 100 g',
      nutrientsPer100g,
      updatedAt: now,
    };

    customFoods[existingIndex] = updated;

    localStorage.persist();

    return updated;
  }

  const customFood = {
    id: randomUUID(),
    userId,
    name: name.trim(),
    category:
      category?.trim() || null,
    nutrientBasis: 'per 100 g',
    nutrientsPer100g,
    portions: [],
    source: {
      fdcId: nextCustomFdcId(),
      provider: 'User',
      dataset: 'Custom foods',
      isCustom: true,
    },
    createdAt: now,
    updatedAt: now,
  };

  customFoods.push(customFood);

  localStorage.persist();

  return customFood;
}

function getDatasetCounts() {
  return {
    ...datasetCounts,
    custom: customFoods.length,
  };
}

module.exports = {
  loadFoods,
  searchFoods,
  getFoodByFdcId,
  saveCustomFood,
  getDatasetCounts,
};