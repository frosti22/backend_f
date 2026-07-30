const express = require('express');

const waterLogController = require(
  './waterLog.controller',
);

const router = express.Router();

/*
 * Summary must be placed before /:id so Express
 * does not interpret "summary" as a water-log ID.
 */
router.get(
  '/summary',
  waterLogController.getWaterSummary,
);

/*
 * Reusable water-container routes.
 */
router.post(
  '/containers',
  waterLogController.createWaterContainer,
);

router.get(
  '/containers',
  waterLogController.getWaterContainers,
);

router.delete(
  '/containers/:id',
  waterLogController.deleteWaterContainer,
);

/*
 * Water-log routes.
 */
router.post(
  '/',
  waterLogController.createWaterLog,
);

router.get(
  '/',
  waterLogController.getWaterLogs,
);

router.get(
  '/:id',
  waterLogController.getWaterLogById,
);

router.patch(
  '/:id',
  waterLogController.updateWaterLog,
);

router.delete(
  '/:id',
  waterLogController.deleteWaterLog,
);

module.exports = router;