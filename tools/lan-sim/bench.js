const {createSim,startLan}=require('./vsim');
const BASE={predict:false,shotPredict:false,tickHz:30,inHz:30,interpAuto:false,interpFixed:90,lagComp:false};   // the old behaviour
const NEW={predict:true,shotPredict:true,tickHz:60,inHz:60,interpAuto:true,lagComp:true};
const cfgBoth=async(S,c)=>{ for(const p of [S.H,S.G]) await p.page.evaluate(c=>Object.assign(window.__T.NETCFG,c),c); };
const key=async(pg,k,down)=>pg.page.evaluate(([k,down])=>{ const code=k==='w'?'KeyW':k==='s'?'KeyS':k==='a'?'KeyA':'KeyD'; window.dispatchEvent(new KeyboardEvent(down?'keydown':'keyup',{key:k,code,bubbles:true})); },[k,down]);
async function setup(S){ for(const p of [S.H,S.G]) await p.page.evaluate(()=>{ const T=window.__T; window.__rec=[]; const o=window.__frame; window.__frame=(t)=>{ const r=o(t); window.__rec.push([t,T.P.x,T.P.z,T.B.x,T.B.z,T.P.y,T.B.y]); if(window.__rec.length>6000) window.__rec.shift(); return r; }; }); }
async function ensurePlaying(S){ for(let i=0;i<120;i++){ const st=await S.H.page.evaluate(()=>{ const T=window.__T; if(T.G.state==='pick'&&T.G.picker&&!T.G.picker.remote) T.choose(0); return T.G.state+'|'+T.NET.hs; }); const gs=await S.G.page.evaluate(()=>window.__T.NET.hs); if(st.startsWith('playing')&&gs==='playing') return true; await S.run(250); } return false; }
async function place(S){ await ensurePlaying(S); await S.H.page.evaluate(()=>{ const T=window.__T; T.G.roundT=0; T.G.sudden=false; for(const f of T.FIGHTERS) f.hp=1e5; }); await S.H.page.evaluate(()=>{ const T=window.__T, r=T.FIGHTERS.find(f=>f.remote), me=T.FIGHTERS.find(f=>!f.remote); for(const f of [me,r]){ f.vx=f.vz=f.vy=0; f.y=0; f.yaw=-Math.PI/2; } me.x=-18; me.z=-3; r.x=-18; r.z=3; });
  await S.G.page.evaluate(()=>{ const T=window.__T; T.P.x=-18; T.P.z=3; T.P.vx=T.P.vz=0; T.P.yaw=-Math.PI/2; T.NET.hist.length=0; }); await S.run(400); }
const resetRec=async(S)=>{ for(const p of [S.H,S.G]) await p.page.evaluate(()=>{ window.__rec.length=0; const N=window.__T.NS; N.err=0; N.corr=0; N.hard=0; }); };
const getRec=async(pg)=>pg.page.evaluate(()=>window.__rec);
function jerk(track,thr){ let n=0, mx=0, prev=null; for(let i=1;i<track.length;i++){ const d=[track[i][0]-track[i-1][0],track[i][1]-track[i-1][1]]; const dd=Math.hypot(d[0]/Math.max(1,track[i][2]),0); } return 0; }
async function moveTest(S,label){ await place(S); await resetRec(S);
  const dirs=[['w',1400],['s',1400],['w',1400],['s',1400]]; let firstLat=null;
  for(const [k,ms] of dirs){ const t0=S.t; const z0=(await S.G.page.evaluate(()=>[window.__T.P.x,window.__T.P.z])); await key(S.G,k,true);
    if(firstLat===null){ const x0=z0[0]; while(S.t-t0<400){ await S.run(1); const x=(await S.G.page.evaluate(()=>window.__T.P.x)); if(Math.abs(x-x0)>.01){ firstLat=S.t-t0; break; } } }
    await S.step(t0+ms); await key(S.G,k,false); await S.run(120); }
  await S.run(500);
  const g=await getRec(S.G), h=await getRec(S.H); const gp=g.map(r=>[r[0],r[1]]);
  // jerk: frame-to-frame change of per-frame displacement beyond what accel allows
  let j=0, mxj=0; for(let i=2;i<gp.length;i++){ const d1=(gp[i][1]-gp[i-1][1])/(gp[i][0]-gp[i-1][0])*1000, d0=(gp[i-1][1]-gp[i-2][1])/(gp[i-1][0]-gp[i-2][0])*1000, a=Math.abs(d1-d0)/((gp[i][0]-gp[i-1][0])/1000); mxj=Math.max(mxj,a); if(a>260) j++; }
  const ns=await S.G.page.evaluate(()=>({err:window.__T.NS.err*100,corr:window.__T.NS.corr,hard:window.__T.NS.hard,rtt:window.__T.NS.rtt,interp:window.__T.NS.interp}));
  // opponent lag: guest's view of the host fighter vs the host's real position (host moves too)
  return {label,firstMotionMs:firstLat,accelSpikes:j,maxAccel:Math.round(mxj),errCm:+ns.err.toFixed(1),corrections:ns.corr,hardSnaps:ns.hard,rtt:Math.round(ns.rtt),interp:Math.round(ns.interp)}; }
async function oppTest(S){ await place(S); await resetRec(S); await key(S.H,'w',true); await S.run(1500); await key(S.H,'w',false); await S.run(300); await key(S.H,'s',true); await S.run(1500); await key(S.H,'s',false); await S.run(400);
  const g=await getRec(S.G), h=await getRec(S.H); // host fighter: host.P ; guest sees it as B
  let lags=[], jit=0, n=0; const hp=h.map(r=>[r[0],r[1]]), gb=g.map(r=>[r[0],r[3]]);
  for(let i=5;i<gb.length-1;i++){ const v=(gb[i+1][1]-gb[i-1][1])/(gb[i+1][0]-gb[i-1][0])*1000; if(Math.abs(v)<4) continue; // find host time when host x equalled this value
    let best=null,bd=1e9; for(let k=0;k<hp.length;k++){ const d=Math.abs(hp[k][1]-gb[i][1]); if(d<bd&&Math.abs(hp[k][0]-gb[i][0])<400){ bd=d; best=hp[k][0]; } } if(best!==null) lags.push(gb[i][0]-best); }
  lags.sort((a,b)=>a-b); const med=lags.length?lags[lags.length>>1]:null;
  let spikes=0; for(let i=2;i<gb.length;i++){ const d1=(gb[i][1]-gb[i-1][1])/(gb[i][0]-gb[i-1][0])*1000, d0=(gb[i-1][1]-gb[i-2][1])/(gb[i-1][0]-gb[i-2][0])*1000; if(Math.abs(d1-d0)/((gb[i][0]-gb[i-1][0])/1000)>300) spikes++; }
  return {opponentViewLagMs:med===null?null:Math.round(med),opponentSpikes:spikes}; }
async function shootTest(S){ await place(S);
  await S.H.page.evaluate(()=>{ const T=window.__T, r=T.FIGHTERS.find(f=>f.remote), me=T.FIGHTERS.find(f=>!f.remote); me.x=-18; me.z=0; r.z=-6; r.x=-18; me.hp=me.stats.maxHp; window.__T.NS.comp; });
  await S.G.page.evaluate(()=>{ const T=window.__T; T.P.x=-18; T.P.z=-6; T.NET.hist.length=0; }); await S.run(700);
  // local feedback + host receive
  await S.G.page.evaluate(()=>{ const T=window.__T,P=T.P,B=T.B; const dx=B.x-P.x, dz=B.z-P.z, dy=(B.y+1.2)-(P.y+1.6); P.yaw=Math.atan2(-dx,-dz); P.pitch=Math.atan2(dy,Math.hypot(dx,dz)); window.__a0=P.ammo; }); await S.run(150);
  const t0=S.t; await S.G.page.evaluate(()=>{ document.querySelectorAll('canvas').forEach(c=>c.dispatchEvent(new MouseEvent('mousedown',{button:0,bubbles:true}))); }); let local=null, hostGot=null;
  while(S.t-t0<500){ await S.run(1); if(local===null&&await S.G.page.evaluate(()=>window.__T.P.ammo<window.__a0)) local=S.t-t0; if(hostGot===null&&await S.H.page.evaluate(()=>window.__T.G.bullets.some(b=>b.owner.remote))) hostGot=S.t-t0; if(local!==null&&hostGot!==null) break; }
  await S.G.page.evaluate(()=>{ window.dispatchEvent(new MouseEvent('mouseup',{button:0,bubbles:true})); }); await S.run(600);
  return {localFeedbackMs:local,hostSpawnsShotMs:hostGot}; }
async function findLane(S){ return S.G.page.evaluate(()=>{ const T=window.__T; const eye=(x,z)=>new THREE.Vector3(x,1.6,z), tg=(x,z)=>new THREE.Vector3(x,1.2,z); const clear=(sx,sz,tx,tz)=>{ for(let k=0;k<=12;k++){ const x=tx+k*1.1; if(!T.hasLOS(eye(sx,sz),tg(x,tz))) return false; } return true; };
  for(let sz=-24;sz<=24;sz+=2) for(let sx=-24;sx<=6;sx+=2) for(const d of [14,-14]){ const tz=sz+d; if(Math.abs(tz)>26) continue; if(clear(sx,sz,sx,tz)&&clear(sx,sz,sx+1,tz)) return {sx,sz,tx:sx,tz}; } return null; }); }
async function hitTest(S,moving){ // guest fires 10 single shots at the host fighter 14m away, leading a moving target by its displayed velocity
  let hits=0, shots=0; const L=await findLane(S); if(!L) return {hits:-1,shots:0};
  for(let n=0;n<10;n++){ await place(S);
    await S.H.page.evaluate(L=>{ const T=window.__T, r=T.FIGHTERS.find(f=>f.remote), me=T.FIGHTERS.find(f=>!f.remote); me.x=L.tx; me.z=L.tz; r.x=L.sx; r.z=L.sz; me.ammo=me.stats.ammo; r.ammo=r.stats.ammo; me.blockT=0; },L);
    await S.G.page.evaluate(L=>{ const T=window.__T; T.P.x=L.sx; T.P.z=L.sz; T.NET.hist.length=0; },L); await S.run(500);
    if(moving){ await key(S.H,'w',true); await S.run(700); }
    const aim=()=>S.G.page.evaluate(()=>{ const T=window.__T,P=T.P,B=T.B; const e=[P.x,P.y+1.6,P.z]; const dx0=B.x-P.x, dz0=B.z-P.z, dist=Math.hypot(dx0,dz0), tf=dist/(T.P.stats.bSpeed||58); const tx=B.x+(B.vx||0)*tf, tz=B.z+(B.vz||0)*tf, ty=B.y+1.15+(T.P.stats.drop||0)*.5*tf*tf; const dx=tx-e[0], dz=tz-e[2], dy=ty-e[1]; P.yaw=Math.atan2(-dx,-dz); P.pitch=Math.atan2(dy,Math.hypot(dx,dz)); });
    await aim(); await S.run(33); await aim(); await S.run(20); await aim();
    const hp0=await S.H.page.evaluate(()=>Math.round(window.__T.FIGHTERS.find(f=>!f.remote).hp)); if(process.env.DBG&&n<2){ const d=await S.G.page.evaluate(()=>[window.__T.B.x,window.__T.B.z,window.__T.B.vx,window.__T.NS.rtt,window.__T.NS.interp,window.__T.NET.snaps.length]); const r=await S.H.page.evaluate(()=>{ const f=window.__T.FIGHTERS.find(f=>!f.remote); return [f.x,f.z,f.vx,window.__T.NS.comp]; }); console.log('dbg disp',d.map(v=>+v.toFixed(2)),'real',r.map(v=>+v.toFixed(2))); }
    await S.G.page.evaluate(()=>{ document.querySelectorAll('canvas').forEach(c=>c.dispatchEvent(new MouseEvent('mousedown',{button:0,bubbles:true}))); }); await S.run(20); await S.G.page.evaluate(()=>{ window.dispatchEvent(new MouseEvent('mouseup',{button:0,bubbles:true})); });
    for(let k=0;k<12;k++){ await S.run(50); }
    const hp1=await S.H.page.evaluate(()=>Math.round(window.__T.FIGHTERS.find(f=>!f.remote).hp)); shots++; if(hp1<hp0) hits++;
    if(moving) await key(S.H,'w',false); await S.run(200); await S.H.page.evaluate(()=>{ const T=window.__T; if(T.G.state!=='playing'){} }); }
  return {hits,shots}; }
(async()=>{ const S=await createSim({}); await startLan(S,'town'); await setup(S);
  const mode=process.env.MODE||'lat';
  const run=async(name,lat,loss,fg,fh,cfgs,tests)=>{ S.o.lat=lat; S.o.loss=loss; S.o.fpsGuest=fg; S.o.fpsHost=fh; S.o.jitter=lat*.08;
    for(const [cn,cfg] of cfgs){ await cfgBoth(S,cfg); const out={label:name+' / '+cn}; if(tests.includes('m')) Object.assign(out,await moveTest(S,'')); if(tests.includes('o')) Object.assign(out,await oppTest(S)); if(tests.includes('s')) Object.assign(out,await shootTest(S));
      if(tests.includes('h')){ const a=await hitTest(S,false), b=await hitTest(S,true); out.hitsStill=a.hits+'/'+a.shots; out.hitsMoving=b.hits+'/'+b.shots; } delete out.label2; console.log(JSON.stringify(out)); } };
  const both=[['OLD',BASE],['NEW',NEW]];
  if(mode==='lat'){ for(const lat of [0,20,60,120]) await run('RTT '+lat+'ms',lat,0,60,60,both,'mos'); }
  if(mode==='hit'){ for(const lat of (process.env.LATS||'0,60,120').split(',').map(Number)) await run('RTT '+lat+'ms',lat,0,60,60,[['OLD',BASE],['NEW no-lagcomp',Object.assign({},NEW,{lagComp:false})],['NEW',NEW]],'h'); }
  if(mode==='loss'){ for(const loss of [0,5,10,20]) await run('RTT 40ms loss '+loss+'%',40,loss,60,60,[['NEW',NEW]],'mo'); }
  if(mode==='fps'){ for(const [fg,fh] of [[30,60],[60,60],[120,60],[30,30],[144,144]]) await run('guest '+fg+'fps host '+fh+'fps RTT 20',20,0,fg,fh,[['NEW',NEW]],'mos'); }
  console.log('errs',JSON.stringify(S.H.errs.concat(S.G.errs).filter(e=>!/404/.test(e)).slice(0,4)));
  await S.close(); })();
