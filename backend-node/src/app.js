const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

const foodRoutes = require(
  './modules/foods/food.routes',
);
const nutritionRoutes = require(
  './modules/nutrition/nutrition.routes',
);
const foodLogRoutes = require(
  './modules/food_logs/foodLog.routes',
);
const waterLogRoutes = require(
  './modules/water_logs/waterLog.routes',
);
const checkupRecordRoutes = require(
  './modules/checkup_records/checkupRecord.routes',
);
const foodService = require(
  './modules/foods/food.service',
);

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));

foodService.loadFoods();

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'log-ckd-backend',
  });
});

app.use('/api/foods', foodRoutes);
app.use('/api/nutrition', nutritionRoutes);
app.use('/api/food-logs', foodLogRoutes);
app.use('/api/water-logs', waterLogRoutes);
app.use('/api/checkup-records', checkupRecordRoutes);

app.use((_req, res) => {
  res.status(404).json({
    success: false,
    message: 'API endpoint not found.',
  });
});

module.exports = app;
