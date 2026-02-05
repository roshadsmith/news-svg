import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import express from "express";
import cors from "cors";
import { load } from "cheerio";

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
const SOURCE_CONCURRENCY = 3;
const FETCH_TIMEOUT_MS = 18000;
const SOURCE_TIMEOUT_MS = 22000;
const LIST_CACHE_TTL_MS = 60 * 1000;
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

async function withTimeout(promise, ms, onTimeout) {
  let timeoutId;
  const timeout = new Promise((resolve) => {
    timeoutId = setTimeout(() => resolve(onTimeout?.()), ms);
  });
  const result = await Promise.race([promise, timeout]);
  clearTimeout(timeoutId);
  return result;
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
  try {
    const html = await fetchHtmlWithFallback(source.listUrl);
    items = extractArticles(html, source);
  } catch (error) {
    console.warn(`List fetch failed for ${source.name || source.listUrl}:`, error.message);
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

  const sources = ids.length
    ? DEFAULT_SOURCES.filter((source) => ids.includes(source.id))
    : DEFAULT_SOURCES;

  const results = await asyncPool(SOURCE_CONCURRENCY, sources, (source) =>
    safeScrapeSourceWithTimeout(source),
  );
  const items = results.flatMap((result) => result.items || []);
  res.json({
    items,
    sources: results.map(({ sourceId, sourceName }) => ({ sourceId, sourceName })),
  });
});

app.post("/api/news", async (req, res) => {
  const sources = resolveSources(req.body?.sources);

  const results = await asyncPool(SOURCE_CONCURRENCY, sources, (source) =>
    safeScrapeSourceWithTimeout(source),
  );
  const items = results.flatMap((result) => result.items || []);
  res.json({
    items,
    sources: results.map(({ sourceId, sourceName }) => ({ sourceId, sourceName })),
  });
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
app.listen(PORT, () => {
  console.log(`News proxy listening on http://localhost:${PORT}`);
});
