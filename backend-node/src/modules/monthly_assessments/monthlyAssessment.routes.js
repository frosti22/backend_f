const express = require('express');

const monthlyAssessmentController = require(
  './monthlyAssessment.controller',
);

const router = express.Router();

router.get(
  '/',
  monthlyAssessmentController.getMonthlyAssessment,
);

module.exports = router;
