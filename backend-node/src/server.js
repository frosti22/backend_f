require('dotenv').config();
const app = require('./app');

const port = Number(process.env.PORT || 3000);

app.listen(port, () => {
  console.log(`log.CKD backend running on port ${port}`);
});
