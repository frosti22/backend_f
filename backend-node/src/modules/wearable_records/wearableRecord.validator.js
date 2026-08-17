const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function optionalNumber(value, fieldName, { integer = false } = {}) {
  if (value === undefined || value === null || value === '') {
    return { valid: true, value: null };
  }

  const number = Number(value);

  if (!Number.isFinite(number) || number < 0) {
    return {
      valid: false,
      message: `${fieldName} must be zero or a positive number.`,
    };
  }

  if (integer && !Number.isInteger(number)) {
    return {
      valid: false,
      message: `${fieldName} must be a whole number.`,
    };
  }

  return { valid: true, value: number };
}

function normalizeWorkout(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  return {
    type: String(value.type || 'Workout').trim(),
    startTime: value.startTime ? String(value.startTime) : null,
    endTime: value.endTime ? String(value.endTime) : null,
    durationMinutes: Math.max(0, Number(value.durationMinutes) || 0),
    distanceMeters: Math.max(0, Number(value.distanceMeters) || 0),
    energyKcal: Math.max(0, Number(value.energyKcal) || 0),
    steps: Math.max(0, Math.round(Number(value.steps) || 0)),
    source: value.source ? String(value.source).trim() : null,
  };
}

function validateWearablePayload(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return {
      valid: false,
      message: 'Request body must be an object.',
    };
  }

  const date = String(payload.date || '').trim();

  if (!DATE_PATTERN.test(date) || Number.isNaN(Date.parse(`${date}T00:00:00`))) {
    return {
      valid: false,
      message: 'date must use YYYY-MM-DD format.',
    };
  }

  const numericFields = [
    ['steps', true],
    ['distanceMeters', false],
    ['activeCaloriesKcal', false],
    ['activeMinutes', false],
    ['sedentaryHours', false],
    ['sleepMinutes', false],
    ['lightSleepMinutes', false],
    ['deepSleepMinutes', false],
    ['remSleepMinutes', false],
    ['awakeMinutes', false],
    ['latestHeartRateBpm', false],
  ];

  const normalized = { date };

  for (const [fieldName, integer] of numericFields) {
    const result = optionalNumber(payload[fieldName], fieldName, { integer });

    if (!result.valid) {
      return result;
    }

    normalized[fieldName] = result.value;
  }

  normalized.sources = Array.isArray(payload.sources)
    ? payload.sources
        .map((value) => String(value || '').trim())
        .filter(Boolean)
        .slice(0, 50)
    : [];

  normalized.workouts = Array.isArray(payload.workouts)
    ? payload.workouts
        .map(normalizeWorkout)
        .filter(Boolean)
        .slice(0, 100)
    : [];

  normalized.sourcePlatform = String(
    payload.sourcePlatform || 'health_connect',
  ).trim();

  normalized.syncedAt = payload.syncedAt
    ? String(payload.syncedAt)
    : new Date().toISOString();

  return {
    valid: true,
    data: normalized,
  };
}

module.exports = {
  validateWearablePayload,
};
