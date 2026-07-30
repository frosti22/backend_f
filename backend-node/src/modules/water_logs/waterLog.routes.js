const express = require('express');
const waterLogController = require('./waterLog.controller');

const router = express.Router();

router.get('/summary', waterLogController.getWaterSummary);
router.post('/', waterLogController.createWaterLog);
router.get('/', waterLogController.getWaterLogs);
router.get('/:id', waterLogController.getWaterLogById);
router.patch('/:id', waterLogController.updateWaterLog);
router.delete('/:id', waterLogController.deleteWaterLog);

module.exports = router;
