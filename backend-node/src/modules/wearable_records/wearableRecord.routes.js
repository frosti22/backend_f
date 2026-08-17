const express = require('express');

const wearableRecordController = require(
  './wearableRecord.controller',
);

const router = express.Router();

router.post(
  '/daily',
  wearableRecordController.saveDailyWearableRecord,
);

router.get(
  '/',
  wearableRecordController.getWearableRecords,
);

router.get(
  '/date/:date',
  wearableRecordController.getWearableRecordByDate,
);

module.exports = router;
