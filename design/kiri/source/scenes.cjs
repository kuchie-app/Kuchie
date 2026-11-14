const inks = {
  white:'#f4efe5',
  black:'#151424',
  lilac:'#b5aaff',
  deep:'#3a315e',
  lavender:'#d9d1ff',
};
const {white, black, lilac, deep, lavender} = inks;
const lerp=(a,b,t)=>a+(b-a)*t;
const ease=t=>t*t*(3-2*t);
const pi=Math.PI;
const center=[145,192];

const scenes = {
  offline:{label:'Tidak ada internet', duration:2400, summary:'Jalur kertas putus. Kiri menarik syalnya kembali dan memeluk komik yang masih bisa dibaca.', action:'Buka unduhan', alt:'Kiri memeluk sebuah komik di depan jalur kertas yang terputus.'},
  loading:{label:'Memuat bab', duration:2000, summary:'Kiri menangkap halaman yang melayang, membaliknya, lalu mengambil halaman berikutnya.', action:'Batal', alt:'Kiri membalik halaman yang melayang dari komik terbuka.'},
  'fetch-failed':{label:'Gagal mengambil data', duration:2300, summary:'Kiri meraih lembar dari bingkai. Lembar itu tersedot kembali, dan Kiri mengulurkan tangan sekali lagi.', action:'Coba lagi', alt:'Kiri mengulurkan tangan ke halaman yang tertarik kembali ke dalam bingkai.'},
  error:{label:'Halaman bermasalah', duration:2050, summary:'Kertas terbelah di tangannya. Kiri terkejut, lalu menyandingkan kedua potongannya.', action:'Muat ulang', alt:'Kiri memegang dua potongan halaman manga yang robek.'},
  empty:{label:'Library kosong', duration:1850, summary:'Kiri duduk di ambang rak kosong dan menggantung syalnya sebagai penanda tempat.', action:'Jelajahi', alt:'Kiri duduk di depan rak kosong dengan syal penanda buku terjulur.'},
  'no-results':{label:'Pencarian tanpa hasil', duration:2050, summary:'Kiri mengintip ke balik dua lembar, lalu memiringkan kepala ketika keduanya kosong.', action:'Ubah kata kunci', alt:'Kiri mengintip dari balik dua lembar kertas kosong.'},
  intro:{label:'Pembuka Kuchie', duration:1450, summary:'Kiri melangkah keluar dari bingkai manga, disusul syalnya.', action:'', alt:'Kiri melangkah keluar dari sebuah bingkai manga.'},
  'download-paused':{label:'Unduhan dijeda', duration:1700, summary:'Kiri menaruh penanda di tengah komik dan duduk di sampingnya.', action:'Lanjutkan', alt:'Kiri duduk di sebelah komik dengan penanda buku terpasang.'},
  complete:{label:'Unduhan selesai', duration:1700, summary:'Kiri menangkap lembar terakhir, memasukkannya ke jilid, lalu mengangkat komiknya.', action:'Baca', alt:'Kiri mengangkat komik yang sudah lengkap.'},
};

const partPivots={
  head:[151,119], eyes:[176,84], scarf:[146,119], body:[150,121],
  'arm-front':[151,127], 'arm-back':[166,127], 'leg-front':[145,165], 'leg-back':[161,163],
};
const round=n=>Number(n.toFixed(2));
function pose(f,x,y,a=0,s=1){
  return 'translate('+round(x)+' '+round(y)+') translate('+f.join(' ')+') rotate('+round(a)+') scale('+round(s)+') translate('+f.map(n=>-n).join(' ')+')';
}
function shift(p,id,x,y,a,s=1){
  p[id]=pose(partPivots[id],x,y,a,s);
}
function sheet(x,y,a=0,scale=1,kind='printed',opacity=1){
  const rules=kind==='blank'
    ? '<path d="M-13 8H13" stroke="'+deep+'" opacity=".55" stroke-width="1.4" stroke-linecap="round"/>'
    : '<path fill="'+deep+'" d="M-13-17H13V-1H-13zM-13 5H-2V16H-13zM2 5H13V16H2z"/><path fill="'+lilac+'" d="m-13-3 7-6 4 4 4-2 10 6H-13z"/><circle cx="6" cy="-12" r="2" fill="'+lavender+'"/>';
  return '<g transform="translate('+round(x)+' '+round(y)+') rotate('+round(a)+') scale('+round(scale)+')" opacity="'+round(opacity)+'"><path fill="'+white+'" stroke="'+black+'" stroke-width="2.5" stroke-linejoin="round" d="M-18-22Q0-24 18-21L19 19Q0 25-18 21Z"/>'+rules+'</g>';
}
function closed(x,y,a=0,s=1){
  return '<g transform="translate('+round(x)+' '+round(y)+') rotate('+round(a)+') scale('+round(s)+')"><path d="M-19-24 17-20 18 22-18 26-23 22-23-21Z" fill="'+black+'" stroke="'+lilac+'" stroke-width="2.4" stroke-linejoin="round"/><path d="M-17-22 19-20 20 20-17 23Z" fill="'+deep+'" stroke="'+black+'" stroke-width="2"/><path d="m-10-13 23 1 .4 18-23.4 3z" fill="'+white+'"/><path d="M-8 4 1-5 6 0 13-5v10L-8 8z" fill="'+lilac+'"/><path d="m-6 12 17-1m-16 6 12-1" stroke="'+lilac+'" stroke-width="1.4" stroke-linecap="round"/><path d="M-19 23 17 21m-36 2v2l36-3" stroke="'+white+'" stroke-width="1.4" stroke-linecap="round" fill="none"/></g>';
}
function book(x,y,a=0,s=1,bookmark=0){
  const ribbon = bookmark ? '<path d="M1-3 6-2 9 28 5 25 1 29Z" fill="'+lilac+'" stroke="'+black+'" stroke-width="1.6"/>' : '';
  return '<g transform="translate('+round(x)+' '+round(y)+') rotate('+round(a)+') scale('+round(s)+')"><path d="M-34-14Q-15-16 0-8q18-10 33-6L34 17Q16 13 0 23q-15-8-34-5Z" fill="'+deep+'" stroke="'+lilac+'" stroke-width="2.5" stroke-linejoin="round"/><path d="M-31-18Q-15-20 0-10q17-11 31-8L31 13Q16 10 0 19q-14-8-31-4Z" fill="'+white+'" stroke="'+black+'" stroke-width="2.3" stroke-linejoin="round"/><path d="M0-10V18m-24-28q10 0 17 5m-17 1q10 0 17 5m-17 1q10 0 17 5M8-7q9-4 16-3M8 0q9-4 16-3M8 7q9-4 16-3" stroke="'+deep+'" stroke-width="1.55" fill="none" stroke-linecap="round"/>'+ribbon+'</g>';
}
function frame(x,y,w,h,angle=0){
  return '<g transform="translate('+x+' '+y+') rotate('+angle+')"><path d="M'+(w-12)+' 0H0V'+h+'H'+w+'V16" fill="'+deep+'" fill-opacity=".56" stroke="'+lilac+'" stroke-opacity=".8" stroke-width="3.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 '+(h-9)+' '+(w-8)+' '+(h-24)+'v19H5Z" fill="url(#k-scene-tone)" opacity=".75"/></g>';
}
function dust(x,y,r,op=.85){
  return '<path d="M'+round(x-r)+' '+round(y)+'h'+round(2*r)+'m'+round(-r)+' '+round(-r)+'v'+round(2*r)+'" stroke="'+lilac+'" stroke-width="1.55" opacity="'+round(op)+'" stroke-linecap="round"/>';
}
function fragment(x,y,a,side){
  const path=side==='left'?'M-15-22 10-21 4-11 12-4 6 2 11 9 5 21-15 22Z':'M-10-21 16-22 17 22-15 21-9 9-14 2-8-4-16-11Z';
  const detail=side==='left'?'M-10-15H3l-6 7h-7zM-10-3H3l-1 6h-12zM-10 10H2l-2 6h-10z':'M-5-15H11v7H-3zM-3-2H12v6H-7zM-6 10h18v6H-9z';
  return '<g transform="translate('+round(x)+' '+round(y)+') rotate('+round(a)+')"><path d="'+path+'" fill="'+white+'" stroke="'+black+'" stroke-width="2.5" stroke-linejoin="round"/><path d="'+detail+'" fill="'+deep+'"/></g>';
}
function travel(t,a,b){return ease(Math.max(0,Math.min(1,(t-a)/(b-a))));}
function blink(t,at){return Math.max(0,1-Math.abs(t-at)/.048);}
function gesture(id,t){
  const p={};
  let dx=0,dy=0,angle=0,scale=1,back='',front='';
  const w=Math.sin(2*pi*t);
  const wobble=Math.sin(4*pi*t);
  let close=blink(t,.89);
  let shadow=1;
  switch(id){
    case 'offline': {
      const step=travel(t,0,.31), stop=travel(t,.35,.69), hug=travel(t,.58,.95);
      dx=-13+21*step-25*stop; dy=3*step+4*hug; angle=7*step-11*stop+5*hug;
      shift(p,'head',0,0,8*step-20*stop+8*hug);
      shift(p,'scarf',0,0,-15*step+36*stop+3*w*(1-hug));
      shift(p,'arm-front',0,0,-32*step+46*stop-3*hug);
      shift(p,'arm-back',0,0,-22*step+33*stop);
      shift(p,'leg-front',0,0,9*step-9*stop);
      shift(p,'leg-back',0,0,-10*step+10*stop);
      close=Math.max(close,blink(t,.44));
      const snap=travel(t,.30,.54);
      back=frame(65,72,60,75,-8)+'<path d="M'+round(184+6*step)+' '+round(119-10*step)+'Q205 '+round(99-8*step)+' '+round(225-5*snap)+' '+round(98+16*snap)+'L'+round(234-7*snap)+' '+round(93+25*snap)+'" fill="none" stroke="'+lilac+'" stroke-width="5" stroke-linecap="round" opacity=".8"/><path d="M'+round(235+8*snap)+' '+round(93-16*snap)+'q17-5 32 4l7 9" fill="none" stroke="'+lilac+'" stroke-width="5" stroke-linecap="round" opacity="'+round(.8-.25*snap)+'"/>';
      front=closed(181+19*step-27*stop-5*hug,148-12*step+13*stop-8*hug,11-15*hug,.78);
      if(snap>.05) back+=dust(238,100,4,snap*.65)+dust(229,84,2.2,snap*.5);
      break;
    }
    case 'loading': {
      const turn=(1-Math.cos(2*pi*t))/2;
      dy=-3*turn; angle=-5*turn;
      shift(p,'head',0,0,8*turn);
      shift(p,'scarf',0,0,7*w);
      shift(p,'arm-front',0,0,-32*turn);
      shift(p,'arm-back',0,0,-23*turn);
      close=blink(t,.91);
      back=frame(64,82,76,77,-9);
      front=book(206,166,4,.83);
      front+=sheet(208+20*Math.sin(pi*t),153-51*turn,-17+38*turn,.72,'printed',.97);
      front+='<path d="M226 119q12 0 18 9m-16-17q13 0 20 8" fill="none" stroke="'+lilac+'" stroke-width="1.6" stroke-linecap="round" opacity="'+round(.15+.63*turn)+'"/>';
      break;
    }
    case 'fetch-failed': {
      const reach=travel(t,0,.32), vanish=travel(t,.36,.58), retry=travel(t,.65,.99);
      dx=-10+19*reach-23*vanish+13*retry; angle=3+8*reach-16*vanish+8*retry;
      shift(p,'head',0,0,5*reach-15*vanish+15*retry);
      shift(p,'arm-front',0,0,-39*reach+45*vanish-37*retry);
      shift(p,'arm-back',0,0,-11*reach+11*vanish);
      shift(p,'scarf',0,0,8*reach-22*vanish+16*retry);
      close=Math.max(close,blink(t,.54));
      back=frame(218,77,61,86,8)+sheet(250-60*reach+60*vanish-13*retry,117-9*reach-1*vanish,8-24*reach+31*vanish,.88-.48*vanish,'printed',1-.34*vanish+.15*retry);
      back+='<path d="M221 94l-9-3m7 14-13-1m17 11-8 4" stroke="'+lilac+'" fill="none" stroke-width="2" stroke-linecap="round" opacity="'+round(.18+.82*vanish-.45*retry)+'"/>';
      break;
    }
    case 'error': {
      const tear=travel(t,.19,.43), react=travel(t,.40,.6), inspect=travel(t,.59,.92);
      dx=-9-8*react+5*inspect; dy=-7*react+7*inspect; angle=-13*react+9*inspect;
      shift(p,'head',0,0,-12*react+22*inspect);
      shift(p,'arm-front',0,0,-21+14*react-14*inspect);
      shift(p,'arm-back',0,0,-17-8*react+9*inspect);
      shift(p,'scarf',0,0,-15*react+16*inspect);
      close=Math.max(close,blink(t,.42));
      back=frame(223,82,49,78,9);
      if(tear<.13) front=sheet(188,141,-4,.93);
      else front=fragment(187-9*tear+3*inspect,141+6*tear,-4-16*tear,'left')+fragment(187+17*tear-2*inspect,141-8*tear+8*inspect,-4+24*tear,'right');
      back+=dust(204,101,5,tear*(1-inspect))+dust(216,109,3,tear*(1-inspect));
      break;
    }
    case 'empty': {
      const sit=travel(t,.08,.73);
      dx=-24; dy=1+12*sit; scale=1-.06*sit;
      shift(p,'head',0,0,12*sit-5*Math.sin(pi*t));
      shift(p,'scarf',0,0,-22*sit+5*w*(1-sit));
      shift(p,'leg-front',2*sit,-2*sit,-38*sit);
      shift(p,'leg-back',1*sit,-3*sit,25*sit);
      back=frame(177,66,88,113,-5)+'<path d="M183 139h74m-69 25h69" fill="none" stroke="'+lilac+'" stroke-width="2.8" stroke-linecap="round" opacity=".68"/>';
      front='<path d="M207 '+round(135-24*(1-sit))+'h10l1 28-6-4-6 4Z" fill="'+lilac+'" stroke="'+black+'" stroke-width="1.9" opacity="'+round(sit)+'"/>';
      break;
    }
    case 'no-results': {
      const peek=travel(t,.04,.33), swap=travel(t,.33,.65), think=travel(t,.7,.98);
      dx=-19+13*peek-11*swap; angle=2+7*peek-10*swap;
      shift(p,'head',0,0,12*peek-25*swap+21*think);
      shift(p,'arm-front',0,0,-31*peek+19*swap);
      shift(p,'scarf',0,0,6*w);
      close=Math.max(close,blink(t,.68));
      back=frame(70,78,48,67,-10)+sheet(229+8*peek,124,-14+9*swap,.96,'blank');
      front=sheet(197+14*peek,150-17*peek+13*swap,11-26*peek+35*swap,.9,'blank');
      break;
    }
    case 'intro': {
      const emerge=travel(t,.04,.81);
      dx=-51+47*emerge; dy=4-12*Math.sin(pi*emerge); angle=12*(1-emerge); scale=.77+.23*emerge;
      shift(p,'scarf',0,0,-18*(1-emerge)+9*w*(1-emerge));
      shift(p,'leg-front',0,0,23*Math.sin(2*pi*emerge));
      shift(p,'leg-back',0,0,-19*Math.sin(2*pi*emerge));
      shift(p,'arm-front',0,0,-18*Math.sin(pi*emerge));
      back=frame(62,73,89,103,-9)+dust(248,96,4,emerge*.65);
      front=sheet(204+9*emerge,149-8*emerge,-13,.76,'printed',.95);
      break;
    }
    case 'download-paused': {
      const sit=travel(t,.13,.78);
      dx=-17; dy=11*sit; scale=1-.07*sit;
      shift(p,'head',0,0,12*sit);
      shift(p,'arm-front',0,0,-23*(1-sit)+10*sit);
      shift(p,'scarf',0,0,-14*sit);
      shift(p,'leg-front',1*sit,-1*sit,-39*sit);
      shift(p,'leg-back',1*sit,-2*sit,24*sit);
      back=frame(205,85,63,81,8);
      front=book(212,174,4,.88,true);
      if(sit<.7) front+=sheet(208,131+28*sit,-16+22*sit,.65,'printed',1-sit/.7);
      break;
    }
    case 'complete': {
      const catchPage=travel(t,.07,.40), bind=travel(t,.40,.68), lift=travel(t,.68,.97);
      dx=-12; dy=-9*lift; angle=-4*lift;
      shift(p,'head',0,0,-9*catchPage+15*bind-14*lift);
      shift(p,'arm-front',0,0,-24*catchPage+16*bind-29*lift);
      shift(p,'arm-back',0,0,-14*catchPage+10*bind-20*lift);
      shift(p,'scarf',0,0,13*lift-8*catchPage);
      back=frame(63,93,62,63,-8)+dust(241,108,5,lift)+dust(255,121,3,lift*.65)+dust(225,92,3,lift*.75);
      front=closed(196-9*lift,167-46*lift,7-13*lift,.84+.17*lift);
      if(bind<1) front+=sheet(222-23*catchPage,91+66*catchPage,-14+19*catchPage,.82,'printed',1-bind);
      break;
    }
  }
  // Compress only the eyes for a blink, keeping the mask and folded hood fixed.
  shift(p,'eyes',0,0,0,1);
  if(close>0) p.eyes='translate(0 '+round(87.05*.82*close)+') scale(1 '+round(1-.82*close)+')';
  shadow=1+dy*.012;
  return {p,kiri:pose(center,dx,dy,angle,scale),back,front,shadow,dx};
}
function draw(id,t,rig,opaque=false){
  const g=gesture(id,t);
  let actor=rig.content;
  for(const [part,transform] of Object.entries({...g.p,kiri:g.kiri})){
    actor=actor.replace(new RegExp('(<g\\s+id="'+part+'")(?=[\\s>])'), '$1 transform="'+transform+'"');
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240" role="img"><title>'+scenes[id].alt+'</title><defs>'+rig.defs+'<pattern id="k-scene-tone" width="5" height="5" patternUnits="userSpaceOnUse"><circle cx="1.4" cy="1.4" r=".72" fill="'+lilac+'"/></pattern></defs>'+(opaque?'<rect width="320" height="240" fill="#191629"/>':'')+'<ellipse cx="'+round(160+g.dx*.46)+'" cy="202" rx="'+round(89*g.shadow)+'" ry="6.5" fill="'+lilac+'" opacity=".13"/>'+g.back+actor+g.front+'</svg>';
}
module.exports={scenes,draw};
