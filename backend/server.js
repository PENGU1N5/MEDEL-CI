// MED-EL CI Service Pool — Backend (Render)
// Scheduled tasks: shortage alerts, monthly reports, service reminders
require("dotenv").config();
const express = require("express");
const { createClient } = require("@supabase/supabase-js");
const { CronJob } = require("cron");

const app = express();
const PORT = process.env.PORT || 3001;

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

app.use(express.json());

// Health check — Render uses this
app.get("/health", (_req, res) => res.json({ status: "ok" }));

// ---------- Daily: check for countries with zero available units ----------
async function checkZeroStock() {
  const { data: matrix, error } = await sb.from("v_stock_matrix").select("*");
  if (error) { console.error("Stock matrix error:", error); return; }

  const alerts = matrix.filter((r) => r.total_active > 0 && r.available === 0);
  if (alerts.length === 0) {
    console.log("Zero-stock check passed — all countries have stock.");
    return;
  }

  for (const row of alerts) {
    console.warn(
      `ALERT: ${row.country_name} has 0 available ${row.model_name} ` +
        `(${row.at_service} at service, ${row.issued} with patients)`
    );
  }
}

// ---------- Weekly: slow-moving service items (> 30 days at Austria) ----------
async function checkServiceDelays() {
  const { data: turnaround } = await sb.from("v_service_turnaround").select("*");
  if (!turnaround) return;

  const stuck = turnaround.filter((r) => {
    if (!r.returned_on) {
      const days = Math.round((Date.now() - new Date(r.sent_on)) / 864e5);
      return days > 30;
    }
    return false;
  });

  for (const row of stuck) {
    const days = Math.round((Date.now() - new Date(row.sent_on)) / 864e5);
    console.warn(
      `SERVICE DELAY: ${row.serial_number} (${row.model_code}) from ${row.country_code} ` +
        `has been at Austria for ${days} days.`
    );
  }
}

// ---------- Monthly: shortage summary ----------
async function monthlyShortageReport() {
  const now = new Date();
  const firstOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

  const { data: shortages } = await sb
    .from("shortage_events")
    .select("country_code, model_code, units_needed")
    .gte("occurred_on", firstOfMonth);

  if (!shortages || shortages.length === 0) {
    console.log("Monthly report: No shortages this month.");
    return;
  }

  const total = shortages.reduce((s, r) => s + r.units_needed, 0);
  console.log(`Monthly report: ${shortages.length} shortage events, ${total} total units short.`);
}

// ---------- Schedule jobs ----------
const jobDaily = new CronJob("0 8 * * *", checkZeroStock, null, false, "Asia/Riyadh");
const jobWeekly = new CronJob("0 9 * * 1", checkServiceDelays, null, false, "Asia/Riyadh");
const jobMonthly = new CronJob("0 10 1 * *", monthlyShortageReport, null, false, "Asia/Riyadh");

jobDaily.start();
jobWeekly.start();
jobMonthly.start();

console.log("Scheduled jobs running (daily 08:00, weekly Mon 09:00, monthly 1st 10:00 AST)");

// ---------- Manual trigger endpoints ----------
app.post("/run/check-stock", async (_req, res) => {
  await checkZeroStock();
  res.json({ done: true });
});

app.post("/run/check-service", async (_req, res) => {
  await checkServiceDelays();
  res.json({ done: true });
});

app.post("/run/monthly-report", async (_req, res) => {
  await monthlyShortageReport();
  res.json({ done: true });
});

app.listen(PORT, () => console.log(`Backend running on port ${PORT}`));
