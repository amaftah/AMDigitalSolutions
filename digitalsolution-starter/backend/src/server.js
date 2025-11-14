const express = require('express');
const bodyParser = require('body-parser');
const flows = require('./routes/flows');
const { init } = require('./db');

const app = express();
app.use(bodyParser.json());
app.use('/api/flows', flows);

const port = process.env.BACKEND_PORT || 4000;

(async () => {
  await init();
  app.listen(port, () => console.log('backend listening on', port));
})();
