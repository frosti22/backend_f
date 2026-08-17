const wearableRecordService = require(
  './wearableRecord.service',
);

const {
  validateWearablePayload,
} = require('./wearableRecord.validator');

function getUserId(req) {
  return String(
    req.header('x-user-id') || 'test-user',
  ).trim();
}

function saveDailyWearableRecord(req, res) {
  const validation = validateWearablePayload(req.body);

  if (!validation.valid) {
    return res.status(400).json({
      success: false,
      message: validation.message,
    });
  }

  const result = wearableRecordService.upsertDailyWearableRecord({
    userId: getUserId(req),
    data: validation.data,
  });

  return res.status(result.created ? 201 : 200).json({
    success: true,
    created: result.created,
    message: result.created
      ? 'Daily wearable record saved successfully.'
      : 'Daily wearable record updated successfully.',
    data: result.record,
  });
}

function getWearableRecords(req, res) {
  const month = req.query.month
    ? String(req.query.month).trim()
    : undefined;

  if (month && !/^\d{4}-\d{2}$/.test(month)) {
    return res.status(400).json({
      success: false,
      message: 'month must use YYYY-MM format.',
    });
  }

  const records = wearableRecordService.getWearableRecords({
    userId: getUserId(req),
    month,
  });

  return res.json({
    success: true,
    count: records.length,
    data: records,
  });
}

function getWearableRecordByDate(req, res) {
  const date = String(req.params.date || '').trim();

  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return res.status(400).json({
      success: false,
      message: 'date must use YYYY-MM-DD format.',
    });
  }

  const record = wearableRecordService.getWearableRecordByDate({
    userId: getUserId(req),
    date,
  });

  if (!record) {
    return res.status(404).json({
      success: false,
      message: 'Wearable record not found.',
    });
  }

  return res.json({
    success: true,
    data: record,
  });
}

module.exports = {
  saveDailyWearableRecord,
  getWearableRecords,
  getWearableRecordByDate,
};
