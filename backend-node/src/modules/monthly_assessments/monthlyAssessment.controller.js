const monthlyAssessmentService = require(
  './monthlyAssessment.service',
);

function getUserId(req) {
  return String(
    req.header('x-user-id') || 'test-user',
  ).trim();
}

function currentMonth() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

function getMonthlyAssessment(req, res) {
  const month = String(
    req.query.month || currentMonth(),
  ).trim();

  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) {
    return res.status(400).json({
      success: false,
      message: 'month must use YYYY-MM format.',
    });
  }

  const result = monthlyAssessmentService.getMonthlyAssessment({
    userId: getUserId(req),
    month,
  });

  return res.json({
    success: true,
    data: result,
  });
}

module.exports = {
  getMonthlyAssessment,
};
