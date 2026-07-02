const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");
const { toFile } = require("openai/uploads");

admin.initializeApp();

const openAiKey = defineSecret("OPENAI_API_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function handleCors(req, res) {
  Object.entries(corsHeaders).forEach(([key, value]) => res.set(key, value));
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  if (req.method !== "POST") {
    res.status(405).json({ error: "Use POST." });
    return true;
  }
  return false;
}

function openaiClient() {
  return new OpenAI({ apiKey: openAiKey.value() });
}

function stripJsonFence(value) {
  return value
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function normalizeWeekdays(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => Number(item))
    .filter((item) => Number.isInteger(item) && item >= 1 && item <= 7);
}

function sanitizeTasks(tasks) {
  if (!Array.isArray(tasks)) return [];
  return tasks
    .map((task) => ({
      title: String(task.title || "").trim(),
      subtitle: String(task.subtitle || "").trim(),
      dueDate: task.dueDate ? String(task.dueDate).trim() : null,
      repeatsDaily: task.repeatsDaily === true,
      repeatWeekdays: normalizeWeekdays(task.repeatWeekdays),
    }))
    .filter((task) => task.title.length > 0)
    .slice(0, 24);
}

exports.taskPlan = onRequest(
  { secrets: [openAiKey], cors: true, timeoutSeconds: 120, region: "us-central1" },
  async (req, res) => {
    if (handleCors(req, res)) return;

    try {
      const {
        goalTitle = "",
        category = "",
        deadline = "",
        daysPerWeek = 3,
        minutesPerSession = 30,
        preferredWeekdays = [],
      } = req.body || {};

      const prompt = `
You are Lucy, a practical coach inside the LevelUp app.
Create a realistic task plan for this goal.

Goal: ${goalTitle}
Life area: ${category}
Deadline: ${deadline}
Preferred days per week: ${daysPerWeek}
Minutes per session: ${minutesPerSession}
Preferred weekdays: ${JSON.stringify(preferredWeekdays)}

Rules:
- Return only JSON, no markdown.
- Weekdays are ISO numbers: Monday=1, Sunday=7.
- Use dueDate for one-time tasks in YYYY-MM-DD format.
- Use repeatWeekdays for repeating tasks.
- repeatsDaily true only if it really should happen every day.
- Keep the plan realistic and editable.
- For reading goals, monthly book tasks are OK.
- For running goals, use progressive training and one final goal-check task.

JSON shape:
{
  "note": "short note for the user",
  "tasks": [
    {
      "title": "Task title",
      "subtitle": "Short detail",
      "dueDate": "YYYY-MM-DD or null",
      "repeatsDaily": false,
      "repeatWeekdays": [1,3,5]
    }
  ]
}
`;

      const response = await openaiClient().responses.create({
        model: process.env.OPENAI_TEXT_MODEL || "gpt-4.1-mini",
        input: prompt,
      });

      const parsed = JSON.parse(stripJsonFence(response.output_text || "{}"));
      const tasks = sanitizeTasks(parsed.tasks);
      if (tasks.length === 0) {
        res.status(502).json({ error: "AI returned no tasks." });
        return;
      }

      res.status(200).json({
        note: String(parsed.note || "Lucy drafted a plan. Review it before saving."),
        tasks,
      });
    } catch (error) {
      console.error("taskPlan failed", error);
      res.status(500).json({ error: "Task plan generation failed." });
    }
  },
);

exports.futureImage = onRequest(
  {
    secrets: [openAiKey],
    cors: true,
    timeoutSeconds: 300,
    memory: "1GiB",
    region: "us-central1",
  },
  async (req, res) => {
    if (handleCors(req, res)) return;

    try {
      const {
        sourceImageBase64 = "",
        sourceImageMimeType = "image/jpeg",
        vision = "",
        areaVisions = {},
      } = req.body || {};

      if (!sourceImageBase64) {
        res.status(400).json({ error: "Missing sourceImageBase64." });
        return;
      }

      const imageBuffer = Buffer.from(sourceImageBase64, "base64");
      if (imageBuffer.length > 8 * 1024 * 1024) {
        res.status(413).json({ error: "Image is too large." });
        return;
      }

      const prompt = `
Create a realistic aspirational "Future Me" portrait.
Preserve the person's identity from the uploaded photo.
Reflect this future vision: ${vision}
Life-area visions: ${JSON.stringify(areaVisions)}

The image should feel premium, calm, warm, minimal, and aligned with a self-development app.
It may include subtle visual cues from the user's goals, but must remain believable.
No text, no logos, no medical claims, no exaggerated fantasy styling.
`;

      const imageFile = await toFile(
        imageBuffer,
        sourceImageMimeType.includes("png") ? "future-me.png" : "future-me.jpg",
        { type: sourceImageMimeType },
      );

      const result = await openaiClient().images.edit({
        model: process.env.OPENAI_IMAGE_MODEL || "gpt-image-1",
        image: imageFile,
        prompt,
        size: "1024x1024",
      });

      const b64 = result.data && result.data[0] && result.data[0].b64_json;
      if (!b64) {
        res.status(502).json({ error: "AI returned no image." });
        return;
      }

      const outputBuffer = Buffer.from(b64, "base64");
      const bucket = admin.storage().bucket();
      const fileName = `ai/future-me/${Date.now()}-${Math.random()
        .toString(36)
        .slice(2)}.png`;
      const file = bucket.file(fileName);

      await file.save(outputBuffer, {
        metadata: {
          contentType: "image/png",
          cacheControl: "public, max-age=31536000",
        },
      });

      await file.makePublic();

      res.status(200).json({
        imageUrl: `https://storage.googleapis.com/${bucket.name}/${fileName}`,
      });
    } catch (error) {
      console.error("futureImage failed", error);
      res.status(500).json({ error: "Future image generation failed." });
    }
  },
);
