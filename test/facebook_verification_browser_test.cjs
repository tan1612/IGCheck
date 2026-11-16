const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const source = readFileSync(require('node:path').join(__dirname, '../assets/facebook_verification.js'), 'utf8');

function fixture({host='m.facebook.com', path='/ixt/renderscreen/msite/', text='Upload identity document', buttons=[], inputs=[], selects=[]} = {}) {
  const document = {
    body: {innerText:text},
    querySelector: () => null,
    querySelectorAll: selector => selector === 'input[type="file"]' ? inputs :
      selector === 'select' ? selects : selector === 'label' ? [] : buttons,
  };
  const context = vm.createContext({
    location:{protocol:'https:',hostname:host,pathname:path}, document, window:{},
    getComputedStyle:()=>({visibility:'visible'}), URLSearchParams, crypto:require('node:crypto').webcrypto,
    Event:class {constructor(type){this.type=type;}},
    Uint8Array, atob:s=>Buffer.from(s,'base64').toString('binary'),
    File:class {constructor(bytes,name,options){this.name=name;this.type=options.type;}},
    DataTransfer:class {constructor(){this.files=[];this.items={add:file=>this.files.push(file)};}},
  });
  vm.runInContext(source,context);
  return {context, api:context.window.IGCheckFacebook, document};
}
const image = {base64:'AQID', name:'document.jpg', mime:'image/jpeg'};
const args = (extra={}) => ({images:[image],documentType:'national_id',uploaded:[],submitted:false,...extra});
function button(text) {
  return {innerText:text, clicks:0, getClientRects:()=>[{}], getAttribute:()=>null, click(){this.clicks++;}};
}
function input(extra={}) {
  return {dataset:{},files:[],multiple:false,name:'',id:'',getAttribute:()=>null,
    closest:()=>null,dispatchEvent(){}, ...extra};
}

test('does not run on external origins or ordinary Facebook feed',()=>{
  assert.equal(fixture({host:'example.com'}).api.step(args()).state,'blocked');
  assert.equal(fixture({path:'/feed/'}).api.step(args()).state,'blocked');
});
test('never submits without all document images',()=>{
  const send=button('Submit'); const f=fixture({buttons:[send]});
  assert.equal(f.api.step(args()).state,'blocked'); assert.equal(send.clicks,0);
});
test('fills images and submits once, then waits for receipt',()=>{
  const send=button('Submit'), file=input(); const f=fixture({inputs:[file],buttons:[send]});
  const upload=f.api.step(args()); assert.equal(upload.state,'uploaded'); assert.equal(file.files.length,1);
  assert.equal(f.api.step(args({uploaded:[0]})).state,'submitted'); assert.equal(send.clicks,1);
  assert.equal(f.api.step(args({uploaded:[0],submitted:true})).state,'waiting'); assert.equal(send.clicks,1);
  f.document.body.innerText="We've received your ID";
  assert.equal(f.api.step(args({uploaded:[0],submitted:true})).state,'confirmed');
});
test('does not treat generic thank-you or HTTP success as confirmation',()=>{
  assert.equal(fixture({text:'Thank you'}).api.step(args({uploaded:[0],submitted:true})).state,'waiting');
});
test('two images cannot be silently squeezed into ambiguous single input',()=>{
  const file=input(); const f=fixture({inputs:[file]});
  assert.equal(f.api.step(args({images:[image,image]})).state,'blocked'); assert.equal(file.files.length,0);
});
test('multiple upload accepts both front and back',()=>{
  const file=input({multiple:true}); const f=fixture({inputs:[file]});
  assert.equal(f.api.step(args({images:[image,image]})).state,'uploaded'); assert.equal(file.files.length,2);
});
test('selfie and authentication challenges stop automation',()=>{
  assert.equal(fixture({text:'Take a selfie'}).api.step(args()).state,'blocked');
});
test('Facebook error pages are reported instead of waiting for an upload form',()=>{
  assert.equal(fixture({text:'Sorry, something went wrong'}).api.step(args()).state,'blocked');
  assert.equal(fixture({text:"This page isn't available"}).api.step(args()).state,'blocked');
});
test('continue is clicked once and only in the verification context',()=>{
  const next=button('Continue'); const f=fixture({buttons:[next]});
  assert.equal(f.api.step(args()).state,'advance');
  assert.equal(f.api.step(args()).state,'waiting'); assert.equal(next.clicks,1);
  const unrelated=button('Continue');
  assert.equal(fixture({text:'Account settings',buttons:[unrelated]}).api.step(args()).state,'waiting');
  assert.equal(unrelated.clicks,0);
});
test('selects the requested document type',()=>{
  const select={value:'id',options:[{value:'id',text:'National ID card'},{value:'passport',text:'Passport'}],dispatchEvent(){}};
  const f=fixture({selects:[select]});
  assert.equal(f.api.step(args({documentType:'passport'})).state,'advance');
  assert.equal(select.value,'passport');
});
test('selects National ID radio and proceeds through the mobile Capture your ID page',()=>{
  const radio={...button(''), type:'radio', checked:false, parentElement:{innerText:'National ID'},
    click(){this.checked=true;this.clicks++;}};
  const next=button('Next');
  const f=fixture({text:"Capture your ID to confirm that it's you",buttons:[radio,next]});
  assert.equal(f.api.step(args()).state,'advance'); assert.equal(radio.checked,true);
  assert.equal(f.api.step(args()).state,'advance'); assert.equal(next.clicks,1);
  assert.equal(radio.clicks,1);
});
test('F12 starts on mobile Facebook and opens the returned mobile link',async()=>{
  const f=fixture({host:'m.facebook.com',path:'/'});
  f.context.require=name=>({SiteData:{__rev:123},CurrentUserInitialData:{ACCOUNT_ID:'123'},
    DTSGInitialData:{token:'session-dtsg'},LSD:{token:'session-lsd'},SprinkleConfig:{jazoest:123}}[name]);
  let requests=0;
  f.context.fetch=async (url,options)=>{
    requests++; assert.equal(url,'https://accountscenter.facebook.com/api/graphql/'); assert.equal(options.credentials,'include');
    const body=new URLSearchParams(options.body);
    assert.equal(body.get('doc_id'),'28497467229951945');
    assert.equal(JSON.parse(body.get('variables')).input.authenticity_product,'FB_NME_PAID_BLUE_BADGE_IDV');
    return {ok:true,text:async()=> 'for (;;);'+JSON.stringify({data:{ixt_authenticity_wizard_trigger:{screen:{view_model:{serialized_state:'a+b/c='}}}}})};
  };
  const result=await f.api.trigger(); assert.equal(requests,1); assert.equal(result.state,'link');
  assert.equal(new URL(result.url).searchParams.get('serialized_state'),'a+b/c=');
});
test('GraphQL errors never produce a successful verification link',async()=>{
  const f=fixture({host:'accountscenter.facebook.com',path:'/subscriptions'});
  f.context.require=name=>({SiteData:{},CurrentUserInitialData:{ACCOUNT_ID:'123'},DTSGInitialData:{token:'x'},LSD:{token:'y'},SprinkleConfig:{}}[name]);
  f.context.fetch=async()=>({ok:true,text:async()=>JSON.stringify({errors:[{message:'not eligible'}]})});
  assert.equal((await f.api.trigger()).state,'blocked');
});
test('Accounts Center Verification pending confirms a submitted job only',()=>{
  const f=fixture({host:'accountscenter.facebook.com',path:'/meta_verified/',text:'Meta Verified Verification pending We are verifying your information'});
  assert.equal(f.api.step(args()).state,'blocked');
  assert.equal(f.api.step(args({submitted:true,uploaded:[0]})).state,'review');
});
test('Accounts Center payment success alone does not confirm document submission',()=>{
  const f=fixture({host:'accountscenter.facebook.com',path:'/meta_verified/',text:'Your payment was successful'});
  assert.equal(f.api.step(args({submitted:true,uploaded:[0]})).state,'waiting');
});
