const { randomUUID } = require('crypto');

const waterLogs = [];

function createWaterLog({
  userId,
  amountMl,
  loggedAt,
  source,
  clientRecordId,
  notes,
}) {
  if (clientRecordId) {
    const existingRecord = waterLogs.find(
      (record) =>
        record.userId === userId &&
        record.clientRecordId === clientRecordId,
    );

    if (existingRecord) {
      return {
        created: false,
        duplicate: true,
        record: existingRecord,
      };
    }
  }

  const now = new Date().toISOString();
  const record = {
    id: randomUUID(),
    userId,
    clientRecordId: clientRecordId || null,
    amountMl,
    source: source || 'manual',
    loggedAt: loggedAt || now,
    notes:
      typeof notes === 'string' && notes.trim()
        ? notes.trim()
        : null,
    createdAt: now,
    updatedAt: now,
  };

  waterLogs.push(record);

  return {
    created: true,
    duplicate: false,
    record,
  };
}

function getWaterLogs({ userId }) {
  return waterLogs
    .filter((record) => record.userId === userId)
    .sort(
      (a, b) =>
        new Date(b.loggedAt) - new Date(a.loggedAt),
    );
}

function getWaterLogById({ userId, id }) {
  return (
    waterLogs.find(
      (record) =>
        record.userId === userId && record.id === id,
    ) || null
  );
}

function updateWaterLog({ userId, id, changes }) {
  const index = waterLogs.findIndex(
    (record) =>
      record.userId === userId && record.id === id,
  );

  if (index === -1) {
    return null;
  }

  const existing = waterLogs[index];
  const updated = {
    ...existing,
    amountMl:
      changes.amountMl !== undefined
        ? changes.amountMl
        : existing.amountMl,
    loggedAt:
      changes.loggedAt !== undefined
        ? changes.loggedAt
        : existing.loggedAt,
    notes:
      changes.notes !== undefined
        ? changes.notes
        : existing.notes,
    updatedAt: new Date().toISOString(),
  };

  waterLogs[index] = updated;
  return updated;
}

function deleteWaterLog({ userId, id }) {
  const index = waterLogs.findIndex(
    (record) =>
      record.userId === userId && record.id === id,
  );

  if (index === -1) {
    return null;
  }

  const [deleted] = waterLogs.splice(index, 1);
  return deleted;
}

function getWaterSummary({ userId }) {
  const records = getWaterLogs({ userId });
  const totalMl = records.reduce(
    (total, record) => total + record.amountMl,
    0,
  );

  return {
    recordCount: records.length,
    totalMl: Math.round(totalMl * 100) / 100,
  };
}

module.exports = {
  createWaterLog,
  getWaterLogs,
  getWaterLogById,
  updateWaterLog,
  deleteWaterLog,
  getWaterSummary,
};
