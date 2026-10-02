// Deterministic two-page LAN simulator: virtual clock, in-process "network" with latency/jitter/loss, frame-stepped games.
const {chromium}=require('/opt/node22/lib/node_modules/playwright');
const P='/tmp/claude-0/scratch/package/';
const map={'three.min.js':P+'build/three.min.js','CopyShader.js':P+'examples/js/shaders/CopyShader.js','LuminosityHighPassShader.js':P+'examples/js/shaders/LuminosityHighPassShader.js','EffectComposer.js':P+'examples/js/postprocessing/EffectComposer.js','RenderPass.js':P+'examples/js/postprocessing/RenderPass.js','ShaderPass.js':P+'examples/js/postprocessing/ShaderPass.js','UnrealBloomPass.js':P+'examples/js/postprocessing/UnrealBloomPass.js'};
async function mkPage(b){
  const ctx=await b.newContext({viewport:{width:320,height:180}}); const page=await ctx.newPage(); const errs=[];
  page.on('pageerror',e=>errs.push('PAGEERR '+e.message)); page.on('console',m=>{ if(['error'].includes(m.type())) errs.push(m.text()); });
  await page.route('**/*',r=>{ const u=r.request().url(), base=u.split('/').pop().split('?')[0]; if(map[base]&&/cdn/.test(u)) return r.fulfill({path:map[base],contentType:'application/javascript'}); if(u.startsWith('http://localhost')) return r.continue(); return r.abort(); });
  await page.addInitScript(()=>{ window.__vt=1000; performance.now=()=>window.__vt; let q=[]; window.requestAnimationFrame=cb=>{ q.push(cb); return q.length; }; window.cancelAnimationFrame=()=>{};
    window.__frame=(t)=>{ window.__vt=t; const c=q; q=[]; for(const f of c){ try{ f(t); }catch(e){ console.error('frame err '+e.message); } } return q.length; };
    window.__NORENDER=true; });
  return {page,errs};
}
async function createSim(o){
  o=Object.assign({fpsHost:60,fpsGuest:60,lat:0,jitter:0,loss:0,seed:1},o||{});
  const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist','--no-sandbox']});
  const H=await mkPage(b), G=await mkPage(b); const S={o,b,H,G,t:1000,q:[],hs:{next:1000,last:1000},gs:{next:1000,last:1000},rngS:o.seed,stats:{sent:0,dropped:0}};
  const rnd=()=>{ S.rngS=(S.rngS*1664525+1013904223)>>>0; return S.rngS/4294967296; };
  for(const [side,pg,other] of [['h',H,'g'],['g',G,'h']]){ await pg.page.exposeFunction('__send',(lbl,str)=>{ S.stats.sent++; if(lbl==='u'&&o.loss>0&&rnd()*100<o.loss){ S.stats.dropped++; return; } const jit=(rnd()-.5)*2*o.jitter; S.q.push({at:S.t+Math.max(0,o.lat/2+jit),to:other,lbl,str,ord:S.q.length}); }); }
  await Promise.all([H,G].map(p=>p.page.goto('http://localhost:8765/test.html')));
  S.step=async(untilT)=>{ // advance virtual time, running frames and delivering packets in order
    while(S.t<untilT){ const nextMsg=S.q.length?Math.min(...S.q.map(m=>m.at)):Infinity, nt=Math.min(untilT,S.hs.next,S.gs.next,nextMsg); S.t=Math.max(S.t,nt);
      const due=S.q.filter(m=>m.at<=S.t).sort((a,b)=>a.at-b.at||a.ord-b.ord); S.q=S.q.filter(m=>m.at>S.t);
      for(const m of due){ const tt=(/"t":"(\w+)"/.exec(m.str)||[])[1]; if(tt&&tt!=='snap'&&tt!=='ping'&&tt!=='pong'&&tt!=='in') (S.msgs=S.msgs||[]).push([Math.round(S.t),m.to,tt]); const pg=(m.to==='h'?H:G).page; await pg.evaluate(([l,s,t])=>{ window.__vt=Math.max(window.__vt,t); window.__T.netRecv(window.__T.NET[l],s); },[m.lbl,m.str,S.t]); }
      if(S.t>=S.hs.next){ await H.page.evaluate(t=>window.__frame(t),S.t); S.hs.next=S.t+1000/S.o.fpsHost; }
      if(S.t>=S.gs.next){ await G.page.evaluate(t=>window.__frame(t),S.t); S.gs.next=S.t+1000/S.o.fpsGuest; } }
  };
  S.run=ms=>S.step(S.t+ms);
  S.until=async(fn,side,maxMs)=>{ const t0=S.t; while(S.t-t0<maxMs){ await S.run(50); const pg=side==='h'?H.page:G.page; if(await pg.evaluate(fn)) return true; } return false; };
  S.close=()=>b.close();
  return S;
}
// wire fake channels and start a LAN match
async function startLan(S,map,opts){ opts=opts||{};
  await S.until(()=>window.__T&&window.__T.G.state==='menu','h',60000); await S.until(()=>window.__T&&window.__T.G.state==='menu','g',60000);
  const fake=(side,pg)=>pg.page.evaluate(([side])=>{ const T=window.__T, mk=lbl=>({label:lbl,readyState:'open',send:s=>window.__send(lbl,s),close(){}}); T.NET.u=mk('u'); T.NET.r=mk('r'); T.NET.role=side==='h'?'host':'client'; T.netOpen(); T.NS.conn='SIMULATED link'; },[side]);
  await fake('h',S.H); await fake('g',S.G);
  for(const [pg,cfg] of [[S.H,opts.hostCfg||{}],[S.G,opts.guestCfg||{}]]) await pg.page.evaluate(c=>Object.assign(window.__T.NETCFG,c),cfg);
  await S.H.page.evaluate(m=>{ const T=window.__T; T.G.map=m; T.G.target=9; T.G.weapon='rifle'; T.G.noLock=true; return T.lanHostStart(); },map||'town');
  await S.G.page.evaluate(()=>{ window.__T.G.noLock=true; });
  const ok=await S.until(()=>window.__T.G.state==='playing','h',90000); await S.until(()=>window.__T.NET.hs==='playing','g',20000); await S.run(500); return ok; }
module.exports={createSim,startLan};
