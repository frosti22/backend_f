const express = require('express');

const foodLogController = require(
  './foodLog.controller',
);

const router = express.Router();

router.get(
  '/summary',
  foodLogController.getFoodLogSummary,
);

router.post(
  '/manual',
  foodLogController.createManualFoodLog,
);

router.post(
  '/',
  foodLogController.createFoodLog,
);

router.get(
  '/',
  foodLogController.getFoodLogs,
);

router.get(
  '/:id',
  foodLogController.getFoodLogById,
);

router.patch(
  '/:id',
  foodLogController.updateFoodLog,
);

router.delete(
  '/:id',
  foodLogController.deleteFoodLog,
);

module.exports = router;