const { readFileSync }=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const {test}=require('node:test');
const source=readFileSync(require('node:path').join(__dirname,'../assets/facebook_profile_update.js'),'utf8');
const args={uid:'123',stage:'name',currentName:'Old Name',name:{fullName:'Nguyễn Văn An',givenName:'An',middleName:'Văn',familyName:'Nguyễn'}};
function fixture({host='accountscenter.facebook.com',text='',actor='123',password=false,controls=[]}={}){
  const context=vm.createContext({window:{},location:{protocol:'https:',hostname:host,pathname:'/profiles/',href:'https://'+host+'/profiles/'},
    require:()=>({ACCOUNT_ID:actor,NAME:'Old Name'}),getComputedStyle:()=>({visibility:'visible'}),URL,
    document:{body:{innerText:text},querySelector:s=>password?{}:null,querySelectorAll:s=>s==='input[type="text"],input:not([type])'||s==='input'?[]:controls}});
  vm.runInContext(source,context);return context.window.IGCheckProfile;
}
function button(text){return{innerText:text,clicks:0,getClientRects:()=>[{}],getAttribute:()=>null,click(){this.clicks++;}};}
test('refuses to update a different account or external website',()=>{
  assert.equal(fixture({actor:'456'}).step(args).state,'error');
  assert.equal(fixture({host:'example.com'}).step(args).state,'error');
});
test('does not automate password confirmation',()=>{
  assert.equal(fixture({password:true}).step(args).state,'error');
});
test('will not save a name absent from the review screen',()=>{
  const save=button('Save changes');
  assert.equal(fixture({text:'Review another name',controls:[save]}).step(args).state,'error');
  assert.equal(save.clicks,0);
});
test('does not infer avatar success from a generic page',()=>{
  assert.equal(fixture({host:'www.facebook.com',text:'Profile page'}).step({...args,stage:'avatar_saving'}).state,'waiting');
});
test('recognises an explicit avatar update receipt',()=>{
  assert.equal(fixture({host:'www.facebook.com',text:'Your profile picture has been updated'}).step({...args,stage:'avatar_saving'}).state,'avatar_confirmed');
});
