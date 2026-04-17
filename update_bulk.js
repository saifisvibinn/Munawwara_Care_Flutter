const fs = require('fs');
const p = 'C:/Users/drago/Desktop/projects/Durrah care mob app/mc_backend_app/controllers/auth_controller.js';
let t = fs.readFileSync(p, 'utf8');

t = t.replace('for (let p of pilgrims) {', 'let createdFields=[]; let rowCount=0; for (let p of pilgrims) { rowCount++;');
t = t.replace(/await Group\.findByIdAndUpdate(.*?);/s, 'await Group.findByIdAndUpdate\;');
t = t.replace(/addedCount\+\+;/g, 'addedCount++; createdFields.push({ _id: user._id, full_name: user.full_name, phone_number: user.phone_number, one_time_code: user._otc || null });');

let bulk_res = "sendSuccess(res, 200, 'Bulk provision complete', { added: addedCount, errors: errors.length > 0 ? errors : null });";
let new_bulk_res = "sendSuccess(res, 200, 'Bulk provision complete', { summary: { total_rows: rowCount, created_count: addedCount, skipped_count: errors.length }, created: createdFields, skipped: errors.map((e,i)=>({row:i, reason:e.error})) });";

t = t.replace(bulk_res, new_bulk_res);

fs.writeFileSync(p, t);
console.log('Fixed Bulk!');
