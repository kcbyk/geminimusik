import express from 'express';

const app = express();
const port = process.env.PORT || 3000;
const https = (value) => typeof value === 'string' && value.startsWith('https://') ? value : '';
const normalized = (item, provider) => provider === 'pexels' ? {
  title: item.alt || 'Pexels fotoğrafı', thumbnail_url: item.src?.medium, image_url: item.src?.large2x || item.src?.original,
  source_url: item.url, source_name: 'Pexels', photographer: item.photographer, width: item.width, height: item.height,
} : {
  title: item.title || item.description || 'Görsel', thumbnail_url: item.thumbnail?.src, image_url: item.properties?.url || item.thumbnail?.src,
  source_url: item.url, source_name: item.source || new URL(item.url).hostname, width: item.properties?.width, height: item.properties?.height,
};

app.get('/api/image-search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const count = Math.max(1, Math.min(Number(req.query.count) || 10, 12));
  const page = Math.max(1, Number(req.query.page) || 1);
  if (!q || q.length > 180) return res.status(400).json({error: 'Geçerli bir arama sorgusu gerekli.'});
  try {
    let images;
    if (process.env.BRAVE_SEARCH_API_KEY) {
      const response = await fetch(`https://api.search.brave.com/res/v1/images/search?${new URLSearchParams({q, count: String(count), safesearch: 'strict'})}`, {headers: {'X-Subscription-Token': process.env.BRAVE_SEARCH_API_KEY}});
      if (!response.ok) throw new Error(`Brave ${response.status}`);
      images = (await response.json()).results.map(item => normalized(item, 'brave'));
    } else if (process.env.PEXELS_API_KEY) {
      const response = await fetch(`https://api.pexels.com/v1/search?${new URLSearchParams({query: q, page: String(page), per_page: String(count), locale: 'tr-TR'})}`, {headers: {Authorization: process.env.PEXELS_API_KEY}});
      if (!response.ok) throw new Error(`Pexels ${response.status}`);
      images = (await response.json()).photos.map(item => normalized(item, 'pexels'));
    } else return res.status(503).json({error: 'Görsel arama sağlayıcısı yapılandırılmamış.'});
    res.json({images: images.filter(item => https(item.thumbnail_url) && https(item.image_url) && https(item.source_url))});
  } catch (error) { res.status(502).json({error: 'Görsel araması tamamlanamadı.'}); }
});
app.listen(port, () => console.log(`Image search proxy listening on ${port}`));
