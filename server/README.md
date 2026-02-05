# News Proxy

Lightweight Express + Cheerio proxy to scrape known sources and avoid CORS issues for Flutter web.

## Setup

```bash
cd server
npm install
npm run dev
```

## Endpoints

- `GET /api/health` - health check
- `GET /api/sources` - default sources
- `GET /api/news` - scrape default sources (includes `imageUrl`, `excerpt`, `author`, `preview` when available)
- `GET /api/news?sources=iwnsvg,onenews` - scrape selected defaults
- `POST /api/news` - scrape custom sources (includes `imageUrl`, `excerpt`, `author`, `preview` when available)
- `POST /api/article` - fetch a single article with `content` paragraphs + image
- `GET /api/image?url=` - proxy images from allowed hosts to avoid hotlinking blocks

### POST /api/news body example

```json
{
  "sources": [
    {
      "name": "Custom Site",
      "listUrl": "https://example.com/",
      "baseUrl": "https://example.com"
    }
  ]
}
```

### POST /api/article body example

```json
{
  "url": "https://www.iwnsvg.com/2026/02/03/example-article/"
}
```
