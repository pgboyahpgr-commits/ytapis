import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:ytapis/ytapis.dart';

const String indexHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>ytapis Search</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}
body{background:#0e0e0e;color:#f1f1f1;min-height:100vh}
#search-view{max-width:1400px;margin:0 auto;padding:2rem 1.5rem}
.header{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:1rem;margin-bottom:.25rem}
.header h1{font-size:2.2rem;font-weight:700;background:linear-gradient(135deg,#f9d423,#ff4e50);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.header .badge{background:#1e1e1e;padding:.3rem 1rem;border-radius:20px;font-size:.7rem;font-weight:600;color:#aaa;border:1px solid #333;text-transform:uppercase}
.subtitle{color:#888;margin-bottom:2rem;display:flex;flex-wrap:wrap;align-items:center;gap:.8rem;font-size:.95rem}
.subtitle .dot{display:inline-block;width:10px;height:10px;background:#4ade80;border-radius:50%;animation:pulse 1.5s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.2}}
.search-wrapper{display:flex;gap:.8rem;margin-bottom:2rem;flex-wrap:wrap}
.search-wrapper input{flex:1;min-width:220px;padding:.9rem 1.2rem;background:#181818;border:1px solid #303030;border-radius:12px;color:#fff;font-size:1rem;outline:none;transition:border-color .25s,box-shadow .25s}
.search-wrapper input:focus{border-color:#3ea6ff;box-shadow:0 0 0 3px rgba(62,166,255,.15)}
.search-wrapper input::placeholder{color:#666}
.search-wrapper button{padding:.9rem 2.5rem;background:#3ea6ff;color:#0f0f0f;border:none;border-radius:12px;font-weight:700;font-size:1rem;cursor:pointer;transition:background .2s,transform .1s;white-space:nowrap}
.search-wrapper button:hover{background:#65b8ff}
.search-wrapper button:active{transform:scale(.96)}
.search-wrapper button:disabled{opacity:.5;cursor:not-allowed;transform:none}
.stats{padding:.7rem 1rem;background:#151515;border-radius:10px;border:1px solid #222;margin-bottom:2rem;color:#aaa;font-size:.95rem;display:flex;justify-content:space-between;flex-wrap:wrap;gap:.5rem;min-height:50px;align-items:center}
.stats .highlight{color:#3ea6ff;font-weight:600}
.video-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:1.8rem}
.video-card{background:#161616;border-radius:14px;overflow:hidden;border:1px solid #262626;cursor:pointer;transition:transform .2s,border-color .2s,box-shadow .3s}
.video-card:hover{transform:translateY(-6px);border-color:#3a3a3a;box-shadow:0 12px 30px rgba(0,0,0,.7)}
.video-card .thumbnail{position:relative;aspect-ratio:16/9;background:#0a0a0a;overflow:hidden}
.video-card .thumbnail img{width:100%;height:100%;object-fit:cover;transition:filter .3s}
.video-card:hover .thumbnail img{filter:brightness(.7)}
.video-card .play-overlay{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:60px;height:60px;background:rgba(255,255,255,.92);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:1.8rem;color:#0f0f0f;transition:transform .2s,background .2s;box-shadow:0 4px 20px rgba(0,0,0,.6);pointer-events:none}
.video-card:hover .play-overlay{background:#fff;transform:translate(-50%,-50%) scale(1.1)}
.video-card .play-overlay::after{content:"\25B6";margin-left:3px}
.video-card .info{padding:.8rem 1rem 1rem 1rem}
.video-card .info h3{font-size:.95rem;font-weight:600;color:#f1f1f1;margin-bottom:.2rem;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;line-height:1.4}
.video-card .info .author{color:#888;font-size:.8rem}
.state-message{grid-column:1/-1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:4rem 1.5rem;text-align:center;color:#666;gap:.75rem}
.state-message .spinner{width:50px;height:50px;border:4px solid #222;border-top:4px solid #3ea6ff;border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{100%{transform:rotate(360deg)}}
.state-message .icon{font-size:3rem}
.state-message .title{font-size:1.2rem;color:#aaa}
.state-message .desc{font-size:.9rem;color:#555}
.error-msg{color:#f87171;grid-column:1/-1;text-align:center;padding:2rem;background:#1f1212;border-radius:12px;border:1px solid #3b1e1e}
#watch-view{display:none;min-height:100vh;background:#0e0e0e}
#watch-view .watch-nav{display:flex;align-items:center;gap:1.2rem;padding:.8rem 2rem;background:#181818;border-bottom:1px solid #2a2a2a;position:sticky;top:0;z-index:10}
#watch-view .watch-nav a{color:#fff;text-decoration:none;font-size:1.4rem;font-weight:300;display:flex;align-items:center;gap:.5rem;transition:color .2s;padding:.3rem .6rem;border-radius:8px}
#watch-view .watch-nav a:hover{color:#3ea6ff;background:#252525}
#watch-view .watch-nav .brand{font-size:1.1rem;font-weight:600;color:#aaa;letter-spacing:.5px}
#watch-view .watch-nav .brand span{background:linear-gradient(135deg,#f9d423,#ff4e50);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.watch-container{max-width:1100px;margin:0 auto;padding:2rem 1.5rem 4rem 1.5rem}
.watch-container .player-wrapper{position:relative;aspect-ratio:16/9;background:#000;border-radius:16px;overflow:hidden;box-shadow:0 8px 40px rgba(0,0,0,.8);margin-bottom:1.5rem}
.watch-container .player-wrapper iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:none}
.watch-container .watch-title{font-size:1.5rem;font-weight:600;margin-bottom:.2rem;line-height:1.3}
.watch-container .watch-author{color:#888;font-size:1rem;margin-bottom:.5rem}
.watch-container .watch-meta{display:flex;gap:1.5rem;flex-wrap:wrap;border-top:1px solid #262626;padding-top:1rem;margin-top:.5rem}
.watch-container .watch-meta a{color:#3ea6ff;text-decoration:none;font-size:.9rem}
.watch-container .watch-meta a:hover{text-decoration:underline}
.watch-container .watch-meta .id-badge{color:#666;font-family:monospace;font-size:.8rem;background:#1a1a1a;padding:.15rem .8rem;border-radius:4px}
.grid-label{display:flex;justify-content:space-between;align-items:center;margin-bottom:1rem}
.grid-label .badge{display:inline-block;background:#1e1e1e;padding:.2rem 1rem;border-radius:20px;font-size:.8rem;font-weight:600;color:#f9d423;border:1px solid #333}
.grid-label .count{color:#555;font-size:.8rem}
.footer{text-align:center;padding:2rem 0 1rem 0;color:#555;border-top:1px solid #222;margin-top:2rem;font-size:.9rem}
.footer a{color:#3ea6ff;text-decoration:none}
.footer a:hover{text-decoration:underline}
@media(max-width:700px){#search-view{padding:1rem}.header h1{font-size:1.6rem}.search-wrapper button{width:100%}.video-grid{grid-template-columns:1fr 1fr;gap:1rem}.watch-container{padding:1rem}.watch-container .watch-title{font-size:1.2rem}#watch-view .watch-nav{padding:.6rem 1rem}}
@media(max-width:450px){.video-grid{grid-template-columns:1fr}}
</style>
</head>
<body>
<div id="search-view">
<div class="header"><h1>ytapis Search</h1><span class="badge">Click to watch</span></div>
<div class="subtitle"><span class="dot"></span> Powered by <strong>ytapis</strong></div>
<div class="search-wrapper">
<input type="text" id="searchInput" placeholder="Search for songs, artists, videos..." />
<button id="searchBtn">Search</button></div>
<div class="stats" id="statsBar"><span id="statusInfo">Enter a query to search YouTube</span></div>
<div class="grid-label"><span class="badge" id="gridBadge">Results</span><span class="count" id="resultCount"></span></div>
<div class="video-grid" id="videoGrid"><div class="state-message"><div class="icon">&#128269;</div><div class="title">Search YouTube</div><div class="desc">Type a query above and click Search.</div></div></div></div>
<div id="watch-view">
<div class="watch-nav"><a href="#" id="backBtn">&larr; <span style="font-size:.9rem;font-weight:400;">Back</span></a><div class="brand">&#9654; <span>Video</span> Player</div></div>
<div class="watch-container">
<div class="player-wrapper" id="playerWrapper"></div>
<h2 class="watch-title" id="watchTitle">Loading video...</h2>
<p class="watch-author" id="watchAuthor">&mdash;</p>
<div class="watch-meta">
<a href="#" id="watchYoutubeLink" target="_blank">Watch on YouTube</a>
<span class="id-badge" id="watchIdBadge">&mdash;</span></div></div></div>
<script>
(function(){var a=document.getElementById("search-view"),b=document.getElementById("watch-view"),c=document.getElementById("searchInput"),d=document.getElementById("searchBtn"),e=document.getElementById("videoGrid"),f=document.getElementById("statusInfo"),g=document.getElementById("backBtn"),h=document.getElementById("playerWrapper"),i=document.getElementById("watchTitle"),j=document.getElementById("watchAuthor"),k=document.getElementById("watchYoutubeLink"),l=document.getElementById("watchIdBadge"),m=document.getElementById("gridBadge"),n=document.getElementById("resultCount"),o=[],p=null,q=null;function r(t){return t?document.createElement("div").textContent=t,document.createElement("div").innerHTML:""}async function s(t){var u=t.trim();if(!u)return;e.innerHTML='<div class="state-message"><div class="spinner"></div><div class="title">Searching...</div></div>',f.innerHTML='Searching for "'+r(u)+'"...',d.disabled=0;try{var v=await fetch("/search?q="+encodeURIComponent(u)+"&limit=15");if(!v.ok)throw new Error("Server returned "+v.status);var w=await v.json();if(!w||!w.length){e.innerHTML='<div class="state-message"><div class="icon">&#128533;</div><div class="title">No results</div><div class="desc">Try a different search term.</div></div>',f.innerHTML="No results found.",m.textContent="Results",n.textContent="";return}o=w,x(w),m.textContent="Search Results",n.textContent=w.length+" videos",f.innerHTML='Found <strong class="highlight">'+w.length+'</strong> videos.'}catch(v){e.innerHTML='<div class="error-msg">Error: '+r(v.message)+"</div>",f.innerHTML="Error: "+r(v.message)}finally{d.disabled=1}}function x(t){var u="";for(var v=0;v<t.length;v++){var w=t[v],x=r(w.title||"Untitled"),y=r(w.author||"Unknown"),z=w.thumbnail||"https://i.ytimg.com/vi/"+w.id+"/hqdefault.jpg";u+='<div class="video-card" data-id="'+w.id+'"><div class="thumbnail"><img src="'+z+'" alt="'+x+'" loading="lazy"/><div class="play-overlay"></div></div><div class="info"><h3 title="'+x+'">'+x+'</h3><div class="author">'+y+"</div></div></div>"}e.innerHTML=u,document.querySelectorAll(".video-card").forEach(function(A){A.addEventListener("click",function(){B(this.dataset.id)})})}function B(t){var u=o.find(function(v){return v.id===t});if(!u)return;p=t,a.style.display="none",b.style.display="block",i.textContent=u.title||"Untitled",j.textContent=u.author||"Unknown",k.href=u.fullUrl||"https://www.youtube.com/watch?v="+t,l.textContent=t,q||(q=document.createElement("iframe"),q.setAttribute("allow","accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"),q.setAttribute("allowfullscreen",""),h.appendChild(q)),q.src="https://www.youtube-nocookie.com/embed/"+t+"?autoplay=1&rel=0"}function C(){a.style.display="block",b.style.display="none",q&&(q.src=""),h.innerHTML="",q=null}d.addEventListener("click",function(){s(c.value)}),c.addEventListener("keydown",function(t){t.key==="Enter"&&(t.preventDefault(),s(c.value))}),g.addEventListener("click",function(t){t.preventDefault(),C()})})();
</script>
</body>
</html>''';

void main() async {
  final app = Router();

  app.get('/', (Request req) => Response.ok(indexHtml, headers: {'Content-Type': 'text/html'}));

  app.get('/search', (Request req) async {
    final query = req.url.queryParameters['q'] ?? '';
    if (query.isEmpty) {
      return Response.badRequest(body: '{"error":"missing query param \\"q\\""}',
          headers: {'Content-Type': 'application/json'});
    }
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '15') ?? 15;
    try {
      final results = await search(query, limit: limit);
      final json = jsonEncode(results.map((v) => v.toJson()).toList());
      return Response.ok(json, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: '{"error":"${e.toString().replaceAll('"', '\\"')}"}',
          headers: {'Content-Type': 'application/json'});
    }
  });

  final server = await serve(app, '0.0.0.0', 0);
  final port = server.port;
  final url = 'http://localhost:$port';

  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', url]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else {
    await Process.run('xdg-open', [url]);
  }

  print('\n  ytapis Dart app running at $url');
  print('  Close this window or press Ctrl+C to stop.\n');
}
