const {__mobiusHR,__mobiusHRs}=require('./headroom-persist.js');
const assert=require('assert');
// big log
let log=[];for(let i=0;i<5000;i++)log.push(`INFO step ${i} ok`);log.splice(2500,0,'Traceback (most recent call last):','  File "a.py", line 3','FATAL disk full');log.push('3 passed, 1 failed');
const big=log.join('\n');
const c=__mobiusHRs(big);
console.log(big.length,'->',c.length);
assert(c.includes('FATAL disk full')&&c.includes('Traceback')&&c.includes('3 passed, 1 failed')&&c.includes('INFO step 0 ok')&&c.includes('INFO step 4999 ok'));
assert.strictEqual(__mobiusHRs(c),c,'idempotent');
// small unchanged
assert.strictEqual(__mobiusHRs('hello'),'hello');
// dense line
const dense='x'.repeat(50000);const d=__mobiusHRs('head\n'+dense+'\ntail');console.log('dense',d.length);assert(d.length<1000);assert.strictEqual(__mobiusHRs(d),d);
// single huge line w/ spaces (prose)
const prose=('word '.repeat(10000));const pc=__mobiusHRs(prose);console.log('prose',pc.length);assert(pc.length<=16384+300);assert.strictEqual(__mobiusHRs(pc),pc);
// CJK long
const cjk='中文'.repeat(20000);const cc=__mobiusHRs(cjk);console.log('cjk',cc.length);assert.strictEqual(__mobiusHRs(cc),cc);
// part: copy on write, no mutation
const part={kind:'toolInvocationSerialized',toolId:'run_in_terminal',toolSpecificData:{kind:'terminal',terminalCommandOutput:{text:big}},resultDetails:{output:{type:'data',base64Data:'A'.repeat(9000)}},invocationMessage:{value:'run'}};
const before=JSON.stringify(part);const r=__mobiusHR(part);
assert.strictEqual(JSON.stringify(part),before,'input not mutated');assert.notStrictEqual(r,part);
assert(r.toolSpecificData.terminalCommandOutput.text.length<20000);assert.strictEqual(r.resultDetails,part.resultDetails);assert.strictEqual(r.invocationMessage,part.invocationMessage);
// determinism (diff stability)
assert.deepStrictEqual(__mobiusHR(part),r);
// other kinds untouched
const md={kind:'textEditGroup',edits:[[{text:big}]]};assert.strictEqual(__mobiusHR(md),md);
assert.strictEqual(__mobiusHR('str'),'str');assert.strictEqual(__mobiusHR(null),null);
// whole-part size
console.log('part', before.length,'->',JSON.stringify(r).length);
// many medium lines under 16K but >100 lines
const med=Array.from({length:300},(_,i)=>'line '+i+' '+'y'.repeat(40)).join('\n');const mc=__mobiusHRs(med);console.log('med',med.length,'->',mc.length);assert.strictEqual(__mobiusHRs(mc),mc);
console.log('ALL OK');
