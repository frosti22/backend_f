const waterLogService = require(
  './waterLog.service',
);

function getUserId(req) {
  return String(
    req.header('x-user-id') || 'test-user',
  ).trim();
}

function parseAmount(value) {
  const amount = Number(value);

  return Number.isFinite(amount) &&
    amount > 0 &&
    amount <= 10000
    ? amount
    : null;
}

function validDate(value) {
  return (
    value === undefined ||
    value === null ||
    !Number.isNaN(Date.parse(value))
  );
}

function createWaterContainer(req, res) {
  const name = String(
    req.body.name || '',
  ).trim();

  const capacityMl = parseAmount(
    req.body.capacityMl,
  );

  if (
    name.length < 2 ||
    name.length > 80
  ) {
    return res.status(400).json({
      success: false,
      message:
        'Container name must contain between 2 and 80 characters.',
    });
  }

  if (capacityMl === null) {
    return res.status(400).json({
      success: false,
      message:
        'capacityMl must be between 0.01 and 10,000 mL.',
    });
  }

  const result =
    waterLogService.createWaterContainer({
      userId: getUserId(req),
      name,
      capacityMl,
    });

  return res
    .status(result.created ? 201 : 200)
    .json({
      success: true,
      created: result.created,

      message: result.created
        ? 'Water container saved successfully.'
        : 'Saved water container updated successfully.',

      data: result.container,
    });
}

function getWaterContainers(req, res) {
  const containers =
    waterLogService.getWaterContainers({
      userId: getUserId(req),
    });

  return res.json({
    success: true,
    count: containers.length,
    data: containers,
  });
}

function deleteWaterContainer(req, res) {
  const container =
    waterLogService.deleteWaterContainer({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!container) {
    return res.status(404).json({
      success: false,
      message:
        'Water container not found.',
    });
  }

  return res.json({
    success: true,
    message:
      'Water container deleted successfully.',
    data: container,
  });
}

function createWaterLog(req, res) {
  const containerId =
    typeof req.body.containerId ===
      'string' &&
    req.body.containerId.trim()
      ? req.body.containerId.trim()
      : null;

  /*
   * When a saved container is selected,
   * the amount comes from the container capacity.
   */
  const amountMl = containerId
    ? null
    : parseAmount(req.body.amountMl);

  if (
    !containerId &&
    amountMl === null
  ) {
    return res.status(400).json({
      success: false,
      message:
        'Select a saved container or provide a valid amountMl.',
    });
  }

  if (!validDate(req.body.loggedAt)) {
    return res.status(400).json({
      success: false,
      message:
        'loggedAt must be a valid date and time.',
    });
  }

  const result =
    waterLogService.createWaterLog({
      userId: getUserId(req),
      containerId,
      amountMl,
      containerName:
        req.body.containerName,
      loggedAt: req.body.loggedAt,
      source: 'manual',
      clientRecordId:
        req.body.clientRecordId,
      notes: req.body.notes,
    });

  if (!result.record) {
    return res.status(404).json({
      success: false,
      message:
        'Saved water container not found.',
    });
  }

  return res
    .status(result.duplicate ? 200 : 201)
    .json({
      success: true,
      duplicate: result.duplicate,

      message: result.duplicate
        ? 'This water entry was already submitted.'
        : 'Water entry created successfully.',

      data: result.record,
    });
}

function getWaterLogs(req, res) {
  const records =
    waterLogService.getWaterLogs({
      userId: getUserId(req),
    });

  return res.json({
    success: true,
    count: records.length,
    data: records,
  });
}

function getWaterLogById(req, res) {
  const record =
    waterLogService.getWaterLogById({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!record) {
    return res.status(404).json({
      success: false,
      message:
        'Water entry not found.',
    });
  }

  return res.json({
    success: true,
    data: record,
  });
}

function updateWaterLog(req, res) {
  const changes = {};

  if (
    req.body.amountMl !== undefined
  ) {
    const amountMl = parseAmount(
      req.body.amountMl,
    );

    if (amountMl === null) {
      return res.status(400).json({
        success: false,
        message:
          'amountMl must be between 0.01 and 10,000 mL.',
      });
    }

    changes.amountMl = amountMl;
  }

  if (!validDate(req.body.loggedAt)) {
    return res.status(400).json({
      success: false,
      message:
        'loggedAt must be a valid date and time.',
    });
  }

  if (
    req.body.loggedAt !== undefined
  ) {
    changes.loggedAt =
      req.body.loggedAt;
  }

  if (req.body.notes !== undefined) {
    changes.notes = req.body.notes;
  }

  const record =
    waterLogService.updateWaterLog({
      userId: getUserId(req),
      id: req.params.id,
      changes,
    });

  if (!record) {
    return res.status(404).json({
      success: false,
      message:
        'Water entry not found.',
    });
  }

  return res.json({
    success: true,
    message:
      'Water entry updated successfully.',
    data: record,
  });
}

function deleteWaterLog(req, res) {
  const record =
    waterLogService.deleteWaterLog({
      userId: getUserId(req),
      id: req.params.id,
    });

  if (!record) {
    return res.status(404).json({
      success: false,
      message:
        'Water entry not found.',
    });
  }

  return res.json({
    success: true,
    message:
      'Water entry deleted successfully.',
    data: record,
  });
}

function getWaterSummary(req, res) {
  return res.json({
    success: true,

    data:
      waterLogService.getWaterSummary({
        userId: getUserId(req),
      }),
  });
}

module.exports = {
  createWaterContainer,
  getWaterContainers,
  deleteWaterContainer,
  createWaterLog,
  getWaterLogs,
  getWaterLogById,
  updateWaterLog,
  deleteWaterLog,
  getWaterSummary,
};