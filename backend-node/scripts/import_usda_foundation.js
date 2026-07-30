const fs = require('fs');
const path = require('path');
const csv = require('csv-parser');

const RAW_DIRECTORY = path.join(
  __dirname,
  '..',
  'data',
  'usda',
  'raw',
  'foundation',
);

const OUTPUT_DIRECTORY = path.join(
  __dirname,
  '..',
  'data',
  'usda',
  'processed',
);

const OUTPUT_FILE = path.join(
  OUTPUT_DIRECTORY,
  'foundation_foods.json',
);

function cleanHeader(header) {
  return header
    .replace(/^\uFEFF/, '')
    .trim();
}

function readCsv(filename) {
  const filePath = path.join(RAW_DIRECTORY, filename);

  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing required file: ${filePath}`);
  }

  return new Promise((resolve, reject) => {
    const rows = [];

    fs.createReadStream(filePath)
      .pipe(
        csv({
          mapHeaders: ({ header }) => cleanHeader(header),
        }),
      )
      .on('data', (row) => rows.push(row))
      .on('end', () => resolve(rows))
      .on('error', reject);
  });
}

function toNumber(value) {
  if (
    value === undefined ||
    value === null ||
    String(value).trim() === ''
  ) {
    return null;
  }

  const number = Number(value);

  return Number.isFinite(number) ? number : null;
}

function getNutrientTarget(name, unitName) {
  const normalizedName = String(name || '')
    .trim()
    .toLowerCase();

  const normalizedUnit = String(unitName || '')
    .trim()
    .toLowerCase();

  if (
    normalizedName === 'energy' &&
    normalizedUnit === 'kcal'
  ) {
    return {
      key: 'energyKcal',
      priority: 1,
    };
  }

  if (
    normalizedName.includes(
      'energy (atwater general factors)',
    ) &&
    normalizedUnit === 'kcal'
  ) {
    return {
      key: 'energyKcal',
      priority: 2,
    };
  }

  if (
    normalizedName.includes(
      'energy (atwater specific factors)',
    ) &&
    normalizedUnit === 'kcal'
  ) {
    return {
      key: 'energyKcal',
      priority: 3,
    };
  }

  if (
    normalizedName === 'protein' &&
    normalizedUnit === 'g'
  ) {
    return {
      key: 'proteinG',
      priority: 1,
    };
  }

  if (
    normalizedName === 'carbohydrate, by difference' &&
    normalizedUnit === 'g'
  ) {
    return {
      key: 'carbohydratesG',
      priority: 1,
    };
  }

  if (
    normalizedName === 'total lipid (fat)' &&
    normalizedUnit === 'g'
  ) {
    return {
      key: 'fatG',
      priority: 1,
    };
  }

  if (
    normalizedName === 'sodium, na' &&
    normalizedUnit === 'mg'
  ) {
    return {
      key: 'sodiumMg',
      priority: 1,
    };
  }

  if (
    normalizedName === 'potassium, k' &&
    normalizedUnit === 'mg'
  ) {
    return {
      key: 'potassiumMg',
      priority: 1,
    };
  }

  return null;
}

function createEmptyNutrients() {
  return {
    energyKcal: null,
    proteinG: null,
    carbohydratesG: null,
    fatG: null,
    sodiumMg: null,
    potassiumMg: null,
  };
}

async function importFoundationFoods() {
  console.log('Reading USDA Foundation Foods files...');

  const [
    foundationRows,
    foodRows,
    nutrientRows,
    foodNutrientRows,
    foodPortionRows,
    measureUnitRows,
    foodCategoryRows,
  ] = await Promise.all([
    readCsv('foundation_food.csv'),
    readCsv('food.csv'),
    readCsv('nutrient.csv'),
    readCsv('food_nutrient.csv'),
    readCsv('food_portion.csv'),
    readCsv('measure_unit.csv'),
    readCsv('food_category.csv'),
  ]);

  /*
   * foundation_food.csv identifies which records are actual
   * Foundation Foods. Other CSV files can contain supporting
   * or input-food records that should not become searchable foods.
   */
  const foundationFoodIds = new Set(
    foundationRows
      .map((row) => String(row.fdc_id))
      .filter((id) => id && id !== 'undefined'),
  );

  console.log(
    `Foundation food IDs found: ${foundationFoodIds.size}`,
  );

  const measureUnitsById = new Map();

  for (const row of measureUnitRows) {
    measureUnitsById.set(
      String(row.id),
      row.name || row.abbreviation || null,
    );
  }

  const categoriesById = new Map();

  for (const row of foodCategoryRows) {
    categoriesById.set(
      String(row.id),
      row.description || null,
    );
  }

  const nutrientTargetsById = new Map();

  for (const row of nutrientRows) {
    const target = getNutrientTarget(
      row.name,
      row.unit_name,
    );

    if (target) {
      nutrientTargetsById.set(
        String(row.id),
        target,
      );
    }
  }

  console.log(
    `Required nutrient definitions found: ${nutrientTargetsById.size}`,
  );

  const foodsById = new Map();

  for (const row of foodRows) {
    const fdcId = String(row.fdc_id);

    if (!foundationFoodIds.has(fdcId)) {
      continue;
    }

    foodsById.set(fdcId, {
      source: {
        provider: 'USDA FoodData Central',
        dataset: 'Foundation Foods',
        fdcId: toNumber(row.fdc_id),
      },

      name: row.description || 'Unnamed food',
      dataType: row.data_type || 'foundation_food',

      category:
        categoriesById.get(
          String(row.food_category_id),
        ) || null,

      publicationDate:
        row.publication_date || null,

      nutrientBasis: 'per 100 g',

      nutrientsPer100g: createEmptyNutrients(),

      portions: [],

      verification: {
        status: 'official_source',
        importedAt: new Date().toISOString(),
      },

      /*
       * Internal field used only while selecting between
       * multiple possible calorie measurements.
       */
      _nutrientPriorities: {},
    });
  }

  for (const row of foodNutrientRows) {
    const fdcId = String(row.fdc_id);
    const food = foodsById.get(fdcId);

    if (!food) {
      continue;
    }

    const target = nutrientTargetsById.get(
      String(row.nutrient_id),
    );

    if (!target) {
      continue;
    }

    const amount = toNumber(row.amount);

    if (amount === null) {
      continue;
    }

    const previousPriority =
      food._nutrientPriorities[target.key];

    if (
      previousPriority === undefined ||
      target.priority < previousPriority
    ) {
      food.nutrientsPer100g[target.key] = amount;
      food._nutrientPriorities[target.key] =
        target.priority;
    }
  }

  for (const row of foodPortionRows) {
    const fdcId = String(row.fdc_id);
    const food = foodsById.get(fdcId);

    if (!food) {
      continue;
    }

    const gramWeight = toNumber(row.gram_weight);

    if (gramWeight === null || gramWeight <= 0) {
      continue;
    }

    const amount = toNumber(row.amount);

    const measureUnit =
      measureUnitsById.get(
        String(row.measure_unit_id),
      ) || null;

    const description =
      row.portion_description ||
      row.modifier ||
      measureUnit ||
      'serving';

    food.portions.push({
      amount,
      measureUnit,
      description,
      gramWeight,
    });
  }

  const normalizedFoods = Array.from(
    foodsById.values(),
  )
    .map((food) => {
      delete food._nutrientPriorities;

      food.portions.sort(
        (a, b) => a.gramWeight - b.gramWeight,
      );

      return food;
    })
    .sort((a, b) => a.name.localeCompare(b.name));

  fs.mkdirSync(OUTPUT_DIRECTORY, {
    recursive: true,
  });

  fs.writeFileSync(
    OUTPUT_FILE,
    JSON.stringify(normalizedFoods, null, 2),
    'utf8',
  );

  const foodsWithCalories = normalizedFoods.filter(
    (food) =>
      food.nutrientsPer100g.energyKcal !== null,
  ).length;

  const foodsWithSodium = normalizedFoods.filter(
    (food) =>
      food.nutrientsPer100g.sodiumMg !== null,
  ).length;

  console.log('');
  console.log('Foundation import completed.');
  console.log(`Foods exported: ${normalizedFoods.length}`);
  console.log(`Foods with calories: ${foodsWithCalories}`);
  console.log(`Foods with sodium: ${foodsWithSodium}`);
  console.log(`Output file: ${OUTPUT_FILE}`);
}

importFoundationFoods().catch((error) => {
  console.error('');
  console.error('Foundation import failed.');
  console.error(error.message);
  process.exit(1);
});