const express = require('express');

const checkupRecordController = require(
  './checkupRecord.controller',
);

const router = express.Router();

router.post(
  '/',
  checkupRecordController.createCheckupRecord,
);

router.get(
  '/',
  checkupRecordController.getCheckupRecords,
);

router.get(
  '/:id',
  checkupRecordController.getCheckupRecordById,
);

router.patch(
  '/:id',
  checkupRecordController.updateCheckupRecord,
);

router.delete(
  '/:id',
  checkupRecordController.deleteCheckupRecord,
);

module.exports = router;