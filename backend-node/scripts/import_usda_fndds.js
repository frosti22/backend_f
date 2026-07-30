const fs = require('fs');
const path = require('path');
const csv = require('csv-parser');

const RAW_DIRECTORY = path.join(
  __dirname,
  '..',
  'data',
  'usda',
  'raw',
  'fndds',
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
  'fndds_foods.json',
);

function cleanHeader(header) {
  return String(header || '')
    .replace(/^\uFEFF/, '')
    .trim();
}

function readCsv(filename) {
  const filePath = path.join(
    RAW_DIRECTORY,
    filename,
  );

  if (!fs.existsSync(filePath)) {
    throw new Error(
      `Missing required file: ${filePath}`,
    );
  }

  return new Promise((resolve, reject) => {
    const rows = [];

    fs.createReadStream(filePath)
      .pipe(
        csv({
          mapHeaders: ({ header }) =>
            cleanHeader(header),
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

  const parsed = Number(value);

  return Number.isFinite(parsed)
    ? parsed
    : null;
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
    normalizedName ===
      'carbohydrate, by difference' &&
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

function getCategoryCode(row) {
  return String(
    row.wweia_food_category_code ||
      row.wweia_category_code ||
      row.food_category_code ||
      row.code ||
      row.id ||
      '',
  );
}

function getCategoryDescription(row) {
  return (
    row.wweia_food_category_description ||
    row.wweia_category_description ||
    row.description ||
    row.name ||
    null
  );
}

async function importFnddsFoods() {
  console.log(
    'Reading USDA Survey Foods (FNDDS) files...',
  );

  const [
    surveyRows,
    foodRows,
    nutrientRows,
    foodNutrientRows,
    foodPortionRows,
    measureUnitRows,
    categoryRows,
  ] = await Promise.all([
    readCsv('survey_fndds_food.csv'),
    readCsv('food.csv'),
    readCsv('nutrient.csv'),
    readCsv('food_nutrient.csv'),
    readCsv('food_portion.csv'),
    readCsv('measure_unit.csv'),
    readCsv('wweia_food_category.csv'),
  ]);

  const surveyMetadataById = new Map();

  for (const row of surveyRows) {
    const fdcId = String(row.fdc_id || '');

    if (!fdcId) {
      continue;
    }

    surveyMetadataById.set(fdcId, {
      foodCode:
        row.food_code || null,

      categoryCode: String(
        row.wweia_category_code ||
          row.wweia_food_category_code ||
          '',
      ),

      startDate:
        row.start_date || null,

      endDate:
        row.end_date || null,
    });
  }

  console.log(
    `FNDDS food IDs found: ${surveyMetadataById.size}`,
  );

  const categoryByCode = new Map();

  for (const row of categoryRows) {
    const code = getCategoryCode(row);

    if (!code) {
      continue;
    }

    categoryByCode.set(
      code,
      getCategoryDescription(row),
    );
  }

  const measureUnitsById = new Map();

  for (const row of measureUnitRows) {
    measureUnitsById.set(
      String(row.id),
      row.name ||
        row.abbreviation ||
        null,
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
    const fdcId = String(row.fdc_id || '');
    const surveyMetadata =
      surveyMetadataById.get(fdcId);

    if (!surveyMetadata) {
      continue;
    }

    foodsById.set(fdcId, {
      source: {
        provider: 'USDA FoodData Central',
        dataset: 'Survey Foods (FNDDS)',
        fdcId: toNumber(row.fdc_id),
        foodCode:
          surveyMetadata.foodCode,
      },

      name:
        row.description ||
        'Unnamed food',

      dataType:
        row.data_type ||
        'survey_fndds_food',

      category:
        categoryByCode.get(
          surveyMetadata.categoryCode,
        ) || null,

      publicationDate:
        row.publication_date || null,

      dateRange: {
        startDate:
          surveyMetadata.startDate,
        endDate:
          surveyMetadata.endDate,
      },

      nutrientBasis: 'per 100 g',

      nutrientsPer100g:
        createEmptyNutrients(),

      portions: [],

      verification: {
        status: 'official_source',
        importedAt:
          new Date().toISOString(),
      },

      _nutrientPriorities: {},
    });
  }

  for (const row of foodNutrientRows) {
    const food = foodsById.get(
      String(row.fdc_id),
    );

    if (!food) {
      continue;
    }

    const target =
      nutrientTargetsById.get(
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
      food.nutrientsPer100g[
        target.key
      ] = amount;

      food._nutrientPriorities[
        target.key
      ] = target.priority;
    }
  }

  for (const row of foodPortionRows) {
    const food = foodsById.get(
      String(row.fdc_id),
    );

    if (!food) {
      continue;
    }

    const gramWeight = toNumber(
      row.gram_weight,
    );

    if (
      gramWeight === null ||
      gramWeight <= 0
    ) {
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
        (a, b) =>
          a.gramWeight -
          b.gramWeight,
      );

      return food;
    })
    .sort((a, b) =>
      a.name.localeCompare(b.name),
    );

  fs.mkdirSync(OUTPUT_DIRECTORY, {
    recursive: true,
  });

  fs.writeFileSync(
    OUTPUT_FILE,
    JSON.stringify(
      normalizedFoods,
      null,
      2,
    ),
    'utf8',
  );

  const foodsWithCalories =
    normalizedFoods.filter(
      (food) =>
        food.nutrientsPer100g
          .energyKcal !== null,
    ).length;

  const foodsWithSodium =
    normalizedFoods.filter(
      (food) =>
        food.nutrientsPer100g
          .sodiumMg !== null,
    ).length;

  console.log('');
  console.log('FNDDS import completed.');
  console.log(
    `Foods exported: ${normalizedFoods.length}`,
  );
  console.log(
    `Foods with calories: ${foodsWithCalories}`,
  );
  console.log(
    `Foods with sodium: ${foodsWithSodium}`,
  );
  console.log(
    `Output file: ${OUTPUT_FILE}`,
  );
}

importFnddsFoods().catch((error) => {
  console.error('');
  console.error('FNDDS import failed.');
  console.error(error);
  process.exit(1);
});