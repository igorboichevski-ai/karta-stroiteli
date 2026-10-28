// Офлайн-оболочка приложения и просмотренные куски схемы OSM.
// Данные (Supabase) сюда не попадают: их хранит сама страница. Спутниковые слои не кешируем (условия Esri и Mapbox).
const CACHE='ks-v1',TILES='ks-tiles',MAX_TILES=3000;
const SHELL=['./','index.html','config.js','manifest.webmanifest','icons/icon-192.png','icons/favicon.png'];
const CDN=['unpkg.com','cdn.jsdelivr.net','fonts.googleapis.com','fonts.gstatic.com'];

self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()));});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('ks-')&&k!==CACHE&&k!==TILES).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});

// запрос с CORS, чтобы в кеше лежал обычный ответ, а не «непрозрачный» (тот занимает в квоте по 7 МБ)
const corsFetch=r=>fetch(r.url,{mode:'cors',credentials:'omit'}).catch(()=>fetch(r));
let puts=0;
async function trimTiles(){const c=await caches.open(TILES),ks=await c.keys();for(const k of ks.slice(0,Math.max(0,ks.length-MAX_TILES)))await c.delete(k);}

self.addEventListener('fetch',e=>{
  const r=e.request;if(r.method!=='GET')return;
  const u=new URL(r.url);
  // свои файлы: сначала сеть (чтобы обновления приходили сразу), без сети — из кеша
  if(u.origin===location.origin){
    e.respondWith(fetch(r).then(res=>{if(res.ok){const cp=res.clone();caches.open(CACHE).then(c=>c.put(r,cp));}return res;})
      .catch(()=>caches.match(r,{ignoreSearch:true}).then(m=>m||caches.match('index.html'))));
    return;
  }
  // библиотеки и шрифты с версиями: из кеша, если уже скачаны
  if(CDN.includes(u.hostname)){
    e.respondWith(caches.match(r.url).then(m=>m||corsFetch(r).then(res=>{if(res.ok){const cp=res.clone();caches.open(CACHE).then(c=>c.put(r.url,cp));}return res;})));
    return;
  }
  // схема OSM: из сети, а куски, которые уже смотрели, остаются на случай, когда связи нет
  if(u.hostname==='tile.openstreetmap.org'){
    e.respondWith(corsFetch(r).then(res=>{if(res.ok){const cp=res.clone();caches.open(TILES).then(c=>c.put(r.url,cp)).then(()=>{if(++puts%100===0)trimTiles();});}return res;})
      .catch(()=>caches.match(r.url,{cacheName:TILES}).then(m=>m||Response.error())));
  }
});
