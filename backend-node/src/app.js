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
const wearableRecordRoutes = require(
  './modules/wearable_records/wearableRecord.routes',
);
const monthlyAssessmentRoutes = require(
  './modules/monthly_assessments/monthlyAssessment.routes',
);
const facilityRoutes = require(
  './modules/facility_directory/facility.routes',
);
const locationRoutes = require(
  './modules/location_directory/location.routes',
);
const facilityService = require(
  './modules/facility_directory/facility.service',
);
const locationService = require(
  './modules/location_directory/location.service',
);
const foodService = require(
  './modules/foods/food.service',
);

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));

foodService.loadFoods();
facilityService.loadFacilities();
locationService.loadLocations();

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
app.use('/api/wearable-records', wearableRecordRoutes);
app.use('/api/monthly-assessments', monthlyAssessmentRoutes);
app.use('/api/facilities', facilityRoutes);
app.use('/api/locations', locationRoutes);

app.use((_req, res) => {
  res.status(404).json({
    success: false,
    message: 'API endpoint not found.',
  });
});

module.exports = app;
