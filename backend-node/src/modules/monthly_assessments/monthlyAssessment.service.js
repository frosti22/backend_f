const localStorage = require(
  '../../common/storage/localJsonStorage',
);

const foodLogs = localStorage.getCollection('foodLogs');
const waterLogs = localStorage.getCollection('waterLogs');
const wearableRecords = localStorage.getCollection('wearableRecords');

const FOOD_NUTRIENTS = {
  calories: {
    sourceKey: 'energyKcal',
    totalKey: 'totalCaloriesKcal',
    averageKey: 'averageDailyCaloriesKcal',
    daysKey: 'daysWithCaloriesData',
  },
  sodium: {
    sourceKey: 'sodiumMg',
    totalKey: 'totalSodiumMg',
    averageKey: 'averageDailySodiumMg',
    daysKey: 'daysWithSodiumData',
  },
  protein: {
    sourceKey: 'proteinG',
    totalKey: 'totalProteinG',
    averageKey: 'averageDailyProteinG',
    daysKey: 'daysWithProteinData',
  },
  carbohydrates: {
    sourceKey: 'carbohydratesG',
    totalKey: 'totalCarbohydratesG',
    averageKey: 'averageDailyCarbohydratesG',
    daysKey: 'daysWithCarbohydratesData',
  },
  fat: {
    sourceKey: 'fatG',
    totalKey: 'totalFatG',
    averageKey: 'averageDailyFatG',
    daysKey: 'daysWithFatData',
  },
  potassium: {
    sourceKey: 'potassiumMg',
    totalKey: 'totalPotassiumMg',
    averageKey: 'averageDailyPotassiumMg',
    daysKey: 'daysWithPotassiumData',
  },
};

function roundNumber(value, decimalPlaces = 2) {
  if (!Number.isFinite(value)) {
    return null;
  }

  const multiplier = 10 ** decimalPlaces;

  return (
    Math.round(
      (value + Number.EPSILON) * multiplier,
    ) / multiplier
  );
}

function dateKey(value) {
  const text = String(value || '');
  const match = text.match(/^(\d{4}-\d{2}-\d{2})/);

  if (match) {
    return match[1];
  }

  const parsed = new Date(value);

  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  return parsed.toISOString().slice(0, 10);
}

function currentMonthKey() {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, '0');

  return `${now.getFullYear()}-${month}`;
}

function getPeriod(month) {
  const [yearText, monthText] = month.split('-');
  const year = Number(yearText);
  const monthNumber = Number(monthText);
  const daysInMonth = new Date(year, monthNumber, 0).getDate();
  const currentMonth = currentMonthKey();

  let assessmentDays = daysInMonth;

  if (month === currentMonth) {
    assessmentDays = new Date().getDate();
  } else if (month > currentMonth) {
    assessmentDays = 0;
  }

  return {
    startDate: `${month}-01`,
    endDate: `${month}-${String(daysInMonth).padStart(2, '0')}`,
    daysInMonth,
    assessmentDays,
  };
}

function optionalFiniteNumber(value) {
  if (
    value === null ||
    value === undefined ||
    value === ''
  ) {
    return null;
  }

  const number = Number(value);

  return Number.isFinite(number) ? number : null;
}

function valuesByDay(records, getDate, getValue) {
  const totals = new Map();

  for (const record of records) {
    const day = dateKey(getDate(record));

    if (!day) {
      continue;
    }

    const value = getValue(record);

    if (!Number.isFinite(value)) {
      continue;
    }

    totals.set(day, (totals.get(day) || 0) + value);
  }

  return totals;
}

function totalOfMap(values) {
  return Array.from(values.values()).reduce(
    (total, value) => total + value,
    0,
  );
}

function coverage(daysWithData, assessmentDays) {
  if (assessmentDays <= 0) {
    return null;
  }

  return roundNumber(daysWithData / assessmentDays, 4);
}

function average(total, validDays) {
  if (validDays <= 0) {
    return null;
  }

  return roundNumber(total / validDays);
}

function buildFoodNutrientSummary(monthlyFoodLogs) {
  const summary = {};

  for (const definition of Object.values(FOOD_NUTRIENTS)) {
    const values = valuesByDay(
      monthlyFoodLogs,
      (record) => record.consumedAt,
      (record) => {
        const value = optionalFiniteNumber(
          record.nutrients?.[definition.sourceKey],
        );

        return value ?? Number.NaN;
      },
    );

    const total = totalOfMap(values);
    const validDays = values.size;

    summary[definition.totalKey] = roundNumber(total);
    summary[definition.averageKey] = average(total, validDays);
    summary[definition.daysKey] = validDays;
  }

  return summary;
}

function getMonthlyAssessment({ userId, month }) {
  const period = getPeriod(month);

  const monthlyFoodLogs = foodLogs.filter((record) => {
    const day = dateKey(record.consumedAt);
    return record.userId === userId && day?.startsWith(`${month}-`);
  });

  const monthlyWaterLogs = waterLogs.filter((record) => {
    const day = dateKey(record.loggedAt);
    return record.userId === userId && day?.startsWith(`${month}-`);
  });

  const monthlyWearableRecords = wearableRecords.filter(
    (record) =>
      record.userId === userId &&
      String(record.date || '').startsWith(`${month}-`),
  );

  const foodLogDays = new Set(
    monthlyFoodLogs
      .map((record) => dateKey(record.consumedAt))
      .filter(Boolean),
  );

  const foodNutrients = buildFoodNutrientSummary(monthlyFoodLogs);

  const waterByDay = valuesByDay(
    monthlyWaterLogs,
    (record) => record.loggedAt,
    (record) => {
      const value = optionalFiniteNumber(record.amountMl);
      return value ?? Number.NaN;
    },
  );

  const totalWaterMl = totalOfMap(waterByDay);

  const validWearableRecords = monthlyWearableRecords.filter(
    (record) => record.hasData !== false,
  );

  const stepsRecords = validWearableRecords.filter((record) =>
    Number.isFinite(Number(record.steps)),
  );

  const activeMinuteRecords = validWearableRecords.filter((record) =>
    Number.isFinite(Number(record.activeMinutes)),
  );

  const sedentaryRecords = validWearableRecords.filter((record) =>
    record.sedentaryHours !== null &&
    record.sedentaryHours !== undefined &&
    Number.isFinite(Number(record.sedentaryHours)),
  );

  const sleepRecords = validWearableRecords.filter(
    (record) =>
      record.sleepMinutes !== null &&
      record.sleepMinutes !== undefined &&
      Number(record.sleepMinutes) > 0,
  );

  const sum = (records, field) =>
    records.reduce(
      (total, record) => total + (Number(record[field]) || 0),
      0,
    );

  const daysWithFoodLogs = foodLogDays.size;
  const daysWithWaterLogs = waterByDay.size;
  const daysWithWearableData = new Set(
    validWearableRecords.map((record) => record.date),
  ).size;

  const averageDailyWaterMl = average(
    totalWaterMl,
    daysWithWaterLogs,
  );

  const averageDailySteps = average(
    sum(stepsRecords, 'steps'),
    stepsRecords.length,
  );

  const averageActiveMinutes = average(
    sum(activeMinuteRecords, 'activeMinutes'),
    activeMinuteRecords.length,
  );

  const averageSedentaryHours = average(
    sum(sedentaryRecords, 'sedentaryHours'),
    sedentaryRecords.length,
  );

  const averageSleepHours = sleepRecords.length
    ? roundNumber(
        sum(sleepRecords, 'sleepMinutes') /
          sleepRecords.length /
          60,
      )
    : null;

  const dietCoverage = coverage(
    daysWithFoodLogs,
    period.assessmentDays,
  );

  const waterCoverage = coverage(
    daysWithWaterLogs,
    period.assessmentDays,
  );

  const wearableCoverage = coverage(
    daysWithWearableData,
    period.assessmentDays,
  );

  return {
    assessmentMonth: month,
    generatedAt: new Date().toISOString(),
    period,

    food: {
      ...foodNutrients,
      daysWithFoodLogs,
      dietCoverage,
    },

    water: {
      totalWaterMl: roundNumber(totalWaterMl),
      averageDailyWaterMl,
      daysWithWaterLogs,
      waterCoverage,
    },

    wearable: {
      averageDailySteps,
      averageActiveMinutes,
      averageSedentaryHours,
      averageSleepHours,
      daysWithWearableData,
      daysWithStepsData: stepsRecords.length,
      daysWithActiveMinutesData: activeMinuteRecords.length,
      daysWithSedentaryData: sedentaryRecords.length,
      daysWithSleepData: sleepRecords.length,
      wearableCoverage,
    },

    mlInputs: {
      average_daily_sodium: foodNutrients.averageDailySodiumMg,
      average_daily_water: averageDailyWaterMl,
      average_daily_steps: averageDailySteps,
      average_active_minutes: averageActiveMinutes,
      average_sedentary_hours: averageSedentaryHours,
      average_sleep_hours: averageSleepHours,
      diet_coverage: dietCoverage,
      wearable_coverage: wearableCoverage,
    },
  };
}

module.exports = {
  getMonthlyAssessment,
};
