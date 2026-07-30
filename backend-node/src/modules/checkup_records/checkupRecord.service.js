const { randomUUID } = require('crypto');

const localStorage = require(
  '../../common/storage/localJsonStorage',
);

const checkupRecords =
  localStorage.getCollection(
    'checkupRecords',
  );

function createCheckupRecord({
  userId,
  data,
}) {
  /*
   * Prevent duplicate submissions when the Flutter
   * application sends the same clientRecordId again.
   */
  if (data.clientRecordId) {
    const existing = checkupRecords.find(
      (record) =>
        record.userId === userId &&
        record.clientRecordId ===
          data.clientRecordId,
    );

    if (existing) {
      return {
        duplicate: true,
        record: existing,
      };
    }
  }

  const now = new Date().toISOString();

  const record = {
    id: randomUUID(),
    userId,

    clientRecordId:
      data.clientRecordId || null,

    checkupDate: data.checkupDate,

    egfrMlMin173m2:
      data.egfrMlMin173m2,

    serumCreatinineMgDl:
      data.serumCreatinineMgDl,

    uacrMgG:
      data.uacrMgG,

    systolicBloodPressure:
      data.systolicBloodPressure,

    diastolicBloodPressure:
      data.diastolicBloodPressure,

    bloodGlucoseMgDl:
      data.bloodGlucoseMgDl,

    notes:
      data.notes || null,

    source: 'manual',

    createdAt: now,
    updatedAt: now,
  };

  checkupRecords.push(record);

  /*
   * Save the updated collection in:
   * data/local_storage/app_storage.json
   */
  localStorage.persist();

  return {
    duplicate: false,
    record,
  };
}

function getCheckupRecords({
  userId,
}) {
  return checkupRecords
    .filter(
      (record) =>
        record.userId === userId,
    )
    .sort((a, b) => {
      const dateComparison =
        String(
          b.checkupDate,
        ).localeCompare(
          String(a.checkupDate),
        );

      if (dateComparison !== 0) {
        return dateComparison;
      }

      return String(
        b.createdAt,
      ).localeCompare(
        String(a.createdAt),
      );
    });
}

function getCheckupRecordById({
  userId,
  id,
}) {
  return (
    checkupRecords.find(
      (record) =>
        record.userId === userId &&
        record.id === id,
    ) || null
  );
}

function updateCheckupRecord({
  userId,
  id,
  data,
}) {
  const index = checkupRecords.findIndex(
    (record) =>
      record.userId === userId &&
      record.id === id,
  );

  if (index === -1) {
    return null;
  }

  const existing =
    checkupRecords[index];

  const updated = {
    ...existing,

    checkupDate:
      data.checkupDate,

    egfrMlMin173m2:
      data.egfrMlMin173m2,

    serumCreatinineMgDl:
      data.serumCreatinineMgDl,

    uacrMgG:
      data.uacrMgG,

    systolicBloodPressure:
      data.systolicBloodPressure,

    diastolicBloodPressure:
      data.diastolicBloodPressure,

    bloodGlucoseMgDl:
      data.bloodGlucoseMgDl,

    notes:
      data.notes || null,

    source: 'manual',

    updatedAt:
      new Date().toISOString(),
  };

  checkupRecords[index] = updated;

  localStorage.persist();

  return updated;
}

function deleteCheckupRecord({
  userId,
  id,
}) {
  const index = checkupRecords.findIndex(
    (record) =>
      record.userId === userId &&
      record.id === id,
  );

  if (index === -1) {
    return null;
  }

  const [deletedRecord] =
    checkupRecords.splice(index, 1);

  localStorage.persist();

  return deletedRecord;
}

module.exports = {
  createCheckupRecord,
  getCheckupRecords,
  getCheckupRecordById,
  updateCheckupRecord,
  deleteCheckupRecord,
};