const {
  CHECKUP_MEASUREMENT_FIELDS,
} = require('./checkupRecord.model');

const FIELD_LIMITS = {
  egfrMlMin173m2: { min: 0, max: 300 },
  serumCreatinineMgDl: { min: 0, max: 50 },
  uacrMgG: { min: 0, max: 100000 },
  systolicBloodPressure: { min: 30, max: 350 },
  diastolicBloodPressure: { min: 20, max: 250 },
  bloodGlucoseMgDl: { min: 10, max: 2000 },
};

function normalizeDate(value) {
  if (typeof value !== 'string' || !value.trim()) {
    return null;
  }

  const trimmed = value.trim();
  const datePart = trimmed.slice(0, 10);

  if (!/^\d{4}-\d{2}-\d{2}$/.test(datePart)) {
    return null;
  }

  const date = new Date(`${datePart}T00:00:00.000Z`);

  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== datePart
  ) {
    return null;
  }

  return datePart;
}

function normalizeOptionalNumber(value, fieldName) {
  if (
    value === undefined ||
    value === null ||
    String(value).trim() === ''
  ) {
    return { value: null };
  }

  const number = Number(value);
  const limits = FIELD_LIMITS[fieldName];

  if (
    !Number.isFinite(number) ||
    number < limits.min ||
    number > limits.max
  ) {
    return {
      error: `${fieldName} must be between ${limits.min} and ${limits.max}.`,
    };
  }

  return { value: number };
}

function validateCheckupPayload(payload) {
  const checkupDate = normalizeDate(payload.checkupDate);

  if (!checkupDate) {
    return {
      valid: false,
      message: 'checkupDate must use the YYYY-MM-DD format.',
    };
  }

  const normalized = {
    checkupDate,
  };

  for (const fieldName of CHECKUP_MEASUREMENT_FIELDS) {
    const result = normalizeOptionalNumber(
      payload[fieldName],
      fieldName,
    );

    if (result.error) {
      return {
        valid: false,
        message: result.error,
      };
    }

    normalized[fieldName] = result.value;
  }

  const hasMeasurement = CHECKUP_MEASUREMENT_FIELDS.some(
    (fieldName) => normalized[fieldName] !== null,
  );

  if (!hasMeasurement) {
    return {
      valid: false,
      message: 'Enter at least one checkup measurement.',
    };
  }

  if (
    payload.notes !== undefined &&
    payload.notes !== null &&
    typeof payload.notes !== 'string'
  ) {
    return {
      valid: false,
      message: 'notes must be text.',
    };
  }

  const notes =
    typeof payload.notes === 'string'
      ? payload.notes.trim()
      : '';

  if (notes.length > 1000) {
    return {
      valid: false,
      message: 'notes must not exceed 1,000 characters.',
    };
  }

  normalized.notes = notes || null;

  if (
    payload.clientRecordId !== undefined &&
    payload.clientRecordId !== null &&
    typeof payload.clientRecordId !== 'string'
  ) {
    return {
      valid: false,
      message: 'clientRecordId must be text.',
    };
  }

  normalized.clientRecordId =
    typeof payload.clientRecordId === 'string' &&
    payload.clientRecordId.trim()
      ? payload.clientRecordId.trim()
      : null;

  return {
    valid: true,
    data: normalized,
  };
}

module.exports = {
  validateCheckupPayload,
};
