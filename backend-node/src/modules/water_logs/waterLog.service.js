const { randomUUID } = require('crypto');

const localStorage = require(
  '../../common/storage/localJsonStorage',
);

const waterLogs = localStorage.getCollection(
  'waterLogs',
);

const waterContainers = localStorage.getCollection(
  'waterContainers',
);

function normalizeName(value) {
  return String(value || '')
    .trim()
    .toLowerCase();
}

function createWaterContainer({
  userId,
  name,
  capacityMl,
}) {
  const normalizedName = normalizeName(name);
  const now = new Date().toISOString();

  /*
   * If a container with the same name already exists,
   * update its capacity instead of creating a duplicate.
   */
  const existingIndex = waterContainers.findIndex(
    (container) =>
      container.userId === userId &&
      normalizeName(container.name) ===
        normalizedName,
  );

  if (existingIndex !== -1) {
    const existing =
      waterContainers[existingIndex];

    const updated = {
      ...existing,
      name: name.trim(),
      capacityMl,
      updatedAt: now,
    };

    waterContainers[existingIndex] = updated;

    localStorage.persist();

    return {
      created: false,
      container: updated,
    };
  }

  const container = {
    id: randomUUID(),
    userId,
    name: name.trim(),
    capacityMl,
    createdAt: now,
    updatedAt: now,
  };

  waterContainers.push(container);

  localStorage.persist();

  return {
    created: true,
    container,
  };
}

function getWaterContainers({ userId }) {
  return waterContainers
    .filter(
      (container) =>
        container.userId === userId,
    )
    .sort((a, b) =>
      String(a.name).localeCompare(
        String(b.name),
      ),
    );
}

function getWaterContainerById({
  userId,
  id,
}) {
  return (
    waterContainers.find(
      (container) =>
        container.userId === userId &&
        container.id === id,
    ) || null
  );
}

function deleteWaterContainer({
  userId,
  id,
}) {
  const index = waterContainers.findIndex(
    (container) =>
      container.userId === userId &&
      container.id === id,
  );

  if (index === -1) {
    return null;
  }

  const [deletedContainer] =
    waterContainers.splice(index, 1);

  localStorage.persist();

  return deletedContainer;
}

function createWaterLog({
  userId,
  containerId,
  amountMl,
  containerName,
  loggedAt,
  source,
  clientRecordId,
  notes,
}) {
  /*
   * Prevent duplicate submissions from the app.
   */
  if (clientRecordId) {
    const existingRecord = waterLogs.find(
      (record) =>
        record.userId === userId &&
        record.clientRecordId ===
          clientRecordId,
    );

    if (existingRecord) {
      return {
        created: false,
        duplicate: true,
        record: existingRecord,
      };
    }
  }

  let selectedContainer = null;

  /*
   * When the user clicks a saved container,
   * use that container's saved name and capacity.
   */
  if (containerId) {
    selectedContainer =
      getWaterContainerById({
        userId,
        id: containerId,
      });

    if (!selectedContainer) {
      return {
        created: false,
        duplicate: false,
        record: null,
        reason: 'container_not_found',
      };
    }
  }

  const resolvedAmount = selectedContainer
    ? selectedContainer.capacityMl
    : amountMl;

  const resolvedName = selectedContainer
    ? selectedContainer.name
    : containerName || null;

  const now = new Date().toISOString();

  const record = {
    id: randomUUID(),
    userId,
    clientRecordId:
      clientRecordId || null,

    containerId:
      selectedContainer?.id || null,

    containerName: resolvedName,

    amountMl: resolvedAmount,

    source: source || 'manual',

    loggedAt: loggedAt || now,

    notes:
      typeof notes === 'string' &&
      notes.trim()
        ? notes.trim()
        : null,

    createdAt: now,
    updatedAt: now,
  };

  waterLogs.push(record);

  localStorage.persist();

  return {
    created: true,
    duplicate: false,
    record,
  };
}

function getWaterLogs({ userId }) {
  return waterLogs
    .filter(
      (record) =>
        record.userId === userId,
    )
    .sort(
      (a, b) =>
        new Date(b.loggedAt) -
        new Date(a.loggedAt),
    );
}

function getWaterLogById({
  userId,
  id,
}) {
  return (
    waterLogs.find(
      (record) =>
        record.userId === userId &&
        record.id === id,
    ) || null
  );
}

function updateWaterLog({
  userId,
  id,
  changes,
}) {
  const index = waterLogs.findIndex(
    (record) =>
      record.userId === userId &&
      record.id === id,
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

  localStorage.persist();

  return updated;
}

function deleteWaterLog({
  userId,
  id,
}) {
  const index = waterLogs.findIndex(
    (record) =>
      record.userId === userId &&
      record.id === id,
  );

  if (index === -1) {
    return null;
  }

  const [deletedRecord] =
    waterLogs.splice(index, 1);

  localStorage.persist();

  return deletedRecord;
}

function getWaterSummary({ userId }) {
  const records = getWaterLogs({
    userId,
  });

  const totalMl = records.reduce(
    (total, record) =>
      total + record.amountMl,
    0,
  );

  return {
    recordCount: records.length,
    totalMl:
      Math.round(totalMl * 100) / 100,
  };
}

module.exports = {
  createWaterContainer,
  getWaterContainers,
  getWaterContainerById,
  deleteWaterContainer,
  createWaterLog,
  getWaterLogs,
  getWaterLogById,
  updateWaterLog,
  deleteWaterLog,
  getWaterSummary,
};