const fs = require('fs');
const path = require('path');
const { randomUUID } = require('crypto');

const DATA_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'checkup_records',
  'checkup_records.json',
);

function ensureDataFile() {
  fs.mkdirSync(path.dirname(DATA_FILE), {
    recursive: true,
  });

  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, '[]\n', 'utf8');
  }
}

function loadRecords() {
  ensureDataFile();

  try {
    const parsed = JSON.parse(
      fs.readFileSync(DATA_FILE, 'utf8'),
    );

    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.error(
      'Could not read checkup record storage:',
      error.message,
    );
    return [];
  }
}

const checkupRecords = loadRecords();

function persistRecords() {
  fs.writeFileSync(
    DATA_FILE,
    `${JSON.stringify(checkupRecords, null, 2)}\n`,
    'utf8',
  );
}

function createCheckupRecord({
  userId,
  data,
}) {
  if (data.clientRecordId) {
    const existing = checkupRecords.find(
      (record) =>
        record.userId === userId &&
        record.clientRecordId === data.clientRecordId,
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
    clientRecordId: data.clientRecordId,
    checkupDate: data.checkupDate,
    egfrMlMin173m2: data.egfrMlMin173m2,
    serumCreatinineMgDl:
      data.serumCreatinineMgDl,
    uacrMgG: data.uacrMgG,
    systolicBloodPressure:
      data.systolicBloodPressure,
    diastolicBloodPressure:
      data.diastolicBloodPressure,
    bloodGlucoseMgDl: data.bloodGlucoseMgDl,
    notes: data.notes,
    source: 'manual',
    createdAt: now,
    updatedAt: now,
  };

  checkupRecords.push(record);
  persistRecords();

  return {
    duplicate: false,
    record,
  };
}

function getCheckupRecords({ userId }) {
  return checkupRecords
    .filter((record) => record.userId === userId)
    .sort((a, b) => {
      const dateComparison = String(
        b.checkupDate,
      ).localeCompare(String(a.checkupDate));

      if (dateComparison !== 0) {
        return dateComparison;
      }

      return String(b.createdAt).localeCompare(
        String(a.createdAt),
      );
    });
}

function getCheckupRecordById({ userId, id }) {
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

  const existing = checkupRecords[index];
  const updated = {
    ...existing,
    checkupDate: data.checkupDate,
    egfrMlMin173m2: data.egfrMlMin173m2,
    serumCreatinineMgDl:
      data.serumCreatinineMgDl,
    uacrMgG: data.uacrMgG,
    systolicBloodPressure:
      data.systolicBloodPressure,
    diastolicBloodPressure:
      data.diastolicBloodPressure,
    bloodGlucoseMgDl: data.bloodGlucoseMgDl,
    notes: data.notes,
    source: 'manual',
    updatedAt: new Date().toISOString(),
  };

  checkupRecords[index] = updated;
  persistRecords();
  return updated;
}

function deleteCheckupRecord({ userId, id }) {
  const index = checkupRecords.findIndex(
    (record) =>
      record.userId === userId &&
      record.id === id,
  );

  if (index === -1) {
    return null;
  }

  const [deleted] = checkupRecords.splice(index, 1);
  persistRecords();
  return deleted;
}

module.exports = {
  createCheckupRecord,
  getCheckupRecords,
  getCheckupRecordById,
  updateCheckupRecord,
  deleteCheckupRecord,
};
