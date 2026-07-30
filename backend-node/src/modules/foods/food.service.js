const fs = require('fs');
const path = require('path');

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
  'filipino_Food_Nutrients.json',
);

let foods = [];
let foodsByFdcId = new Map();

let datasetCounts = {
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

  const fileContents = fs.readFileSync(
    filePath,
    'utf8',
  );

  const parsedData = JSON.parse(fileContents);

  if (!Array.isArray(parsedData)) {
    throw new Error(
      `${datasetName} JSON must contain an array.`,
    );
  }

  return parsedData;
}

function loadFoods() {
  console.log('Loading USDA food datasets...');

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
  /*
   * Place Foundation Foods first because they contain
   * high-quality analytical food records.
   */
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

    /*
     * USDA fdcId values should be unique. This also
     * prevents accidental duplicate records.
     */
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
    `Total searchable foods: ${datasetCounts.total}`,
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

function searchFoods({
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

  const matches = [];

  for (const food of foods) {
    const sourceDataset = normalizeText(
      food.source?.dataset,
    );

    if (normalizedDataset) {

  const wantsFilipino =
    normalizedDataset === 'filipino';

  const wantsFoundation =
    normalizedDataset === 'foundation';

  const wantsFndds =
    normalizedDataset === 'fndds';


  if (
    wantsFilipino &&
    !sourceDataset.includes('filipino')
  ) {
    continue;
  }


  if (
    wantsFoundation &&
    !sourceDataset.includes('foundation')
  ) {
    continue;
  }


  if (
    wantsFndds &&
    !sourceDataset.includes('survey')
  ) {
    continue;
  }
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

    /*
     * Prefer Foundation Foods when scores are equal.
     */
    const aIsFilipino =
  normalizeText(
    a.food.source?.dataset,
  ).includes('filipino');

const bIsFilipino =
  normalizeText(
    b.food.source?.dataset,
  ).includes('filipino');

if (aIsFilipino !== bIsFilipino) {
  return aIsFilipino ? -1 : 1;
}

    const aIsFoundation =
      normalizeText(
        a.food.source?.dataset,
      ).includes('foundation');

    const bIsFoundation =
      normalizeText(
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
      source: food.source,
    }));

  return {
    total: matches.length,
    results,
  };
}

function getFoodByFdcId(fdcId) {
  const numericFdcId = Number(fdcId);

  if (!Number.isInteger(numericFdcId)) {
    return null;
  }

  return foodsByFdcId.get(numericFdcId) || null;
}

function getDatasetCounts() {
  return {
    ...datasetCounts,
  };
}

module.exports = {
  loadFoods,
  searchFoods,
  getFoodByFdcId,
  getDatasetCounts,
};