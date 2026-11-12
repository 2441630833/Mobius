// Mobius x headroom: persistence-side compression for chat session logs.
// Port of headroom's LogCompressor defaults (max_errors=10, error_context_lines=3,
// max_warnings=5 deduped, keep summary lines, max_total_lines=100) and
// DenseLineElider (>=300 chars, <6% spaces, <10% non-ASCII, head 160 / tail 80).
// Applied ONLY to the copy written to disk; the live chat model is never mutated.
function __mobiusHRs(t){
  if(typeof t!=="string"||t.length<=4096)return t;
  if(t.indexOf("[headroom: persisted copy")!==-1&&t.length<=16384)return t;
  var o=t,L=t.split("\n"),n=L.length,i,x;
  // 1. dense machine-generated lines (minified bundles, base64, RSC payloads)
  var dense=function(s){var m=s.length;if(m<300||s.indexOf("\t")!==-1)return!1;var sp=0,na=0;for(var k=0;k<m;k++){var c=s.charCodeAt(k);c===32?sp++:c>127&&na++}if(sp/m>=.06||na>m*.1)return!1;var st=s.trim(),a=st[0],b=st[st.length-1];return!((a==="{"||a==="[")&&(b==="}"||b==="]"))};
  var dt=0;for(i=0;i<n;i++)dense(L[i])&&(dt+=L[i].length);
  if(dt>=2000)for(i=0;i<n;i++)dense(L[i])&&(L[i]=L[i].slice(0,160)+" ...["+(L[i].length-240)+" chars of dense machine-generated content elided]... "+L[i].slice(-80));
  t=L.join("\n");
  if(t.length<=4096||(n<=100&&t.length<=16384))return t.length<o.length?t+"\n[headroom: persisted copy compressed "+o.length+" -> "+t.length+" chars]":t;
  // 2. log compression: keep head/tail, errors (+context), deduped warnings, summaries, stack frames
  var ER=/\b(error|exception|fail|failed|failure|fatal|critical|crash|panic|abort|timeout|denied|rejected)\b|traceback|报错|失败|错误/i,
      WR=/\bwarn(ing)?\b|警告/i,
      SR=/(\b\d+ (passed|failed|errors?|warnings?|tests?|skipped)\b)|^\s*(total|summary|result|tests?:|done in|finished|exit code|build (succeeded|failed))|\bexit(ed)? (with )?code\b/i,
      TR=/^\s+at |^\s*File "|^Traceback|^\s+\^|^\s*Caused by/;
  var keep=new Uint8Array(n),H=20,T=20,errs=[],ws=0,seenW={},k;
  for(i=0;i<Math.min(H,n);i++)keep[i]=1;for(i=Math.max(0,n-T);i<n;i++)keep[i]=1;
  for(i=0;i<n;i++){x=L[i];if(ER.test(x))errs.push(i);else if(WR.test(x)&&ws<5){var nk=x.replace(/[0-9]+/g,"#").replace(/[A-Za-z]:?[\\\/][^\s:]*/g,"<p>");seenW[nk]||(seenW[nk]=1,keep[i]=1,ws++)}else if(SR.test(x))keep[i]=1}
  var pick=errs.length<=10?errs:errs.slice(0,5).concat(errs.slice(-5));
  for(k=0;k<pick.length;k++){var e=pick[k];for(i=Math.max(0,e-3);i<=Math.min(n-1,e+3);i++)keep[i]=1;var f=0;for(i=e+1;i<n&&f<20&&TR.test(L[i]);i++,f++)keep[i]=1}
  var out=[],gap=0,kept=0,prev=null,rep=0;
  for(i=0;i<n;i++){if(!keep[i]){gap++;continue}
    if(gap){out.push("... ["+gap+" lines omitted]");gap=0}
    if(L[i]===prev){rep++;continue}if(rep){out.push("... [previous line repeated "+rep+" more times]");rep=0}
    out.push(L[i]);prev=L[i];kept++;if(kept>=100&&i<n-T){var r=0;for(var j=i+1;j<n;j++)keep[j]&&r++;out.push("... ["+(n-i-1)+" lines omitted, "+r+" flagged]");break}}
  if(rep)out.push("... [previous line repeated "+rep+" more times]");if(gap)out.push("... ["+gap+" lines omitted]");
  t=out.join("\n");
  // 3. hard cap so a single value can never balloon the log again
  if(t.length>16384)t=t.slice(0,10240)+"\n... ["+(t.length-14336)+" chars omitted] ...\n"+t.slice(-4096);
  return t+"\n[headroom: persisted copy compressed "+o.length+" -> "+t.length+" chars, "+n+" lines; the live output was not changed]";
}
// Copy-on-write walk: returns the same reference when nothing changed, never mutates input.
function __mobiusHRw(v,d){
  if(typeof v==="string")return __mobiusHRs(v);
  if(!v||typeof v!=="object"||d>12)return v;
  var c=null,k,a,b;
  if(Array.isArray(v)){for(k=0;k<v.length;k++){a=v[k];b=__mobiusHRw(a,d+1);if(b!==a){c||(c=v.slice());c[k]=b}}return c||v}
  if(typeof v.toJSON==="function"||Object.getPrototypeOf(v)!==Object.prototype&&Object.getPrototypeOf(v)!==null)return v;
  for(k in v){if(k==="base64Data"||k==="uri"||k==="resource")continue;a=v[k];b=__mobiusHRw(a,d+1);if(b!==a){c||(c=Object.assign({},v));c[k]=b}}
  return c||v;
}
function __mobiusHR(p){
  try{if(p&&typeof p==="object"&&(p.kind==="toolInvocationSerialized"||p.kind==="thinking"||p.kind==="progressTaskSerialized"||p.kind==="elicitationSerialized"))return __mobiusHRw(p,0)}catch(e){}
  return p;
}
if(typeof module!=="undefined")module.exports={__mobiusHR,__mobiusHRs};
