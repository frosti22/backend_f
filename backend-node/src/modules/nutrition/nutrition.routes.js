const express = require('express');

const nutritionController = require(
  './nutrition.controller',
);

const router = express.Router();

router.post(
  '/calculate',
  nutritionController.calculateNutrition,
);

module.exports = router;