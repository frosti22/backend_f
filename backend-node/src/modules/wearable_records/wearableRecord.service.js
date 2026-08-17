const { randomUUID } = require('crypto');

const localStorage = require(
  '../../common/storage/localJsonStorage',
);

const wearableRecords = localStorage.getCollection(
  'wearableRecords',
);

function hasWearableData(data) {
  return (
    (data.steps ?? 0) > 0 ||
    (data.distanceMeters ?? 0) > 0 ||
    (data.activeCaloriesKcal ?? 0) > 0 ||
    (data.activeMinutes ?? 0) > 0 ||
    (data.sleepMinutes ?? 0) > 0 ||
    data.latestHeartRateBpm !== null ||
    data.workouts.length > 0
  );
}

function upsertDailyWearableRecord({ userId, data }) {
  const now = new Date().toISOString();
  const existingIndex = wearableRecords.findIndex(
    (record) =>
      record.userId === userId &&
      record.date === data.date,
  );

  const record = {
    id:
      existingIndex === -1
        ? randomUUID()
        : wearableRecords[existingIndex].id,
    userId,
    ...data,
    hasData: hasWearableData(data),
    createdAt:
      existingIndex === -1
        ? now
        : wearableRecords[existingIndex].createdAt,
    updatedAt: now,
  };

  if (existingIndex === -1) {
    wearableRecords.push(record);
  } else {
    wearableRecords[existingIndex] = record;
  }

  localStorage.persist();

  return {
    created: existingIndex === -1,
    record,
  };
}

function getWearableRecords({ userId, month }) {
  return wearableRecords
    .filter((record) => {
      if (record.userId !== userId) {
        return false;
      }

      if (month && !String(record.date).startsWith(`${month}-`)) {
        return false;
      }

      return true;
    })
    .sort((a, b) => String(b.date).localeCompare(String(a.date)));
}

function getWearableRecordByDate({ userId, date }) {
  return (
    wearableRecords.find(
      (record) =>
        record.userId === userId &&
        record.date === date,
    ) || null
  );
}

module.exports = {
  upsertDailyWearableRecord,
  getWearableRecords,
  getWearableRecordByDate,
};
