import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import express from "express";
import cors from "cors";
import { load } from "cheerio";
import sqlite3 from "sqlite3";
import { open } from "sqlite";

const app = express();
app.use(cors());
app.use(express.json({ limit: "256kb" }));

loadLocalEnv();
console.log(
  `Pexels fallback: ${process.env.PEXELS_API_KEY ? "enabled" : "missing API key"}`,
);

const DEFAULT_SOURCES = [
  {
    id: "iwnsvg",
    name: "iWitness News",
    listUrl: "https://www.iwnsvg.com/",
    baseUrl: "https://www.iwnsvg.com",
    articleUrlPatterns: ["/\\d{4}\\/\\d{2}\\/\\d{2}\\/"],
  },
  {
    id: "onenews",
    name: "One News SVG",
    listUrl: "https://onenewsstvincent.com/",
    baseUrl: "https://onenewsstvincent.com",
    articleUrlPatterns: ["/\\d{4}\\/\\d{2}\\/\\d{2}\\/"],
  },
];

const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36";
const MAX_ARTICLES_PER_SOURCE = 25;
const ENRICH_CONCURRENCY = 5;
const SOURCE_CONCURRENCY = 4;
const FETCH_TIMEOUT_MS = 8000;
const SOURCE_TIMEOUT_MS = 12000;
const REQUEST_TIMEOUT_MS = 12000;
const REFRESH_INTERVAL_MS = 12 * 60 * 1000;
const RETENTION_DAYS = 30;
const MAX_RESPONSE_ITEMS = 500;
const DEFAULT_REFRESH_MINUTES = 20;
const SOURCE_REFRESH_MINUTES = {
  iwnsvg: 15,
  onenews: 15,
  stvincenttimes: 15,
  searchlight: 20,
  "guardian-tt": 20,
  trinidadexpress: 20,
  cnn: 10,
  bbc: 10,
};
const LIST_CACHE_TTL_MS = 3 * 60 * 1000;
const ARTICLE_CACHE_TTL_MS = 5 * 60 * 1000;
const DETAIL_CACHE_TTL_MS = 10 * 60 * 1000;
const FALLBACK_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_PARAGRAPHS = 36;
const EXTRA_IMAGE_HOSTS = [
  "wp.com",
  "wordpress.com",
  "files.wordpress.com",
  "i0.wp.com",
  "i1.wp.com",
  "i2.wp.com",
  "s0.wp.com",
];
const AUTHOR_IGNORE_BY_SOURCE = {
  onenews: ["admin", "one news svg"],
  iwnsvg: ["kentonxchance"],
};

const listCache = new Map();
const articleCache = new Map();
const detailCache = new Map();
const fallbackImageCache = new Map();
let backgroundRefreshInFlight = false;
let lastBackgroundRefresh = 0;
let db;

function loadLocalEnv() {
  const currentFile = fileURLToPath(import.meta.url);
  const envPath = path.join(path.dirname(currentFile), "..", ".env");
  if (!fs.existsSync(envPath)) return;

  const content = fs.readFileSync(envPath, "utf8");
  content.split(/\r?\n/).forEach((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) return;
    const index = trimmed.indexOf("=");
    if (index === -1) return;
    const key = trimmed.slice(0, index).trim();
    let value = trimmed.slice(index + 1).trim();
    value = value.replace(/^"(.*)"$/, "$1");
    if (!process.env[key]) {
      process.env[key] = value;
    }
  });
}

async function initDb() {
  const dbPath =
    process.env.DB_PATH || path.join(process.cwd(), "data", "news.db");
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  db = await open({
    filename: dbPath,
    driver: sqlite3.Database,
  });
  await db.exec("PRAGMA journal_mode=WAL;");
  await db.exec(`
    CREATE TABLE IF NOT EXISTS sources (
      id TEXT PRIMARY KEY,
      name TEXT,
      listUrl TEXT,
      baseUrl TEXT,
      articleUrlPatterns TEXT,
      refreshIntervalMinutes INTEGER,
      lastFetchedAt TEXT,
      updatedAt TEXT
    );
  `);
  await db.exec(`
    CREATE TABLE IF NOT EXISTS articles (
      id TEXT PRIMARY KEY,
      url TEXT UNIQUE,
      sourceId TEXT,
      sourceName TEXT,
      title TEXT,
      publishedAt TEXT,
      imageUrl TEXT,
      excerpt TEXT,
      preview TEXT,
      author TEXT,
      fetchedAt TEXT,
      updatedAt TEXT
    );
  `);
  await db.exec(
    "CREATE INDEX IF NOT EXISTS idx_articles_source ON articles(sourceId);",
  );
  await db.exec(
    "CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(publishedAt);",
  );
  await db.exec(
    "CREATE INDEX IF NOT EXISTS idx_articles_fetched ON articles(fetchedAt);",
  );

  const columns = await db.all("PRAGMA table_info(sources);");
  const names = new Set(columns.map((col) => col.name));
  if (!names.has("refreshIntervalMinutes")) {
    await db.exec("ALTER TABLE sources ADD COLUMN refreshIntervalMinutes INTEGER;");
  }
  if (!names.has("lastFetchedAt")) {
    await db.exec("ALTER TABLE sources ADD COLUMN lastFetchedAt TEXT;");
  }
}

function resolveRefreshMinutes(source) {
  if (Number.isFinite(source.refreshIntervalMinutes)) {
    return Math.max(5, Math.min(120, source.refreshIntervalMinutes));
  }
  return SOURCE_REFRESH_MINUTES[source.id] || DEFAULT_REFRESH_MINUTES;
}

async function registerSources(sources) {
  if (!db) return;
  const now = new Date().toISOString();
  for (const source of sources) {
    const patterns = Array.isArray(source.articleUrlPatterns)
      ? JSON.stringify(source.articleUrlPatterns)
      : null;
    const existing = await db.get(
      "SELECT refreshIntervalMinutes, lastFetchedAt FROM sources WHERE id = ?",
      [source.id],
    );
    const refreshIntervalMinutes =
      Number.isFinite(source.refreshIntervalMinutes)
        ? resolveRefreshMinutes(source)
        : existing?.refreshIntervalMinutes || resolveRefreshMinutes(source);
    const lastFetchedAt = existing?.lastFetchedAt || null;
    await db.run(
      `
      INSERT INTO sources (
        id, name, listUrl, baseUrl, articleUrlPatterns,
        refreshIntervalMinutes, lastFetchedAt, updatedAt
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name=excluded.name,
        listUrl=excluded.listUrl,
        baseUrl=excluded.baseUrl,
        articleUrlPatterns=excluded.articleUrlPatterns,
        refreshIntervalMinutes=excluded.refreshIntervalMinutes,
        lastFetchedAt=excluded.lastFetchedAt,
        updatedAt=excluded.updatedAt;
      `,
      [
        source.id,
        source.name,
        source.listUrl,
        source.baseUrl,
        patterns,
        refreshIntervalMinutes,
        lastFetchedAt,
        now,
      ],
    );
  }
}

async function loadSourcesFromDb() {
  if (!db) return [];
  const rows = await db.all(
    "SELECT id, name, listUrl, baseUrl, articleUrlPatterns, refreshIntervalMinutes, lastFetchedAt FROM sources;",
  );
  return rows.map((row) => {
    let patterns = [];
    if (row.articleUrlPatterns) {
      try {
        patterns = JSON.parse(row.articleUrlPatterns);
      } catch {
        patterns = [];
      }
    }
    return {
      id: row.id,
      name: row.name,
      listUrl: row.listUrl,
      baseUrl: row.baseUrl,
      articleUrlPatterns: patterns,
      refreshIntervalMinutes: row.refreshIntervalMinutes,
      lastFetchedAt: row.lastFetchedAt,
    };
  });
}

async function upsertArticles(source, items) {
  if (!db || items.length === 0) return;
  const now = new Date().toISOString();
  for (const item of items) {
    await db.run(
      `
      INSERT INTO articles (
        id, url, sourceId, sourceName, title, publishedAt, imageUrl,
        excerpt, preview, author, fetchedAt, updatedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(url) DO UPDATE SET
        sourceId=excluded.sourceId,
        sourceName=excluded.sourceName,
        title=excluded.title,
        publishedAt=COALESCE(excluded.publishedAt, articles.publishedAt),
        imageUrl=COALESCE(excluded.imageUrl, articles.imageUrl),
        excerpt=COALESCE(excluded.excerpt, articles.excerpt),
        preview=COALESCE(excluded.preview, articles.preview),
        author=COALESCE(excluded.author, articles.author),
        fetchedAt=excluded.fetchedAt,
        updatedAt=excluded.updatedAt;
      `,
      [
        item.id,
        item.url,
        source.id,
        source.name,
        item.title,
        item.publishedAt,
        item.imageUrl,
        item.excerpt,
        item.preview,
        item.author,
        now,
        now,
      ],
    );
  }
}

async function markSourceFetched(sourceId) {
  if (!db) return;
  await db.run("UPDATE sources SET lastFetchedAt = ? WHERE id = ?;", [
    new Date().toISOString(),
    sourceId,
  ]);
}

async function pruneOldArticles() {
  if (!db) return;
  const cutoff = new Date(
    Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();
  await db.run(
    `
    DELETE FROM articles
    WHERE (publishedAt IS NOT NULL AND publishedAt < ?)
       OR (publishedAt IS NULL AND fetchedAt < ?);
    `,
    [cutoff, cutoff],
  );
}

async function refreshAllSources() {
  const sources = await loadSourcesFromDb();
  if (sources.length === 0) {
    await registerSources(DEFAULT_SOURCES);
    return refreshAllSources();
  }
  const now = Date.now();
  const dueSources = sources.filter((source) => {
    const interval = resolveRefreshMinutes(source) * 60 * 1000;
    if (!source.lastFetchedAt) return true;
    const last = Date.parse(source.lastFetchedAt);
    if (Number.isNaN(last)) return true;
    return now - last >= interval;
  });

  if (dueSources.length === 0) {
    await pruneOldArticles();
    return;
  }

  const results = await asyncPool(SOURCE_CONCURRENCY, dueSources, (source) =>
    safeScrapeSource(source),
  );
  for (const result of results) {
    if (result?.items?.length) {
      await upsertArticles(
        { id: result.sourceId, name: result.sourceName },
        result.items,
      );
    }
    await markSourceFetched(result.sourceId);
  }
  await pruneOldArticles();
}

async function getArticlesFromDb(sourceIds) {
  if (!db) return [];
  const ids = sourceIds?.filter(Boolean) ?? [];
  const params = [];
  let where = "";
  if (ids.length > 0) {
    where = `WHERE sourceId IN (${ids.map(() => "?").join(",")})`;
    params.push(...ids);
  }
  const rows = await db.all(
    `
    SELECT id, url, sourceId, sourceName, title, publishedAt, imageUrl, excerpt, preview, author
    FROM articles
    ${where}
    ORDER BY COALESCE(publishedAt, fetchedAt) DESC
    LIMIT ?;
    `,
    [...params, MAX_RESPONSE_ITEMS],
  );
  return rows;
}

async function getLatestTimestamp(sourceIds) {
  if (!db) return null;
  const ids = sourceIds?.filter(Boolean) ?? [];
  const params = [];
  let where = "";
  if (ids.length > 0) {
    where = `WHERE sourceId IN (${ids.map(() => "?").join(",")})`;
    params.push(...ids);
  }
  const row = await db.get(
    `
    SELECT MAX(COALESCE(publishedAt, fetchedAt)) AS latest
    FROM articles
    ${where};
    `,
    params,
  );
  return row?.latest ?? null;
}

function getCache(map, key, ttlMs) {
  const cached = map.get(key);
  if (!cached) return null;
  if (Date.now() - cached.ts > ttlMs) {
    map.delete(key);
    return null;
  }
  return cached.data;
}

function setCache(map, key, data) {
  map.set(key, { ts: Date.now(), data });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function withTimeout(promise, ms, onTimeout, onTimeoutError) {
  let timeoutId;
  const timeout = new Promise((resolve, reject) => {
    timeoutId = setTimeout(() => {
      if (onTimeoutError) {
        reject(onTimeoutError);
        return;
      }
      resolve(onTimeout?.());
    }, ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timeoutId);
  }
}

function buildFallbackQuery(title, sourceName) {
  const raw = `${title || ""} ${sourceName || ""}`.toLowerCase();
  const cleaned = raw.replace(/[^a-z0-9\s]/g, " ");
  const words = cleaned.split(/\s+/).filter(Boolean);
  const stopwords = new Set([
    "the",
    "a",
    "an",
    "and",
    "or",
    "but",
    "if",
    "then",
    "than",
    "of",
    "for",
    "to",
    "from",
    "in",
    "on",
    "at",
    "by",
    "with",
    "about",
    "over",
    "under",
    "after",
    "before",
    "during",
    "into",
    "out",
    "up",
    "down",
    "as",
    "is",
    "are",
    "was",
    "were",
    "be",
    "been",
    "being",
    "it",
    "its",
    "this",
    "that",
    "these",
    "those",
    "he",
    "she",
    "they",
    "we",
    "you",
    "i",
    "his",
    "her",
    "their",
    "our",
    "your",
    "my",
    "new",
    "news",
    "live",
    "updates",
    "update",
    "today",
    "latest",
    "breaking",
  ]);
  const keywords = words.filter((word) => !stopwords.has(word));
  const selected = keywords.slice(0, 4);
  if (selected.length > 0) return selected.join(" ");
  if (sourceName) return sourceName.toLowerCase();
  return "news";
}

async function fetchPexelsFallbackImage(query) {
  const apiKey = process.env.PEXELS_API_KEY;
  if (!apiKey) return null;

  const cacheKey = `pexels:${query}`;
  const cached = getCache(fallbackImageCache, cacheKey, FALLBACK_CACHE_TTL_MS);
  if (cached) return cached;

  try {
    const url = new URL("https://api.pexels.com/v1/search");
    url.searchParams.set("query", query);
    url.searchParams.set("per_page", "1");
    url.searchParams.set("orientation", "landscape");

    const response = await fetch(url.toString(), {
      headers: {
        Authorization: apiKey,
        "User-Agent": USER_AGENT,
        Accept: "application/json",
      },
    });

    if (!response.ok) return null;
    const data = await response.json();
    const photo = Array.isArray(data?.photos) ? data.photos[0] : null;
    const imageUrl =
      photo?.src?.landscape ||
      photo?.src?.large ||
      photo?.src?.large2x ||
      photo?.src?.original ||
      null;

    if (imageUrl) {
      setCache(fallbackImageCache, cacheKey, imageUrl);
    }
    return imageUrl;
  } catch {
    return null;
  }
}

async function resolveFallbackImage(title, sourceName) {
  const query = buildFallbackQuery(title, sourceName);
  return fetchPexelsFallbackImage(query);
}

function normalizeUrl(url, baseUrl) {
  if (!url) return null;
  try {
    return new URL(url, baseUrl).toString();
  } catch {
    return null;
  }
}

function withHostSwap(urlString) {
  try {
    const url = new URL(urlString);
    if (url.hostname.startsWith("www.")) {
      url.hostname = url.hostname.replace(/^www\./, "");
      return url.toString();
    }
    if (url.hostname.split(".").length === 2) {
      url.hostname = `www.${url.hostname}`;
      return url.toString();
    }
    return null;
  } catch {
    return null;
  }
}

function normalizeArticleUrl(url, baseUrl) {
  const absolute = normalizeUrl(url, baseUrl);
  if (!absolute) return null;
  try {
    const parsed = new URL(absolute);
    parsed.hash = "";
    parsed.search = "";
    parsed.pathname = parsed.pathname.replace(/\/comment-page-\d+\/?$/i, "/");
    return parsed.toString();
  } catch {
    return absolute;
  }
}

function resolveSourceIdFromUrl(url) {
  try {
    const host = new URL(url).host.replace(/^www\./, "");
    const match = DEFAULT_SOURCES.find((source) => {
      const sourceHost = new URL(source.baseUrl).host.replace(/^www\./, "");
      return host === sourceHost;
    });
    return match?.id ?? null;
  } catch {
    return null;
  }
}

function isAllowedImageUrl(url) {
  try {
    const target = new URL(url);
    const sourceHosts = DEFAULT_SOURCES.flatMap((source) => {
      const host = new URL(source.baseUrl).host;
      const root = host.replace(/^www\./, "");
      return [host, root];
    });
    const allowedHosts = [...sourceHosts, ...EXTRA_IMAGE_HOSTS];
    if (allowedHosts.some((host) => target.host === host || target.host.endsWith(`.${host}`))) {
      return true;
    }

    return !isPrivateHost(target.host);
  } catch {
    return false;
  }
}

function isPrivateHost(host) {
  const lower = host.toLowerCase();
  if (lower === "localhost" || lower.endsWith(".localhost") || lower.endsWith(".local")) {
    return true;
  }

  if (isIpv4Address(lower)) {
    return isPrivateIpv4(lower);
  }

  if (lower.includes(":")) {
    return isPrivateIpv6(lower);
  }

  return false;
}

function isIpv4Address(host) {
  return /^(\d{1,3}\.){3}\d{1,3}$/.test(host);
}

function isPrivateIpv4(host) {
  const parts = host.split(".").map((part) => Number(part));
  if (parts.some((part) => Number.isNaN(part) || part < 0 || part > 255)) return true;

  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 0) return true;
  if (a === 169 && b === 254) return true;
  if (a === 192 && b === 168) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  return false;
}

function isPrivateIpv6(host) {
  const normalized = host.replace(/^\[|\]$/g, "").toLowerCase();
  if (normalized === "::1") return true;
  if (normalized.startsWith("fe80:")) return true;
  if (normalized.startsWith("fc") || normalized.startsWith("fd")) return true;
  return false;
}

function parseSrcset(value) {
  if (!value) return null;
  const candidates = value
    .split(",")
    .map((part) => part.trim().split(" ")[0])
    .filter(Boolean);
  if (candidates.length === 0) return null;
  return candidates[candidates.length - 1];
}

function parseBackgroundImage(value) {
  if (!value) return null;
  const match = value.match(/background-image\s*:\s*url\((['"]?)(.*?)\1\)/i);
  return match?.[2] ?? null;
}

function resolveImageFromAttributes($, element, baseUrl) {
  if (!element || element.length === 0) return null;

  const srcset =
    element.attr("data-srcset") ||
    element.attr("data-lazy-srcset") ||
    element.attr("data-bgset") ||
    element.attr("srcset");
  const direct =
    element.attr("data-src") ||
    element.attr("data-lazy-src") ||
    element.attr("data-src-large") ||
    element.attr("data-src-medium") ||
    element.attr("data-src-small") ||
    element.attr("data-thumb") ||
    element.attr("data-full-url") ||
    element.attr("data-lazy") ||
    element.attr("data-original") ||
    element.attr("data-original-src") ||
    element.attr("data-bg") ||
    element.attr("data-background") ||
    element.attr("data-bg-url") ||
    element.attr("data-image") ||
    element.attr("src") ||
    parseSrcset(srcset);

  if (direct) {
    const normalized = normalizeUrl(direct, baseUrl);
    if (normalized && normalized.startsWith("data:")) {
      return null;
    }
    return normalized;
  }

  const style = element.attr("style");
  const background = parseBackgroundImage(style);
  if (background) {
    const normalized = normalizeUrl(background, baseUrl);
    if (normalized && normalized.startsWith("data:")) {
      return null;
    }
    return normalized;
  }

  return null;
}

function isLikelyPlaceholderImage(url) {
  if (!url) return true;
  const lower = url.toLowerCase();
  if (lower.startsWith("data:")) return true;
  if (lower.endsWith(".svg")) return true;
  const tokens = [
    "placeholder",
    "default",
    "transparent",
    "spacer",
    "blank",
    "pixel",
    "sprite",
    "icon",
    "logo",
    "avatar",
    "profile",
  ];
  return tokens.some((token) => lower.includes(token));
}

function selectBestImage(...candidates) {
  for (const candidate of candidates) {
    if (!candidate) continue;
    if (isLikelyPlaceholderImage(candidate)) continue;
    return candidate;
  }
  return null;
}

function getRootDomain(host) {
  if (!host) return host;
  const clean = host.replace(/^\.+/, "").toLowerCase();
  const parts = clean.split(".").filter(Boolean);
  if (parts.length <= 2) return clean;
  return parts.slice(-2).join(".");
}

function normalizeReferer(value, imageUrl) {
  if (!value) return null;
  try {
    const ref = new URL(value);
    if (!["http:", "https:"].includes(ref.protocol)) return null;
    if (isPrivateHost(ref.host)) return null;
    if (imageUrl) {
      const img = new URL(imageUrl);
      const refRoot = getRootDomain(ref.host);
      const imgRoot = getRootDomain(img.host);
      if (refRoot === imgRoot) {
        return ref.origin;
      }
    }
    return ref.toString();
  } catch {
    return null;
  }
}

function resolveImageFromNoscript($, element, baseUrl) {
  const raw = element.find("noscript").html();
  if (!raw) return null;
  try {
    const $$ = load(raw);
    const img = $$("img").first();
    const imageUrl = resolveImageFromAttributes($$, img, baseUrl);
    return imageUrl;
  } catch {
    return null;
  }
}

function resolveImageFromSources($, element, baseUrl) {
  const sources = element.find("source");
  if (!sources.length) return null;

  for (const node of sources.toArray()) {
    const source = $(node);
    const srcset =
      source.attr("srcset") ||
      source.attr("data-srcset") ||
      source.attr("data-lazy-srcset") ||
      source.attr("data-glide-srcset");
    const direct =
      source.attr("src") ||
      source.attr("data-src") ||
      source.attr("data-lazy-src") ||
      source.attr("data-glide-src");
    const candidate = direct || parseSrcset(srcset);
    if (!candidate) continue;
    const normalized = normalizeUrl(candidate, baseUrl);
    if (normalized && normalized.startsWith("data:")) {
      continue;
    }
    return normalized;
  }

  return null;
}

function isSameHost(url, baseUrl) {
  try {
    const a = new URL(url);
    const b = new URL(baseUrl);
    if (a.host === b.host) return true;
    return getRootDomain(a.host) === getRootDomain(b.host);
  } catch {
    return false;
  }
}

function isLikelyArticleUrl(url, source) {
  if (!isSameHost(url, source.baseUrl)) return false;

  const path = new URL(url).pathname.toLowerCase();
  if (path === "/" || path.length < 2) return false;
  if (
    path.includes("/category/") ||
    path.includes("/tag/") ||
    path.includes("/author/") ||
    path.includes("/page/") ||
    path.includes("/feed/") ||
    path.includes("/privacy") ||
    path.includes("/terms") ||
    path.includes("/about") ||
    path.includes("/contact") ||
    path.includes("/wp-admin") ||
    path.includes("/wp-json") ||
    path.includes("/xmlrpc") ||
    path.includes("/wp-content") ||
    path.includes("/wp-includes") ||
    path.includes("/comment-page-")
  ) {
    return false;
  }

  if (/\.(jpg|jpeg|png|gif|webp|svg|mp4|mp3|pdf|zip)$/i.test(path)) {
    return false;
  }

  if (!looksLikeArticlePath(path)) {
    return false;
  }

  const patterns = (source.articleUrlPatterns || []).map((pattern) => new RegExp(pattern));
  if (patterns.length === 0) return true;
  return patterns.some((pattern) => pattern.test(path));
}

function looksLikeArticlePath(path) {
  if (!path) return false;
  const hasDate = /\/\d{4}\/\d{2}\/\d{2}\//.test(path);
  const hasLongId = /\d{5,}(?:\/|$)/.test(path);
  if (hasDate || hasLongId) return true;

  const trimmed = path.replace(/\/+$/, "");
  const segments = trimmed.split("/").filter(Boolean);
  if (segments.length <= 1) {
    const single = segments[0] || "";
    return looksLikeArticleSlug(single) && !isCategorySlug(single);
  }

  const last = segments[segments.length - 1] || "";
  if (isCategorySlug(last)) {
    return false;
  }

  if (segments.length <= 2) {
    return looksLikeArticleSlug(last);
  }

  return true;
}

function looksLikeArticleSlug(slug) {
  if (!slug) return false;
  if (slug.length >= 14 && slug.includes("-")) return true;
  if (/\d{5,}/.test(slug)) return true;
  return slug.length >= 20;
}

function isCategorySlug(slug) {
  const categories = new Set([
    "news",
    "world",
    "politics",
    "business",
    "sports",
    "sport",
    "entertainment",
    "life",
    "travel",
    "opinion",
    "tech",
    "money",
    "finance",
    "food",
    "health",
    "weather",
    "science",
    "shopping",
    "grocery",
    "games",
    "photos",
    "video",
    "videos",
  ]);
  return categories.has(slug);
}

function isCommentAnchor(title, href) {
  const text = title.toLowerCase();
  if (/(^|\b)\d+\s+comments?\b/.test(text)) return true;
  if (text.startsWith("comment") || text.includes("comments on")) return true;
  if (!href) return false;
  return /replytocom=|#comments?|comment-page-/i.test(href);
}

function extractPublishedAtFromUrl(url) {
  const match = url.match(/\/(\d{4})\/(\d{2})\/(\d{2})\//);
  if (!match) return null;
  const [_, year, month, day] = match;
  const date = new Date(`${year}-${month}-${day}T00:00:00Z`);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function parseDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function hashString(value) {
  let hash = 0;
  for (let i = 0; i < value.length; i += 1) {
    hash = (hash << 5) - hash + value.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash).toString(16);
}

async function fetchWithTimeout(url, headers, attempts = 3) {
  let lastError = null;

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        signal: controller.signal,
        headers: {
          "User-Agent": USER_AGENT,
          ...headers,
        },
      });

      if (response.ok) {
        return response;
      }

      const shouldRetryStatus = response.status === 408 || response.status === 429 || response.status >= 500;
      if (!shouldRetryStatus || attempt === attempts) {
        throw new Error(`Failed to fetch ${url}: ${response.status}`);
      }
      await sleep(250 * attempt);
      continue;
    } catch (error) {
      const isTimeout = error?.name === "AbortError";
      const message = isTimeout ? `Timed out fetching ${url}` : error?.message || "fetch failed";
      lastError = new Error(message);

      if (attempt === attempts) {
        break;
      }
      await sleep(250 * attempt);
    } finally {
      clearTimeout(timeout);
    }
  }

  throw lastError || new Error(`Failed to fetch ${url}`);
}

async function fetchHtml(url) {
  const response = await fetchWithTimeout(url, {
    Accept: "text/html,application/xhtml+xml",
  });
  return response.text();
}

async function fetchHtmlWithFallback(url) {
  try {
    return await fetchHtml(url);
  } catch (error) {
    const alternate = withHostSwap(url);
    if (!alternate || alternate === url) {
      throw error;
    }
    return fetchHtml(alternate);
  }
}

async function fetchJson(url) {
  const response = await fetchWithTimeout(url, {
    Accept: "application/json",
  });
  return response.json();
}

function stripHtml(value) {
  if (!value) return "";
  return String(value)
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

async function fetchWordPressPosts(baseUrl, source) {
  const attempt = async (apiUrl) => {
    const data = await fetchJson(apiUrl.toString());
    if (!Array.isArray(data)) return [];
    return data
      .map((post) => {
        const link = post?.link;
        const title = stripHtml(post?.title?.rendered || "");
        if (!link || !title) return null;
        const featured = post?._embedded?.["wp:featuredmedia"]?.[0];
        const imageUrl = featured?.source_url || null;
        const excerpt = stripHtml(post?.excerpt?.rendered || "");
        const publishedAt = parseDate(post?.date) || extractPublishedAtFromUrl(link);
        return {
          id: `${source.id}:${hashString(link)}`,
          title,
          url: link,
          publishedAt,
          imageUrl,
          excerpt: excerpt || null,
          preview: null,
          author: null,
          sourceId: source.id,
          sourceName: source.name,
        };
      })
      .filter(Boolean);
  };

  try {
    const apiUrl = new URL("/wp-json/wp/v2/posts", baseUrl);
    apiUrl.searchParams.set("per_page", String(MAX_ARTICLES_PER_SOURCE));
    apiUrl.searchParams.set("_embed", "1");
    return await attempt(apiUrl);
  } catch (error) {
    console.warn(`WordPress fallback failed for ${source.name || source.baseUrl}:`, error.message);
    try {
      const apiUrl = new URL("/?rest_route=/wp/v2/posts", baseUrl);
      apiUrl.searchParams.set("per_page", String(MAX_ARTICLES_PER_SOURCE));
      apiUrl.searchParams.set("_embed", "1");
      return await attempt(apiUrl);
    } catch (fallbackError) {
      console.warn(
        `WordPress alt fallback failed for ${source.name || source.baseUrl}:`,
        fallbackError.message,
      );
      return [];
    }
  }
}

function shouldTryWordPressFallback(source) {
  try {
    const host = new URL(source.baseUrl || source.listUrl).host.replace(/^www\./, "");
    const nonWordPressHosts = new Set([
      "bbc.com",
      "cnn.com",
      "edition.cnn.com",
      "guardian.co.tt",
      "jamaica-gleaner.com",
    ]);
    return !nonWordPressHosts.has(host);
  } catch {
    return true;
  }
}

function extractImageFromElement($, el, source) {
  const element = $(el);
  const imgElement = element.find("img").first();
  const img =
    resolveImageFromAttributes($, imgElement, source.baseUrl) ||
    resolveImageFromSources($, element, source.baseUrl) ||
    resolveImageFromAttributes($, element, source.baseUrl) ||
    resolveImageFromNoscript($, element, source.baseUrl);
  if (img) return img;

  const parent = element.closest(
    "article, li, .post, .entry, .story, .card, .promo, .teaser, .media, .td_module_10, .td_module_6, .td_module_4, .post-thumbnail, .featured-image",
  );
  const parentImgElement = parent.find("img").first();
  const parentImg =
    resolveImageFromAttributes($, parentImgElement, source.baseUrl) ||
    resolveImageFromSources($, parent, source.baseUrl) ||
    resolveImageFromAttributes($, parent, source.baseUrl) ||
    resolveImageFromNoscript($, parent, source.baseUrl);

  return parentImg;
}

function extractArticles(html, source) {
  const $ = load(html);
  const items = [];
  const seen = new Set();

  const candidates = collectCandidateLinks($);

  candidates.each((_, el) => {
    const href = $(el).attr("href");
    const absoluteUrl = normalizeArticleUrl(href, source.baseUrl);
    if (!absoluteUrl) return;
    if (!isLikelyArticleUrl(absoluteUrl, source)) return;

    const title = extractAnchorTitle($, el);
    if (title.length < 12) return;
    if (isCommentAnchor(title, href)) return;

    if (seen.has(absoluteUrl)) return;
    seen.add(absoluteUrl);

    items.push({
      id: `${source.id}:${hashString(absoluteUrl)}`,
      title,
      url: absoluteUrl,
      publishedAt: extractPublishedAtFromUrl(absoluteUrl),
      imageUrl: extractImageFromElement($, el, source),
      excerpt: null,
      preview: null,
      author: null,
      sourceId: source.id,
      sourceName: source.name,
    });
  });

  return items.slice(0, MAX_ARTICLES_PER_SOURCE);
}

function extractRssLinkFromHtml(html, baseUrl) {
  try {
    const $ = load(html);
    const link =
      $('link[rel="alternate"][type*="rss"]').first().attr("href") ||
      $('link[type*="rss"]').first().attr("href") ||
      $('link[rel="alternate"][type*="atom"]').first().attr("href") ||
      $('link[type*="atom"]').first().attr("href");
    return normalizeUrl(link, baseUrl);
  } catch {
    return null;
  }
}

function buildRssCandidates(source, html) {
  const candidates = new Set();
  const base = source.baseUrl || source.listUrl;
  if (html) {
    const discovered = extractRssLinkFromHtml(html, base);
    if (discovered) candidates.add(discovered);
  }
  if (base) {
    const baseUrl = new URL(base);
    const paths = [
      "/rss",
      "/rss.xml",
      "/feed",
      "/feed/",
      "/?feed=rss2",
      "/?feed=rss",
      "/?feed=atom",
    ];
    for (const path of paths) {
      candidates.add(new URL(path, baseUrl).toString());
    }
  }
  return Array.from(candidates);
}

function extractRssImage($item, baseUrl) {
  const mediaContent =
    $item.find("media\\:content").attr("url") ||
    $item.find("media\\:thumbnail").attr("url") ||
    $item.find("enclosure").attr("url") ||
    null;
  return normalizeUrl(mediaContent, baseUrl);
}

function extractRssLink($item) {
  const link =
    $item.find("link").first().attr("href") ||
    $item.find("link").first().text();
  return link ? link.trim() : null;
}

function extractRssDate($item) {
  const value =
    $item.find("pubDate").first().text() ||
    $item.find("updated").first().text() ||
    $item.find("published").first().text() ||
    $item.find("dc\\:date").first().text();
  return parseDate(value);
}

function extractRssExcerpt($item) {
  const description =
    $item.find("description").first().text() ||
    $item.find("summary").first().text() ||
    $item.find("content\\:encoded").first().text();
  return stripHtml(description);
}

async function fetchRssItems(feedUrl, source) {
  const response = await fetchWithTimeout(
    feedUrl,
    {
      Accept: "application/rss+xml,application/atom+xml,application/xml,text/xml",
    },
    2,
  );
  const xml = await response.text();
  const $ = load(xml, { xmlMode: true });
  const items = [];
  const entries = $("item");
  const nodes = entries.length ? entries : $("entry");

  nodes.each((_, el) => {
    const $item = $(el);
    const title = stripHtml($item.find("title").first().text());
    const link = extractRssLink($item);
    const absoluteUrl = normalizeArticleUrl(link, source.baseUrl || source.listUrl);
    if (!title || !absoluteUrl) return;
    if (!isLikelyArticleUrl(absoluteUrl, source)) return;

    items.push({
      id: `${source.id}:${hashString(absoluteUrl)}`,
      title,
      url: absoluteUrl,
      publishedAt: extractRssDate($item),
      imageUrl: extractRssImage($item, source.baseUrl),
      excerpt: extractRssExcerpt($item) || null,
      preview: null,
      author: null,
      sourceId: source.id,
      sourceName: source.name,
    });
  });

  return items.slice(0, MAX_ARTICLES_PER_SOURCE);
}

async function fetchRssFallback(source, html) {
  const candidates = buildRssCandidates(source, html);
  for (const candidate of candidates) {
    try {
      const items = await fetchRssItems(candidate, source);
      if (items.length > 0) return items;
    } catch {
      continue;
    }
  }
  return [];
}

function collectCandidateLinks($) {
  const selectors = [
    "article a[href]",
    ".entry-title a[href]",
    ".post-title a[href]",
    ".jeg_post_title a[href]",
    ".td-module-title a[href]",
    ".tdb-module-title a[href]",
    "a[rel=\"bookmark\"]",
    "h1 a[href]",
    "h2 a[href]",
    "h3 a[href]",
    "h4 a[href]",
  ];

  let combined = $();
  for (const selector of selectors) {
    const matches = $(selector);
    if (matches.length > 0) {
      combined = combined.add(matches);
    }
  }

  if (combined.length > 0) {
    return combined;
  }

  return $("a[href]");
}

function extractAnchorTitle($, el) {
  const element = $(el);
  const candidates = [];

  candidates.push(element.text());
  candidates.push(element.attr("aria-label"));
  candidates.push(element.attr("title"));

  const heading = element.closest("h1, h2, h3, h4, h5");
  if (heading.length) {
    candidates.push(heading.text());
  }

  const parentHeading = element.parents().find("h1, h2, h3, h4, h5").first();
  if (parentHeading.length) {
    candidates.push(parentHeading.text());
  }

  for (const candidate of candidates) {
    if (!candidate) continue;
    const text = String(candidate).replace(/\s+/g, " ").trim();
    if (text.length >= 8) {
      return text;
    }
  }

  return element.text().replace(/\s+/g, " ").trim();
}

function extractImageFromJsonLd($, baseUrl) {
  const scripts = $('script[type="application/ld+json"]');
  if (!scripts.length) return null;

  function resolveFromNode(node) {
    if (!node) return null;
    if (Array.isArray(node)) {
      for (const item of node) {
        const result = resolveFromNode(item);
        if (result) return result;
      }
      return null;
    }
    if (node["@graph"]) {
      return resolveFromNode(node["@graph"]);
    }
    const image = node.image || node.thumbnailUrl || node.logo;
    if (Array.isArray(image)) {
      for (const item of image) {
        const result = resolveFromNode(item);
        if (result) return result;
      }
      return null;
    }
    if (typeof image === "object") {
      return image.url || image["@id"] || null;
    }
    if (typeof image === "string") {
      return image;
    }
    if (typeof node === "object") {
      return node.url || null;
    }
    return null;
  }

  for (const el of scripts.toArray()) {
    const raw = $(el).contents().text();
    if (!raw) continue;
    try {
      const parsed = JSON.parse(raw);
      const found = resolveFromNode(parsed);
      if (found) return normalizeUrl(found, baseUrl);
    } catch {
      continue;
    }
  }

  return null;
}

function extractMeta(html, baseUrl, sourceId) {
  const $ = load(html);

  const content = (selector) => $(selector).attr("content")?.trim();
  const title =
    content('meta[property="og:title"]') ||
    content('meta[name="twitter:title"]') ||
    $("title").text().trim() ||
    null;

  const excerpt =
    content('meta[property="og:description"]') ||
    content('meta[name="description"]') ||
    content('meta[name="twitter:description"]') ||
    null;

  const authorCandidates = [
    content('meta[name="author"]'),
    content('meta[property="article:author"]'),
    $("a[rel=\"author\"]").first().text().trim(),
    $(".author a").first().text().trim(),
    $(".author").first().text().trim(),
    $(".byline").first().text().trim(),
    $(".td-post-author-name").first().text().trim(),
    parseByline($(".posted-on").first().text()),
    parseByline($(".entry-meta").first().text()),
  ];
  const author = selectAuthor(authorCandidates, sourceId);

  const jsonLdImage = extractImageFromJsonLd($, baseUrl);
  const imageUrl =
    normalizeUrl(content('meta[property="og:image"]'), baseUrl) ||
    normalizeUrl(content('meta[property="og:image:secure_url"]'), baseUrl) ||
    normalizeUrl(content('meta[property="og:image:url"]'), baseUrl) ||
    normalizeUrl(content('meta[name="twitter:image"]'), baseUrl) ||
    normalizeUrl(content('meta[name="twitter:image:src"]'), baseUrl) ||
    normalizeUrl(content('meta[itemprop="image"]'), baseUrl) ||
    normalizeUrl(content('meta[name="thumbnail"]'), baseUrl) ||
    normalizeUrl(content('meta[name="parsely-image-url"]'), baseUrl) ||
    jsonLdImage;

  const publishedRaw =
    content('meta[property="article:published_time"]') ||
    content('meta[property="article:modified_time"]') ||
    content('meta[name="pubdate"]') ||
    content('meta[name="publish-date"]') ||
    $("time[datetime]").attr("datetime") ||
    null;

  return {
    title,
    excerpt,
    imageUrl,
    author,
    publishedAt: parseDate(publishedRaw),
  };
}

function parseByline(value) {
  if (!value) return null;
  const normalized = value.replace(/\s+/g, " ").trim();
  const match = normalized.match(/\bby\s+(.+?)(?:\s+\b(updated|posted)\b|$)/i);
  return match ? match[1].trim() : null;
}

function normalizeAuthor(value) {
  if (!value) return null;
  let text = value.replace(/\s+/g, " ").trim();
  text = text.replace(/^by\s*:?\s*/i, "");
  text = text.replace(/^posted by\s*/i, "");
  text = text.replace(/^written by\s*/i, "");
  text = text.replace(/^by\s+by\s+/i, "");
  text = text.replace(/\s*(,|\||-|\u2014)\s*updated.*$/i, "");
  text = text.replace(/\s*(,|\||-|\u2014)\s*posted.*$/i, "");
  text = text.replace(/\s*[|•]\s*.*$/, "");
  text = text.replace(/\.$/, "");
  text = text.trim();
  return text.length > 0 ? text : null;
}

function shouldIgnoreAuthor(value, sourceId) {
  if (!value) return true;
  const lower = value.toLowerCase();
  if (lower.includes("http://") || lower.includes("https://")) return true;
  if (lower.includes("facebook.com") || lower.includes("twitter.com")) return true;
  if (lower.startsWith("www.")) return true;
  const ignore = AUTHOR_IGNORE_BY_SOURCE[sourceId] || [];
  if (ignore.some((token) => lower === token || lower.includes(token))) return true;
  if (lower === "admin" || lower === "administrator") return true;
  if (lower.length < 2) return true;
  return false;
}

function selectAuthor(candidates, sourceId) {
  const cleaned = [];
  const seen = new Set();

  for (const candidate of candidates) {
    if (!candidate) continue;
    const parts = String(candidate).split(/\bupdated\b|\blast updated\b|\bposted\b/i);
    for (const part of parts) {
      const normalized = normalizeAuthor(part);
      if (!normalized) continue;
      if (shouldIgnoreAuthor(normalized, sourceId)) continue;
      const key = normalized.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      cleaned.push(normalized);
    }
  }

  return cleaned[0] ?? null;
}

function extractArticleBody(html, baseUrl) {
  const $ = load(html);
  const selectors = [
    ".td-post-content",
    ".entry-content",
    ".post-content",
    ".tdb-block-inner",
    ".article-content",
    "article",
    ".post",
  ];

  const candidates = [];
  for (const selector of selectors) {
    $(selector).each((_, el) => {
      const container = $(el);
      const paragraphs = collectParagraphs($, container);
      if (paragraphs.length === 0) return;
      const score = paragraphs.join(" ").length;
      candidates.push({ container, paragraphs, score });
    });
  }

  let chosen = candidates.sort((a, b) => b.score - a.score)[0];
  if (!chosen) {
    const container = $("body");
    chosen = {
      container,
      paragraphs: collectParagraphs($, container),
      score: 0,
    };
  }

  const imageUrl = extractImageFromContainer($, chosen.container, baseUrl);

  return {
    paragraphs: chosen.paragraphs,
    imageUrl,
  };
}

function collectParagraphs($, container) {
  const paragraphs = [];
  const seen = new Set();

  container.find("p").each((_, el) => {
    if (paragraphs.length >= MAX_PARAGRAPHS) return;
    if (shouldSkipParagraph($, el)) return;
    const text = $(el).text().replace(/\s+/g, " ").trim();
    if (text.length < 20) return;
    if (seen.has(text)) return;
    seen.add(text);
    paragraphs.push(text);
  });

  return paragraphs;
}

function shouldSkipParagraph($, el) {
  const text = $(el).text().replace(/\s+/g, " ").trim();
  const lower = text.toLowerCase();

  const noisePhrases = [
    "leave a comment",
    "share this",
    "like loading",
    "post navigation",
    "published by",
    "posted on",
    "this image was obtained",
    "photo:",
    "image:",
    "credit:",
  ];

  if (noisePhrases.some((phrase) => lower.startsWith(phrase))) return true;
  if (lower.includes("leave a comment") || lower.includes("share this:")) return true;
  if (lower.startsWith("by ") || lower.startsWith("by:")) {
    if (text.length < 120) return true;
  }
  if (lower.startsWith("updated") || lower.startsWith("last updated")) return true;
  if (lower.includes("updated") && text.length < 160) return true;
  if (lower.includes("facebook.com") || lower.includes("twitter.com")) return true;

  const className = ($(el).attr("class") || "").toLowerCase();
  if (
    className.includes("caption") ||
    className.includes("credit") ||
    className.includes("sharedaddy") ||
    className.includes("comment") ||
    className.includes("navigation") ||
    className.includes("related") ||
    className.includes("author")
  ) {
    return true;
  }

  if (
    $(el).closest(
      "figure, figcaption, .sharedaddy, .jp-relatedposts, .comments-area, .comment-list, .post-navigation, .nav-links, footer, .author-bio, .author, .byline",
    ).length
  ) {
    return true;
  }

  return false;
}

function extractImageFromContainer($, container, baseUrl) {
  const imgElement = container.find("img").first();
  const imageUrl =
    resolveImageFromAttributes($, imgElement, baseUrl) ||
    resolveImageFromSources($, container, baseUrl) ||
    resolveImageFromAttributes($, container, baseUrl) ||
    resolveImageFromNoscript($, container, baseUrl);

  return imageUrl;
}

async function enrichArticle(article, source) {
  try {
    const cached = getCache(articleCache, article.url, ARTICLE_CACHE_TTL_MS);
    if (cached) {
      return { ...article, ...cached };
    }

    const html = await fetchHtml(article.url);
    const meta = extractMeta(html, source.baseUrl, source.id);
    const body = extractArticleBody(html, source.baseUrl);
    const fallbackExcerpt = body.paragraphs?.[0];
    const preview = buildPreview(body.paragraphs);
    const chosenTitle =
      meta.title && meta.title.length > article.title.length ? meta.title : article.title;
    const primaryImage = selectBestImage(meta.imageUrl, article.imageUrl, body.imageUrl);
    const fallbackImage =
      primaryImage == null ? await resolveFallbackImage(chosenTitle, source.name) : null;

    const enriched = {
      title: chosenTitle,
      author: article.author || meta.author,
      excerpt: article.excerpt || meta.excerpt || fallbackExcerpt,
      preview: article.preview || preview,
      imageUrl: primaryImage || fallbackImage,
      publishedAt: article.publishedAt || meta.publishedAt,
    };

    setCache(articleCache, article.url, enriched);
    return {
      ...article,
      ...enriched,
    };
  } catch {
    const existing = selectBestImage(article.imageUrl);
    if (existing) {
      return article;
    }
    const fallbackImage = await resolveFallbackImage(article.title, source.name);
    if (!fallbackImage) {
      return article;
    }
    return {
      ...article,
      imageUrl: fallbackImage,
    };
  }
}

async function fetchArticleDetail(url) {
  const cached = getCache(detailCache, url, DETAIL_CACHE_TTL_MS);
  if (cached) return cached;

  const baseUrl = new URL(url).origin;
  const html = await fetchHtml(url);
  const sourceId = resolveSourceIdFromUrl(url);
  const sourceName =
    DEFAULT_SOURCES.find((source) => source.id === sourceId)?.name ||
    new URL(url).host.replace(/^www\./, "");
  const meta = extractMeta(html, baseUrl, sourceId);
  const body = extractArticleBody(html, baseUrl);
  const primaryImage = selectBestImage(meta.imageUrl, body.imageUrl);
  const fallbackImage =
    primaryImage == null ? await resolveFallbackImage(meta.title || "news", sourceName) : null;

  const detail = {
    url,
    title: meta.title,
    author: meta.author,
    excerpt: meta.excerpt || body.paragraphs?.[0],
    imageUrl: primaryImage || fallbackImage,
    publishedAt: meta.publishedAt,
    content: body.paragraphs,
  };

  setCache(detailCache, url, detail);
  return detail;
}

function buildPreview(paragraphs, maxChars = 420) {
  if (!Array.isArray(paragraphs) || paragraphs.length === 0) return null;
  let preview = "";
  for (const paragraph of paragraphs) {
    if (!paragraph) continue;
    const next = preview ? `${preview}\n\n${paragraph}` : paragraph;
    if (next.length > maxChars && preview.length > 0) break;
    preview = next;
  }
  return preview;
}

async function asyncPool(limit, array, iteratorFn) {
  const ret = [];
  const executing = [];

  for (const item of array) {
    const p = Promise.resolve().then(() => iteratorFn(item));
    ret.push(p);

    if (limit <= array.length) {
      let e;
      e = p.then(() => executing.splice(executing.indexOf(e), 1));
      executing.push(e);
      if (executing.length >= limit) {
        await Promise.race(executing);
      }
    }
  }

  return Promise.all(ret);
}

async function scrapeSource(source) {
  const cacheKey = `${source.listUrl}|${JSON.stringify(source.articleUrlPatterns || [])}`;
  const cached = getCache(listCache, cacheKey, LIST_CACHE_TTL_MS);
  if (cached) return cached;

  let items = [];
  let listHtml = null;
  try {
    listHtml = await fetchHtmlWithFallback(source.listUrl);
    items = extractArticles(listHtml, source);
  } catch (error) {
    console.warn(`List fetch failed for ${source.name || source.listUrl}:`, error.message);
  }
  if (items.length === 0) {
    const rssItems = await fetchRssFallback(source, listHtml);
    if (rssItems.length > 0) {
      items = rssItems;
    }
  }
  if (items.length === 0 && shouldTryWordPressFallback(source)) {
    const wpItems = await fetchWordPressPosts(source.baseUrl, source);
    if (wpItems.length > 0) {
      items = wpItems;
    }
  }
  const enriched = await asyncPool(ENRICH_CONCURRENCY, items, (item) => enrichArticle(item, source));

  const result = {
    sourceId: source.id,
    sourceName: source.name,
    items: enriched,
  };

  setCache(listCache, cacheKey, result);
  return result;
}

async function safeScrapeSource(source) {
  try {
    return await scrapeSource(source);
  } catch (error) {
    console.warn(`Failed to scrape ${source.name || source.listUrl}:`, error.message);
    return {
      sourceId: source.id,
      sourceName: source.name,
      items: [],
      error: error.message,
    };
  }
}

async function safeScrapeSourceWithTimeout(source) {
  return withTimeout(
    safeScrapeSource(source),
    SOURCE_TIMEOUT_MS,
    () => ({
      sourceId: source.id,
      sourceName: source.name,
      items: [],
      error: "timeout",
    }),
  );
}

function buildResponse(results, timedOut = false) {
  const items = results.flatMap((result) => result.items || []);
  return {
    items,
    sources: results.map(({ sourceId, sourceName }) => ({ sourceId, sourceName })),
    partial: timedOut,
  };
}

function maybeRefreshInBackground(sources) {
  if (backgroundRefreshInFlight) return;
  if (Date.now() - lastBackgroundRefresh < LIST_CACHE_TTL_MS / 2) return;
  backgroundRefreshInFlight = true;
  asyncPool(SOURCE_CONCURRENCY, sources, (source) => safeScrapeSource(source))
    .catch(() => {})
    .finally(() => {
      backgroundRefreshInFlight = false;
      lastBackgroundRefresh = Date.now();
    });
}

function resolveSources(inputSources) {
  if (!Array.isArray(inputSources) || inputSources.length === 0) {
    return DEFAULT_SOURCES;
  }

  return inputSources.map((source, index) => {
    const id = source.id || `custom-${index + 1}`;
    const name = source.name || source.listUrl || `Custom Source ${index + 1}`;
    const listUrl = source.listUrl || source.url;
    const baseUrl = source.baseUrl || listUrl;
    return {
      id,
      name,
      listUrl,
      baseUrl,
      articleUrlPatterns: source.articleUrlPatterns || [],
      refreshIntervalMinutes: Number.isFinite(source.refreshIntervalMinutes)
        ? source.refreshIntervalMinutes
        : undefined,
    };
  });
}

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, timestamp: new Date().toISOString() });
});

app.get("/api/sources", (_req, res) => {
  res.json(DEFAULT_SOURCES);
});

app.get("/api/image", async (req, res) => {
  const url = req.query.url;
  const referer = req.query.referer;
  if (!url || typeof url !== "string") {
    res.status(400).json({ error: "Missing image url" });
    return;
  }

  if (!isAllowedImageUrl(url)) {
    res.status(403).json({ error: "Image host not allowed" });
    return;
  }

  try {
    const imageUrl = new URL(url);
    const safeReferer =
      typeof referer === "string" ? normalizeReferer(referer, imageUrl.toString()) : null;

    const attemptFetch = async (headers) =>
      fetch(imageUrl.toString(), {
        headers,
        redirect: "follow",
      });

    const baseHeaders = {
      "User-Agent": USER_AGENT,
      Accept: "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
      "Sec-Fetch-Dest": "image",
      "Sec-Fetch-Mode": "no-cors",
    };

    const initialReferer = safeReferer || imageUrl.origin;
    const initialOrigin = initialReferer ? new URL(initialReferer).origin : imageUrl.origin;
    const initialHost = initialReferer ? new URL(initialReferer).host : imageUrl.host;
    const sameSite =
      initialReferer && getRootDomain(initialHost) === getRootDomain(imageUrl.host)
        ? "same-site"
        : "cross-site";

    let response = await attemptFetch({
      ...baseHeaders,
      "Sec-Fetch-Site": sameSite,
      Referer: initialReferer,
      Origin: initialOrigin,
    });

    if (!response.ok) {
      const fallbackReferer = imageUrl.origin;
      response = await attemptFetch({
        ...baseHeaders,
        "Sec-Fetch-Site": "same-origin",
        Referer: fallbackReferer,
        Origin: fallbackReferer,
      });
    }

    if (!response.ok) {
      response = await attemptFetch(baseHeaders);
    }

    if (!response.ok && imageUrl.search) {
      const strippedUrl = new URL(imageUrl.toString());
      strippedUrl.search = "";
      response = await fetch(strippedUrl.toString(), {
        headers: baseHeaders,
        redirect: "follow",
      });
    }

    if (!response.ok) {
      res.status(502).json({ error: `Image fetch failed (${response.status})` });
      return;
    }

    const contentType = response.headers.get("content-type") || "image/jpeg";
    if (!contentType.toLowerCase().startsWith("image/")) {
      res.status(502).json({ error: "Image fetch failed (non-image response)" });
      return;
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    res.setHeader("Content-Type", contentType);
    res.setHeader("Cache-Control", "public, max-age=86400");
    res.send(buffer);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/news", async (req, res) => {
  const ids = String(req.query.sources || "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean);

  const items = await getArticlesFromDb(ids);
  const latest = await getLatestTimestamp(ids);
  res.json({
    items,
    sources: ids.map((id) => ({ sourceId: id, sourceName: id })),
    latest,
  });
});

app.post("/api/news", async (req, res) => {
  const sources = resolveSources(req.body?.sources);
  await registerSources(sources);
  const ids = sources.map((source) => source.id);
  const items = await getArticlesFromDb(ids);
  const latest = await getLatestTimestamp(ids);
  res.json({
    items,
    sources: sources.map(({ id, name }) => ({ sourceId: id, sourceName: name })),
    latest,
  });
});

app.post("/api/sources/register", async (req, res) => {
  const sources = resolveSources(req.body?.sources);
  await registerSources(sources);
  res.json({ ok: true });
});

app.get("/api/status", async (req, res) => {
  const ids = String(req.query.sources || "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean);
  const latest = await getLatestTimestamp(ids);
  const row = db
    ? await db.get(
        "SELECT MAX(lastFetchedAt) AS lastRefresh FROM sources;",
      )
    : null;
  res.json({ latest, lastRefresh: row?.lastRefresh ?? null });
});

app.post("/api/article", async (req, res) => {
  const url = req.body?.url;
  if (!url || typeof url !== "string") {
    res.status(400).json({ error: "Missing article url" });
    return;
  }

  try {
    const detail = await fetchArticleDetail(url);
    res.json({ article: detail });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 4000;

async function startServer() {
  await initDb();
  await registerSources(DEFAULT_SOURCES);

  app.listen(PORT, () => {
    console.log(`News proxy listening on http://localhost:${PORT}`);
  });

  refreshAllSources().catch((error) => {
    console.warn("Initial refresh failed:", error.message);
  });
  setInterval(() => {
    refreshAllSources().catch((error) => {
      console.warn("Scheduled refresh failed:", error.message);
    });
  }, REFRESH_INTERVAL_MS);
}

startServer().catch((error) => {
  console.error("Failed to start server:", error.message);
  process.exit(1);
});
