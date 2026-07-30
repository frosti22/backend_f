const checkupRecordService = require(
  './checkupRecord.service',
);

const {
  validateCheckupPayload,
} = require('./checkupRecord.validator');

function getUserId(req) {
  return String(
    req.header('x-user-id') || 'test-user',
  ).trim();
}

function createCheckupRecord(req, res) {
  const validation = validateCheckupPayload(
    req.body,
  );

  if (!validation.valid) {
    return res.status(400).json({
      success: false,
      message: validation.message,
    });
  }

  const result =
    checkupRecordService.createCheckupRecord({
      userId: getUserId(req),
      data: validation.data,
    });

  return res
    .status(result.duplicate ? 200 : 201)
    .json({
      success: true,
      duplicate: result.duplicate,

      message: result.duplicate
        ? 'This checkup record was already submitted.'
        : 'Checkup record saved successfully.',

      data: result.record,
    });
}

function getCheckupRecords(req, res) {
  const records =
    checkupRecordService.getCheckupRecords({
      userId: getUserId(req),
    });

  return res.json({
    success: true,
    count: records.length,
    data: records,
  });
}

function getCheckupRecordById(req, res) {
  const record =
    checkupRecordService.getCheckupRecordById({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!record) {
    return res.status(404).json({
      success: false,
      message: 'Checkup record not found.',
    });
  }

  return res.json({
    success: true,
    data: record,
  });
}

function updateCheckupRecord(req, res) {
  const existing =
    checkupRecordService.getCheckupRecordById({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!existing) {
    return res.status(404).json({
      success: false,
      message: 'Checkup record not found.',
    });
  }

  /*
   * Combine the existing record and the new values.
   * This allows partial PATCH updates.
   */
  const validation = validateCheckupPayload({
    ...existing,
    ...req.body,
    clientRecordId:
      existing.clientRecordId,
  });

  if (!validation.valid) {
    return res.status(400).json({
      success: false,
      message: validation.message,
    });
  }

  const record =
    checkupRecordService.updateCheckupRecord({
      userId: getUserId(req),
      id: req.params.id,
      data: validation.data,
    });

  return res.json({
    success: true,
    message:
      'Checkup record updated successfully.',
    data: record,
  });
}

function deleteCheckupRecord(req, res) {
  const record =
    checkupRecordService.deleteCheckupRecord({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!record) {
    return res.status(404).json({
      success: false,
      message: 'Checkup record not found.',
    });
  }

  return res.json({
    success: true,
    message:
      'Checkup record deleted successfully.',
    data: record,
  });
}

module.exports = {
  createCheckupRecord,
  getCheckupRecords,
  getCheckupRecordById,
  updateCheckupRecord,
  deleteCheckupRecord,
};