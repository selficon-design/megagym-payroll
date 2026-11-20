// Παράγει το supabase/functions/guide/content.ts από το docs/guide.md (τρέξτε το μετά από κάθε αλλαγή του οδηγού).
//   node scripts/build-guide.mjs
import { readFileSync, writeFileSync } from "node:fs";
export const guideModule = (md) => `// ΠΑΡΑΓΕΤΑΙ ΑΥΤΟΜΑΤΑ από το docs/guide.md με: node scripts/build-guide.mjs — μην το αλλάζετε με το χέρι.\nexport const GUIDE = ${JSON.stringify(md)};\n`;
if (import.meta.url === `file://${process.argv[1]}`) {
  const root = new URL("../", import.meta.url);
  const md = readFileSync(new URL("docs/guide.md", root), "utf8");
  writeFileSync(new URL("supabase/functions/guide/content.ts", root), guideModule(md));
  console.log("ok: supabase/functions/guide/content.ts");
}
