const express = require('express');
const foodController = require('./food.controller');

const router = express.Router();

router.get('/status', foodController.getFoodStatus);
router.get('/search', foodController.searchFoods);
router.get('/:fdcId', foodController.getFoodByFdcId);

module.exports = router;