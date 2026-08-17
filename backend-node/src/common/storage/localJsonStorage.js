const fs = require('fs');
const path = require('path');

const DATA_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'local_storage',
  'app_storage.json',
);

const LEGACY_CHECKUP_FILE = path.join(
  __dirname,
  '..',
  '..',
  '..',
  'data',
  'checkup_records',
  'checkup_records.json',
);

const COLLECTION_NAMES = [
  'foodLogs',
  'waterLogs',
  'customFoods',
  'waterContainers',
  'checkupRecords',
  'wearableRecords',
];

function emptyStorage() {
  return {
    version: 2,
    foodLogs: [],
    waterLogs: [],
    customFoods: [],
    waterContainers: [],
    checkupRecords: [],
    wearableRecords: [],
  };
}

function normalizeStorage(value) {
  const normalized = emptyStorage();

  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value)
  ) {
    return normalized;
  }

  normalized.version = Number.isInteger(value.version)
    ? Math.max(value.version, 2)
    : 2;

  for (const collectionName of COLLECTION_NAMES) {
    normalized[collectionName] =
      Array.isArray(value[collectionName])
        ? value[collectionName]
        : [];
  }

  return normalized;
}

function readLegacyCheckups() {
  if (!fs.existsSync(LEGACY_CHECKUP_FILE)) {
    return [];
  }

  try {
    const fileContents = fs.readFileSync(
      LEGACY_CHECKUP_FILE,
      'utf8',
    );

    const parsed = JSON.parse(fileContents);

    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.error(
      'Could not migrate legacy checkup storage:',
      error.message,
    );

    return [];
  }
}

function loadStorage() {
  fs.mkdirSync(path.dirname(DATA_FILE), {
    recursive: true,
  });

  let storage = emptyStorage();

  if (fs.existsSync(DATA_FILE)) {
    try {
      const fileContents = fs.readFileSync(
        DATA_FILE,
        'utf8',
      );

      storage = normalizeStorage(
        JSON.parse(fileContents),
      );
    } catch (error) {
      console.error(
        'Could not read local app storage. Starting with an empty file:',
        error.message,
      );
    }
  } else {
    storage.checkupRecords = readLegacyCheckups();
  }

  fs.writeFileSync(
    DATA_FILE,
    `${JSON.stringify(storage, null, 2)}\n`,
    'utf8',
  );

  return storage;
}

const storage = loadStorage();

function persist() {
  fs.writeFileSync(
    DATA_FILE,
    `${JSON.stringify(storage, null, 2)}\n`,
    'utf8',
  );
}

function getCollection(collectionName) {
  if (!COLLECTION_NAMES.includes(collectionName)) {
    throw new Error(
      `Unknown storage collection: ${collectionName}`,
    );
  }

  return storage[collectionName];
}

function getStorageFilePath() {
  return DATA_FILE;
}

module.exports = {
  getCollection,
  getStorageFilePath,
  persist,
};
